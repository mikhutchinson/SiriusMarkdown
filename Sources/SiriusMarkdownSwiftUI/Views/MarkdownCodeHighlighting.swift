import Foundation
import SwiftUI

#if canImport(JavaScriptCore)
@preconcurrency import JavaScriptCore
#endif

public protocol MarkdownCodeHighlighterCacheIdentifying: Sendable {
    var codeHighlighterCacheIdentity: String { get }
}

public struct MarkdownCodeLanguage: Sendable, Hashable, CustomStringConvertible {
    public enum Classification: String, Sendable, Hashable {
        case unspecified
        case plaintext
        case supported
        case unsupported
    }

    public var rawInfoString: String?
    public var normalizedInfoString: String?
    public var canonicalName: String?
    public var backendName: String?
    public var classification: Classification

    public init(infoString: String?) {
        self.rawInfoString = infoString

        guard let normalized = Self.normalizedToken(from: infoString) else {
            self.normalizedInfoString = nil
            self.canonicalName = nil
            self.backendName = nil
            self.classification = .unspecified
            return
        }

        self.normalizedInfoString = normalized

        if Self.plainTextAliases.contains(normalized) {
            self.canonicalName = "plaintext"
            self.backendName = nil
            self.classification = .plaintext
            return
        }

        let canonical = Self.languageAliases[normalized] ?? normalized
        self.canonicalName = canonical

        if Self.supportedBackendLanguages.contains(canonical) {
            self.backendName = canonical
            self.classification = .supported
        } else {
            self.backendName = nil
            self.classification = .unsupported
        }
    }

    public var shouldHighlight: Bool {
        classification == .supported && backendName != nil
    }

    public var displayName: String? {
        switch classification {
        case .unspecified:
            return nil
        case .plaintext:
            return "Plain text"
        case .supported, .unsupported:
            if let normalizedInfoString, let displayName = Self.displayNames[normalizedInfoString] {
                return displayName
            }
            if let canonicalName, let displayName = Self.displayNames[canonicalName] {
                return displayName
            }
            if let normalizedInfoString {
                return Self.titleCasedDisplayName(normalizedInfoString)
            }
            return nil
        }
    }

    public var cacheIdentity: String {
        switch classification {
        case .unspecified:
            return "unspecified"
        case .plaintext:
            return "plaintext"
        case .supported:
            return "supported:\(backendName ?? canonicalName ?? "")"
        case .unsupported:
            return "unsupported:\(canonicalName ?? normalizedInfoString ?? "")"
        }
    }

    public var description: String {
        cacheIdentity
    }

    private static func normalizedToken(from infoString: String?) -> String? {
        guard var token = firstInfoToken(from: infoString) else {
            return nil
        }

        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix(".") {
            token.removeFirst()
        }

        token = token.lowercased()
        if token.hasPrefix("language-") {
            token.removeFirst("language-".count)
        } else if token.hasPrefix("lang-") {
            token.removeFirst("lang-".count)
        }

        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        return token.isEmpty ? nil : token
    }

