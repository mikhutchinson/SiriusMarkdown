import SiriusMarkdownCore
import SwiftUI

struct NativeInlineLineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var baseFont: Font
    var theme: MarkdownTheme

    static var isSupported: Bool { true }

    var body: some View {
        let lines = InlineRunsView.attributedLines(for: prepared, layout: layoutResult)

        if lines.isEmpty {
            Text(fallbackAttributed)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
        } else {
            VStack(alignment: .leading, spacing: lineSpacing) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    let isEmpty = line.characters.isEmpty
                    Text(isEmpty ? AttributedString(" ") : line)
                        .font(baseFont)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minHeight: CGFloat(prepared.lineHeight), alignment: .leading)
                        .opacity(isEmpty ? 0 : 1)
                        .accessibilityHidden(isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(fallbackAttributed.characters))
        }
    }

    private var lineSpacing: CGFloat {
        max(0, CGFloat(prepared.lineHeight - prepared.fontSize) * 0.25)
    }
}
