import SiriusMarkdownCore
import Foundation

#if canImport(JavaScriptCore)
@preconcurrency import JavaScriptCore
#endif

public protocol MarkdownMermaidRenderer: Sendable {
    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram?
}

public protocol MarkdownMermaidRendererCacheIdentifying: Sendable {
    var mermaidRendererCacheIdentity: String { get }
}

public struct MarkdownPreparedMermaidDiagram: Sendable, Hashable {
    public var source: String
    public var sourceRange: MarkdownSourceRange?
    public var ascii: String
    public var svg: String?

    public init(
        source: String,
        sourceRange: MarkdownSourceRange?,
        ascii: String,
        svg: String? = nil
    ) {
        self.source = source
        self.sourceRange = sourceRange
        self.ascii = ascii
        self.svg = svg
    }
}

public struct DefaultMarkdownMermaidRenderer: MarkdownMermaidRenderer, MarkdownMermaidRendererCacheIdentifying {
    public init() {}

    public var mermaidRendererCacheIdentity: String {
        "siriusmarkdown.default.beautiful-mermaid.1.1.3"
    }

    public func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        guard let result = MermaidJavaScriptRuntime.shared.render(source: source, theme: theme) else {
            return nil
        }

        return MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: result.ascii,
            svg: result.svg
        )
    }
}

public extension MarkdownCodeLanguage {
    var isMermaid: Bool {
        canonicalName == "mermaid" || normalizedInfoString == "mermaid"
    }
}

private struct MermaidJavaScriptResult: Sendable {
    var ascii: String
    var svg: String?
}

private final class MermaidJavaScriptRuntime: @unchecked Sendable {
    static let shared = MermaidJavaScriptRuntime()

    private let lock = NSLock()

#if canImport(JavaScriptCore)
    private var script: String?
    private var didLoadScript = false
    private let group: JSContextGroupRef = JSContextGroupCreate()
    private var context: JSGlobalContextRef?
    private var renderFunction: JSObjectRef?
    private var svgRenderFunction: JSObjectRef?
#endif

    private init() {}

    func renderASCII(source: String, theme: MarkdownTheme) -> String? {
        render(source: source, theme: theme)?.ascii
    }

    func render(source: String, theme: MarkdownTheme) -> MermaidJavaScriptResult? {
        _ = theme
#if canImport(JavaScriptCore)
        return lock.withLock {
            guard let runtime = ensureRuntime() else {
                return nil
            }

            var ascii: String?
            if let asciiJSON = callRenderFunction(
                runtime.asciiFunction,
                context: runtime.context,
                source: source
            ) {
                ascii = Self.decodeASCII(asciiJSON)
            }

            var svg: String?
            if let svgJSON = callRenderFunction(
                runtime.svgFunction,
                context: runtime.context,
                source: source
            ) {
                svg = Self.decodeSVG(svgJSON)
            }

            guard let asciiResult = ascii else {
                return nil
            }

            let trimmed = asciiResult.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            return MermaidJavaScriptResult(ascii: trimmed, svg: svg)
        }
#else
        return nil
#endif
    }

#if canImport(JavaScriptCore)
    private func ensureRuntime() -> (context: JSGlobalContextRef, asciiFunction: JSObjectRef, svgFunction: JSObjectRef)? {
        if let context, let renderFunction, let svgRenderFunction {
            return (context, renderFunction, svgRenderFunction)
        }

        guard let script = loadedScript(),
              let context = JSGlobalContextCreateInGroup(self.group, nil),
              Self.evaluate(Self.bufferShimScript, in: context) != nil,
              Self.evaluate(script, in: context) != nil
        else {
            return nil
        }

        guard let asciiFnValue = Self.evaluate(Self.renderFunctionScript, in: context),
              JSValueIsObject(context, asciiFnValue),
              let svgFnValue = Self.evaluate(Self.svgRenderFunctionScript, in: context),
              JSValueIsObject(context, svgFnValue)
        else {
            return nil
        }

        var exception: JSValueRef?
        guard let asciiFunction = JSValueToObject(context, asciiFnValue, &exception),
              exception == nil,
              let svgFunction = JSValueToObject(context, svgFnValue, &exception),
              exception == nil
        else {
            return nil
        }

        JSValueProtect(context, asciiFnValue)
        JSValueProtect(context, svgFnValue)
        self.context = context
        self.renderFunction = asciiFunction
        self.svgRenderFunction = svgFunction
        return (context, asciiFunction, svgFunction)
    }

    private func loadedScript() -> String? {
        if didLoadScript {
            return script
        }

        didLoadScript = true
        guard let scriptURL = Bundle.module.url(forResource: "beautiful-mermaid.bundle", withExtension: "js")
                  ?? Bundle.module.url(
                      forResource: "beautiful-mermaid.bundle",
                      withExtension: "js",
                      subdirectory: "MermaidJS"
                  ),
              let contents = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            return nil
        }

