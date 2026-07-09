import Foundation
import SiriusMarkdownSwiftUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NativeMarkdownMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying, MarkdownMathRendererFallbackDiagnosing {
    private static let maximumRenderableFontSize = 512.0

    private let rasterizationScale: Double

    public init() {
        self.rasterizationScale = Self.resolveBackingScale()
    }

    init(rasterizationScaleForTesting rasterizationScale: Double) {
        self.rasterizationScale = rasterizationScale
    }

    /// Rasterization scale for math images. Main-thread callers use the
    /// screen's backing scale; background preparation uses a nonblocking
    /// Retina fallback because callers may be running while the main actor is
    /// synchronously waiting for prepared content.
    static var renderScale: Double {
        NativeMarkdownMathRenderer.resolveBackingScale()
    }

    static func resolveBackingScaleForTesting() -> Double {
        resolveBackingScale()
    }

    private static func resolveBackingScale() -> Double {
        guard Thread.isMainThread else {
            return 2.0
        }

        return MainActor.assumeIsolated {
            resolveBackingScaleOnMain()
        }
    }

    @MainActor
    private static func resolveBackingScaleOnMain() -> Double {
        #if os(visionOS) || os(watchOS)
        return 2.0
        #elseif canImport(UIKit)
        return max(2.0, Double(UIScreen.main.scale))
        #elseif canImport(AppKit)
        return max(2.0, Double(NSScreen.main?.backingScaleFactor ?? 2.0))
        #else
        return 3.0
        #endif
    }

    public var mathRendererCacheIdentity: String {
        #if canImport(SwiftMath)
        return "siriusmarkdown.native-math.swiftmath.1.7.3.scale\(Self.cacheIdentityScaleComponent(rasterizationScale)).compat7-diagnostics"
        #else
        return "siriusmarkdown.native-math.unicode-fallback.v1"
        #endif
    }

    private static func cacheIdentityScaleComponent(_ scale: Double) -> String {
        scale.description
    }

    public var recordsTextFallbackAsMathFallback: Bool {
        true
    }

    public func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
        guard fontSize.isFinite, fontSize > 0, fontSize <= Self.maximumRenderableFontSize else {
            return .text(renderedMath(source, isBlock: isBlock))
        }

        #if canImport(SwiftMath)
        if let image = SwiftMathTypesetter.shared.preparedImage(
            latex: source,
            isBlock: isBlock,
            fontSize: fontSize,
            scale: rasterizationScale
        ) {
            return .image(image)
        }
        #endif
        return .text(renderedMath(source, isBlock: isBlock))
    }

    public func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        var rendered = AttributedString(Self.normalizedMath(source))
        rendered.inlinePresentationIntent = .code
        rendered.foregroundColor = isBlock ? .primary : .secondary
        return rendered
    }

    public static func normalizedMath(_ source: String) -> String {
        var result = replaceKnownCommands(in: source)
        result = replaceSuperscriptDigits(in: result)
        result = replaceSubscriptDigits(in: result)
        return result
    }

    private static let commandReplacements: [String: Character] = [
        "rightarrow": "→",
        "leftarrow": "←",
        "leq": "≤",
        "geq": "≥",
        "neq": "≠",
        "times": "×",
        "cdot": "·",
        "alpha": "α",
        "beta": "β",
        "gamma": "γ",
        "delta": "δ",
        "lambda": "λ",
        "pi": "π",
        "theta": "θ",
        "sum": "∑",
        "int": "∫"
    ]

    private static func replaceKnownCommands(in source: String) -> String {
        var result = ""
        var cursor = source.startIndex

        while cursor < source.endIndex {
            guard source[cursor] == "\\" else {
                result.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }

            let commandStart = source.index(after: cursor)
            guard commandStart < source.endIndex else {
                result.append("\\")
                break
            }
            if source[commandStart] == "\\" {
                result.append(contentsOf: source[cursor...commandStart])
                cursor = source.index(after: commandStart)
                continue
            }

            var commandEnd = commandStart
            while commandEnd < source.endIndex, isASCIILetter(source[commandEnd]) {
                commandEnd = source.index(after: commandEnd)
            }
            guard commandEnd > commandStart else {
                result.append("\\")
                cursor = commandStart
                continue
            }

            let command = String(source[commandStart..<commandEnd])
            if let replacement = commandReplacements[command] {
                result.append(replacement)
            } else {
                result.append(contentsOf: source[cursor..<commandEnd])
            }
            cursor = commandEnd
        }

        return result
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value
        else {
            return false
        }
        return (65...90).contains(value) || (97...122).contains(value)
    }

    private static func replaceSuperscriptDigits(in source: String) -> String {
        replaceScriptDigits(in: source, marker: "^", digits: superscriptDigits)
    }

    private static func replaceSubscriptDigits(in source: String) -> String {
        replaceScriptDigits(in: source, marker: "_", digits: subscriptDigits)
    }

    private static func replaceScriptDigits(
        in source: String,
        marker: Character,
        digits: [Character: Character]
    ) -> String {
        var result = ""
        var cursor = source.startIndex

        while cursor < source.endIndex {
            if source[cursor] == "\\" {
                result.append("\\")
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    result.append(source[cursor])
                    cursor = source.index(after: cursor)
                }
                continue
            }

            guard source[cursor] == marker else {
                result.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }

            let next = source.index(after: cursor)
            guard next < source.endIndex else {
                result.append(source[cursor])
                cursor = next
                continue
            }

            if source[next] == "{" {
                if let group = bracedScriptGroup(in: source, openingBrace: next, digits: digits) {
                    if let replacement = group.replacement {
                        result.append(replacement)
                    } else {
                        result.append(contentsOf: source[cursor..<group.upperBound])
                    }
                    cursor = group.upperBound
                } else {
                    result.append(contentsOf: source[cursor...])
                    cursor = source.endIndex
                }
            } else if let replacement = digits[source[next]] {
                result.append(replacement)
                cursor = source.index(after: next)
            } else {
                result.append(source[cursor])
                cursor = next
            }
        }

        return result
    }

    private static func bracedScriptGroup(
        in source: String,
        openingBrace: String.Index,
        digits: [Character: Character]
    ) -> (upperBound: String.Index, replacement: String?)? {
        var cursor = source.index(after: openingBrace)
        var depth = 1
        var replacement = ""
        var isDigitOnly = true

        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "\\" {
                isDigitOnly = false
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }
            if character == "{" {
                depth += 1
                isDigitOnly = false
                cursor = source.index(after: cursor)
                continue
            }
            if character == "}" {
                depth -= 1
                let upperBound = source.index(after: cursor)
                if depth == 0 {
                    return (upperBound, isDigitOnly && !replacement.isEmpty ? replacement : nil)
                }
                cursor = upperBound
                continue
            }
            if depth == 1, let digit = digits[character] {
                replacement.append(digit)
            } else {
                isDigitOnly = false
            }
            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
    ]

    private static let subscriptDigits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
    ]
}
