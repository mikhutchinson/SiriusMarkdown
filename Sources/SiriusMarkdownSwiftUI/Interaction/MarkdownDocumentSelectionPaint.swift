import SiriusMarkdownCore
import SwiftUI

/// Immutable paint input from the one document selection owner. Existing native
/// surfaces consume it without new text hosts or observation subscriptions.
struct MarkdownDocumentSelectionPaint: Equatable {
    var ranges: [MarkdownSourceRange] = []
    var emphasized = true

    func rects(blockID: MarkdownBlockID?, prepared: MarkdownPreparedInlineContent,
               layout: InlineLayoutResult, width: CGFloat) -> [CGRect] {
        guard let blockID, !ranges.isEmpty, width > 0 else { return [] }
        let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: blockID, prepared: prepared, layout: layout,
            rect: CGRect(x: 0, y: 0, width: width, height: max(1, CGFloat(layout.lines.count) * CGFloat(prepared.lineHeight))),
            idPrefix: "selection-paint")
        return fragments.flatMap { $0.highlightRects(for: ranges, extendsLineEndings: true).map(\.rect) }
    }
}

private struct MarkdownDocumentSelectionPaintKey: EnvironmentKey {
    static let defaultValue = MarkdownDocumentSelectionPaint()
}

private struct MarkdownDocumentSelectionPaintOwnerKey: EnvironmentKey {
    static let defaultValue: MarkdownBlockID? = nil
}

extension EnvironmentValues {
    // Separate from fragment publication: grid cells suppress that context while
    // retaining the enclosing document owner for their existing paint surfaces.
    var markdownDocumentSelectionPaintOwner: MarkdownBlockID? {
        get { self[MarkdownDocumentSelectionPaintOwnerKey.self] }
        set { self[MarkdownDocumentSelectionPaintOwnerKey.self] = newValue }
    }
    var markdownDocumentSelectionPaint: MarkdownDocumentSelectionPaint {
        get { self[MarkdownDocumentSelectionPaintKey.self] }
        set { self[MarkdownDocumentSelectionPaintKey.self] = newValue }
    }
}

#if os(macOS)
import AppKit

extension MarkdownDocumentSelectionPaint {
    var background: NSColor {
        emphasized ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
    }
    var foreground: NSColor {
        emphasized ? .selectedTextColor : .unemphasizedSelectedTextColor
    }

    /// Intersect with the complement of every rectangle, including overlapping
    /// ones. A single even-odd path would accidentally restore overlaps.
    static func clipOutside(_ rects: [CGRect], bounds: CGRect, in context: CGContext) {
        for rect in rects {
            context.addRect(bounds)
            context.addRect(rect)
            context.clip(using: .evenOdd)
        }
    }

    /// Repaint glyph alpha with the system selection foreground. The existing
    /// shaped lines remain untouched; clipping preserves exact partial edges.
    static func drawSelectedGlyphs(in context: CGContext, rects: [CGRect], color: NSColor,
                                   bounds: CGRect, excluding excludedRects: [CGRect] = [], glyphs: () -> Void) {
        guard !rects.isEmpty else { return }
        context.saveGState()
        context.addRects(rects)
        context.clip()
        clipOutside(excludedRects, bounds: bounds, in: context)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        glyphs()
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
#endif
