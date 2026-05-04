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
    public var darkSVG: String?

    public init(
        source: String,
        sourceRange: MarkdownSourceRange?,
        ascii: String,
        svg: String? = nil,
        darkSVG: String? = nil
    ) {
        self.source = source
        self.sourceRange = sourceRange
        self.ascii = ascii
        self.svg = svg
        self.darkSVG = darkSVG
    }
}

public struct DefaultMarkdownMermaidRenderer: MarkdownMermaidRenderer, MarkdownMermaidRendererCacheIdentifying {
    public init() {}

    public var mermaidRendererCacheIdentity: String {
        "siriusmarkdown.default.beautiful-mermaid.1.1.4.resolved-svg"
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
            svg: result.svg,
            darkSVG: result.darkSVG
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
    var darkSVG: String?
}

private struct MermaidSVGPalette: Sendable {
    var background: String
    var foreground: String
    var line: String
    var accent: String
    var muted: String
    var surface: String
    var border: String
    var transparent: Bool

    static func light(theme: MarkdownTheme) -> MermaidSVGPalette {
        MermaidSVGPalette(
            background: "#F8FAFC",
            foreground: "#1F2937",
            line: "#94A3B8",
            accent: hex(theme.syntaxHighlightingPalette.section, fallback: "#2563EB"),
            muted: "#64748B",
            surface: "#FFFFFF",
            border: "#CBD5E1",
            transparent: true
        )
    }

    static func dark(theme: MarkdownTheme) -> MermaidSVGPalette {
        MermaidSVGPalette(
            background: "#2F3136",
            foreground: "#F3F4F6",
            line: "#9CA3AF",
            accent: softenedAccent(theme.syntaxHighlightingPalette.section),
            muted: "#A1A1AA",
            surface: "#3A3D43",
            border: "#62666F",
            transparent: true
        )
    }

