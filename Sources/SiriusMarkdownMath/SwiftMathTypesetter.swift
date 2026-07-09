import Foundation
import SiriusMarkdownSwiftUI

#if canImport(SwiftMath)
import SwiftMath

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Bridges vendored SwiftMath `MTMathImage` CoreText typesetting into a
/// `Sendable` `MarkdownPreparedMathImage`.
///
/// `SwiftMath`'s typesetting objects are reference types and are not `Sendable`,
/// so all access is confined behind a single lock (mirroring the package's
/// `MermaidJavaScriptRuntime`). The lock yields only value types: PNG data plus
/// point metrics from `MTMathImage.LayoutInfo` (`MTMathListDisplay` ascent/
/// descent). Glyphs are rasterized in opaque black so the bitmap's alpha
/// channel encodes coverage; the SwiftUI layer draws it as a theme-tinted
/// template image.
///
/// `MTMathImage` is preferred over `MathImage` here because its font path uses
/// `MTFont.fontBundle` (filesystem probe, no generated `Bundle.module` access),
/// which is the packaging-safe path covered by `canEnterSwiftMath` (INV-M7).
final class SwiftMathTypesetter: @unchecked Sendable {
    static let shared = SwiftMathTypesetter()

    private static let maximumFontSize = 512.0
    private static let maximumRasterizationScale = 8.0
    private static let maximumRasterPixelDimension = 16_384.0
    private static let maximumRasterPixelCount = 16_777_216.0

    private let lock = NSLock()

    private init() {}

    func preparedImage(
        latex: String,
        isBlock: Bool,
        fontSize: Double,
        scale: Double
    ) -> MarkdownPreparedMathImage? {
        guard fontSize.isFinite,
              fontSize > 0,
              fontSize <= Self.maximumFontSize,
              scale.isFinite,
              scale > 0,
              scale <= Self.maximumRasterizationScale else {
            return nil
        }

        guard Self.canEnterSwiftMath() else {
            return nil
        }

        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return lock.withLock {
            for typesetLatex in Self.swiftMathLatexCandidates(for: latex) {
                guard Self.canPreserveSwiftMathInput(typesetLatex) else {
                    continue
                }
                if let prepared = Self.makePreparedImage(
                    typesetLatex: typesetLatex,
                    originalLatex: latex,
                    isBlock: isBlock,
                    fontSize: fontSize,
                    scale: scale
                ) {
                    return prepared
                }
            }

            return nil
        }
    }

    private static func makePreparedImage(
        typesetLatex: String,
        originalLatex: String,
        isBlock: Bool,
        fontSize: Double,
        scale: Double
    ) -> MarkdownPreparedMathImage? {
        let mathImage = MTMathImage(
            latex: typesetLatex,
            fontSize: CGFloat(fontSize),
            textColor: MTColor.black,
            labelMode: isBlock ? .display : .text,
            textAlignment: .left
        )

        let (error, image, layout) = mathImage.asImage()
        guard error == nil,
              let image,
              let layout,
              image.size.width > 0,
              image.size.height > 0
        else {
            return nil
        }

        let pointWidth = Double(image.size.width)
        let pointHeight = Double(image.size.height)
        guard let imageData = Self.pngData(from: image, scale: CGFloat(scale)) else {
            return nil
        }

        let (ascent, descent) = Self.metricsMatchingImageHeight(
            layout: layout,
            pointHeight: pointHeight,
            fontSize: fontSize
        )

        return MarkdownPreparedMathImage(
            imageData: imageData,
            scale: scale,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            ascent: ascent,
            descent: descent,
            latex: originalLatex
        )
    }

