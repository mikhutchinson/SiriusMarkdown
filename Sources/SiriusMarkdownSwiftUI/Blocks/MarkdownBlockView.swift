import SiriusMarkdownCore
import SwiftUI

/// A bounded group keeps the active streaming suffix small while letting
/// SwiftUI treat completed groups as one stable graph child. Rendering every
/// accumulated row as a direct child makes AttributeGraph revisit a triangular
/// number of row subtrees even when all row equality tokens are unchanged.
private struct MarkdownPreparedTableRowRenderGroup: Identifiable {
    static let capacity = 8

    let startIndex: Int
    let rows: [MarkdownPreparedTableRow]
    let id: String
    let contentFingerprint: MarkdownContentFingerprint
    let preparedLayoutHeight: Double?

    init(startIndex: Int, rows: [MarkdownPreparedTableRow]) {
        self.startIndex = startIndex
        self.rows = rows
        self.id = rows.first?.id ?? "table-row-group:\(startIndex)"
        var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-table-row-group")
        fingerprint.combine(startIndex)
        fingerprint.combine(rows.count)
        for row in rows {
            fingerprint.combine(row.contentFingerprint)
        }
        self.contentFingerprint = fingerprint
        let heights = rows.compactMap(\.preparedLayoutHeight)
        self.preparedLayoutHeight = heights.count == rows.count
            ? heights.reduce(0, +)
            : nil
    }
}

