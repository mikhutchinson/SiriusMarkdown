import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A natively typeset math artifact produced during render preparation.
///
/// The glyphs are rasterized once (off the SwiftUI body) into an alpha-coverage
/// bitmap so the SwiftUI layer can draw them as a template image tinted by the
/// active theme color. Storing a `Sendable` value keeps non-`Sendable` CoreText
/// typesetting objects contained inside the renderer.
public struct MarkdownPreparedMathImage: Sendable, Hashable {
    /// PNG bitmap whose alpha channel encodes glyph coverage (color is ignored when tinted).
    public var imageData: Data
    /// Pixel scale the bitmap was rasterized at (e.g. 3.0 for crisp Retina output).
    public var scale: Double
    /// Natural width of the equation in points.
    public var pointWidth: Double
    /// Natural height of the equation in points (`ascent + descent`).
    public var pointHeight: Double
    /// Distance from the baseline to the top of the equation in points.
    public var ascent: Double
    /// Distance from the baseline to the bottom of the equation in points.
    public var descent: Double
    /// Original LaTeX source, retained for copy-as-Markdown and accessibility.
    public var latex: String

    public init(
        imageData: Data,
        scale: Double,
        pointWidth: Double,
        pointHeight: Double,
        ascent: Double,
        descent: Double,
        latex: String
    ) {
        self.imageData = imageData
        self.scale = scale
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.ascent = ascent
        self.descent = descent
        self.latex = latex
    }
}

/// The prepared representation of a math run or block.
public enum MarkdownPreparedMath: Sendable, Hashable {
    /// A plain attributed-string fallback (used when no native engine is configured
    /// or when the LaTeX failed to typeset, e.g. a partial equation in the streaming tail).
    case text(AttributedString)
    /// Natively typeset glyphs ready to draw as a tinted template image.
    case image(MarkdownPreparedMathImage)
}

public extension MarkdownMathRenderer {
    /// Default preparation wraps the legacy `renderedMath(_:isBlock:)` output so existing
    /// conformers keep working without adopting the native typesetting path.
    func preparedMath(_ source: String, isBlock: Bool, fontSize _: Double) -> MarkdownPreparedMath {
        .text(renderedMath(source, isBlock: isBlock))
    }
}

extension MarkdownPreparedMathImage {
    /// A correctly point-sized template `Image` whose RGB is replaced by the
    /// applied foreground style. The bitmap is stored at `scale`x pixels, so the
    /// platform image is reconstructed at that scale to recover its point size.
    var templateImage: Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData, scale: CGFloat(scale)) else {
            return nil
        }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        image.size = NSSize(width: pointWidth, height: pointHeight)
        image.isTemplate = true
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

/// An ordered fragment of inline content: either styled text or a typeset math image.
///
/// When a paragraph, heading, list item, or table cell contains typeset inline
/// math, the renderer composes these fragments with SwiftUI `Text` concatenation
/// so the math glyphs wrap natively alongside text. Non-math inline content keeps
/// the prepared CoreText line path.
public enum MarkdownInlineMathPiece: Sendable, Hashable {
    case text(AttributedString)
    case math(MarkdownPreparedMathImage)
}

/// Composes inline content that contains typeset math using native `Text`
/// concatenation, baseline-aligning each equation image to the surrounding text.
struct InlineMathTextView: View {
    var pieces: [MarkdownInlineMathPiece]
    var font: Font
    var color: Color
    var fontSize: Double

    var body: some View {
        composed
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composed: Text {
        pieces.reduce(Text(verbatim: "")) { partial, piece in
            switch piece {
            case let .text(attributed):
                return partial + Text(attributed)
            case let .math(image):
                guard let templateImage = image.templateImage else {
                    return partial + Text(verbatim: image.latex)
                }
                return partial + Text(templateImage).baselineOffset(baselineOffset(for: image))
            }
        }
    }

    /// Nudges the typeset glyphs so their optical center sits near the text's
    /// math axis rather than resting on the baseline.
    private func baselineOffset(for image: MarkdownPreparedMathImage) -> CGFloat {
        let overshoot = image.pointHeight - fontSize
        guard overshoot > 0 else {
            return 0
        }
        return -CGFloat(overshoot * 0.32)
    }
}

/// Renders prepared math glyphs as a theme-tinted template image with a plain-text fallback.
struct MarkdownMathImageView: View {
    var image: MarkdownPreparedMathImage
    var color: Color

    var body: some View {
        if let templateImage = image.templateImage {
            templateImage
                .resizable()
                .interpolation(.high)
                .frame(width: CGFloat(image.pointWidth), height: CGFloat(image.pointHeight))
                .foregroundStyle(color)
                .accessibilityLabel(Text(image.latex))
        } else {
            Text(image.latex)
                .foregroundStyle(color)
        }
    }
}