    var javaScriptOptionsJSON: String {
        let payload: [String: Any] = [
            "bg": background,
            "fg": foreground,
            "line": line,
            "accent": accent,
            "muted": muted,
            "surface": surface,
            "border": border,
            "transparent": transparent,
            "font": "-apple-system, BlinkMacSystemFont, 'SF Pro Text'"
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    var resolvedVariables: [String: String] {
        [
            "bg": background,
            "fg": foreground,
            "line": line,
            "accent": accent,
            "muted": muted,
            "surface": surface,
            "border": border,
            "_text": foreground,
            "_text-sec": muted,
            "_text-muted": muted,
            "_text-faint": Self.mix(foreground, 0.25, background, 0.75),
            "_line": line,
            "_arrow": accent,
            "_node-fill": surface,
            "_node-stroke": border,
            "_group-fill": background,
            "_group-hdr": Self.mix(foreground, 0.05, background, 0.95),
            "_inner-stroke": Self.mix(foreground, 0.12, background, 0.88),
            "_key-badge": Self.mix(foreground, 0.10, background, 0.90)
        ]
    }

    private static func hex(_ color: MarkdownSyntaxHighlightingColor, fallback: String) -> String {
        guard color.opacity > 0 else {
            return fallback
        }
        return String(
            format: "#%02X%02X%02X",
            clampToByte(color.red),
            clampToByte(color.green),
            clampToByte(color.blue)
        )
    }

    private static func softenedAccent(_ color: MarkdownSyntaxHighlightingColor) -> String {
        let base = hex(color, fallback: "#60A5FA")
        return mix(base, 0.55, "#FFFFFF", 0.45)
    }

    private static func clampToByte(_ value: Double) -> Int {
        Int((min(1, max(0, value)) * 255).rounded())
    }

    private static func mix(_ first: String, _ firstWeight: Double, _ second: String, _ secondWeight: Double) -> String {
        guard let a = RGB(hex: first), let b = RGB(hex: second) else {
            return first
        }

        let total = firstWeight + secondWeight
        guard total > 0 else {
            return first
        }

        return String(
            format: "#%02X%02X%02X",
            clampToByte((Double(a.red) * firstWeight + Double(b.red) * secondWeight) / total / 255),
            clampToByte((Double(a.green) * firstWeight + Double(b.green) * secondWeight) / total / 255),
            clampToByte((Double(a.blue) * firstWeight + Double(b.blue) * secondWeight) / total / 255)
        )
    }

    private struct RGB {
        var red: Int
        var green: Int
        var blue: Int

        init?(hex: String) {
            let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard value.count == 6, let integer = Int(value, radix: 16) else {
                return nil
            }
            red = (integer >> 16) & 0xFF
            green = (integer >> 8) & 0xFF
            blue = integer & 0xFF
        }
    }
}

private enum MermaidSVGPostProcessor {
    static func rasterCompatibleSVG(_ svg: String, palette: MermaidSVGPalette) -> String {
        var result = svg
        for (variable, value) in palette.resolvedVariables.sorted(by: { $0.key.count > $1.key.count }) {
            result = replacingCSSVariable(variable, with: value, in: result)
        }
        return result
    }

    private static func replacingCSSVariable(_ variable: String, with value: String, in input: String) -> String {
        let needle = "var(--\(variable)"
        var output = ""
        var searchStart = input.startIndex

        while let range = input[searchStart...].range(of: needle) {
            output.append(contentsOf: input[searchStart..<range.lowerBound])
            var cursor = range.upperBound
            skipWhitespace(in: input, from: &cursor)

            if cursor < input.endIndex, input[cursor] == ")" {
                output.append(value)
                searchStart = input.index(after: cursor)
                continue
            }

            if cursor < input.endIndex, input[cursor] == "," {
                cursor = input.index(after: cursor)
                var depth = 1
                while cursor < input.endIndex {
                    if input[cursor] == "(" {
                        depth += 1
                    } else if input[cursor] == ")" {
                        depth -= 1
                        if depth == 0 {
                            output.append(value)
                            searchStart = input.index(after: cursor)
                            break
                        }
                    }
                    cursor = input.index(after: cursor)
                }
                if depth == 0 {
                    continue
                }
            }

            output.append(contentsOf: input[range.lowerBound..<range.upperBound])
            searchStart = range.upperBound
        }

        output.append(contentsOf: input[searchStart...])
        return output
    }

    private static func skipWhitespace(in string: String, from index: inout String.Index) {
        while index < string.endIndex, string[index].isWhitespace {
            index = string.index(after: index)
        }
    }
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
            let lightPalette = MermaidSVGPalette.light(theme: theme)
            if let svgJSON = callRenderFunction(
                runtime.svgFunction,
                context: runtime.context,
                source: source,
                optionsJSON: lightPalette.javaScriptOptionsJSON
            ) {
                svg = Self.decodeSVG(svgJSON).map {
                    MermaidSVGPostProcessor.rasterCompatibleSVG($0, palette: lightPalette)
                }
            }

            var darkSVG: String?
            let darkPalette = MermaidSVGPalette.dark(theme: theme)
            if let svgJSON = callRenderFunction(
                runtime.svgFunction,
                context: runtime.context,
                source: source,
                optionsJSON: darkPalette.javaScriptOptionsJSON
            ) {
                darkSVG = Self.decodeSVG(svgJSON).map {
                    MermaidSVGPostProcessor.rasterCompatibleSVG($0, palette: darkPalette)
                }
            }

            guard let asciiResult = ascii else {
                return nil
            }

            let trimmed = asciiResult.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            return MermaidJavaScriptResult(ascii: trimmed, svg: svg, darkSVG: darkSVG)
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
        source: String,
        optionsJSON: String? = nil
    ) -> String? {
        guard let sourceString = Self.makeJSString(source) else {
            return nil
        }
        defer {
            JSStringRelease(sourceString)
        }

        var arguments: [JSValueRef?] = [
            JSValueMakeString(context, sourceString)
        ]
        var optionsString: JSStringRef?
        if let optionsJSON {
            optionsString = Self.makeJSString(optionsJSON)
            if let optionsString {
                arguments.append(JSValueMakeString(context, optionsString))
            }
        }
        defer {
            if let optionsString {
                JSStringRelease(optionsString)
            }
        }

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
            (function(source, optionsJSON) {
              if (typeof BeautifulMermaid === "undefined" || typeof BeautifulMermaid.renderMermaidSVG !== "function") {
                return JSON.stringify({ supported: false, error: "SVG renderer unavailable." });
              }
              try {
                var options = {};
                if (optionsJSON) {
                  options = JSON.parse(optionsJSON);
                }
                var svg = BeautifulMermaid.renderMermaidSVG(source, options);
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
