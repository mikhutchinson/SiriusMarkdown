import SiriusMarkdownCore
import SwiftUI

struct NativeInlineLineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var baseFont: Font
    var theme: MarkdownTheme
    var containerWidth: CGFloat
    var linkAction: MarkdownLinkAction?
    var inlineRenderingMode: MarkdownInlineRenderingMode
    var nativeTextSelection: MarkdownNativeTextSelection
    var dragSelectionHandler: ((CGPoint, CGPoint) -> Void)?

    static var isSupported: Bool { true }

    var body: some View {
        let width = max(0, containerWidth)
        let height = nativeLineSurfaceHeight

        if shouldPaintWithCoreText {
            CoreTextPaintedInlineLineView(
                prepared: prepared,
                layoutResult: layoutResult,
                fallbackAttributed: fallbackAttributed,
                theme: theme,
                containerWidth: width,
                linkAction: linkAction,
                dragSelectionHandler: dragSelectionHandler
            )
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(prepared.semanticAccessibilityText)
        } else {
            let renderedAttributed = InlineRunsView.renderingAttributedString(for: prepared)
            let renderedLines = InlineRunsView.nativeLineAttributedString(
                for: prepared,
                attributed: renderedAttributed,
                layout: layoutResult
            )

            if renderedLines.characters.isEmpty {
                MarkdownSelectableText(
                    attributed: fallbackAttributed,
                    font: baseFont,
                    fontSize: prepared.fontSize,
                    lineHeight: prepared.lineHeight,
                    fontProfile: prepared.fontProfiles.body,
                    textColor: theme.textColor,
                    nativeTextSelection: nativeTextSelection,
                    lineSpacing: lineSpacing,
                    wraps: false
                )
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipped()
            } else {
                MarkdownSelectableText(
                    attributed: renderedLines,
                    font: baseFont,
                    fontSize: prepared.fontSize,
                    lineHeight: prepared.lineHeight,
                    fontProfile: prepared.fontProfiles.body,
                    textColor: theme.textColor,
                    nativeTextSelection: nativeTextSelection,
                    lineSpacing: lineSpacing,
                    wraps: false
                )
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipped()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(prepared.semanticAccessibilityText)
            }
        }
    }

    private var lineSpacing: CGFloat {
        InlineRunsView.nativeLineSpacing(for: prepared)
    }

    private var shouldPaintWithCoreText: Bool {
        inlineRenderingMode == .coreTextPaintedLines &&
            nativeTextSelection != .enabled &&
            CoreTextPaintedInlineLineView.isSupported &&
            !layoutResult.lines.isEmpty
    }

    private var nativeLineSurfaceHeight: CGFloat {
        let lineCount = max(1, layoutResult.lines.count)
        let lineHeight = CGFloat(prepared.lineHeight)
        let spacing = lineSpacing
        return CGFloat(lineCount) * lineHeight + CGFloat(max(0, lineCount - 1)) * spacing
    }
}
