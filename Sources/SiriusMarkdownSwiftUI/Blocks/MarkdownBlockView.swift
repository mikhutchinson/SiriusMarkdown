import SiriusMarkdownCore
import SwiftUI

public struct MarkdownBlockView: View {
    private var block: MarkdownBlock
    private var configuration: MarkdownRendererConfiguration
    private var preparedContent: MarkdownPreparedBlockContent
    @State private var isCodeBlockCollapsed: Bool

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(block: MarkdownBlock, theme: MarkdownTheme = .compactChat) {
        self.block = block
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .preparedNativeLines)
        self.preparedContent = self.configuration.prepare(block: block)
        _isCodeBlockCollapsed = State(initialValue: self.configuration.theme.codeBlockAffordances.startsCollapsed)
    }

    public init(block: MarkdownBlock, configuration: MarkdownRendererConfiguration) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = configuration.prepare(block: block)
        _isCodeBlockCollapsed = State(initialValue: configuration.theme.codeBlockAffordances.startsCollapsed)
    }

    public init(
        block: MarkdownBlock,
        configuration: MarkdownRendererConfiguration,
        preparedContent: MarkdownPreparedBlockContent?
    ) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = preparedContent ?? configuration.prepare(block: block)
        _isCodeBlockCollapsed = State(initialValue: configuration.theme.codeBlockAffordances.startsCollapsed)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let inlineLayout = preparedContent.inlineLayout {
            InlineRunsView(
                prepared: inlineLayout,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let inline = preparedContent.inline {
            InlineRunsView(
                attributed: inline,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode
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
                inlineRenderingMode: configuration.inlineRenderingMode,
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
            VStack(alignment: .leading, spacing: 0) {
                if showsCodeBlockHeader {
                    codeBlockHeader
                }
                if !isCodeBlockCollapsed {
                    ScrollView(.horizontal) {
                        Text(code)
                            .font(theme.codeFont)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.top, showsCodeBlockHeader ? 4 : 10)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("\(Self.codeCopyText(for: block).utf8.count.formatted()) bytes hidden")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Code block collapsed")
                }
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

    private var showsCodeBlockHeader: Bool {
        (theme.codeBlockAffordances.showsLanguageLabel && Self.codeBlockLanguageLabel(for: block) != nil) ||
            theme.codeBlockAffordances.showsCopyButton ||
            theme.codeBlockAffordances.showsExportButton ||
            theme.codeBlockAffordances.showsCollapseButton
    }

    @ViewBuilder
    private var codeBlockHeader: some View {
        HStack(spacing: 8) {
            if theme.codeBlockAffordances.showsLanguageLabel,
               let label = Self.codeBlockLanguageLabel(for: block)
            {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .accessibilityLabel("Code language: \(label)")
            }

            Spacer(minLength: 8)

            if theme.codeBlockAffordances.showsCopyButton {
                Button {
                    copyCodeBlock()
                } label: {
                    MarkdownAffordanceIcon(systemName: MarkdownAffordanceSymbols.copy, size: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Copy code")
                .help("Copy code")
            }

            if theme.codeBlockAffordances.showsExportButton {
                Button {
                    exportCodeBlock()
                } label: {
                    MarkdownAffordanceIcon(systemName: MarkdownAffordanceSymbols.export, size: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Export code")
                .help("Export code")
            }

            if theme.codeBlockAffordances.showsCollapseButton {
                Button {
                    isCodeBlockCollapsed.toggle()
                } label: {
                    MarkdownAffordanceIcon(
                        systemName: isCodeBlockCollapsed ? MarkdownAffordanceSymbols.expand : MarkdownAffordanceSymbols.collapse,
                        size: 12
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel(isCodeBlockCollapsed ? "Expand code block" : "Collapse code block")
                .help(isCodeBlockCollapsed ? "Expand code block" : "Collapse code block")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
            let columnWidths = tableColumnWidths(for: table)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    if !table.header.isEmpty {
                        tableRow(
                            cells: table.header,
                            rowIndex: -1,
                            isHeader: true,
                            columnWidths: columnWidths
                        )
                    }

                    ForEach(Array(table.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        tableRow(
                            cells: row.cells,
                            rowIndex: rowIndex,
                            isHeader: false,
                            columnWidths: columnWidths
                        )
                    }
                }
                .background(theme.tableBackground)
                .clipShape(RoundedRectangle(cornerRadius: theme.tableCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.tableCornerRadius)
                        .stroke(theme.tableBorderColor)
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            inlineContent(baseFont: theme.codeFont, fallbackText: block.text)
        }
    }

    private func tableRow(
        cells: [MarkdownPreparedTableCell],
        rowIndex: Int,
        isHeader: Bool,
        columnWidths: [CGFloat]
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(columnWidths.indices, id: \.self) { column in
                tableCell(
                    cells[safe: column],
                    column: column,
                    isHeader: isHeader,
                    isLastColumn: column == columnWidths.count - 1,
                    width: columnWidths[column]
                )
            }
        }
        .background(tableRowBackground(rowIndex: rowIndex, isHeader: isHeader))
        .overlay(alignment: .top) {
            if isHeader {
                Rectangle()
                    .fill(theme.tableAccentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.tableBorderColor)
                .frame(height: 1)
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

    @ViewBuilder
    private func tableCell(
        _ cell: MarkdownPreparedTableCell?,
        column: Int,
        isHeader: Bool,
        isLastColumn: Bool,
        width: CGFloat
    ) -> some View {
        Group {
            if let inlineLayout = cell?.inlineLayout {
                InlineRunsView(
                    prepared: inlineLayout,
                    theme: theme,
                    baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                    linkAction: configuration.linkAction,
                    inlineRenderingMode: configuration.inlineRenderingMode
                )
            } else {
                InlineRunsView(
                    attributed: cell?.inline ?? AttributedString(""),
                    theme: theme,
                    baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                    linkAction: configuration.linkAction,
                    inlineRenderingMode: configuration.inlineRenderingMode
                )
            }
        }
        .font(isHeader ? theme.paragraphFont.bold() : theme.paragraphFont)
        .foregroundStyle(theme.textColor)
        .padding(.horizontal, theme.tableHorizontalCellPadding)
        .padding(.vertical, theme.tableVerticalCellPadding)
        .frame(width: width, alignment: tableAlignment(column))
        .frame(minHeight: 38)
        .overlay(alignment: .trailing) {
            if !isLastColumn {
                Rectangle()
                    .fill(theme.tableBorderColor.opacity(0.72))
                    .frame(width: 1)
            }
        }
        .textSelection(.enabled)
    }

    private func tableRowBackground(rowIndex: Int, isHeader: Bool) -> Color {
        if isHeader {
            return theme.tableHeaderBackground
        }

        return rowIndex.isMultiple(of: 2) ? Color.clear : theme.tableAlternateRowBackground
    }

    private func tableColumnWidths(for table: MarkdownPreparedTableBlock) -> [CGFloat] {
        let columnCount = max(
            table.header.count,
            table.rows.map { $0.cells.count }.max() ?? 0
        )
        guard columnCount > 0 else {
            return []
        }

        return (0..<columnCount).map { column in
            let naturalWidth = tableNaturalWidth(table: table, column: column)
            let paddedWidth = naturalWidth + (theme.tableHorizontalCellPadding * 2) + 18
            let minimum = columnCount > 3 ? CGFloat(112) : CGFloat(132)
            let maximum = columnCount <= 2 ? CGFloat(520) : CGFloat(360)
            return min(max(CGFloat(paddedWidth), minimum), maximum)
        }
    }

    private func tableNaturalWidth(table: MarkdownPreparedTableBlock, column: Int) -> Double {
        var cells: [MarkdownPreparedTableCell] = []
        if let header = table.header[safe: column] {
            cells.append(header)
        }
        cells.append(contentsOf: table.rows.compactMap { $0.cells[safe: column] })

        let measuredWidths = cells.map { cell in
            cell.inlineLayout?.measured.naturalWidth ??
                Double(cell.inline?.characters.count ?? 0) * theme.paragraphFontSize * 0.56
        }
        return measuredWidths.max() ?? 0
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
            configuration.affordanceActionHandler.copyString(markdown)
        }
    }

    private func copyCodeBlock() {
        let code = Self.codeCopyText(for: block)
        guard !code.isEmpty else {
            return
        }

        Task { @MainActor in
            configuration.affordanceActionHandler.copyString(code)
        }
    }

    private func exportCodeBlock() {
        let code = Self.codeCopyText(for: block)
        guard !code.isEmpty else {
            return
        }

        let payload = MarkdownExportPayload(
            markdown: code,
            suggestedFilename: Self.codeExportFilename(for: block)
        )
        Task { @MainActor in
            configuration.affordanceActionHandler.exportMarkdown(payload)
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
            let codeText = MarkdownRendererConfiguration.codeText(for: block)
            let decision = configuration.codePolicy.evaluateCodeBlock(
                infoString: block.infoString,
                code: codeText
            )
            let codeAllowed = policyAllowed(decision)
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                codeAllowed: codeAllowed,
                codeLanguageLabel: codeAllowed && configuration.theme.codeBlockAffordances.showsLanguageLabel
                    ? Self.codeBlockLanguageLabel(for: block)
                    : nil,
                codeCopyButtonVisible: codeAllowed && configuration.theme.codeBlockAffordances.showsCopyButton,
                codeExportButtonVisible: codeAllowed && configuration.theme.codeBlockAffordances.showsExportButton,
                codeCollapseButtonVisible: codeAllowed && configuration.theme.codeBlockAffordances.showsCollapseButton,
                codeInitiallyCollapsed: codeAllowed && configuration.theme.codeBlockAffordances.startsCollapsed,
                policyDenialReason: denialReason(decision)
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

    public nonisolated static func codeBlockLanguageLabel(for block: MarkdownBlock) -> String? {
        guard block.kind == .codeBlock else {
            return nil
        }

        return MarkdownCodeLanguage(infoString: block.infoString).displayName
    }

    public nonisolated static func codeCopyText(for block: MarkdownBlock) -> String {
        guard block.kind == .codeBlock else {
            return ""
        }

        return MarkdownRendererConfiguration.codeText(for: block)
    }

    public nonisolated static func codeExportFilename(for block: MarkdownBlock) -> String {
        let language = MarkdownCodeLanguage(infoString: block.infoString)
        let suffix = language.canonicalName ?? language.normalizedInfoString ?? "txt"
        let cleanedSuffix = suffix
            .replacingOccurrences(of: "plaintext", with: "txt")
            .replacingOccurrences(of: "javascript", with: "js")
            .replacingOccurrences(of: "typescript", with: "ts")
            .replacingOccurrences(of: "objectivec", with: "m")
        return "CodeBlock.\(cleanedSuffix)"
    }

    private var headingFallbackText: String {
        let inlineText = block.inlines.map(\.text).joined()
        return inlineText.isEmpty ? block.text : inlineText
    }

    private var headingFont: Font {
        theme.headingStyle(for: block.headingLevel).font
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
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                markerView
                    .frame(width: markerWidth, alignment: .trailing)
                listItemInlineView
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !item.childItems.isEmpty {
                MarkdownListItemsView(
                    items: item.childItems,
                    kind: item.childListKind ?? .unorderedList,
                    orderedStart: item.childOrderedListStart,
                    configuration: configuration,
                    theme: theme
                )
                .padding(.leading, markerWidth + 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var listItemInlineView: some View {
        if let inlineLayout = item.inlineLayout {
            InlineRunsView(
                prepared: inlineLayout,
                theme: theme,
                baseFont: theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode
            )
        } else {
            InlineRunsView(
                attributed: item.inline ?? AttributedString(""),
                theme: theme,
                baseFont: theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode
            )
        }
    }

    private var marker: String {
        switch kind {
        case .orderedList:
            return "\(Int(orderedStart ?? 1) + index)."
        default:
            return "•"
        }
    }

    @ViewBuilder
    private var markerView: some View {
        if let taskState = item.taskState {
            Image(systemName: taskState == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(taskState == .checked ? Color.accentColor : theme.secondaryTextColor)
        } else {
            Text(marker)
                .font(theme.codeFont)
                .foregroundStyle(theme.secondaryTextColor)
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