    /// Maps `MTMathImage.LayoutInfo` onto the rasterized image so
    /// `ascent + descent == pointHeight` and `-descent` matches the bitmap
    /// baseline produced by `MTMathImage.layoutImage`.
    ///
    /// SwiftMath positions the display-list baseline at
    /// `(availableHeight - max(contentHeight, fontSize/2)) / 2 + descent`
    /// from the image bottom (plus bottom content inset). Splitting leftover
    /// height evenly would disagree with that formula whenever the
    /// `fontSize/2` floor is active.
    private static func metricsMatchingImageHeight(
        layout: MTMathImage.LayoutInfo,
        pointHeight: Double,
        fontSize: Double,
        contentInsetsTop: Double = 0,
        contentInsetsBottom: Double = 0
    ) -> (ascent: Double, descent: Double) {
        let layoutAscent = max(0, Double(layout.ascent))
        let layoutDescent = max(0, Double(layout.descent))
        let availableHeight = pointHeight - contentInsetsTop - contentInsetsBottom
        guard availableHeight > 0 else {
            return (ascent: max(0, pointHeight), descent: 0)
        }

        let contentHeight = layoutAscent + layoutDescent
        let layoutHeight = max(contentHeight, fontSize / 2)
        let baselineFromBottom =
            (availableHeight - layoutHeight) / 2 + layoutDescent + contentInsetsBottom
        let descent = min(pointHeight, max(0, baselineFromBottom))
        return (ascent: pointHeight - descent, descent: descent)
    }

    private static func swiftMathLatexCandidates(for latex: String) -> [String] {
        let compatible = swiftMathCompatibleLatex(latex)
        return compatible == latex ? [latex] : [latex, compatible]
    }

    private static func swiftMathCompatibleLatex(_ latex: String) -> String {
        replacingUnsupportedShorthandCommands(
            in: replacingCasesEnvironment(
                in: replacingArrayEnvironments(
                    in: replacingEnvironmentAliases(
                        in: replacingOperatorNameCommands(
                            in: replacingUnicodeMathShorthands(in: latex)
                        )
                    )
                )
            )
        )
    }

    private static func canPreserveSwiftMathInput(_ latex: String) -> Bool {
        var cursor = latex.startIndex
        while cursor < latex.endIndex {
            let character = latex[cursor]
            if character == "\\" {
                cursor = latex.index(after: cursor)
                if cursor < latex.endIndex, isASCIILetter(latex[cursor]) {
                    repeat {
                        cursor = latex.index(after: cursor)
                    } while cursor < latex.endIndex && isASCIILetter(latex[cursor])
                } else if cursor < latex.endIndex {
                    guard latex[cursor].unicodeScalars.allSatisfy({ $0.value <= 0x7E }) else {
                        return false
                    }
                    cursor = latex.index(after: cursor)
                }
                continue
            }

            guard character.unicodeScalars.allSatisfy({ $0.value <= 0x7E }) else {
                return false
            }
            cursor = latex.index(after: cursor)
        }

        return true
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value
        else {
            return false
        }

        return (65...90).contains(value) || (97...122).contains(value)
    }

    private static func replacingUnicodeMathShorthands(in latex: String) -> String {
        var result = ""
        var cursor = latex.startIndex

        while cursor < latex.endIndex {
            let character = latex[cursor]
            if character == "\\" {
                result.append(character)
                cursor = latex.index(after: cursor)
                if cursor < latex.endIndex, !isASCIILetter(latex[cursor]) {
                    result.append(latex[cursor])
                    cursor = latex.index(after: cursor)
                }
            } else if let subscriptValue = unicodeSubscriptReplacement(character) {
                let (replacement, upperBound) = unicodeScriptRunReplacement(
                    in: latex,
                    from: cursor,
                    marker: "_",
                    firstValue: subscriptValue,
                    transform: unicodeSubscriptReplacement
                )
                result.append(replacement)
                cursor = upperBound
            } else if let superscriptValue = unicodeSuperscriptReplacement(character) {
                let (replacement, upperBound) = unicodeScriptRunReplacement(
                    in: latex,
                    from: cursor,
                    marker: "^",
                    firstValue: superscriptValue,
                    transform: unicodeSuperscriptReplacement
                )
                result.append(replacement)
                cursor = upperBound
            } else if let command = unicodeMathCommandReplacement(character) {
                result.append("\\")
                result.append(command)
                result.append(" ")
                cursor = latex.index(after: cursor)
            } else {
                result.append(character)
                cursor = latex.index(after: cursor)
            }
        }

        return result
    }

    private static func unicodeScriptRunReplacement(
        in latex: String,
        from lowerBound: String.Index,
        marker: Character,
        firstValue: Character,
        transform: (Character) -> Character?
    ) -> (replacement: String, upperBound: String.Index) {
        var values = [firstValue]
        var cursor = latex.index(after: lowerBound)

        while cursor < latex.endIndex, let value = transform(latex[cursor]) {
            values.append(value)
            cursor = latex.index(after: cursor)
        }

        return ("\(marker){\(String(values))}", cursor)
    }