public struct MarkdownBlockView: View {
    private var block: MarkdownBlock
    private var configuration: MarkdownRendererConfiguration
    private var preparedContent: MarkdownPreparedBlockContent
    @State private var isCodeBlockCollapsed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.markdownDocumentSelectionContext) private var documentSelectionContext
    @Environment(\.markdownDocumentStyleAggregate) private var documentStyleAggregate
    @Environment(\.markdownHeadingBlockStyleOverride) private var headingBlockStyleOverride
    @Environment(\.markdownParagraphBlockStyleOverride) private var paragraphBlockStyleOverride
    @Environment(\.markdownBlockQuoteStyleOverride) private var blockQuoteStyleOverride
    @Environment(\.markdownThematicBreakStyleOverride) private var thematicBreakStyleOverride
    @Environment(\.markdownCodeBlockStyleOverride) private var codeBlockStyleOverride
    @Environment(\.markdownMermaidBlockStyleOverride) private var mermaidBlockStyleOverride
    @Environment(\.markdownMathBlockStyleOverride) private var mathBlockStyleOverride
    @Environment(\.markdownHTMLBlockStyleOverride) private var htmlBlockStyleOverride
    @Environment(\.markdownTableBlockStyleOverride) private var tableBlockStyleOverride
    @Environment(\.markdownTableCellStyleOverride) private var tableCellStyleOverride

    private var theme: MarkdownTheme {
        configuration.theme
    }

    // MARK: - Style resolution (INV-BS9)
    //
    // `override ?? environment aggregate slot ?? configuration.documentStyle
    // slot ?? MarkdownDefault*Style` — see `resolvedMarkdownStyle` in
    // `View+Markdown.swift` for the merge-order contract.

    private var resolvedHeadingStyle: any MarkdownHeadingBlockStyle {
        resolvedMarkdownStyle(
            override: headingBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.headingStyle },
            default: MarkdownDefaultHeadingBlockStyle()
        )
    }

    private var resolvedParagraphStyle: any MarkdownParagraphBlockStyle {
        resolvedMarkdownStyle(
            override: paragraphBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.paragraphStyle },
            default: MarkdownDefaultParagraphBlockStyle()
        )
    }

    private var resolvedBlockQuoteStyle: any MarkdownBlockQuoteStyle {
        resolvedMarkdownStyle(
            override: blockQuoteStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.blockQuoteStyle },
            default: MarkdownDefaultBlockQuoteStyle()
        )
    }

    private var resolvedThematicBreakStyle: any MarkdownThematicBreakStyle {
        resolvedMarkdownStyle(
            override: thematicBreakStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.thematicBreakStyle },
            default: MarkdownDefaultThematicBreakStyle()
        )
    }

    private var resolvedCodeBlockStyle: any MarkdownCodeBlockStyle {
        resolvedMarkdownStyle(
            override: codeBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.codeBlockStyle },
            default: MarkdownDefaultCodeBlockStyle()
        )
    }

    private var resolvedMermaidBlockStyle: any MarkdownMermaidBlockStyle {
        resolvedMarkdownStyle(
            override: mermaidBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.mermaidBlockStyle },
            default: MarkdownDefaultMermaidBlockStyle()
        )
    }

    private var resolvedMathBlockStyle: any MarkdownMathBlockStyle {
        resolvedMarkdownStyle(
            override: mathBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.mathBlockStyle },
            default: MarkdownDefaultMathBlockStyle()
        )
    }

    private var resolvedHTMLBlockStyle: any MarkdownHTMLBlockStyle {
        resolvedMarkdownStyle(
            override: htmlBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.htmlBlockStyle },
            default: MarkdownDefaultHTMLBlockStyle()
        )
    }

    private var resolvedTableStyle: any MarkdownTableBlockStyle {
        resolvedMarkdownStyle(
            override: tableBlockStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.tableStyle },
            default: MarkdownDefaultTableBlockStyle()
        )
    }

    private var resolvedTableCellStyle: any MarkdownTableCellStyle {
        resolvedMarkdownStyle(
            override: tableCellStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.tableCellStyle },
            default: MarkdownDefaultTableCellStyle()
        )
    }

    @available(*, deprecated, message: "Prepare block content outside SwiftUI update paths and use init(block:configuration:preparedContent:) for streaming or large documents.")
    public init(block: MarkdownBlock, theme: MarkdownTheme = .compactChat) {
        self.block = block
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .coreTextPaintedLines)
        self.preparedContent = self.configuration.unpreparedContent(for: block)
        _isCodeBlockCollapsed = State(initialValue: self.configuration.theme.codeBlockAffordances.startsCollapsed)
    }

    @available(*, deprecated, message: "Prepare block content outside SwiftUI update paths and use init(block:configuration:preparedContent:) for streaming or large documents.")
    public init(block: MarkdownBlock, configuration: MarkdownRendererConfiguration) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = configuration.unpreparedContent(for: block)
        _isCodeBlockCollapsed = State(initialValue: configuration.theme.codeBlockAffordances.startsCollapsed)
    }

    public init(
        block: MarkdownBlock,
        configuration: MarkdownRendererConfiguration,
        preparedContent: MarkdownPreparedBlockContent?
    ) {
        self.block = block
        self.configuration = configuration
        self.preparedContent = preparedContent ?? configuration.unpreparedContent(for: block)
        _isCodeBlockCollapsed = State(initialValue: configuration.theme.codeBlockAffordances.startsCollapsed)
    }

    public var body: some View {
        Group {
            switch block.kind {
            case .heading:
                headingContent
            case .codeBlock:
                codeBlockContent
            case .blockQuote:
                blockQuoteContent
            case .thematicBreak:
                thematicBreakContent
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
                paragraphContent
            }
        }
        .id(block.id)
        .accessibilityLabel(Self.accessibilityLabel(for: block))
        .onAppear {
            MarkdownDiagnostics().signpostEvent("BlockRender", category: "SwiftUI")
        }
    }

    private var headingContent: some View {
        AnyView(resolvedHeadingStyle.makeBody(
            configuration: MarkdownHeadingBlockStyleConfiguration(
                label: MarkdownBlockStyleLabel(inlineContent(baseFont: headingFont, fallbackText: headingFallbackText)),
                theme: theme,
                blockID: block.id,
                indentationLevel: 0,
                headingLevel: block.headingLevel ?? 1
            )
        ))
    }

    private var paragraphContent: some View {
        AnyView(resolvedParagraphStyle.makeBody(
            configuration: MarkdownParagraphBlockStyleConfiguration(
                label: MarkdownBlockStyleLabel(inlineContent(baseFont: theme.paragraphFont, fallbackText: block.text)),
                theme: theme,
                blockID: block.id,
                indentationLevel: 0
            )
        ))
    }

    private var blockQuoteContent: some View {
        AnyView(resolvedBlockQuoteStyle.makeBody(
            configuration: MarkdownBlockQuoteStyleConfiguration(
                label: MarkdownBlockStyleLabel(
                    inlineContent(
                        baseFont: theme.paragraphFont,
                        fallbackText: block.text,
                        nativeTextSelection: selectionModeInsideLeadingLayout
                    )
                ),
                theme: theme,
                blockID: block.id,
                indentationLevel: 0
            )
        ))
    }

    private var thematicBreakContent: some View {
        AnyView(resolvedThematicBreakStyle.makeBody(
            configuration: MarkdownThematicBreakStyleConfiguration(
                theme: theme,
                blockID: block.id,
                indentationLevel: 0
            )
        ))
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
                nativeTextSelection: selectionMode,
                fontSize: fallbackTextMetrics.fontSize,
                lineHeight: fallbackTextMetrics.lineHeight,
                fontProfile: fallbackTextMetrics.fontProfile
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
                imagePolicy: configuration.imagePolicy,
                fontSize: fallbackTextMetrics.fontSize,
                lineHeight: fallbackTextMetrics.lineHeight,
                fontProfile: fallbackTextMetrics.fontProfile
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
        wraps: Bool = true,
        selectionInlineLayout: MarkdownPreparedInlineContent? = nil
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
            wraps: wraps,
            selectionInlineLayout: selectionInlineLayout
        )
    }

    private var fallbackTextMetrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        switch block.kind {
        case .heading:
            let style = theme.headingStyle(for: block.headingLevel)
            return sanitizedTextMetrics(
                fontSize: style.fontSize,
                lineHeight: style.lineHeight,
                fontProfile: style.fontProfiles.body,
                fallbackFontSize: 20,
                fallbackLineHeight: 28
            )
        case .codeBlock, .htmlBlock, .mathBlock:
            return codeTextMetrics
        default:
            return paragraphTextMetrics
        }
    }

    @ViewBuilder
    private var codeBlockContent: some View {
        if let mermaid = preparedContent.mermaid {
            AnyView(resolvedMermaidBlockStyle.makeBody(
                configuration: MarkdownMermaidBlockStyleConfiguration(
                    label: MarkdownBlockStyleLabel(mermaidLabel(mermaid)),
                    theme: theme,
                    blockID: block.id,
                    indentationLevel: 0,
                    languageLabel: Self.codeBlockLanguageLabel(for: block),
                    isCollapsed: isCodeBlockCollapsed,
                    actions: codeBlockActions
                )
            ))
        } else if let code = preparedContent.code {
            AnyView(resolvedCodeBlockStyle.makeBody(
                configuration: MarkdownCodeBlockStyleConfiguration(
                    label: MarkdownBlockStyleLabel(codeLabel(code)),
                    theme: theme,
                    blockID: block.id,
                    indentationLevel: 0,
                    languageHint: block.infoString,
                    languageLabel: Self.codeBlockLanguageLabel(for: block),
                    isCollapsed: isCodeBlockCollapsed,
                    actions: codeBlockActions
                )
            ))
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            // Deprecated unprepared path: no highlighting ever ran, so
            // default chrome intentionally shows no header/affordances
            // here, matching pre-style `MarkdownBlockView` exactly.
            AnyView(resolvedCodeBlockStyle.makeBody(
                configuration: MarkdownCodeBlockStyleConfiguration(
                    label: MarkdownBlockStyleLabel(
                        selectableText(
                            AttributedString(MarkdownRendererConfiguration.codeText(for: block)),
                            font: theme.codeFont,
                            textColor: theme.textColor,
                            selectionMode: configuration.nativeTextSelection,
                            metrics: codeTextMetrics,
                            wraps: false,
                            selectionInlineLayout: preparedContent.selectionInlineLayout
                        )
                    ),
                    theme: theme,
                    blockID: block.id,
                    indentationLevel: 0,
                    languageHint: nil,
                    languageLabel: nil,
                    isCollapsed: false,
                    actions: MarkdownCodeBlockActions()
                )
            ))
        }
    }

    @ViewBuilder
    private func mermaidLabel(_ mermaid: MarkdownPreparedMermaidDiagram) -> some View {
        if isCodeBlockCollapsed {
            Text("\(Self.codeCopyText(for: block).utf8.count.formatted()) bytes hidden")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Mermaid diagram collapsed")
        } else {
            MarkdownMermaidDiagramView(
                mermaid: mermaid,
                colorScheme: colorScheme,
                theme: theme,
                baseFont: theme.codeFont,
                nativeTextSelection: configuration.nativeTextSelection
            )
        }
    }

    @ViewBuilder
    private func codeLabel(_ code: AttributedString) -> some View {
        if isCodeBlockCollapsed {
            Text("\(Self.codeCopyText(for: block).utf8.count.formatted()) bytes hidden")
                .font(.caption)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Code block collapsed")
        } else {
            selectableText(
                code,
                font: theme.codeFont,
                textColor: theme.textColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics,
                wraps: false,
                selectionInlineLayout: preparedContent.selectionInlineLayout
            )
        }
    }

    private var codeBlockActions: MarkdownCodeBlockActions {
        // NOTE: built with `if` statements rather than `?:` ternaries.
        // Ternary branches selecting between a `self`-capturing closure
        // literal and `nil` do not propagate the `@MainActor` (implicitly
        // `Sendable`) target type into the closure literal correctly, and
        // fail with a spurious Sendable conversion error (or, with three
        // in one initializer call, a compiler diagnostic-emission crash).
        var copyAction: (@MainActor () -> Void)?
        if theme.codeBlockAffordances.showsCopyButton {
            copyAction = { copyCodeBlock() }
        }
        var exportAction: (@MainActor () -> Void)?
        if theme.codeBlockAffordances.showsExportButton {
            exportAction = { exportCodeBlock() }
        }
        var collapseAction: (@MainActor () -> Void)?
        if theme.codeBlockAffordances.showsCollapseButton {
            collapseAction = { isCodeBlockCollapsed.toggle() }
        }
        return MarkdownCodeBlockActions(
            copy: copyAction,
            export: exportAction,
            toggleCollapse: collapseAction
        )
    }

    private var listContent: some View {
        MarkdownListItemsView(
            items: preparedContent.listItems,
            kind: block.kind,
            orderedStart: block.orderedListStart,
            configuration: configuration,
            theme: theme,
            blockID: block.id,
            indentationLevel: 0
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tableContent: some View {
        if let table = preparedContent.table {
            let columnWidths = table.columnWidths.map { CGFloat($0) }
            let usesPreparedLayoutHeights = resolvedTableCellStyle is MarkdownDefaultTableCellStyle &&
                table.hasPreparedLayoutHeights
            let grid = MarkdownStreamingTableRowStackLayout(
                diagnosticsRecorder: configuration.diagnosticsRecorder,
                measurementCache: usesPreparedLayoutHeights
                    ? configuration.preparationCache
                    : nil
            ) {
                if !table.header.isEmpty {
                    let layoutToken = MarkdownStreamingTableRowLayoutToken(
                        id: table.headerID,
                        contentFingerprint: table.headerContentFingerprint,
                        columnWidthFingerprint: table.columnWidthFingerprint,
                        columnWidthRevision: table.columnWidthRevision,
                        layoutContextIdentity: theme.renderCacheIdentity,
                        inlineRenderingMode: configuration.inlineRenderingMode,
                        nativeTextSelection: selectionModeInsideCompositeGrid,
                        preparedLayoutHeight: usesPreparedLayoutHeights
                            ? table.headerPreparedLayoutHeight
                            : nil
                    )
                    tableRowsWithStableRenderBoundary(
                        layoutToken: layoutToken,
                        columnAlignments: table.columnAlignments,
                        usesStableRenderBoundary: usesPreparedLayoutHeights
                    ) {
                        tableRow(
                            cells: table.header,
                            rowIndex: -1,
                            isHeader: true,
                            columnWidths: columnWidths,
                            preparedLayoutHeight: usesPreparedLayoutHeights
                                ? table.headerPreparedLayoutHeight
                                : nil
                        )
                    }
                }

                ForEach(tableRowRenderGroups(table.rows)) { group in
                    let layoutToken = MarkdownStreamingTableRowLayoutToken(
                        id: group.id,
                        contentFingerprint: group.contentFingerprint,
                        columnWidthFingerprint: table.columnWidthFingerprint,
                        columnWidthRevision: table.columnWidthRevision,
                        layoutContextIdentity: theme.renderCacheIdentity,
                        inlineRenderingMode: configuration.inlineRenderingMode,
                        nativeTextSelection: selectionModeInsideCompositeGrid,
                        preparedLayoutHeight: usesPreparedLayoutHeights
                            ? group.preparedLayoutHeight
                            : nil
                    )
                    tableRowsWithStableRenderBoundary(
                        layoutToken: layoutToken,
                        columnAlignments: table.columnAlignments,
                        usesStableRenderBoundary: usesPreparedLayoutHeights
                    ) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { offset, row in
                                tableRow(
                                    cells: row.cells,
                                    rowIndex: group.startIndex + offset,
                                    isHeader: false,
                                    columnWidths: columnWidths,
                                    preparedLayoutHeight: usesPreparedLayoutHeights
                                        ? row.preparedLayoutHeight
                                        : nil
                                )
                            }
                        }
                    }
                }
            }
            .background(tableSelectionFragmentPreference(
                table: table,
                enabled: usesPreparedLayoutHeights
            ))

            AnyView(resolvedTableStyle.makeBody(
                configuration: MarkdownTableBlockStyleConfiguration(
                    label: MarkdownBlockStyleLabel(grid),
                    theme: theme,
                    blockID: block.id,
                    indentationLevel: 0
                )
            ))
        } else {
            inlineContent(baseFont: theme.codeFont, fallbackText: block.text)
        }
    }

    @ViewBuilder
    private func tableRowsWithStableRenderBoundary<Content: View>(
        layoutToken: MarkdownStreamingTableRowLayoutToken,
        columnAlignments: [MarkdownTableColumnAlignment?],
        usesStableRenderBoundary: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if usesStableRenderBoundary {
            MarkdownStreamingTableRowRenderBoundary(
                token: MarkdownStreamingTableRowRenderToken(
                    layoutToken: layoutToken,
                    columnAlignments: columnAlignments,
                    linkActionIdentity: configuration.linkAction?.renderIdentity
                ),
                diagnosticsRecorder: configuration.diagnosticsRecorder
            ) {
                content()
            }
            .equatable()
            .markdownStreamingTableRowLayoutToken(layoutToken)
        } else {
            content()
            .markdownStreamingTableRowLayoutToken(layoutToken)
        }
    }

    private func tableRowRenderGroups(
        _ rows: [MarkdownPreparedTableRow]
    ) -> [MarkdownPreparedTableRowRenderGroup] {
        stride(from: 0, to: rows.count, by: MarkdownPreparedTableRowRenderGroup.capacity).map { start in
            let end = min(rows.count, start + MarkdownPreparedTableRowRenderGroup.capacity)
            return MarkdownPreparedTableRowRenderGroup(
                startIndex: start,
                rows: Array(rows[start..<end])
            )
        }
    }

    private func tableRow(
        cells: [MarkdownPreparedTableCell],
        rowIndex: Int,
        isHeader: Bool,
        columnWidths: [CGFloat],
        preparedLayoutHeight: Double?
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(columnWidths.indices, id: \.self) { column in
                tableCell(
                    cells[safe: column],
                    row: rowIndex,
                    column: column,
                    columnCount: columnWidths.count,
                    isHeader: isHeader,
                    isLastColumn: column == columnWidths.count - 1,
                    width: columnWidths[column]
                )
            }
        }
        .frame(
            minHeight: preparedLayoutHeight.map { CGFloat($0) },
            alignment: .top
        )
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
    private func tableSelectionFragmentPreference(
        table: MarkdownPreparedTableBlock,
        enabled: Bool
    ) -> some View {
        if enabled {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MarkdownDocumentSelectionFragmentsKey.self,
                    value: tableSelectionFragments(
                        table: table,
                        rect: proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
                    )
                )
            }
            .allowsHitTesting(false)
        }
    }

    private func tableSelectionFragments(
        table: MarkdownPreparedTableBlock,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0
        else {
            return []
        }

        let horizontalPadding = theme.renderTableHorizontalCellPadding
        let verticalPadding = theme.renderTableVerticalCellPadding
        var fragments: [MarkdownDocumentSelectionFragment] = []
        var rowOriginY = rect.minY

        func appendCells(
            _ cells: [MarkdownPreparedTableCell],
            rowID: String,
            rowHeight: CGFloat
        ) {
            var columnOriginX = rect.minX
            for column in table.columnWidths.indices {
                let columnWidth = CGFloat(table.columnWidths[column])
                defer { columnOriginX += columnWidth }
                guard cells.indices.contains(column),
                      let prepared = cells[column].inlineLayout ?? cells[column].selectionInlineLayout,
                      let layout = prepared.initialLayoutResult
                else {
                    continue
                }
                let contentRect = CGRect(
                    x: columnOriginX + horizontalPadding,
                    y: rowOriginY + verticalPadding,
                    width: max(1, columnWidth - horizontalPadding * 2),
                    height: max(1, rowHeight - verticalPadding * 2)
                )
                fragments.append(contentsOf: MarkdownDocumentSelectionFragment.inlineLineFragments(
                    blockID: documentSelectionContext.blockID,
                    prepared: prepared,
                    layout: layout,
                    rect: contentRect,
                    idPrefix: "table:\(rowID):\(column)"
                ))
            }
        }

        let headerHeight = CGFloat(table.headerPreparedLayoutHeight ?? 38)
        appendCells(table.header, rowID: table.headerID, rowHeight: headerHeight)
        rowOriginY += headerHeight
        for row in table.rows {
            let rowHeight = CGFloat(row.preparedLayoutHeight ?? 38)
            appendCells(row.cells, rowID: row.id, rowHeight: rowHeight)
            rowOriginY += rowHeight
        }
        return fragments
    }

    @ViewBuilder
    private var mathBlockContent: some View {
        if let mathRender = preparedContent.mathRender {
            switch mathRender {
            case let .image(image):
                mathBlockStyleBody(label: mathImageLabel(image), isImage: true)
            case let .text(attributed):
                mathBlockStyleBody(label: mathTextLabel(attributed), isImage: false)
            }
        } else if let math = preparedContent.math {
            mathBlockStyleBody(label: mathTextLabel(math), isImage: false)
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            mathBlockStyleBody(
                label: mathTextLabel(AttributedString(MarkdownRendererConfiguration.mathText(for: block))),
                isImage: false
            )
        }
    }

    private func mathBlockStyleBody(label: some View, isImage: Bool) -> some View {
        AnyView(resolvedMathBlockStyle.makeBody(
            configuration: MarkdownMathBlockStyleConfiguration(
                label: MarkdownBlockStyleLabel(label),
                theme: theme,
                blockID: block.id,
                indentationLevel: 0,
                isImage: isImage
            )
        ))
    }

    @ViewBuilder
    private func mathImageLabel(_ image: MarkdownPreparedMathImage) -> some View {
        let mathView = MarkdownMathImageView(
            image: image,
            color: theme.textColor,
            font: theme.codeFont,
            fontSize: codeTextMetrics.fontSize,
            lineHeight: codeTextMetrics.lineHeight,
            fontProfile: codeTextMetrics.fontProfile,
            nativeTextSelection: configuration.nativeTextSelection
        )
            .padding(.vertical, 6)
        ViewThatFits(in: .horizontal) {
            mathView
                .frame(maxWidth: .infinity, alignment: .center)
            ScrollView(.horizontal, showsIndicators: false) {
                mathView
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(mathImageSelectionFragmentPreference)
    }

    private var mathImageSelectionFragmentPreference: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: mathImageSelectionFragments(rect: rect)
            )
        }
        .allowsHitTesting(false)
    }

    private func mathImageSelectionFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext,
              let selectionInlineLayout = preparedContent.selectionInlineLayout,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0
        else {
            return []
        }

        let layoutWidth = max(
            InlineRunsView.nativeLineLayoutWidth(
                for: selectionInlineLayout,
                containerWidth: Double(rect.width)
            ),
            selectionInlineLayout.measured.naturalWidth
        )
        let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: documentSelectionContext.blockID,
            prepared: selectionInlineLayout,
            layout: selectionInlineLayout.layout(
                containerWidth: layoutWidth,
                allowsOverwideFallback: false
            ),
            rect: rect,
            idPrefix: "math-image-block"
        )
        if !fragments.isEmpty {
            return fragments
        }

        return [
            MarkdownDocumentSelectionFragment.fallbackTextFragment(
                blockID: documentSelectionContext.blockID,
                sourceRange: selectionInlineLayout.prepared.sourceRange ?? block.sourceRange,
                rect: rect,
                idPrefix: "math-image-block"
            )
        ]
    }

    @ViewBuilder
    private func mathTextLabel(_ attributed: AttributedString) -> some View {
        selectableText(
            attributed,
            font: theme.codeFont,
            textColor: theme.textColor,
            selectionMode: configuration.nativeTextSelection,
            metrics: codeTextMetrics,
            selectionInlineLayout: preparedContent.selectionInlineLayout
        )
    }

    @ViewBuilder
    private var htmlBlockContent: some View {
        if preparedContent.htmlAllowed == true {
            AnyView(resolvedHTMLBlockStyle.makeBody(
                configuration: MarkdownHTMLBlockStyleConfiguration(
                    label: MarkdownBlockStyleLabel(
                        nativeRichHTMLContent
                    ),
                    theme: theme,
                    blockID: block.id,
                    indentationLevel: 0
                )
            ))
        } else if let reason = preparedContent.policyDenialReason {
            policyDeniedView(reason: reason)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var nativeRichHTMLContent: some View {
        if let richContent = preparedContent.richContent {
            VStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(richContent.blocks) { richBlock in
                    MarkdownBlockView(
                        block: richBlock.block,
                        configuration: configuration,
                        preparedContent: richBlock.preparedContent
                    )
                    // Rich HTML children are presentation-only native blocks
                    // nested inside one source HTML block. Prevent them from
                    // publishing child identities, then emit source-precise
                    // fragments from each child's actual on-screen bounds
                    // using the enclosing block identity.
                    .environment(\.markdownDocumentSelectionContext, nil)
                    .background(
                        richHTMLSelectionFragmentPreference(
                            block: richBlock.block,
                            preparedContent: richBlock.preparedContent
                        )
                    )
                }
            }
        } else {
            // Manually-constructed legacy HTML blocks may not carry a parsed
            // rich model. Keep that source inert and visibly escaped.
            selectableText(
                AttributedString(block.text),
                font: theme.codeFont,
                textColor: theme.secondaryTextColor,
                selectionMode: configuration.nativeTextSelection,
                metrics: codeTextMetrics,
                selectionInlineLayout: preparedContent.selectionInlineLayout
            )
        }
    }

    private func richHTMLSelectionFragmentPreference(
        block richBlock: MarkdownBlock,
        preparedContent richPreparedContent: MarkdownPreparedBlockContent
    ) -> some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: richHTMLSelectionFragments(
                    block: richBlock,
                    preparedContent: richPreparedContent,
                    rect: rect
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func richHTMLSelectionFragments(
        block richBlock: MarkdownBlock,
        preparedContent richPreparedContent: MarkdownPreparedBlockContent,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext else { return [] }
        return MarkdownDocumentSelectionFragment.fragments(
            for: richBlock,
            preparedContent: richPreparedContent,
            rect: rect
        ).map { fragment in
            var fragment = fragment
            fragment.id = "rich-html:\(documentSelectionContext.blockID.rawValue):\(fragment.id)"
            fragment.blockID = documentSelectionContext.blockID
            return fragment
        }
    }

    @ViewBuilder
    private func tableCell(
        _ cell: MarkdownPreparedTableCell?,
        row: Int,
        column: Int,
        columnCount: Int,
        isHeader: Bool,
        isLastColumn: Bool,
        width: CGFloat
    ) -> some View {
        let fixedPreparedContainerWidth: Double? = if resolvedTableCellStyle is MarkdownDefaultTableCellStyle {
            Double(max(1, width - theme.renderTableHorizontalCellPadding * 2))
        } else {
            nil
        }
        AnyView(resolvedTableCellStyle.makeBody(
            configuration: MarkdownTableCellStyleConfiguration(
                label: MarkdownBlockStyleLabel(tableCellLabel(
                    cell,
                    isHeader: isHeader,
                    fixedPreparedContainerWidth: fixedPreparedContainerWidth
                )),
                theme: theme,
                blockID: block.id,
                indentationLevel: 0,
                row: row,
                column: column,
                columnCount: columnCount,
                isHeader: isHeader,
                isLastColumn: isLastColumn,
                alignment: preparedContent.table?.columnAlignments[safe: column] ?? nil,
                width: width
            )
        ))
    }

    @ViewBuilder
    private func tableCellLabel(
        _ cell: MarkdownPreparedTableCell?,
        isHeader: Bool,
        fixedPreparedContainerWidth: Double?
    ) -> some View {
        if let inlineLayout = cell?.inlineLayout {
            InlineRunsView(
                prepared: inlineLayout,
                theme: theme,
                baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideCompositeGrid
            )
            .preparedContainerWidth(fixedPreparedContainerWidth)
        } else if let selectionInlineLayout = cell?.selectionInlineLayout {
            InlineRunsView(
                prepared: selectionInlineLayout,
                theme: theme,
                baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideCompositeGrid
            )
            .preparedContainerWidth(fixedPreparedContainerWidth)
        } else {
            InlineRunsView(
                attributed: cell?.inline ?? AttributedString(""),
                theme: theme,
                baseFont: isHeader ? theme.paragraphFont.bold() : theme.paragraphFont,
                linkAction: configuration.linkAction,
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideCompositeGrid,
                fontSize: paragraphTextMetrics.fontSize,
                lineHeight: paragraphTextMetrics.lineHeight,
                fontProfile: paragraphTextMetrics.fontProfile
            )
            .preparedContainerWidth(fixedPreparedContainerWidth)
        }
    }

    private func tableRowBackground(rowIndex: Int, isHeader: Bool) -> Color {
        if isHeader {
            return theme.tableHeaderBackground
        }

        return rowIndex.isMultiple(of: 2) ? Color.clear : theme.tableAlternateRowBackground
    }

    private var selectionModeInsideLeadingLayout: MarkdownNativeTextSelection {
        configuration.nativeTextSelection
    }

    private var selectionModeInsideCompositeGrid: MarkdownNativeTextSelection {
        configuration.nativeTextSelection
    }

    private var codeTextMetrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        sanitizedTextMetrics(
            fontSize: theme.codeFontSize,
            lineHeight: theme.codeLineHeight,
            fontProfile: theme.codeFontProfiles.body,
            fallbackFontSize: 14,
            fallbackLineHeight: 20
        )
    }

    private var paragraphTextMetrics: (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        sanitizedTextMetrics(
            fontSize: theme.paragraphFontSize,
            lineHeight: theme.paragraphLineHeight,
            fontProfile: theme.paragraphFontProfiles.body,
            fallbackFontSize: 16,
            fallbackLineHeight: 22
        )
    }

    private func sanitizedTextMetrics(
        fontSize: Double,
        lineHeight: Double,
        fontProfile: MarkdownFontProfile,
        fallbackFontSize: Double,
        fallbackLineHeight: Double
    ) -> (fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        let metrics = MarkdownInlineFallbackMetrics(
            fontSize: fontSize,
            lineHeight: lineHeight,
            fontProfile: fontProfile,
            fallbackFontSize: fallbackFontSize,
            fallbackLineHeight: fallbackLineHeight
        )
        return (metrics.fontSize, metrics.lineHeight, metrics.fontProfile)
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
            let mathDecision = configuration.mathPolicy.evaluateMath(
                MarkdownRendererConfiguration.mathText(for: block),
                isBlock: true
            )
            let mathRendered: Bool
            if case .image = preparedContent?.mathRender {
                mathRendered = true
            } else {
                mathRendered = false
            }
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                mathAllowed: policyAllowed(mathDecision),
                mathRendered: mathRendered,
                policyDenialReason: denialReason(mathDecision)
            )
        case .htmlBlock:
            let htmlDecision = configuration.htmlPolicy.evaluateHTML(block.text)
            return MarkdownBlockRenderPlan(
                kind: block.kind,
                htmlAllowed: policyAllowed(htmlDecision),
                policyDenialReason: denialReason(htmlDecision)
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
            return "Math: \(MarkdownRendererConfiguration.mathText(for: block))"
        case .htmlBlock:
            let visibleText = block.richContent?.blocks
                .map(\.text)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return visibleText?.isEmpty == false ? visibleText! : "HTML block"
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
    var blockID: MarkdownBlockID
    var indentationLevel: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MarkdownListItemRow(
                    item: item,
                    index: index,
                    kind: kind,
                    orderedStart: orderedStart,
                    configuration: configuration,
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel
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
    var blockID: MarkdownBlockID
    var indentationLevel: Int

    @Environment(\.markdownDocumentStyleAggregate) private var documentStyleAggregate
    @Environment(\.markdownListItemStyleOverride) private var listItemStyleOverride
    @Environment(\.markdownUnorderedListMarkerStyleOverride) private var unorderedListMarkerStyleOverride
    @Environment(\.markdownOrderedListMarkerStyleOverride) private var orderedListMarkerStyleOverride
    @Environment(\.markdownTaskListMarkerStyleOverride) private var taskListMarkerStyleOverride

    // MARK: - Style resolution (INV-BS9) — see `MarkdownBlockView` above.

    private var resolvedListItemStyle: any MarkdownListItemStyle {
        resolvedMarkdownStyle(
            override: listItemStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.listItemStyle },
            default: MarkdownDefaultListItemStyle()
        )
    }

    private var resolvedUnorderedListMarkerStyle: any MarkdownUnorderedListMarkerStyle {
        resolvedMarkdownStyle(
            override: unorderedListMarkerStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.unorderedListMarkerStyle },
            default: MarkdownDefaultUnorderedListMarkerStyle()
        )
    }

    private var resolvedOrderedListMarkerStyle: any MarkdownOrderedListMarkerStyle {
        resolvedMarkdownStyle(
            override: orderedListMarkerStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.orderedListMarkerStyle },
            default: MarkdownDefaultOrderedListMarkerStyle()
        )
    }

    private var resolvedTaskListMarkerStyle: any MarkdownTaskListMarkerStyle {
        resolvedMarkdownStyle(
            override: taskListMarkerStyleOverride,
            aggregate: documentStyleAggregate,
            configuration: configuration,
            slot: { $0.taskListMarkerStyle },
            default: MarkdownDefaultTaskListMarkerStyle()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AnyView(resolvedListItemStyle.makeBody(
                configuration: MarkdownListItemStyleConfiguration(
                    marker: MarkdownBlockStyleLabel(
                        markerView,
                        firstTextBaselineFromTop: markerFirstTextBaselineFromTop
                    ),
                    block: MarkdownBlockStyleLabel(
                        listItemInlineView,
                        firstTextBaselineFromTop: listItemFirstTextBaselineFromTop
                    ),
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel
                )
            ))
            .frame(maxWidth: .infinity, alignment: .leading)

            if !item.childItems.isEmpty {
                MarkdownListItemsView(
                    items: item.childItems,
                    kind: item.childListKind ?? .unorderedList,
                    orderedStart: item.childOrderedListStart,
                    configuration: configuration,
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel + 1
                )
                .padding(.leading, markerIndentationWidth + MarkdownDefaultListItemStyle.spacing)
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
        } else if let selectionInlineLayout = item.selectionInlineLayout {
            InlineRunsView(
                prepared: selectionInlineLayout,
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
                nativeTextSelection: selectionModeInsideLeadingLayout,
                fontSize: paragraphTextMetrics.fontSize,
                lineHeight: paragraphTextMetrics.lineHeight,
                fontProfile: paragraphTextMetrics.fontProfile
            )
        }
    }

    private var selectionModeInsideLeadingLayout: MarkdownNativeTextSelection {
        configuration.nativeTextSelection
    }

    private var listItemFirstTextBaselineFromTop: CGFloat {
        if let inline = item.inlineLayout ?? item.selectionInlineLayout {
            return inline.firstTextBaselineFromTop(
                inlineRenderingMode: configuration.inlineRenderingMode,
                nativeTextSelection: selectionModeInsideLeadingLayout
            )
        }
        return configuration.listMarkerBaselineMetrics
            .paragraphNaturalFirstTextBaselineFromTop
    }

    private var markerFirstTextBaselineFromTop: CGFloat? {
        if item.taskState != nil {
            guard resolvedTaskListMarkerStyle is MarkdownDefaultTaskListMarkerStyle else {
                return nil
            }
            return configuration.listMarkerBaselineMetrics
                .taskMarkerFirstTextBaselineFromTop
        }
        if kind == .orderedList {
            guard resolvedOrderedListMarkerStyle is MarkdownDefaultOrderedListMarkerStyle else {
                return nil
            }
        } else if !(resolvedUnorderedListMarkerStyle is MarkdownDefaultUnorderedListMarkerStyle) &&
            !(resolvedUnorderedListMarkerStyle is MarkdownGitHubUnorderedListMarkerStyle)
        {
            return nil
        }

        return configuration.listMarkerBaselineMetrics
            .textualMarkerFirstTextBaselineFromTop
    }

    @ViewBuilder
    private var markerView: some View {
        if let taskState = item.taskState {
            AnyView(resolvedTaskListMarkerStyle.makeBody(
                configuration: MarkdownTaskListMarkerStyleConfiguration(
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel,
                    isChecked: taskState == .checked
                )
            ))
        } else if kind == .orderedList {
            AnyView(resolvedOrderedListMarkerStyle.makeBody(
                configuration: MarkdownOrderedListMarkerStyleConfiguration(
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel,
                    ordinal: Int(orderedStart ?? 1) + index
                )
            ))
        } else {
            AnyView(resolvedUnorderedListMarkerStyle.makeBody(
                configuration: MarkdownUnorderedListMarkerStyleConfiguration(
                    theme: theme,
                    blockID: blockID,
                    indentationLevel: indentationLevel
                )
            ))
        }
    }

    private var markerIndentationWidth: CGFloat {
        if item.taskState != nil {
            return resolvedTaskListMarkerStyle.markerWidth ?? MarkdownDefaultTaskListMarkerStyle.width
        }
        if kind == .orderedList {
            return resolvedOrderedListMarkerStyle.markerWidth ?? MarkdownDefaultOrderedListMarkerStyle.width
        }
        return resolvedUnorderedListMarkerStyle.markerWidth ?? MarkdownDefaultUnorderedListMarkerStyle.width
    }

    private var paragraphTextMetrics: MarkdownInlineFallbackMetrics {
        MarkdownInlineFallbackMetrics(
            fontSize: theme.paragraphFontSize,
            lineHeight: theme.paragraphLineHeight,
            fontProfile: theme.paragraphFontProfiles.body,
            fallbackFontSize: 16,
            fallbackLineHeight: 22
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
