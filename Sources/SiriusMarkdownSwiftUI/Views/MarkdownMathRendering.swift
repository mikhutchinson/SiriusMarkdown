import Foundation
import SiriusMarkdownCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Semantic math structure prepared by a native typesetter, independent of UI.
public struct MarkdownMathAccessibilityNode: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case equation, row, fraction, numerator, denominator, radical, radicand, degree
        case superscript, subscriptValue, symbol, group, table, cell, accent, overline, underline
    }
    public let kind: Kind
    public let label: String
    public let children: [MarkdownMathAccessibilityNode]

    public init(kind: Kind, label: String, children: [MarkdownMathAccessibilityNode] = []) {
        self.kind = kind
        self.label = String(label.prefix(256))
        self.children = children
    }
}

/// A bounded, navigable equation tree. Building it never changes authored LaTeX.
public struct MarkdownMathAccessibilityTree: Sendable, Hashable {
    public static let maximumNodeCount = 512
    public static let maximumDepth = 24
    public let root: MarkdownMathAccessibilityNode
    public let isTruncated: Bool
    public let accessibilityLabel: String

    public init(root: MarkdownMathAccessibilityNode, isTruncated: Bool = false) {
        var remaining = Self.maximumNodeCount
        var truncated = isTruncated
        var labels: [String] = []
        func bounded(_ node: MarkdownMathAccessibilityNode, depth: Int) -> MarkdownMathAccessibilityNode {
            remaining -= 1
            labels.append(node.label)
            var children: [MarkdownMathAccessibilityNode] = []
            for child in node.children {
                guard remaining > 0, depth < Self.maximumDepth else { truncated = true; break }
                children.append(bounded(child, depth: depth + 1))
            }
            return .init(kind: node.kind, label: node.label, children: children)
        }
        self.root = bounded(root, depth: 1)
        self.isTruncated = truncated
        self.accessibilityLabel = String(labels.filter { !$0.isEmpty }.joined(separator: ", ").prefix(4096))
    }
}