    private static func firstInfoToken(from infoString: String?) -> String? {
        guard let infoString else {
            return nil
        }

        let trimmed = infoString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("{"), let endIndex = trimmed.firstIndex(of: "}") {
            let body = trimmed[trimmed.index(after: trimmed.startIndex)..<endIndex]
            for rawPart in body.split(whereSeparator: { $0.isWhitespace }) {
                let part = String(rawPart)
                if part.hasPrefix(".language-") || part.hasPrefix(".lang-") || part.hasPrefix(".") {
                    return part
                }
            }
        }

        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private static let plainTextAliases: Set<String> = [
        "no-highlight", "nohighlight", "none", "plain", "plaintext", "text", "txt"
    ]

    private static let languageAliases: [String: String] = [
        "c++": "cpp",
        "cc": "cpp",
        "cplusplus": "cpp",
        "cxx": "cpp",
        "csharp": "csharp",
        "cs": "csharp",
        "c#": "csharp",
        "docker": "dockerfile",
        "dockerfile": "dockerfile",
        "golang": "go",
        "html": "xml",
        "javascript": "javascript",
        "js": "javascript",
        "jsonl": "json",
        "jsx": "javascript",
        "language-c++": "cpp",
        "mjs": "javascript",
        "md": "markdown",
        "mdown": "markdown",
        "mkd": "markdown",
        "objc": "objectivec",
        "obj-c": "objectivec",
        "objective-c": "objectivec",
        "patch": "diff",
        "py": "python",
        "python3": "python",
        "rb": "ruby",
        "rs": "rust",
        "shell": "bash",
        "sh": "bash",
        "tsx": "typescript",
        "ts": "typescript",
        "yml": "yaml",
        "zsh": "bash"
    ]

    private static let displayNames: [String: String] = [
        "bash": "Bash",
        "c": "C",
        "c++": "C++",
        "cpp": "C++",
        "c#": "C#",
        "csharp": "C#",
        "css": "CSS",
        "diff": "Diff",
        "dockerfile": "Dockerfile",
        "go": "Go",
        "graphql": "GraphQL",
        "html": "HTML",
        "ini": "INI",
        "java": "Java",
        "javascript": "JavaScript",
        "json": "JSON",
        "jsx": "JavaScript",
        "kotlin": "Kotlin",
        "less": "Less",
        "lua": "Lua",
        "makefile": "Makefile",
        "markdown": "Markdown",
        "objective-c": "Objective-C",
        "objectivec": "Objective-C",
        "perl": "Perl",
        "php": "PHP",
        "php-template": "PHP",
        "plaintext": "Plain text",
        "python": "Python",
        "python-repl": "Python REPL",
        "r": "R",
        "ruby": "Ruby",
        "rust": "Rust",
        "scss": "SCSS",
        "sh": "Shell",
        "shell": "Shell",
        "sql": "SQL",
        "swift": "Swift",
        "tsx": "TypeScript",
        "typescript": "TypeScript",
        "vbnet": "VB.NET",
        "wasm": "WebAssembly",
        "xml": "XML",
        "yaml": "YAML",
        "yml": "YAML",
        "zsh": "Zsh"
    ]

    private static let supportedBackendLanguages: Set<String> = [
        "bash", "c", "cpp", "csharp", "css", "diff", "go", "graphql", "ini",
        "java", "javascript", "json", "kotlin", "less", "lua", "makefile",
        "markdown", "objectivec", "perl", "php", "php-template", "plaintext",
        "python", "python-repl", "r", "ruby", "rust", "scss", "shell", "sql",
        "swift", "typescript", "vbnet", "wasm", "xml", "yaml"
    ]

    private static func titleCasedDisplayName(_ token: String) -> String {
        let separators = CharacterSet(charactersIn: "-_")
        let parts = token.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return token
        }

        return parts.map { part in
            guard let first = part.first else {
                return part
            }
            return String(first).uppercased() + String(part.dropFirst())
        }
        .joined(separator: " ")
    }
}

public struct DefaultMarkdownCodeHighlighter: MarkdownCodeHighlighter, MarkdownCodeHighlighterCacheIdentifying {
    public init() {}

    public var codeHighlighterCacheIdentity: String {
        "siriusmarkdown.default.highlightjs.11.11.1"
    }

    public func highlightedCode(_ code: String, infoString: String?) -> AttributedString {
        highlightedCode(code, infoString: infoString, palette: .default)
    }

    public func highlightedCode(
        _ code: String,
        infoString: String?,
        palette: MarkdownSyntaxHighlightingPalette
    ) -> AttributedString {
        let language = MarkdownCodeLanguage(infoString: infoString)
        guard language.shouldHighlight, let backendName = language.backendName else {
            return Self.plainCode(code)
        }

        return HighlightJavaScriptRuntime.shared.highlight(
            code: code,
            language: backendName,
            palette: palette
        ) ?? Self.plainCode(code)
    }

