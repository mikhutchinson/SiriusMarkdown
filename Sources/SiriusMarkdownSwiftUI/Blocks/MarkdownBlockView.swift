import SiriusMarkdownCore
import SwiftUI

public struct MarkdownBlockView: View {
    private var block: MarkdownBlock
    private var configuration: MarkdownRendererConfiguration
    private var preparedContent: MarkdownPreparedBlockContent
    @State private var isCodeBlockCollapsed: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                MarkdownLeadingContentLayout(leadingWidth: 3, spacing: 8, stretchesLeadingToContentHeight: true) {
                    Rectangle()
                        .fill(theme.quoteAccent)
                        .frame(width: 3)
                    inlineContent(
                        baseFont: theme.paragraphFont,
                        fallbackText: block.text,
                        nativeTextSelection: selectionModeInsideLeadingLayout
                    )
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
    private func inlineContent(
        baseFont: Font,
        fallbackText: String,
        nativeTextSelection: MarkdownNativeTextSelection? = nil
    ) -> some View {
        let selectionMode = nativeTextSelection ?? configuration.nativeTextSelection
        if let inlineLayout = preparedContent.inlineLayout {
            InlineRunsView(
                prepared: inlineLayout,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionMode
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let inline = preparedContent.inline {
            InlineRunsView(
                attributed: inline,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionMode
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if block.inlines.isEmpty {
            selectableText(
                AttributedString(fallbackText),
                font: baseFont,
                textColor: theme.textColor,
                selectionMode: selectionMode,
                metrics: fallbackTextMetrics
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            InlineRunsView(
                runs: block.inlines,
                theme: theme,
                baseFont: baseFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionMode,
                linkPolicy: configuration.linkPolicy,
                imagePolicy: configuration.imagePolicy
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectableText(
        _ attributed: AttributedString,
        font: Font,
        textColor: Color,
        selectionMode: MarkdownNativeTextSelection,
        metrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile),
        lineSpacing: CGFloat = 0,
        wraps: Bool = true
    ) -> some View {
        MarkdownSelectableText(
            attributed: attributed,
            font: font,
            fontSize: metrics.fontSize,
            lineHeight: metrics.lineHeight,
            fontProfile: metrics.fontProfile,
            textColor: textColor,
            linkAction: configuration.linkAction,
            nativeTextSelection: selectionMode,
            lineSpacing: lineSpacing,
            wraps: wraps
        )
    }

    private var fallbackTextMetrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        switch block.kind {
        case .heading:
            let style = theme.headingStyle(for: block.headingLevel)
            return (style.fontSize, style.lineHeight, style.fontProfiles.body)
        case .codeBlock, .htmlBlock, .mathBlock:
            return (theme.codeFontSize, theme.codeLineHeight, theme.codeFontProfiles.body)
        default:
            return (theme.paragraphFontSize, theme.paragraphLineHeight, theme.paragraphFontProfiles.body)
        }
    }

    @ViewBuilder
    private var codeBlockContent: some View {
        if let mermaid = preparedContent.mermaid {
            VStack(alignment: .leading, spacing: 0) {
                if showsCodeBlockHeader {
                    codeBlockHeader
                }
                if !isCodeBlockCollapsed {
                    MarkdownMermaidDiagramView(
                        mermaid: mermaid,
                        colorScheme: colorScheme,
                        theme: theme,
                        baseFont: theme.codeFont
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, showsCodeBlockHeader ? 4 : 10)
                    .padding(.bottom, 10)
                } else {
                    Text("\(Self.codeCopyText(for: block).utf8.count.formatted()) bytes hidden")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Mermaid diagram collapsed")
                }
            }
            .background(theme.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let code = preparedContent.code {
            VStack(alignment: .leading, spacing: 0) {
                if showsCodeBlockHeader {
                    codeBlockHeader
                }
                if !isCodeBlockCollapsed {
                    ScrollView(.horizontal) {
                        selectableText(
                            code,
                            font: theme.codeFont,
                            textColor: theme.textColor,
                            selectionMode: configuration.nativeTextSelection,
                            metrics: codeTextMetrics,
                            wraps: false
                        )
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
            selectableText(
                AttributedString(MarkdownRendererConfiguration.codeText(for: block)),
                font: theme.codeFont,
                textColor: theme.textColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics,
                wraps: false
            )
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
            selectableText(
                math,
                font: theme.codeFont,
                textColor: theme.textColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics
            )
                .padding(8)
                .background(theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            selectableText(
                AttributedString(MarkdownRendererConfiguration.mathText(for: block)),
                font: theme.codeFont,
                textColor: theme.textColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics
            )
        }
    }

    @ViewBuilder
    private var htmlBlockContent: some View {
        if preparedContent.htmlAllowed == true {
            selectableText(
                AttributedString(block.text),
                font: theme.codeFont,
                textColor: theme.secondaryTextColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics
            )
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
                    inlineRenderingMode: configuration.inlineRenderingMode,
                    nativeTextSelection: selectionModeInsideCompositeGrid
                )
            } else {
                InlineRunsView(
                    attributed: cell?.inline ?? AttributedString(""),
                    theme: theme,
                    baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                    linkAction: configuration.linkAction,
                    inlineRenderingMode: configuration.inlineRenderingMode,
                    nativeTextSelection: selectionModeInsideCompositeGrid
                )
            }
        }
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

    private var selectionModeInsideLeadingLayout: MarkdownNativeTextSelection {
        // Native SelectionOverlay can re-enter custom leading layouts during
        // right-panel updates; keep those composite surfaces copy-only.
        .disabled
    }

    private var selectionModeInsideCompositeGrid: MarkdownNativeTextSelection {
        // Table grids use fixed-width cell composition, which is not a stable
        // native-selection leaf on macOS 26.
        .disabled
    }

    private var codeTextMetrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        (theme.codeFontSize, theme.codeLineHeight, theme.codeFontProfiles.body)
    }

    private func policyDeniedView(reason: String) -> some View {
        selectableText(
            AttributedString(reason),
            font: theme.codeFont,
            textColor: theme.secondaryTextColor,
            selectionMode: configuration.nativeTextSelection,
            metrics: codeTextMetrics
        )
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
        renderPlan(for: block, configuration: configuration, preparedContent: nil)
    }

    public nonisolated static func renderPlan(
        for block: MarkdownBlock,
        configuration: MarkdownRendererConfiguration = .compactChat,
        preparedContent: MarkdownPreparedBlockContent?
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
            let language = MarkdownCodeLanguage(infoString: block.infoString)
            let decision = configuration.codePolicy.evaluateCodeBlock(
                infoString: block.infoString,
                code: codeText
            )
            let codeAllowed = policyAllowed(decision)
            let mermaidRendered = codeAllowed && language.isMermaid && configuration.mermaidRenderer != nil
            let mermaidHasGeometry = preparedContent?.mermaid?.geometry != nil
            let mermaidAffordances = configuration.theme.mermaidAffordances
            let mermaidControlsVisible = mermaidRendered && mermaidHasGeometry && mermaidAffordances.showsToolbar
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                codeAllowed: codeAllowed,
                mermaidRendered: mermaidRendered,
                mermaidControlsVisible: mermaidControlsVisible,
                mermaidZoomControlsVisible: mermaidControlsVisible && mermaidAffordances.showsZoomControls,
                mermaidFitButtonVisible: mermaidControlsVisible && mermaidAffordances.showsFitButton,
                mermaidResetButtonVisible: mermaidControlsVisible && mermaidAffordances.showsResetButton,
                mermaidHasGeometry: mermaidHasGeometry,
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
            return MarkdownCodeLanguage(infoString: block.infoString).isMermaid ? "Mermaid diagram" : "Code block"
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
            MarkdownLeadingContentLayout(leadingWidth: markerWidth, spacing: 8) {
                markerView
                    .frame(width: markerWidth, alignment: .trailing)
                listItemInlineView
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
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideLeadingLayout
            )
        } else {
            InlineRunsView(
                attributed: item.inline ?? AttributedString(""),
                theme: theme,
                baseFont: theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideLeadingLayout
            )
        }
    }

    private var selectionModeInsideLeadingLayout: MarkdownNativeTextSelection {
        // List rows share the same custom leading-layout risk as block quotes.
        .disabled
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
                .font(.system(size: taskMarkerFontSize, weight: .semibold))
                .foregroundStyle(taskState == .checked ? Color.accentColor : theme.secondaryTextColor)
                .frame(height: theme.paragraphLineHeight, alignment: .trailing)
        } else {
            Text(marker)
                .font(theme.codeFont)
                .foregroundStyle(theme.secondaryTextColor)
        }
    }

    private var markerWidth: CGFloat {
        kind == .orderedList ? 34 : 28
    }

    private var taskMarkerFontSize: CGFloat {
        CGFloat(min(max(theme.paragraphFontSize - 2, 12), 14))
    }
}

private struct MarkdownLeadingContentLayout: Layout {
    var leadingWidth: CGFloat
    var spacing: CGFloat
    var stretchesLeadingToContentHeight: Bool = false

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard subviews.count >= 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }

        let availableWidth = finiteWidth(from: proposal)
        let contentWidth = availableWidth.map { max(0, $0 - leadingWidth - spacing) }
        let leadingSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: leadingWidth, height: proposal.height)
        )
        let contentSize = subviews[1].sizeThatFits(
            ProposedViewSize(width: contentWidth, height: proposal.height)
        )
        let height = max(leadingSize.height, contentSize.height)
        let width = availableWidth ?? leadingWidth + spacing + contentSize.width
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard subviews.count >= 2 else {
            subviews.first?.place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
            )
            return
        }

        let contentWidth = max(0, bounds.width - leadingWidth - spacing)
        let leadingHeight = stretchesLeadingToContentHeight ? bounds.height : nil
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: leadingWidth, height: leadingHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leadingWidth + spacing, y: bounds.minY),
            proposal: ProposedViewSize(width: contentWidth, height: bounds.height)
        )
    }

    private func finiteWidth(from proposal: ProposedViewSize) -> CGFloat? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }
        return width
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