    private static func unicodeSubscriptReplacement(_ character: Character) -> Character? {
        switch character {
        case "₀": return "0"
        case "₁": return "1"
        case "₂": return "2"
        case "₃": return "3"
        case "₄": return "4"
        case "₅": return "5"
        case "₆": return "6"
        case "₇": return "7"
        case "₈": return "8"
        case "₉": return "9"
        case "₊": return "+"
        case "₋": return "-"
        case "₌": return "="
        case "₍": return "("
        case "₎": return ")"
        case "ₐ": return "a"
        case "ₑ": return "e"
        case "ₕ": return "h"
        case "ᵢ": return "i"
        case "ⱼ": return "j"
        case "ₖ": return "k"
        case "ₗ": return "l"
        case "ₘ": return "m"
        case "ₙ": return "n"
        case "ₒ": return "o"
        case "ₚ": return "p"
        case "ᵣ": return "r"
        case "ₛ": return "s"
        case "ₜ": return "t"
        case "ᵤ": return "u"
        case "ᵥ": return "v"
        case "ₓ": return "x"
        default: return nil
        }
    }

    private static func unicodeSuperscriptReplacement(_ character: Character) -> Character? {
        switch character {
        case "⁰": return "0"
        case "¹": return "1"
        case "²": return "2"
        case "³": return "3"
        case "⁴": return "4"
        case "⁵": return "5"
        case "⁶": return "6"
        case "⁷": return "7"
        case "⁸": return "8"
        case "⁹": return "9"
        case "⁺": return "+"
        case "⁻": return "-"
        case "⁼": return "="
        case "⁽": return "("
        case "⁾": return ")"
        case "ᴬ": return "A"
        case "ᴮ": return "B"
        case "ᴰ": return "D"
        case "ᴱ": return "E"
        case "ᴳ": return "G"
        case "ᴴ": return "H"
        case "ᴵ": return "I"
        case "ᴶ": return "J"
        case "ᴷ": return "K"
        case "ᴸ": return "L"
        case "ᴹ": return "M"
        case "ᴺ": return "N"
        case "ᴼ": return "O"
        case "ᴾ": return "P"
        case "ᴿ": return "R"
        case "ᵀ": return "T"
        case "ᵁ": return "U"
        case "ⱽ": return "V"
        case "ᵂ": return "W"
        case "ᵃ": return "a"
        case "ᵇ": return "b"
        case "ᶜ": return "c"
        case "ᵈ": return "d"
        case "ᵉ": return "e"
        case "ᶠ": return "f"
        case "ᵍ": return "g"
        case "ʰ": return "h"
        case "ⁱ": return "i"
        case "ʲ": return "j"
        case "ᵏ": return "k"
        case "ˡ": return "l"
        case "ᵐ": return "m"
        case "ⁿ": return "n"
        case "ᵒ": return "o"
        case "ᵖ": return "p"
        case "ʳ": return "r"
        case "ˢ": return "s"
        case "ᵗ": return "t"
        case "ᵘ": return "u"
        case "ᵛ": return "v"
        case "ʷ": return "w"
        case "ˣ": return "x"
        case "ʸ": return "y"
        case "ᶻ": return "z"
        default: return nil
        }
    }

