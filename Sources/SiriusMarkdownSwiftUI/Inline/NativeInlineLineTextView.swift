import SiriusMarkdownCore
import SwiftUI

struct NativeInlineLineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var baseFont: Font
    var theme: MarkdownTheme
    var containerWidth: CGFloat

    static var isSupported: Bool { true }

    var body: some View {
        let renderedAttributed = InlineRunsView.renderingAttributedString(for: prepared)
        let renderedLines = InlineRunsView.nativeLineAttributedString(
            for: prepared,
            attributed: renderedAttributed,
            layout: layoutResult
        )
        let width = max(0, containerWidth)
        let height = nativeLineSurfaceHeight

        if renderedLines.characters.isEmpty {
            Text(fallbackAttributed)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
        } else {
            Text(renderedLines)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .lineSpacing(lineSpacing)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(fallbackAttributed.characters))
        }
    }

    private var lineSpacing: CGFloat {
        InlineRunsView.nativeLineSpacing(for: prepared)
    }

    private var nativeLineSurfaceHeight: CGFloat {
        let lineCount = max(1, layoutResult.lines.count)
        let lineHeight = CGFloat(prepared.lineHeight)
        let spacing = lineSpacing
        return CGFloat(lineCount) * lineHeight + CGFloat(max(0, lineCount - 1)) * spacing
    }
}