/// A natively typeset math artifact produced during render preparation.
///
/// The glyphs are rasterized once (off the SwiftUI body) into an alpha-coverage
/// bitmap so the SwiftUI layer can draw them as a template image tinted by the
/// active theme color. Storing a `Sendable` value keeps non-`Sendable` CoreText
/// typesetting objects contained inside the renderer.
///
/// `ascent` and `descent` come from vendored SwiftMath
/// `MTMathImage.LayoutInfo` (`MTMathListDisplay` typographic metrics),
/// adjusted so `ascent + descent == pointHeight` after image-height layout.
/// Equations with descenders have `ascent < pointHeight`.
public struct MarkdownPreparedMathImage: Sendable, Hashable {
    /// PNG bitmap whose alpha channel encodes glyph coverage (color is ignored when tinted).
    public var imageData: Data
    /// Pixel scale the bitmap was rasterized at (matches the screen's backing scale, min 2.0).
    public var scale: Double
    /// Natural width of the equation in points.
    public var pointWidth: Double
    /// Natural height of the equation in points (`ascent + descent`).
    public var pointHeight: Double
    /// Distance from the baseline to the top of the equation in points,
    /// from SwiftMath display-list metrics (`MTMathImage.LayoutInfo`).
    public var ascent: Double
    /// Distance from the baseline to the bottom of the equation in points,
    /// from SwiftMath display-list metrics (`MTMathImage.LayoutInfo`).
    public var descent: Double
    /// Original LaTeX source, retained for copy-as-Markdown and accessibility.
    public var latex: String
    /// Native semantic structure, prepared alongside the bitmap when available.
    public var accessibilityTree: MarkdownMathAccessibilityTree?

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
        self.accessibilityTree = nil
    }

    public init(imageData: Data, scale: Double, pointWidth: Double, pointHeight: Double,
                ascent: Double, descent: Double, latex: String,
                accessibilityTree: MarkdownMathAccessibilityTree?) {
        self.init(imageData: imageData, scale: scale, pointWidth: pointWidth, pointHeight: pointHeight,
                  ascent: ascent, descent: descent, latex: latex)
        self.accessibilityTree = accessibilityTree
    }

    public var accessibilityLabel: String {
        accessibilityTree?.accessibilityLabel ?? latex
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
    private static let maximumRenderPointDimension = 16_384.0

    var renderScale: CGFloat {
        guard scale.isFinite, scale > 0 else {
            return 1
        }
        return CGFloat(scale)
    }

    var renderPointWidth: CGFloat {
        CGFloat(Self.sanitizedDimension(pointWidth))
    }

    var renderPointHeight: CGFloat {
        CGFloat(Self.sanitizedDimension(pointHeight))
    }

    var renderDescent: CGFloat {
        guard descent.isFinite, descent > 0 else {
            return 0
        }
        return min(CGFloat(descent), renderPointHeight)
    }

    private static func sanitizedDimension(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return min(value, maximumRenderPointDimension)
    }

    /// A correctly point-sized template `Image` whose RGB is replaced by the
    /// applied foreground style. The bitmap is stored at `scale`x pixels, so the
    /// platform image is reconstructed at that scale to recover its point size.
    var templateImage: Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData, scale: renderScale) else {
            return nil
        }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        image.size = NSSize(width: renderPointWidth, height: renderPointHeight)
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
    var prepared: MarkdownPreparedInlineContent? = nil
    var font: Font
    var color: Color
    var fontSize: Double
    var linkAction: MarkdownLinkAction? = nil

    @Environment(\.markdownDocumentSelectionContext) private var documentSelectionContext

    var body: some View {
        composed
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, openURLAction)
            .background(selectionFragmentPreference)
    }

    var openURLAction: OpenURLAction {
        markdownOpenURLAction(linkAction: linkAction)
    }

    private var selectionFragmentPreference: some View {
        GeometryReader { proxy in
            let rect = selectionPreferenceRect(from: proxy)
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: selectionFragments(rect: rect)
            )
        }
        .allowsHitTesting(false)
    }

    private func selectionPreferenceRect(from proxy: GeometryProxy) -> CGRect {
        prepared?.layoutCache.recordSelectionPreferenceBodyEvaluation()
        prepared?.layoutCache.recordSelectionFrameQuery()
        return proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
    }

    private func selectionFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext,
              let sourceRange = prepared?.prepared.sourceRange,
              let prepared,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0
        else {
            return []
        }

        let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
            for: prepared,
            containerWidth: Double(rect.width)
        )
        let lineFragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: documentSelectionContext.blockID,
            prepared: prepared,
            layout: prepared.layout(
                containerWidth: layoutWidth,
                allowsOverwideFallback: true
            ),
            rect: rect,
            idPrefix: "text-leaf-math"
        )
        if !lineFragments.isEmpty {
            return lineFragments
        }

        return [
            MarkdownDocumentSelectionFragment.fallbackTextFragment(
                blockID: documentSelectionContext.blockID,
                sourceRange: sourceRange,
                rect: rect,
                idPrefix: "text-leaf-math"
            )
        ]
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

    /// Aligns the equation's typographic baseline with the surrounding text
    /// baseline using the prepared ascent/descent metrics.
    ///
    /// SwiftUI places an inline `Image` with its bottom edge at the text
    /// baseline. The math baseline sits `descent` points above the image
    /// bottom, so shifting the image down by `descent` aligns the two
    /// baselines. This replaces the prior `−overshoot × 0.32` heuristic with
    /// display-list metrics from `MTMathImage.LayoutInfo` extracted during
    /// preparation.
    private func baselineOffset(for image: MarkdownPreparedMathImage) -> CGFloat {
        -image.renderDescent
    }
}

/// Renders prepared math glyphs as a theme-tinted template image with a plain-text fallback.
struct MarkdownMathImageView: View {
    var image: MarkdownPreparedMathImage
    var color: Color
    var font: Font = .body
    var fontSize: Double = 16
    var lineHeight: Double = 22
    var fontProfile: MarkdownFontProfile = .system()
    var nativeTextSelection: MarkdownNativeTextSelection = .platformDefault

    var body: some View {
        if let templateImage = image.templateImage {
            templateImage
                .resizable()
                .interpolation(.medium)
                .frame(width: image.renderPointWidth, height: image.renderPointHeight)
                .foregroundStyle(color)
                .accessibilityLabel(Text(image.accessibilityLabel))
        } else {
            MarkdownSelectableText(
                attributed: AttributedString(image.latex),
                font: font,
                fontSize: fontSize,
                lineHeight: lineHeight,
                fontProfile: fontProfile,
                textColor: color,
                linkAction: nil,
                nativeTextSelection: nativeTextSelection
            )
        }
    }
}

struct MarkdownMathAccessibilityNodeView: View {
    var node: MarkdownMathAccessibilityNode

    var body: some View {
        AnyView(Text(node.label)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(node.label))
            .accessibilityChildren {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    MarkdownMathAccessibilityNodeView(node: child)
                }
            })
    }
}
