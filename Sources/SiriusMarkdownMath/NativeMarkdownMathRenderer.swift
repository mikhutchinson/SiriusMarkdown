import Foundation
import SiriusMarkdownSwiftUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct NativeMarkdownMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying {
    public init() {}

    /// Rasterization scale matching the screen's backing scale (min 2.0 for
    /// sharp glyphs on non-Retina displays). Resolved lazily on first access
    /// since `UIScreen`/`NSScreen` queries must happen on the main thread.
    static let renderScale: Double = NativeMarkdownMathRenderer.resolveBackingScale()

    private static func resolveBackingScale() -> Double {
        if Thread.isMainThread {
            return resolveBackingScaleOnMain()
        }
        var scale: Double = 3.0
        DispatchQueue.main.sync {
            scale = resolveBackingScaleOnMain()
        }
        return scale
    }

    private static func resolveBackingScaleOnMain() -> Double {
        #if canImport(UIKit)
        return max(2.0, Double(UIScreen.main?.scale ?? 2.0))
        #elseif canImport(AppKit)
        return max(2.0, Double(NSScreen.main?.backingScaleFactor ?? 2.0))
        #else
        return 3.0
        #endif
    }

    public var mathRendererCacheIdentity: String {
        #if canImport(SwiftMath)
        return "siriusmarkdown.native-math.swiftmath.1.7.3.scale\(Int(Self.renderScale)).compat5-layoutinfo"
        #else
        return "siriusmarkdown.native-math.unicode-fallback.v1"
        #endif
    }

    public func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
        #if canImport(SwiftMath)
        if let image = SwiftMathTypesetter.shared.preparedImage(
            latex: source,
            isBlock: isBlock,
            fontSize: fontSize,
            scale: Self.renderScale
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
        var result = source
        for replacement in replacements {
            result = result.replacingOccurrences(of: replacement.key, with: replacement.value)
        }

        result = replaceSuperscriptDigits(in: result)
        result = replaceSubscriptDigits(in: result)
        return result
    }

    private static let replacements: [(key: String, value: String)] = [
        ("\\rightarrow", "→"),
        ("\\leftarrow", "←"),
        ("\\leq", "≤"),
        ("\\geq", "≥"),
        ("\\neq", "≠"),
        ("\\times", "×"),
        ("\\cdot", "·"),
        ("\\alpha", "α"),
        ("\\beta", "β"),
        ("\\gamma", "γ"),
        ("\\delta", "δ"),
        ("\\lambda", "λ"),
        ("\\pi", "π"),
        ("\\theta", "θ"),
        ("\\sum", "∑"),
        ("\\int", "∫")
    ]

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
                var valueCursor = source.index(after: next)
                var replaced = ""
                while valueCursor < source.endIndex, source[valueCursor] != "}" {
                    if let replacement = digits[source[valueCursor]] {
                        replaced.append(replacement)
                    } else {
                        replaced.append(source[valueCursor])
                    }
                    valueCursor = source.index(after: valueCursor)
                }

                guard valueCursor < source.endIndex else {
                    result.append(source[cursor])
                    cursor = next
                    continue
                }

                result.append(replaced)
                cursor = source.index(after: valueCursor)
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

    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
    ]

    private static let subscriptDigits: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
    ]
}