        script = contents
        return contents
    }

    private func callRenderFunction(
        _ function: JSObjectRef,
        context: JSGlobalContextRef,
        source: String
    ) -> String? {
        guard let sourceString = Self.makeJSString(source) else {
            return nil
        }
        defer {
            JSStringRelease(sourceString)
        }

        let arguments: [JSValueRef?] = [
            JSValueMakeString(context, sourceString)
        ]
        var exception: JSValueRef?
        let result = arguments.withUnsafeBufferPointer { buffer in
            JSObjectCallAsFunction(
                context,
                function,
                nil,
                arguments.count,
                buffer.baseAddress,
                &exception
            )
        }

        guard exception == nil, let result else {
            return nil
        }

        guard let resultString = JSValueToStringCopy(context, result, &exception),
              exception == nil
        else {
            return nil
        }
        defer {
            JSStringRelease(resultString)
        }

        return Self.string(from: resultString)
    }

    private static func evaluate(_ script: String, in context: JSGlobalContextRef) -> JSValueRef? {
        guard let source = makeJSString(script) else {
            return nil
        }
        defer {
            JSStringRelease(source)
        }

        var exception: JSValueRef?
        let value = JSEvaluateScript(context, source, nil, nil, 0, &exception)
        guard exception == nil else {
            return nil
        }

        return value
    }

    private static func makeJSString(_ string: String) -> JSStringRef? {
        string.withCString { pointer in
            JSStringCreateWithUTF8CString(pointer)
        }
    }

    private static func string(from jsString: JSStringRef) -> String {
        let capacity = JSStringGetMaximumUTF8CStringSize(jsString)
        var buffer = [CChar](repeating: 0, count: capacity)
        JSStringGetUTF8CString(jsString, &buffer, capacity)
        let endIndex = buffer.firstIndex(of: 0) ?? buffer.count
        let bytes = buffer[..<endIndex].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static let bufferShimScript =
            """
            (function() {
              if (typeof self === "undefined") { self = globalThis; }
              if (typeof window === "undefined") { window = globalThis; }
              if (typeof global === "undefined") { global = globalThis; }
              if (typeof setTimeout === "undefined") {
                globalThis.setTimeout = function(fn) { fn(); return 0; };
              }
              if (typeof clearTimeout === "undefined") {
                globalThis.clearTimeout = function() {};
              }
              Object.defineProperty(Error, 'stackTraceLimit', {
                get: function() { return 0; },
                set: function() {},
                configurable: false
              });
              if (typeof Buffer !== "undefined" && typeof Buffer.from === "function") {
                return true;
              }
              function decodeBase64(input) {
                var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                var str = String(input || '').replace(/[^A-Za-z0-9\\+\\/\\=]/g, '');
                var output = '';
                var index = 0;
                while (index < str.length) {
                  var enc1 = chars.indexOf(str.charAt(index++));
                  var enc2 = chars.indexOf(str.charAt(index++));
                  var enc3 = chars.indexOf(str.charAt(index++));
                  var enc4 = chars.indexOf(str.charAt(index++));
                  var chr1 = (enc1 << 2) | (enc2 >> 4);
                  var chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
                  var chr3 = ((enc3 & 3) << 6) | enc4;
                  output += String.fromCharCode(chr1);
                  if (enc3 !== 64 && enc3 !== -1) {
                    output += String.fromCharCode(chr2);
                  }
                  if (enc4 !== 64 && enc4 !== -1) {
                    output += String.fromCharCode(chr3);
                  }
                }
                return output;
              }
              globalThis.Buffer = {
                from: function(value, encoding) {
                  if (encoding !== 'base64') {
                    throw new Error('Unsupported Buffer encoding: ' + encoding);
                  }
                  var binary = decodeBase64(value);
                  return {
                    toString: function() { return binary; }
                  };
                }
              };
              return true;
            })();
            """

    private static let renderFunctionScript =
            """
            (function(source) {
              if (typeof BeautifulMermaid === "undefined" || typeof BeautifulMermaid.renderMermaidASCII !== "function") {
                return JSON.stringify({ supported: false, error: "Mermaid runtime unavailable." });
              }
              try {
                var ascii = BeautifulMermaid.renderMermaidASCII(source);
                return JSON.stringify({ supported: true, ascii: ascii || "" });
              } catch (error) {
                return JSON.stringify({ supported: false, error: String(error) });
              }
            })
            """

    private static let svgRenderFunctionScript =
            """
            (function(source) {
              if (typeof BeautifulMermaid === "undefined" || typeof BeautifulMermaid.renderMermaidSVG !== "function") {
                return JSON.stringify({ supported: false, error: "SVG renderer unavailable." });
              }
              try {
                var svg = BeautifulMermaid.renderMermaidSVG(source);
                return JSON.stringify({ supported: true, svg: svg || "" });
              } catch (error) {
                return JSON.stringify({ supported: false, error: String(error) });
              }
            })
            """
#endif

    private static func decodeASCII(_ rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["supported"] as? Bool == true,
              let ascii = object["ascii"] as? String
        else {
            return nil
        }
        return ascii
    }

    private static func decodeSVG(_ rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["supported"] as? Bool == true,
              let svg = object["svg"] as? String,
              !svg.isEmpty
        else {
            return nil
        }
        return svg
    }
}