    static func plainCode(_ code: String) -> AttributedString {
        var highlighted = AttributedString(code)
        highlighted.inlinePresentationIntent = .code
        return highlighted
    }
}

private struct HighlightJavaScriptResult: Sendable {
    var value: String
    var language: String
    var illegal: Bool
}

private final class HighlightJavaScriptRuntime: @unchecked Sendable {
    static let shared = HighlightJavaScriptRuntime()

    private let lock = NSLock()

#if canImport(JavaScriptCore)
    private var script: String?
    private var didLoadScript = false
    private var context: JSGlobalContextRef?
    private var highlightFunction: JSObjectRef?
#endif

    private init() {}

    func highlight(
        code: String,
        language: String,
        palette: MarkdownSyntaxHighlightingPalette
    ) -> AttributedString? {
#if canImport(JavaScriptCore)
        return lock.withLock {
            guard let runtime = ensureRuntime(),
                  let rawJSON = callHighlightFunction(
                      runtime.function,
                      context: runtime.context,
                      code: code,
                      language: language
                  ),
                  let result = Self.decodeResult(rawJSON),
                  result.illegal == false
            else {
                return nil
            }

            return HighlightHTMLParser(palette: palette).attributedString(
                from: result.value,
                originalCode: code
            )
        }
#else
        return nil
#endif
    }

#if canImport(JavaScriptCore)
    private func ensureRuntime() -> (context: JSGlobalContextRef, function: JSObjectRef)? {
        if let context, let highlightFunction {
            return (context, highlightFunction)
        }

        guard let script = loadedScript(),
              let context = JSGlobalContextCreate(nil),
              Self.evaluate(script, in: context) != nil,
              let functionValue = Self.evaluate(Self.highlightFunctionScript, in: context),
              JSValueIsObject(context, functionValue)
        else {
            return nil
        }

        var exception: JSValueRef?
        guard let function = JSValueToObject(context, functionValue, &exception),
              exception == nil
        else {
            return nil
        }

        JSValueProtect(context, functionValue)
        self.context = context
        self.highlightFunction = function
        return (context, function)
    }

    private func loadedScript() -> String? {
        if didLoadScript {
            return script
        }

        didLoadScript = true
        guard let scriptURL = Bundle.module.url(forResource: "highlight.min", withExtension: "js")
                  ?? Bundle.module.url(
                      forResource: "highlight.min",
                      withExtension: "js",
                      subdirectory: "HighlightJS"
                  ),
              let contents = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            return nil
        }

        script = contents
        return contents
    }

    private func callHighlightFunction(
        _ function: JSObjectRef,
        context: JSGlobalContextRef,
        code: String,
        language: String
    ) -> String? {
        guard let codeString = Self.makeJSString(code),
              let languageString = Self.makeJSString(language)
        else {
            return nil
        }
        defer {
            JSStringRelease(codeString)
            JSStringRelease(languageString)
        }

        let arguments: [JSValueRef?] = [
            JSValueMakeString(context, codeString),
            JSValueMakeString(context, languageString)
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

    private static let highlightFunctionScript =
            """
            (function(code, language) {
              if (typeof hljs === "undefined" || !language || !hljs.getLanguage(language)) {
                return JSON.stringify({ supported: false });
              }
              try {
                var result = hljs.highlight(code, { language: language, ignoreIllegals: false });
                return JSON.stringify({
                  supported: true,
                  illegal: !!result.illegal,
                  language: result.language || language,
                  value: result.value || ""
                });
              } catch (error) {
                return JSON.stringify({ supported: false, error: String(error) });
              }
            })
            """
#endif

    private static func decodeResult(_ rawJSON: String) -> HighlightJavaScriptResult? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["supported"] as? Bool == true,
              let value = object["value"] as? String,
              let language = object["language"] as? String
        else {
            return nil
        }

        return HighlightJavaScriptResult(
            value: value,
            language: language,
            illegal: object["illegal"] as? Bool ?? false
        )
    }
}