    private static func unicodeMathCommandReplacement(_ character: Character) -> String? {
        switch character {
        case "α": return "alpha"
        case "β": return "beta"
        case "γ": return "gamma"
        case "δ": return "delta"
        case "ε": return "varepsilon"
        case "ζ": return "zeta"
        case "η": return "eta"
        case "θ": return "theta"
        case "ι": return "iota"
        case "κ": return "kappa"
        case "λ": return "lambda"
        case "μ": return "mu"
        case "ν": return "nu"
        case "ξ": return "xi"
        case "π": return "pi"
        case "ρ": return "rho"
        case "σ": return "sigma"
        case "τ": return "tau"
        case "υ": return "upsilon"
        case "φ": return "varphi"
        case "χ": return "chi"
        case "ψ": return "psi"
        case "ω": return "omega"
        case "ϵ": return "epsilon"
        case "ϑ": return "vartheta"
        case "ϕ": return "phi"
        case "Γ": return "Gamma"
        case "Δ": return "Delta"
        case "Θ": return "Theta"
        case "Λ": return "Lambda"
        case "Ξ": return "Xi"
        case "Π": return "Pi"
        case "Σ": return "Sigma"
        case "Υ": return "Upsilon"
        case "Φ": return "Phi"
        case "Ψ": return "Psi"
        case "Ω": return "Omega"
        case "←": return "leftarrow"
        case "→": return "rightarrow"
        case "⇐": return "Leftarrow"
        case "⇒": return "Rightarrow"
        case "⇔": return "Leftrightarrow"
        case "≤": return "leq"
        case "≥": return "geq"
        case "≠": return "neq"
        case "∈": return "in"
        case "∉": return "notin"
        case "≈": return "approx"
        case "⊂": return "subset"
        case "⊃": return "supset"
        case "⊆": return "subseteq"
        case "⊇": return "supseteq"
        case "×": return "times"
        case "÷": return "div"
        case "±": return "pm"
        case "∓": return "mp"
        case "∩": return "cap"
        case "∪": return "cup"
        case "·", "⋅": return "cdot"
        case "ℏ": return "hbar"
        case "∞": return "infty"
        default: return nil
        }
    }

    private static func replacingEnvironmentAliases(in latex: String) -> String {
        var result = latex
        for wrapper in ["equation", "equation*", "displaymath"] {
            result = result
                .replacingOccurrences(of: "\\begin{\(wrapper)}", with: "")
                .replacingOccurrences(of: "\\end{\(wrapper)}", with: "")
        }

        for (source, target) in [
            ("align", "aligned"),
            ("align*", "aligned"),
            ("multline", "gather"),
            ("multline*", "gather")
        ] {
            result = result
                .replacingOccurrences(of: "\\begin{\(source)}", with: "\\begin{\(target)}")
                .replacingOccurrences(of: "\\end{\(source)}", with: "\\end{\(target)}")
        }

        return result
    }

    private static func replacingArrayEnvironments(in latex: String) -> String {
        var result = ""
        var cursor = latex.startIndex
        let token = "\\begin{array}"

        while cursor < latex.endIndex {
            guard latex[cursor...].hasPrefix(token),
                  let afterToken = latex.index(cursor, offsetBy: token.count, limitedBy: latex.endIndex)
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            var specStart = afterToken
            if specStart < latex.endIndex, latex[specStart] == "[" {
                guard let optionalEnd = balancedGroupContentEnd(
                    in: latex,
                    contentStart: latex.index(after: specStart),
                    open: "[",
                    close: "]"
                ) else {
                    result.append(latex[cursor])
                    cursor = latex.index(after: cursor)
                    continue
                }
                specStart = latex.index(after: optionalEnd)
            }

            guard specStart < latex.endIndex,
                  latex[specStart] == "{",
                  let specEnd = balancedGroupContentEnd(
                    in: latex,
                    contentStart: latex.index(after: specStart)
                  )
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            result.append("\\begin{matrix}")
            cursor = latex.index(after: specEnd)
        }

        return result
            .replacingOccurrences(of: "\\end{array}", with: "\\end{matrix}")
            .replacingOccurrences(of: "\\begin{smallmatrix}", with: "\\begin{matrix}")
            .replacingOccurrences(of: "\\end{smallmatrix}", with: "\\end{matrix}")
    }

