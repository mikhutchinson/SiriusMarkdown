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
        let lines = InlineRunsView.attributedLines(
            for: prepared,
            attributed: renderedAttributed,
            layout: layoutResult
        )
        let width = max(0, containerWidth)

        if lines.isEmpty {
            Text(fallbackAttributed)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .frame(width: width, alignment: .leading)
                .clipped()
        } else {
            VStack(alignment: .leading, spacing: lineSpacing) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    let isEmpty = line.characters.isEmpty
                    Text(isEmpty ? AttributedString(" ") : line)
                        .font(baseFont)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(width: width, alignment: .leading)
                        .clipped()
                        .frame(minHeight: CGFloat(prepared.lineHeight), alignment: .leading)
                        .opacity(isEmpty ? 0 : 1)
                        .accessibilityHidden(isEmpty)
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(fallbackAttributed.characters))
        }
    }

    private var lineSpacing: CGFloat {
        InlineRunsView.nativeLineSpacing(for: prepared)
    }
}
