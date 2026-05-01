import SiriusMarkdownCore
import SwiftUI

public struct MarkdownBlockView: View {
    private var block: MarkdownBlock
    private var configuration: MarkdownRendererConfiguration

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(block: MarkdownBlock, theme: MarkdownTheme = .compactChat) {
        self.block = block
        self.configuration = MarkdownRendererConfiguration(theme: theme)
    }

    public init(block: MarkdownBlock, configuration: MarkdownRendererConfiguration) {
        self.block = block
        self.configuration = configuration
    }

    public var body: some View {
        Group {
            switch block.kind {
            case .heading:
                inlineContent(baseFont: headingFont, fallbackText: headingText)
            case .codeBlock:
                ScrollView(.horizontal) {
                    Text(codeText)
                        .font(theme.codeFont)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            case .blockQuote:
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(theme.quoteAccent)
                        .frame(width: 3)
                    inlineContent(baseFont: theme.paragraphFont, fallbackText: block.text)
                        .foregroundStyle(theme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .thematicBreak:
                Divider()
            case .unorderedList, .orderedList, .taskList:
                inlineContent(baseFont: theme.paragraphFont, fallbackText: block.text)
            case .table:
                ScrollView(.horizontal) {
                    inlineContent(baseFont: theme.codeFont, fallbackText: block.text)
                        .padding(.vertical, 4)
                }
            case .mathBlock:
                Text(block.text)
                    .font(theme.codeFont)
                    .foregroundStyle(theme.textColor)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(theme.codeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            case .htmlBlock:
                Text(block.text)
                    .font(theme.codeFont)
                    .foregroundStyle(theme.secondaryTextColor)
                    .textSelection(.enabled)
            case .blank:
                EmptyView()
            case .paragraph:
                inlineContent(baseFont: theme.paragraphFont, fallbackText: block.text)
            }
        }
        .id(block.id)
    }

    @ViewBuilder
    private func inlineContent(baseFont: Font, fallbackText: String) -> some View {
        if block.inlines.isEmpty {
            Text(fallbackText)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            InlineRunsView(
                runs: block.inlines,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                policy: configuration.policy
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headingText: String {
        block.text.replacingOccurrences(
            of: #"^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private var codeText: String {
        var lines = block.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.hasPrefix("```") == true || lines.first?.hasPrefix("~~~") == true {
            lines.removeFirst()
        }
        if lines.last?.hasPrefix("```") == true || lines.last?.hasPrefix("~~~") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private var headingFont: Font {
        switch block.headingLevel ?? 3 {
        case 1:
            return .largeTitle.bold()
        case 2:
            return .title.bold()
        case 3:
            return theme.headingFont
        default:
            return .headline
        }
    }
}