    private static func replacingCasesEnvironment(in latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\begin{cases}", with: "\\left\\{\\begin{matrix}")
            .replacingOccurrences(of: "\\end{cases}", with: "\\end{matrix}\\right.")
    }

    private static func replacingUnsupportedShorthandCommands(in latex: String) -> String {
        let aliases = [
            "dfrac": "\\frac",
            "tfrac": "\\frac",
            "dbinom": "\\binom",
            "tbinom": "\\binom",
            "dots": "\\ldots",
            "implies": "\\Rightarrow",
            "impliedby": "\\Leftarrow",
            "ne": "\\neq",
            "re": "\\Re",
            "im": "\\Im",
            "pr": "\\Pr"
        ]

        var result = ""
        var cursor = latex.startIndex
        while cursor < latex.endIndex {
            guard latex[cursor] == "\\" else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            let nameStart = latex.index(after: cursor)
            guard nameStart < latex.endIndex, latex[nameStart].isLetter else {
                result.append(latex[cursor])
                cursor = nameStart
                continue
            }

            var nameEnd = nameStart
            repeat {
                nameEnd = latex.index(after: nameEnd)
            } while nameEnd < latex.endIndex && latex[nameEnd].isLetter

            let name = String(latex[nameStart..<nameEnd])
            if let replacement = aliases[name] {
                result.append(replacement)
            } else {
                result.append(contentsOf: latex[cursor..<nameEnd])
            }
            cursor = nameEnd
        }

        return result
    }

    private static func replacingOperatorNameCommands(in latex: String) -> String {
        let token = "\\operatorname"
        var result = ""
        var cursor = latex.startIndex

        while cursor < latex.endIndex {
            guard latex[cursor...].hasPrefix(token),
                  var groupStart = latex.index(cursor, offsetBy: token.count, limitedBy: latex.endIndex)
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            if groupStart < latex.endIndex, latex[groupStart] == "*" {
                groupStart = latex.index(after: groupStart)
            }

            guard groupStart < latex.endIndex,
                  latex[groupStart] == "{"
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            let contentStart = latex.index(after: groupStart)
            guard
                  let contentEnd = balancedGroupContentEnd(in: latex, contentStart: contentStart)
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            result.append("\\mathrm{")
            result.append(contentsOf: latex[contentStart..<contentEnd])
            result.append("}")
            cursor = latex.index(after: contentEnd)
        }

        return result
    }

    private static func balancedGroupContentEnd(
        in latex: String,
        contentStart: String.Index,
        open: Character = "{",
        close: Character = "}"
    ) -> String.Index? {
        var depth = 1
        var cursor = contentStart

        while cursor < latex.endIndex {
            if latex[cursor] == open {
                depth += 1
            } else if latex[cursor] == close {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = latex.index(after: cursor)
        }

        return nil
    }

    static func canEnterSwiftMath(
        mainBundleURL: URL = Bundle.main.bundleURL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        // Mirror `MTFont.fontBundle`: enter SwiftMath only when the inner
        // `mathFonts.bundle` and default font assets are loadable from
        // filesystem-probed candidate roots. This never touches SwiftPM's
        // generated `Bundle.module` accessor because that accessor fatals when
        // its generated candidates are absent, making it unsafe as an optional
        // runtime fallback.
        //
        // The resource bundle is named `SiriusMarkdown_SwiftMath.bundle`
        // (SwiftPM's `<PackageName>_<TargetName>` convention) because SwiftMath
        // is vendored as an inline target of the SiriusMarkdown package, not a
        // separate package. Host build scripts must copy
        // `SiriusMarkdown_SwiftMath.bundle` into `Contents/Resources`.
        if let mathFontsBundleURL = MTFont.mathFontsBundleURL(
            mainBundleURL: mainBundleURL,
            fileExists: fileExists
        ), hasDefaultMathFontAssets(in: mathFontsBundleURL, fileExists: fileExists) {
            return true
        }

        return false
    }

    private static func hasDefaultMathFontAssets(
        in mathFontsBundleURL: URL,
        fileExists: (String) -> Bool
    ) -> Bool {
        let defaultFontName = "latinmodern-math"
        return fileExists(mathFontsBundleURL.appendingPathComponent("\(defaultFontName).otf").path)
            && fileExists(mathFontsBundleURL.appendingPathComponent("\(defaultFontName).plist").path)
    }

    /// Re-rasterizes the typeset equation at the requested pixel scale so the
    /// stored bitmap stays crisp when SwiftUI draws it at point size.
    private static func pngData(from image: MTImage, scale: CGFloat) -> Data? {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        let pixelWidthValue = (size.width * scale).rounded(.up)
        let pixelHeightValue = (size.height * scale).rounded(.up)
        guard pixelWidthValue.isFinite,
              pixelHeightValue.isFinite,
              pixelWidthValue > 0,
              pixelHeightValue > 0,
              pixelWidthValue <= maximumRasterPixelDimension,
              pixelHeightValue <= maximumRasterPixelDimension,
              pixelWidthValue * pixelHeightValue <= maximumRasterPixelCount else {
            return nil
        }

        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        if scale > 0 {
            format.scale = scale
        }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rasterized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rasterized.pngData()
        #elseif canImport(AppKit)
        let pixelWidth = Int(pixelWidthValue)
        let pixelHeight = Int(pixelHeightValue)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}
#endif