private struct HighlightHTMLParser {
    var palette: MarkdownSyntaxHighlightingPalette

    func attributedString(from html: String, originalCode: String) -> AttributedString? {
        var result = AttributedString()
        var buffer = ""
        var classStack: [[String]] = []
        var cursor = html.startIndex

        func activeClasses() -> [String] {
            classStack.flatMap { $0 }
        }

        func flushBuffer() {
            guard !buffer.isEmpty else {
                return
            }

            var piece = AttributedString(buffer)
            piece.inlinePresentationIntent = .code
            if let foregroundColor = palette.foregroundColor(for: activeClasses()) {
                piece.foregroundColor = foregroundColor
            }
            result.append(piece)
            buffer.removeAll(keepingCapacity: true)
        }

        while cursor < html.endIndex {
            let character = html[cursor]
            if character == "<", let close = html[cursor...].firstIndex(of: ">") {
                flushBuffer()
                let tagStart = html.index(after: cursor)
                let tag = String(html[tagStart..<close])
                handle(tag: tag, classStack: &classStack)
                cursor = html.index(after: close)
                continue
            }

            if character == "&",
               let decoded = decodedEntity(in: html, startingAt: cursor)
            {
                buffer.append(decoded.value)
                cursor = decoded.endIndex
                continue
            }

            buffer.append(character)
            cursor = html.index(after: cursor)
        }

        flushBuffer()

        guard String(result.characters) == originalCode else {
            return nil
        }

        return result
    }

    private func handle(tag: String, classStack: inout [[String]]) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/span" {
            _ = classStack.popLast()
            return
        }

        guard trimmed.hasPrefix("span") else {
            return
        }

        classStack.append(classes(in: trimmed))
    }

    private func classes(in tag: String) -> [String] {
        guard let classRange = tag.range(of: "class=") else {
            return []
        }

        var remainder = tag[classRange.upperBound...]
        remainder = remainder.drop(while: { $0.isWhitespace })
        guard let quote = remainder.first, quote == "\"" || quote == "'" else {
            return []
        }

        remainder = remainder.dropFirst()
        guard let end = remainder.firstIndex(of: quote) else {
            return []
        }

        return remainder[..<end]
            .split(whereSeparator: { $0.isWhitespace })
            .map { rawClass in
                var value = String(rawClass)
                if value.hasPrefix("hljs-") {
                    value.removeFirst("hljs-".count)
                }
                return value
            }
    }

    private func decodedEntity(
        in html: String,
        startingAt ampersand: String.Index
    ) -> (value: String, endIndex: String.Index)? {
        guard let semicolon = html[ampersand...].firstIndex(of: ";") else {
            return nil
        }

        let entityStart = html.index(after: ampersand)
        let rawEntity = String(html[entityStart..<semicolon])
        let endIndex = html.index(after: semicolon)

        switch rawEntity {
        case "amp":
            return ("&", endIndex)
        case "apos", "#39", "#x27":
            return ("'", endIndex)
        case "gt":
            return (">", endIndex)
        case "lt":
            return ("<", endIndex)
        case "quot":
            return ("\"", endIndex)
        default:
            if rawEntity.hasPrefix("#x"),
               let scalarValue = UInt32(rawEntity.dropFirst(2), radix: 16),
               let scalar = UnicodeScalar(scalarValue)
            {
                return (String(scalar), endIndex)
            }
            if rawEntity.hasPrefix("#"),
               let scalarValue = UInt32(rawEntity.dropFirst(), radix: 10),
               let scalar = UnicodeScalar(scalarValue)
            {
                return (String(scalar), endIndex)
            }
            return nil
        }
    }
}
