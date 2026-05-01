import SiriusMarkdownCore
import SwiftUI

public struct MarkdownBlockView: View {
    private var block: MarkdownBlock
    private var configuration: MarkdownRendererConfiguration
    private var preparedContent: MarkdownPreparedBlockContent

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(block: MarkdownBlock, theme: MarkdownTheme = .compactChat) {
        self.block = block
        self.configuration = MarkdownRendererConfiguration(theme: theme)
        self.preparedContent = self.configuration.prepare(block: block)
    }

    public init(block: MarkdownBlock, configuration: MarkdownRendererConfiguration) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = configuration.prepare(block: block)
    }

    public init(
        block: MarkdownBlock,
        configuration: MarkdownRendererConfiguration,
        preparedContent: MarkdownPreparedBlockContent?
    ) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = preparedContent ?? configuration.prepare(block: block)
    }

    public var body: some View {
        Group {
            switch block.kind {
            case .heading:
                inlineContent(baseFont: headingFont, fallbackText: headingFallbackText)
            case .codeBlock:
                codeBlockContent
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
                listContent
            case .table:
                tableContent
            case .mathBlock:
                mathBlockContent
            case .htmlBlock:
                htmlBlockContent
            case .blank:
                EmptyView()
            case .paragraph:
                inlineContent(baseFont: theme.paragraphFont, fallbackText: block.text)
            }
        }
        .id(block.id)
        .accessibilityLabel(Self.accessibilityLabel(for: block))
        .contextMenu {
            if configuration.copyProvider != nil {
                Button("Copy Markdown") {
                    copyBlockMarkdown()
                }
            }
        }
        .onAppear {
            MarkdownDiagnostics().signpostEvent("BlockRender", category: "SwiftUI")
        }
    }

    @ViewBuilder
    private func inlineContent(baseFont: Font, fallbackText: String) -> some View {
        if let inline = preparedContent.inline {
            InlineRunsView(
                attributed: inline,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if block.inlines.isEmpty {
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
                linkPolicy: configuration.linkPolicy,
                imagePolicy: configuration.imagePolicy
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var codeBlockContent: some View {
        if let code = preparedContent.code {
            ScrollView(.horizontal) {
                Text(code)
                    .font(theme.codeFont)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            Text(MarkdownRendererConfiguration.codeText(for: block))
                .font(theme.codeFont)
                .textSelection(.enabled)
        }
    }

    private var listContent: some View {
        MarkdownListItemsView(
            items: preparedContent.listItems,
            kind: block.kind,
            orderedStart: block.orderedListStart,
            configuration: configuration,
            theme: theme
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tableContent: some View {
        if let table = preparedContent.table {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    if !table.header.isEmpty {
                        GridRow {
                            ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                                tableCell(cell, column: column, isHeader: true)
                            }
                        }
                    }

                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                                tableCell(cell, column: column, isHeader: false)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            inlineContent(baseFont: theme.codeFont, fallbackText: block.text)
        }
    }

    @ViewBuilder
    private var mathBlockContent: some View {
        if let math = preparedContent.math {
            Text(math)
                .font(theme.codeFont)
                .foregroundStyle(theme.textColor)
                .textSelection(.enabled)
                .padding(8)
                .background(theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            Text(MarkdownRendererConfiguration.mathText(for: block))
                .font(theme.codeFont)
                .foregroundStyle(theme.textColor)
        }
    }

    @ViewBuilder
    private var htmlBlockContent: some View {
        if preparedContent.htmlAllowed == true {
            Text(block.text)
                .font(theme.codeFont)
                .foregroundStyle(theme.secondaryTextColor)
                .textSelection(.enabled)
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            EmptyView()
        }
    }

    private func tableCell(_ cell: MarkdownPreparedTableCell, column: Int, isHeader: Bool) -> some View {
        InlineRunsView(
            attributed: cell.inline ?? AttributedString(""),
            theme: theme,
            baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
            linkAction: configuration.linkAction
        )
        .frame(minWidth: 48, alignment: tableAlignment(column))
        .textSelection(.enabled)
    }

    private func tableAlignment(_ column: Int) -> Alignment {
        guard let alignment = preparedContent.table?.columnAlignments[safe: column] ?? nil else {
            return .leading
        }

        switch alignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }

    private func policyDeniedView(reason: String) -> some View {
        Text(reason)
            .font(theme.codeFont)
            .foregroundStyle(theme.secondaryTextColor)
            .textSelection(.enabled)
            .padding(8)
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyBlockMarkdown() {
        guard let markdown = configuration.copyProvider?.markdown(block.sourceRange) else {
            return
        }

        Task { @MainActor in
            MarkdownPasteboard.copy(markdown)
        }
    }

    public nonisolated static func renderPlan(
        for block: MarkdownBlock,
        configuration: MarkdownRendererConfiguration = .compactChat
    ) -> MarkdownBlockRenderPlan {
        switch block.kind {
        case .unorderedList, .orderedList, .taskList:
            return MarkdownBlockRenderPlan(kind: block.kind, listItemCount: block.listItems.count)
        case .table:
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                tableColumnCount: block.table?.header.count ?? 0,
                tableBodyRowCount: block.table?.rows.count ?? 0
            )
        case .codeBlock:
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                codeAllowed: policyAllowed(
                    configuration.codePolicy.evaluateCodeBlock(
                        infoString: block.infoString,
                        code: MarkdownRendererConfiguration.codeText(for: block)
                    )
                ),
                policyDenialReason: denialReason(
                    configuration.codePolicy.evaluateCodeBlock(
                        infoString: block.infoString,
                        code: MarkdownRendererConfiguration.codeText(for: block)
                    )
                )
            )
        case .mathBlock:
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                mathAllowed: policyAllowed(
                    configuration.mathPolicy.evaluateMath(
                        MarkdownRendererConfiguration.mathText(for: block),
                        isBlock: true
                    )
                ),
                policyDenialReason: denialReason(
                    configuration.mathPolicy.evaluateMath(
                        MarkdownRendererConfiguration.mathText(for: block),
                        isBlock: true
                    )
                )
            )
        case .htmlBlock:
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                htmlAllowed: policyAllowed(configuration.htmlPolicy.evaluateHTML(block.text)),
                policyDenialReason: denialReason(configuration.htmlPolicy.evaluateHTML(block.text))
            )
        default:
            return MarkdownBlockRenderPlan(kind: block.kind)
        }
    }

    public nonisolated static func accessibilityLabel(for block: MarkdownBlock) -> String {
        switch block.kind {
        case .heading:
            return "Heading \(block.headingLevel ?? 0): \(block.inlines.map(\.text).joined())"
        case .codeBlock:
            return "Code block"
        case .table:
            let columns = block.table?.header.count ?? 0
            let rows = block.table?.rows.count ?? 0
            return "Table with \(columns) columns and \(rows) rows"
        case .unorderedList, .orderedList, .taskList:
            return "List with \(block.listItems.count) items"
        case .blockQuote:
            return "Quote: \(block.inlines.map(\.text).joined())"
        case .mathBlock:
            return "Math block"
        case .htmlBlock:
            return "HTML block"
        case .thematicBreak:
            return "Thematic break"
        case .blank:
            return ""
        case .paragraph:
            return block.inlines.map(\.text).joined()
        }
    }

    private nonisolated static func policyAllowed(_ decision: MarkdownPolicyDecision) -> Bool {
        switch decision {
        case .allow:
            return true
        case .deny:
            return false
        }
    }

    private nonisolated static func denialReason(_ decision: MarkdownPolicyDecision) -> String? {
        switch decision {
        case .allow:
            return nil
        case let .deny(reason):
            return reason
        }
    }

    private var headingFallbackText: String {
        let inlineText = block.inlines.map(\.text).joined()
        return inlineText.isEmpty ? block.text : inlineText
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

private struct MarkdownListItemsView: View {
    var items: [MarkdownPreparedListItem]
    var kind: MarkdownBlockKind
    var orderedStart: UInt?
    var configuration: MarkdownRendererConfiguration
    var theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                MarkdownListItemRow(
                    item: item,
                    index: index,
                    kind: kind,
                    orderedStart: orderedStart,
                    configuration: configuration,
                    theme: theme
                )
            }
        }
    }
}

private struct MarkdownListItemRow: View {
    var item: MarkdownPreparedListItem
    var index: Int
    var kind: MarkdownBlockKind
    var orderedStart: UInt?
    var configuration: MarkdownRendererConfiguration
    var theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(theme.codeFont)
                    .foregroundStyle(theme.secondaryTextColor)
                    .frame(width: markerWidth, alignment: .trailing)
                InlineRunsView(
                    attributed: item.inline ?? AttributedString(""),
                    theme: theme,
                    baseFont: theme.paragraphFont,
                    linkAction: configuration.linkAction
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !item.childItems.isEmpty {
                MarkdownListItemsView(
                    items: item.childItems,
                    kind: .unorderedList,
                    orderedStart: nil,
                    configuration: configuration,
                    theme: theme
                )
                .padding(.leading, markerWidth + 8)
            }
        }
    }

    private var marker: String {
        if let taskState = item.taskState {
            return taskState == .checked ? "[x]" : "[ ]"
        }

        switch kind {
        case .orderedList:
            return "\(Int(orderedStart ?? 1) + index)."
        default:
            return "-"
        }
    }

    private var markerWidth: CGFloat {
        kind == .orderedList ? 34 : 28
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
