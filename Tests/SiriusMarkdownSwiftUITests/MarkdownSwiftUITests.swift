import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreText)
import CoreText
#endif

@Test
@MainActor
func documentViewCanBeConstructedFromSnapshot() {
    let block = MarkdownBlock(
        id: MarkdownBlockID("block-1"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        isSealed: true
    )
    let snapshot = MarkdownSnapshot(blocks: [block], sourceLength: 5, generation: 1, isFinished: true)
    let documentConfiguration = MarkdownRendererConfiguration.document
    let chatConfiguration = MarkdownRendererConfiguration.compactChat

    _ = MarkdownDocumentView(
        preparedSnapshot: documentConfiguration.prepare(snapshot: snapshot),
        configuration: documentConfiguration
    )
    _ = StreamingMarkdownView(
        preparedSnapshot: chatConfiguration.prepare(snapshot: snapshot),
        configuration: chatConfiguration
    )
}

@available(*, deprecated, message: "Exercises deprecated snapshot compatibility initializers.")
@Test
@MainActor
func deprecatedSnapshotViewInitializersDoNotPrepareSynchronously() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        Paragraph with [link](https://example.com).

        ```swift
        let x = 1
        ```

        ```mermaid
        graph LR
        A --> B
        ```

        $$
        x^2
        $$

        | Name | Value |
        | - | - |
        | [safe](https://example.com) | `code` |
        """
    )
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    let highlighter = CountingCodeHighlighter()
    let mermaidRenderer = CountingMermaidRenderer(ascii: "A -> B")
    let mathRenderer = CountingMathRenderer()
    let configuration = MarkdownRendererConfiguration(
        codeHighlighter: highlighter,
        mermaidRenderer: mermaidRenderer,
        mathRenderer: mathRenderer,
        diagnosticsRecorder: recorder
    )
    let snapshot = stream.snapshot()

    _ = MarkdownDocumentView(snapshot: snapshot, configuration: configuration)
    _ = StreamingMarkdownView(snapshot: snapshot, configuration: configuration)

    let counters = recorder.snapshot()
    #expect(counters.renderPreparationCount == 0)
    #expect(counters.prepareCount == 0)
    #expect(counters.codeHighlightCount == 0)
    #expect(counters.mermaidRenderCount == 0)
    #expect(counters.mathRenderCount == 0)
    #expect(highlighter.count == 0)
    #expect(mermaidRenderer.count == 0)
    #expect(mathRenderer.count == 0)
}

@Test
func javaScriptResourceLookupResolvesBundledRendererScripts() throws {
    let highlighterScript = try #require(
        MarkdownJavaScriptResourceLookup.script(named: "highlight.min", subdirectory: "HighlightJS")
    )
    let mermaidScript = try #require(
        MarkdownJavaScriptResourceLookup.script(named: "beautiful-mermaid.bundle", subdirectory: "MermaidJS")
    )

    #expect(highlighterScript.contains("var hljs"))
    #expect(mermaidScript.contains("renderMermaid"))
}

@Test
func unpreparedSnapshotKeepsStructuredCompatibilityDataWithoutPreparing() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        - [safe](https://example.com)
          - child

        | Name | Value |
        | - | - |
        | [safe](https://example.com) | `code` |
        """
    )
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    let unprepared = configuration.unpreparedSnapshot(for: stream.snapshot())
    let list = try #require(unprepared.items.compactMap { item -> MarkdownPreparedBlockContent? in
        guard case let .block(block, content) = item, block.kind == .unorderedList else {
            return nil
        }
        return content
    }.first)
    let table = try #require(unprepared.items.compactMap { item -> MarkdownPreparedBlockContent? in
        guard case let .block(block, content) = item, block.kind == .table else {
            return nil
        }
        return content
    }.first?.table)

    #expect(list.listItems.count == 1)
    #expect(list.listItems.first?.childItems.count == 1)
    #expect(attributedStringContainsLink(list.listItems.first?.inline) == true)
    #expect(table.header.count == 2)
    #expect(table.rows.count == 1)
    #expect(attributedStringContainsLink(table.rows.first?.cells.first?.inline) == true)
    #expect(recorder.snapshot().renderPreparationCount == 0)
    #expect(recorder.snapshot().prepareCount == 0)
}

@Test
func unpreparedSnapshotStillEnforcesBlockPoliciesWithoutPreparing() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        Paragraph with [safe](https://example.com) and ![](https://example.com/image.png).

        ```swift
        let x = 1
        ```

        $$
        x^2
        $$

        <div>raw</div>
        """
    )
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        htmlPolicy: CountingHTMLPolicy(),
        codePolicy: DenyCodePolicy(),
        mathPolicy: DenyMathPolicy(),
        diagnosticsRecorder: recorder
    )
    let unprepared = configuration.unpreparedSnapshot(for: stream.snapshot())
    let contents = unprepared.items.compactMap { item -> (MarkdownBlockKind, MarkdownPreparedBlockContent)? in
        guard case let .block(block, content) = item else {
            return nil
        }
        return (block.kind, content)
    }
    let paragraph = try #require(contents.first { $0.0 == .paragraph }?.1)
    let paragraphInline = try #require(paragraph.inline)

    #expect(String(paragraphInline.characters) == "Paragraph with safe and [image].")
    #expect(paragraph.inlineLayout == nil)
    #expect(contents.first { $0.0 == .codeBlock }?.1.policyDenialReason == "code denied")
    #expect(contents.first { $0.0 == .mathBlock }?.1.policyDenialReason == "math denied")
    #expect(contents.first { $0.0 == .htmlBlock }?.1.policyDenialReason == "counted html denied")
    #expect(contents.first { $0.0 == .htmlBlock }?.1.htmlAllowed == false)
    #expect(recorder.snapshot().renderPreparationCount == 0)
    #expect(recorder.snapshot().prepareCount == 0)
    #expect(recorder.snapshot().codeHighlightCount == 0)
    #expect(recorder.snapshot().mathRenderCount == 0)
}

@Test
@MainActor
func attributedInlineFallbackCarriesExplicitTextMetrics() {
    let theme = MarkdownTheme.document
    let heading = theme.headingStyle(for: 1)
    let attributed = AttributedString("Heading")
    let view = InlineRunsView(
        attributed: attributed,
        theme: theme,
        baseFont: heading.font,
        fontSize: heading.fontSize,
        lineHeight: heading.lineHeight,
        fontProfile: heading.fontProfiles.body
    )

    #expect(view.fallbackTextMetrics.fontSize == heading.fontSize)
    #expect(view.fallbackTextMetrics.lineHeight == heading.lineHeight)
    #expect(view.fallbackTextMetrics.fontProfile == heading.fontProfiles.body)

    let defaultView = InlineRunsView(
        attributed: attributed,
        theme: theme,
        baseFont: heading.font
    )
    #expect(defaultView.fallbackTextMetrics.fontSize == theme.paragraphFontSize)
    #expect(defaultView.fallbackTextMetrics.lineHeight == theme.paragraphLineHeight)
    #expect(defaultView.fallbackTextMetrics.fontProfile == theme.paragraphFontProfiles.body)
}

@Test
@MainActor
func inlineTextMetricsClampInvalidPublicThemeAndFallbackValues() throws {
    var theme = MarkdownTheme()
    theme.paragraphFontSize = .nan
    theme.paragraphLineHeight = -1
    theme.blockSpacing = -.infinity
    theme.tableCornerRadius = .nan
    theme.tableHorizontalCellPadding = -.infinity
    theme.tableVerticalCellPadding = .nan
    theme.headings.h1.fontSize = .infinity
    theme.headings.h1.lineHeight = .nan

    let paragraph = try firstBlock("Paragraph text")
    let heading = try firstBlock("# Heading")
    let configuration = MarkdownRendererConfiguration(theme: theme)
    let paragraphInline = try #require(configuration.prepare(block: paragraph).inlineLayout)
    let headingInline = try #require(configuration.prepare(block: heading).inlineLayout)

    #expect(paragraphInline.fontSize == 16)
    #expect(paragraphInline.lineHeight == 22)
    #expect(headingInline.fontSize == 20)
    #expect(headingInline.lineHeight == 28)
    #expect(configuration.mathBlockFontSize == 21)
    #expect(theme.renderBlockSpacing == 8)
    #expect(theme.renderTableCornerRadius == 8)
    #expect(theme.renderTableHorizontalCellPadding == 12)
    #expect(theme.renderTableVerticalCellPadding == 9)

    let fallbackView = InlineRunsView(
        attributed: AttributedString("Fallback"),
        fontSize: .nan,
        lineHeight: -.infinity
    )
    #expect(fallbackView.fallbackTextMetrics.fontSize == 14)
    #expect(fallbackView.fallbackTextMetrics.lineHeight == 14)

    let paragraphFallbackMetrics = MarkdownInlineFallbackMetrics(
        fontSize: .nan,
        lineHeight: -.infinity,
        fontProfile: theme.paragraphFontProfiles.body,
        fallbackFontSize: 16,
        fallbackLineHeight: 22
    )
    #expect(paragraphFallbackMetrics.fontSize == 16)
    #expect(paragraphFallbackMetrics.lineHeight == 22)

    let prepared = PreparedInlineContent(runs: [
        MarkdownInlineRun(kind: .text, text: "Prepared")
    ])
    let segment = PreparedInlineSegment(
        kind: .text,
        text: "Prepared",
        byteRange: 0..<8
    )
    let measured = MeasuredInlineContent(
        prepared: prepared,
        segments: [
            MeasuredInlineSegment(
                segment: segment,
                width: .nan,
                units: [
                    MeasuredInlineUnit(byteRange: 0..<8, width: .infinity)
                ]
            )
        ],
        naturalWidth: .nan,
        fontSize: .nan
    )
    let direct = MarkdownPreparedInlineContent(
        attributed: AttributedString("Prepared"),
        prepared: prepared,
        measured: measured,
        fontSize: -.infinity,
        lineHeight: .nan
    )
    #expect(direct.fontSize == 14)
    #expect(direct.lineHeight == 14)
    #expect(direct.measured.fontSize == 14)
    #expect(direct.measured.naturalWidth == 0)
    #expect(direct.measured.segments.first?.width == 0)
    #expect(direct.measured.segments.first?.units.first?.width == 0)
}

@Test
func preparedSnapshotExposesLightweightRenderItems() throws {
    var stream = MarkdownStream()
    stream.append("# Heading\n\nBody with **strong** text.\n")
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(snapshot: stream.snapshot())

    #expect(prepared.renderItems.count == prepared.items.count)
    #expect(prepared.itemIDs == prepared.renderItems.map(\.id))
    for renderItem in prepared.renderItems {
        let item = try #require(prepared.item(at: renderItem.itemIndex))
        #expect(item.id == renderItem.id)
    }
}

@Test
func preparedSnapshotRenderItemsDisambiguateDuplicateHostBoundaryIDs() {
    let firstBoundary = MarkdownHostBoundary(id: MarkdownHostBoundaryID("native-card"), sourceOffset: 0)
    let secondBoundary = MarkdownHostBoundary(id: MarkdownHostBoundaryID("native-card"), sourceOffset: 0)
    let snapshot = MarkdownSnapshot(
        blocks: [],
        items: [
            .hostBoundary(firstBoundary),
            .hostBoundary(secondBoundary)
        ],
        sourceLength: 0,
        generation: 1,
        isFinished: false
    )
    let prepared = MarkdownPreparedSnapshot(
        snapshot: snapshot,
        items: [
            .hostBoundary(firstBoundary),
            .hostBoundary(secondBoundary)
        ],
        preparedContentByBlockID: [:]
    )

    #expect(prepared.itemIDs.count == 2)
    #expect(Set(prepared.itemIDs).count == 2)
    #expect(prepared.itemIDs.first == "host:native-card")
    #expect(prepared.itemIDs.last?.hasPrefix("host:native-card#") == true)
    #expect(prepared.renderItems.map(\.itemIndex) == [0, 1])
}

@Test
func inlineRunsApplyLinkAndImagePolicies() {
    let linked = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(
                kind: .link,
                text: "example",
                destination: "https://example.com"
            )
        ]
    )
    #expect(linked.runs.compactMap(\.link).first?.absoluteString == "https://example.com")

    let blocked = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(
                kind: .link,
                text: "local",
                destination: "file:///tmp/secret"
            )
        ]
    )
    #expect(blocked.runs.compactMap(\.link).isEmpty)

    let hiddenImage = InlineRunsView.plainText(
        for: [
            MarkdownInlineRun(
                kind: .image,
                text: "",
                destination: "https://example.com/image.png",
                imageSource: "https://example.com/image.png"
            )
        ]
    )
    #expect(hiddenImage == "[image]")

    let linkedImage = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(
                kind: .link,
                text: "diagram",
                destination: "https://example.com/diagram",
                imageSource: "https://example.com/image.png",
                presentation: .image
            )
        ]
    )
    #expect(String(linkedImage.characters) == "diagram")
    #expect(linkedImage.runs.compactMap(\.link).first?.absoluteString == "https://example.com/diagram")

    let multilineLink = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(kind: .link, text: "first", destination: "https://example.com/multiline"),
            MarkdownInlineRun(kind: .softBreak, text: "\n", destination: "https://example.com/multiline"),
            MarkdownInlineRun(kind: .link, text: "second", destination: "https://example.com/multiline")
        ]
    )
    let linkedPieces = multilineLink.runs.compactMap { run -> String? in
        guard run.link?.absoluteString == "https://example.com/multiline" else {
            return nil
        }
        return String(multilineLink[run.range].characters)
    }
    #expect(linkedPieces == ["first\nsecond"])
}

@Test
func blockRenderPlanCapturesStructuredListsAndTables() throws {
    let taskList = try firstBlock("- [ ] first\n- [x] second")
    let taskPlan = MarkdownBlockView.renderPlan(for: taskList)
    #expect(taskPlan.kind == .taskList)
    #expect(taskPlan.listItemCount == 2)

    let table = try firstBlock("| A | B |\n| - | - |\n| 1 | 2 |")
    let tablePlan = MarkdownBlockView.renderPlan(for: table)
    #expect(tablePlan.kind == .table)
    #expect(tablePlan.tableColumnCount == 2)
    #expect(tablePlan.tableBodyRowCount == 1)
}

@Test
func preparedNestedListsKeepTheirKindAndStableIDs() throws {
    let list = try firstBlock("- parent\n  - child")
    let prepared = MarkdownRendererConfiguration().prepare(block: list)
    let parent = try #require(prepared.listItems.first)
    let child = try #require(parent.childItems.first)

    #expect(parent.id.hasPrefix("list-item:"))
    #expect(parent.childListKind == .unorderedList)
    #expect(parent.childOrderedListStart == nil)
    #expect(child.id.hasPrefix("list-item:"))
}

@Test
func preparedNestedOrderedAndTaskListsKeepASTMetadata() throws {
    let ordered = try firstBlock("- parent\n  1. child")
    let preparedOrdered = MarkdownRendererConfiguration().prepare(block: ordered)
    let orderedParent = try #require(preparedOrdered.listItems.first)

    #expect(ordered.kind == .unorderedList)
    #expect(orderedParent.childListKind == .orderedList)
    #expect(orderedParent.childOrderedListStart == 1)
    #expect(orderedParent.childItems.first?.inlineLayout != nil)

    let task = try firstBlock("- parent\n  - [x] child")
    let preparedTask = MarkdownRendererConfiguration().prepare(block: task)
    let taskParent = try #require(preparedTask.listItems.first)

    #expect(taskParent.childListKind == .taskList)
    #expect(taskParent.childItems.first?.taskState == .checked)
    #expect(taskParent.childItems.first?.inlineLayout != nil)
}

@Test
func preparedTablesExposeStableRowAndCellIDs() throws {
    let table = try firstBlock("| A | B |\n| - | - |\n| 1 | 2 |")
    let prepared = try #require(MarkdownRendererConfiguration().prepare(block: table).table)

    #expect(prepared.header.allSatisfy { $0.id.hasPrefix("table-cell:") })
    #expect(prepared.rows.first?.id.hasPrefix("table-cell:") == true)
    #expect(prepared.rows.first?.cells.allSatisfy { $0.id.hasPrefix("table-cell:") } == true)
}

@Test
func preparedTableCurrencyAmountsRemainText() throws {
    let table = try firstBlock("""
    | Program | Reward |
    | --- | --- |
    | Coveo Public Bug Bounty | $100 - $5,500 |
    | ICI PARIS XL / AS Watson | $108,500 |
    | Math sample | $x^2$ |
    """)
    let prepared = try #require(MarkdownRendererConfiguration.document.prepare(block: table).table)
    let range = try #require(prepared.rows.first?.cells.dropFirst().first?.inlineLayout)
    let currency = try #require(prepared.rows.dropFirst().first?.cells.dropFirst().first?.inlineLayout)
    let math = try #require(prepared.rows.dropFirst(2).first?.cells.dropFirst().first?.inlineLayout)

    #expect(range.prepared.naturalText == "$100 - $5,500")
    #expect(range.prepared.runs.allSatisfy { $0.kind != .math })
    #expect(currency.prepared.naturalText == "$108,500")
    #expect(currency.prepared.runs.allSatisfy { $0.kind != .math })
    #expect(math.prepared.runs.contains { $0.kind == .math && $0.text == "x^2" })
}

@Test
@MainActor
func tableRendererAcceptsCustomThemeTokens() throws {
    let table = try firstBlock("| Region | Text | Evidence |\n| - | - | - |\n| CJK | 日本語 | measured |")
    let theme = MarkdownTheme(
        tableCornerRadius: 5,
        tableHorizontalCellPadding: 14,
        tableVerticalCellPadding: 7
    )
    let configuration = MarkdownRendererConfiguration(theme: theme)
    let prepared = configuration.prepare(block: table)

    _ = MarkdownBlockView(
        block: table,
        configuration: configuration,
        preparedContent: prepared
    )

    #expect(configuration.theme.tableCornerRadius == 5)
    #expect(configuration.theme.tableHorizontalCellPadding == 14)
    #expect(configuration.theme.tableVerticalCellPadding == 7)
    #expect(prepared.table?.header.count == 3)
}

@Test
@MainActor
func tableRendererAcceptsRaggedPreparedRows() {
    let sourceRange = MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2)
    let block = MarkdownBlock(
        id: MarkdownBlockID("table"),
        kind: .table,
        sourceRange: sourceRange,
        text: "| A | B | C |",
        isSealed: true
    )
    let prepared = MarkdownPreparedBlockContent(
        blockID: block.id,
        table: MarkdownPreparedTableBlock(
            columnAlignments: [.left, .left, .left],
            header: [
                MarkdownPreparedTableCell(id: "h1", sourceRange: sourceRange, inline: AttributedString("A")),
                MarkdownPreparedTableCell(id: "h2", sourceRange: sourceRange, inline: AttributedString("B")),
                MarkdownPreparedTableCell(id: "h3", sourceRange: sourceRange, inline: AttributedString("C"))
            ],
            rows: [
                MarkdownPreparedTableRow(
                    id: "row-1",
                    cells: [
                        MarkdownPreparedTableCell(id: "r1c1", sourceRange: sourceRange, inline: AttributedString("Only one cell"))
                    ]
                )
            ]
        )
    )

    _ = MarkdownBlockView(
        block: block,
        configuration: MarkdownRendererConfiguration(),
        preparedContent: prepared
    )

    #expect(prepared.table?.header.count == 3)
    #expect(prepared.table?.rows.first?.cells.count == 1)
}

@Test
func preparedSnapshotPreservesHostBoundaryItems() {
    let block = MarkdownBlock(
        id: MarkdownBlockID("block"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        inlines: [.init(kind: .text, text: "Hello")],
        isSealed: true
    )
    let boundary = MarkdownHostBoundary(id: MarkdownHostBoundaryID("native"), sourceOffset: 5)
    let snapshot = MarkdownSnapshot(
        blocks: [block],
        items: [.block(block), .hostBoundary(boundary)],
        sourceLength: 5,
        generation: 1,
        isFinished: true
    )

    let prepared = MarkdownRendererConfiguration().prepare(snapshot: snapshot)

    #expect(prepared.items.count == 2)
    #expect(prepared.preparedContentByBlockID[block.id]?.inline != nil)
    if case let .hostBoundary(preparedBoundary) = prepared.items.last {
        #expect(preparedBoundary == boundary)
    } else {
        Issue.record("Expected host boundary item to be preserved.")
    }
}

@Test
func preparedSnapshotCarriesMeasuredInlineLayout() throws {
    var stream = MarkdownStream()
    stream.append("alpha beta gamma delta epsilon")
    stream.finish()
    let snapshot = stream.snapshot()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, containerWidth: 64)

    #expect(inlineLayout.measured.segments.isEmpty == false)
    #expect(lines.count > 1)
    #expect(recorder.snapshot().prepareCount == 1)
}

@Test
func preparedNativeLinesModePreservesPreparedLineText() throws {
    var stream = MarkdownStream()
    stream.append("alpha beta gamma delta epsilon zeta")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 92)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)
    let renderedText = lines.map { String($0.characters) }.joined()

    #expect(configuration.inlineRenderingMode == .preparedNativeLines)
    #expect(lines.count > 1)
    #expect(renderedText == inlineLayout.prepared.naturalText)
    #expect(renderedText.contains("alpha beta"))
}

@Test
func coreTextPaintedLinesModeIsDefaultAndBuildsWholePreparedLinePlan() throws {
    var stream = MarkdownStream()
    stream.append("alpha beta gamma delta epsilon zeta")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .coreTextPaintedLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 92)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)

    #expect(configuration.inlineRenderingMode == .coreTextPaintedLines)
    #expect(lines.count > 1)
    #expect(lines.map { String($0.characters) }.joined() == inlineLayout.prepared.naturalText)

    #if canImport(CoreText)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)
    #expect(plan.lines.count == layout.lines.count)
    #expect(plan.lines.map(\.text).joined() == inlineLayout.prepared.naturalText.replacingOccurrences(of: "\n", with: ""))
    #expect(plan.lines.allSatisfy { $0.typographicWidth.isFinite && $0.typographicWidth > 0 })
    #expect(plan.lines.contains { $0.text.contains(" ") })
    #endif
}

@Test
func coreTextPaintedLinePlanUsesPreparedLinkPolicyForHitRegions() throws {
    #if canImport(CoreText)
    var stream = MarkdownStream()
    stream.append("[allowed](https://example.com) [blocked](file:///tmp/secret)")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 600)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)
    let destinations = Set(plan.linkFragments.map(\.destination))

    #expect(destinations == ["https://example.com"])
    #expect(plan.linkFragments.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    #expect(plan.linkFragments.allSatisfy { !$0.destination.contains("file:///") })
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
func coreTextPaintedLinePlanCreatesHitRegionForBareHTTPSURL() throws {
    #if canImport(CoreText)
    let bareURL = "https://www.google.com/travel/flights?q=DTW%20to%20ORF%20one%20way%20Jun%2012%202026"
    var stream = MarkdownStream()
    stream.append("Friday morning DTW -> Norfolk link:\n\(bareURL)")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 640)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)
    let link = try #require(plan.linkFragments.first { $0.destination == bareURL })

    #expect(inlineLayout.prepared.runs.contains { $0.kind == .link && $0.destination == bareURL })
    #expect(link.rect.width > 0)
    #expect(link.rect.height > 0)
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
func coreTextPaintedLinePlanSplitsWrappedLinksIntoBoundedHitRegions() throws {
    #if canImport(CoreText)
    var stream = MarkdownStream()
    stream.append("[alpha beta gamma delta epsilon zeta](https://example.com/wrapped)")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 72)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)
    let lineIndices = Set(plan.linkFragments.map(\.lineIndex))

    #expect(plan.lines.count > 1)
    #expect(plan.linkFragments.count == lineIndices.count)
    #expect(plan.linkFragments.count > 1)
    #expect(plan.linkFragments.allSatisfy { $0.destination == "https://example.com/wrapped" })
    #expect(plan.linkFragments.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
func coreTextPaintedLinkClickTrackerOpensOnlyStationaryClicks() throws {
    #if canImport(CoreText)
    let fragment = MarkdownCoreTextPaintedLinkFragment(
        lineIndex: 0,
        destination: "https://example.com",
        byteRange: 0..<19,
        rect: CGRect(x: 2, y: 4, width: 80, height: 18)
    )

    var clickTracker = MarkdownCoreTextPaintedLinkClickTracker()
    let clickBegan = clickTracker.begin(at: CGPoint(x: 12, y: 10), fragments: [fragment], hitSlop: 2)
    let clickDestination = clickTracker.finish(at: CGPoint(x: 13, y: 10), fragments: [fragment], hitSlop: 2)
    #expect(clickBegan)
    #expect(clickDestination == "https://example.com")
    #expect(clickTracker.hasPendingClick == false)

    var dragTracker = MarkdownCoreTextPaintedLinkClickTracker()
    let dragBegan = dragTracker.begin(at: CGPoint(x: 12, y: 10), fragments: [fragment], hitSlop: 2)
    dragTracker.updateDrag(to: CGPoint(x: 18, y: 10))
    let dragDestination = dragTracker.finish(at: CGPoint(x: 18, y: 10), fragments: [fragment], hitSlop: 2)
    #expect(dragBegan)
    #expect(dragTracker.hasPendingClick == false)
    #expect(dragDestination == nil)

    var thresholdTracker = MarkdownCoreTextPaintedLinkClickTracker()
    let thresholdBegan = thresholdTracker.begin(at: CGPoint(x: 12, y: 10), fragments: [fragment], hitSlop: 2)
    thresholdTracker.updateDrag(to: CGPoint(x: 16, y: 10))
    let thresholdDestination = thresholdTracker.finish(at: CGPoint(x: 16, y: 10), fragments: [fragment], hitSlop: 2)
    #expect(thresholdBegan)
    #expect(thresholdTracker.hasPendingClick == false)
    #expect(thresholdDestination == nil)

    var outsideTracker = MarkdownCoreTextPaintedLinkClickTracker()
    let outsideBegan = outsideTracker.begin(at: CGPoint(x: 120, y: 10), fragments: [fragment], hitSlop: 2)
    #expect(outsideBegan == false)
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
@MainActor
func hostedCoreTextBareURLClickOpensLinkWithDocumentSelectionEnabledOnMacOS() throws {
    #if canImport(AppKit) && canImport(CoreText)
    let bareURL = "https://www.google.com/travel/flights?q=DTW%20to%20ORF%20one%20way%20Jun%2012%202026"
    var stream = MarkdownStream()
    stream.append(bareURL)
    stream.finish()

    let recorder = LinkActionRecorder()
    let controller = MarkdownSelectionController()
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.inlineRenderingMode = .coreTextPaintedLines
    configuration.documentSelection = .enabled
    configuration.linkAction = MarkdownLinkAction { destination in
        recorder.record(destination)
    }
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    controller.updateSnapshot(stream.snapshot())

    let view = StreamingMarkdownView(
        preparedSnapshot: prepared,
        configuration: configuration,
        selectionController: controller
    )
    .frame(width: 720, height: 80, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 720, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let linkView = try #require(appKitCoreTextPaintedViews(in: hostingView).first { view in
        view.accessibilityLabel()?.contains(bareURL) == true
    })
    let localPoint = CGPoint(x: 12, y: max(1, linkView.bounds.midY))
    let windowPoint = linkView.convert(localPoint, to: nil)
    linkView.mouseDown(with: mouseEvent(type: .leftMouseDown, location: windowPoint, window: window))
    linkView.mouseUp(with: mouseEvent(type: .leftMouseUp, location: windowPoint, window: window))

    #expect(recorder.destinations == [bareURL])
    #expect(controller.selectedSourceRanges.isEmpty)
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
@MainActor
func hostedCoreTextBareURLDragSelectsInsteadOfOpeningLinkOnMacOS() throws {
    #if canImport(AppKit) && canImport(CoreText)
    let bareURL = "https://www.google.com/travel/flights?q=DTW%20to%20ORF%20one%20way%20Jun%2012%202026"
    var stream = MarkdownStream()
    stream.append(bareURL)
    stream.finish()

    let recorder = LinkActionRecorder()
    let controller = MarkdownSelectionController()
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.inlineRenderingMode = .coreTextPaintedLines
    configuration.documentSelection = .enabled
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: bareURL)
    configuration.linkAction = MarkdownLinkAction { destination in
        recorder.record(destination)
    }
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    controller.updateSnapshot(stream.snapshot())

    let view = StreamingMarkdownView(
        preparedSnapshot: prepared,
        configuration: configuration,
        selectionController: controller
    )
    .frame(width: 720, height: 80, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 720, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let linkView = try #require(appKitCoreTextPaintedViews(in: hostingView).first { view in
        view.accessibilityLabel()?.contains(bareURL) == true
    })
    let startLocal = CGPoint(x: 1, y: max(1, linkView.bounds.midY))
    let endLocal = CGPoint(x: min(360, linkView.bounds.maxX - 4), y: max(1, linkView.bounds.midY))
    let startWindow = linkView.convert(startLocal, to: nil)
    let endWindow = linkView.convert(endLocal, to: nil)
    linkView.mouseDown(with: mouseEvent(type: .leftMouseDown, location: startWindow, window: window))
    linkView.mouseDragged(with: mouseEvent(type: .leftMouseDragged, location: endWindow, window: window))
    linkView.mouseUp(with: mouseEvent(type: .leftMouseUp, location: endWindow, window: window))
    pumpLayout(hostingView)

    let selectedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider)
    #expect(recorder.destinations.isEmpty)
    #expect(controller.selectedSourceRanges.isEmpty == false)
    #expect(selectedMarkdown.hasPrefix("https://"))
    #expect(bareURL.hasPrefix(selectedMarkdown))
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
@MainActor
func hostedDocumentSelectionDragStartingInEmptySpaceDoesNotSelectNearestTextOnMacOS() throws {
    #if canImport(AppKit)
    let markdown = "Selectable text is only near the top."
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let controller = MarkdownSelectionController()
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    controller.updateSnapshot(snapshot)

    let view = StreamingMarkdownView(
        preparedSnapshot: prepared,
        configuration: configuration,
        selectionController: controller
    )
    .frame(width: 420, height: 260, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 420, height: 260))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let start = hostingView.convert(CGPoint(x: 8, y: 220), to: nil)
    let end = hostingView.convert(CGPoint(x: 360, y: 235), to: nil)
    window.sendEvent(mouseEvent(type: .leftMouseDown, location: start, window: window))
    window.sendEvent(mouseEvent(type: .leftMouseDragged, location: end, window: window))
    window.sendEvent(mouseEvent(type: .leftMouseUp, location: end, window: window))
    pumpLayout(hostingView)

    #expect(controller.selectedSourceRanges.isEmpty)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider).isEmpty)
    #else
    #expect(true)
    #endif
}

@Test
func coreTextPaintedLinePlanCoversStructuredBlockContexts() throws {
    #if canImport(CoreText)
    var stream = MarkdownStream()
    stream.append(
        """
        # Heading [link](https://example.com/heading)

        Paragraph with **strong**, _emphasis_, `code`, emoji 😄, CJK 日本語, and [link](https://example.com/paragraph).

        > Quote with wrapped text and [quote link](https://example.com/quote).

        - [x] Task item [task](https://example.com/task)
          - Nested item with `code`

        | Name | Detail |
        | --- | --- |
        | Cell [cell link](https://example.com/cell) | Wrapped table text |
        """
    )
    stream.finish()

    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let inlineLayouts = coreTextPaintedTestInlineLayouts(in: prepared)

    #expect(inlineLayouts.count >= 7)

    for inlineLayout in inlineLayouts {
        let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 180)
        let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)

        #expect(plan.lines.isEmpty == false)
        #expect(plan.accessibilityLabel == String(inlineLayout.attributed.characters))
        #expect(plan.lines.allSatisfy { $0.typographicWidth.isFinite && $0.typographicWidth > 0 })
    }
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
func coreTextPaintedLinePlanPreservesHardBreakPreparedText() throws {
    #if canImport(CoreText)
    var stream = MarkdownStream()
    stream.append("first line  \nsecond line")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 220)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)

    #expect(plan.lines.count >= 2)
    #expect(plan.lines.map(\.text).joined() == inlineLayout.prepared.naturalText.replacingOccurrences(of: "\n", with: ""))
    #expect(plan.lines.contains { $0.text.contains("first line") })
    #expect(plan.lines.contains { $0.text.contains("second line") })
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
func coreTextPaintedLinePlanDrawsNonBlankGlyphsOffscreen() throws {
    #if canImport(CoreText)
    var stream = MarkdownStream()
    stream.append("alpha beta gamma with preserved spaces")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines)
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 260)
    let plan = MarkdownCoreTextPaintedLinePlan.make(prepared: inlineLayout, layout: layout)
    let firstLine = try #require(plan.lines.first)
    let noSpaceWidth = coreTextPaintedTestWidth(
        of: firstLine.text.replacingOccurrences(of: " ", with: ""),
        prepared: inlineLayout
    )
    let alphaCoverage = coreTextPaintedTestAlphaCoverage(plan: plan, width: 320, height: 96)

    #expect(firstLine.text.contains("alpha beta"))
    #expect(firstLine.typographicWidth > noSpaceWidth)
    #expect(alphaCoverage > 250)
    #else
    #expect(CoreTextPaintedInlineLineView.isSupported == false)
    #endif
}

@Test
@MainActor
func packagedPresetsUseCoreTextPaintedLinesWhileFallbackModesStayExplicit() throws {
    #expect(MarkdownRendererConfiguration.compactChat.inlineRenderingMode == .coreTextPaintedLines)
    #expect(MarkdownRendererConfiguration.document.inlineRenderingMode == .coreTextPaintedLines)
    #expect(MarkdownRendererConfiguration().inlineRenderingMode == .coreTextPaintedLines)
    #expect(MarkdownRendererConfiguration(inlineRenderingMode: .systemText).inlineRenderingMode == .systemText)
    #expect(MarkdownRendererConfiguration(inlineRenderingMode: .preparedNativeLines).inlineRenderingMode == .preparedNativeLines)
    #expect(MarkdownRendererConfiguration(inlineRenderingMode: .coreTextPaintedLines).inlineRenderingMode == .coreTextPaintedLines)
    #expect(MarkdownRendererConfiguration.compactChat.documentSelection == .enabled)
    #expect(MarkdownRendererConfiguration.document.documentSelection == .enabled)
    #expect(MarkdownRendererConfiguration().documentSelection == .enabled)
    #expect(MarkdownRendererConfiguration(documentSelection: .disabled).documentSelection == .disabled)
    #expect(MarkdownRendererConfiguration.compactChat.nativeTextSelection == .disabled)
    #expect(MarkdownRendererConfiguration.document.nativeTextSelection == .disabled)
    #expect(MarkdownRendererConfiguration().nativeTextSelection == .disabled)
    #expect(MarkdownRendererConfiguration(nativeTextSelection: .enabled).nativeTextSelection == .enabled)
    #expect(MarkdownRendererConfiguration(nativeTextSelection: .disabled).nativeTextSelection == .disabled)

    let block = MarkdownBlock(
        id: MarkdownBlockID("block-default-mode"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        isSealed: true
    )
    let view = MarkdownBlockView(
        block: block,
        configuration: MarkdownRendererConfiguration(theme: .compactChat),
        preparedContent: nil
    )
    let configuration = try #require(mirroredConfiguration(from: view))
    #expect(configuration.inlineRenderingMode == .coreTextPaintedLines)
}

@Test
func documentSelectionDefaultsToEnabledWhileNativeSelectionStaysLeafCompatibilityKnob() throws {
    let root = packageRootURL()
    let configuration = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownRendererConfiguration.swift"),
        encoding: .utf8
    )
    let documentView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentView.swift"),
        encoding: .utf8
    )
    let surfaceView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentSurface.swift"),
        encoding: .utf8
    )

    #expect(configuration.contains("public enum DocumentSelection"))
    #expect(configuration.contains("public var documentSelection: DocumentSelection"))
    #expect(configuration.contains("documentSelection: DocumentSelection = .enabled"))
    #expect(configuration.contains("nativeTextSelection: MarkdownNativeTextSelection = .disabled"))
    #expect(documentView.contains("@StateObject private var internalSelectionController"))
    #expect(documentView.contains("configuration.documentSelection == .enabled"))
    #expect(documentView.contains("selectionController ?? internalSelectionController"))
    #expect(documentView.contains("MarkdownDocumentSelectionLayer"))
    #expect(documentView.contains("#if os(tvOS)"))
    #expect(documentView.contains("TapGesture()"))
    #expect(documentView.contains("MarkdownDocumentSelectionDragActivation"))
    #expect(documentView.contains("DragGesture(minimumDistance: dragActivation.minimumDistance)"))
    #expect(documentView.contains("dragActivation.hasActivated"))
    #expect(documentView.contains("MarkdownDocumentSelectionKeyHandler"))
    #expect(documentView.contains("selectSourceRanges"))
    #expect(documentView.contains(".environment(\\.markdownDocumentSelectionContext"))
    #expect(documentView.contains("emitsTextLeafSelectionFragments"))
    #expect(surfaceView.contains("selectionController: MarkdownSelectionController? = nil"))
}

@Test
func documentSelectionLayoutUsesLightweightPreparedIdentities() throws {
    let root = packageRootURL()
    let configuration = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownRendererConfiguration.swift"),
        encoding: .utf8
    )
    let documentView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentView.swift"),
        encoding: .utf8
    )
    let surfaceView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentSurface.swift"),
        encoding: .utf8
    )
    let selectionGeometry = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Interaction/MarkdownDocumentSelectionGeometry.swift"),
        encoding: .utf8
    )

    #expect(configuration.contains("public var renderItems: [MarkdownPreparedSnapshotRenderItem]"))
    #expect(configuration.contains("public var itemIDs: [String]"))
    #expect(configuration.contains("public struct MarkdownPreparedSnapshotRenderItem"))
    #expect(documentView.occurrences(of: "ForEach(preparedSnapshot.renderItems)") == 2)
    #expect(!documentView.contains("ForEach(preparedSnapshot.items)"))
    #expect(surfaceView.contains("self.itemIDs = preparedSnapshot.itemIDs"))
    #expect(selectionGeometry.contains("private var equalityFingerprint: Int"))
    #expect(selectionGeometry.contains("makeEqualityFingerprint"))
    #expect(selectionGeometry.contains("static func == (\n        lhs: MarkdownDocumentSelectionTextGeometry"))
}

@Test
func nativeTextSelectionMountsOnlyBoundedTextLeaves() throws {
    let root = packageRootURL()
    let helper = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Interaction/MarkdownNativeTextSelection.swift"),
        encoding: .utf8
    )
    let blockView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Blocks/MarkdownBlockView.swift"),
        encoding: .utf8
    )
    let mermaidView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Blocks/MarkdownMermaidDiagramView.swift"),
        encoding: .utf8
    )
    let documentView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentView.swift"),
        encoding: .utf8
    )
    let surfaceView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Views/MarkdownDocumentSurface.swift"),
        encoding: .utf8
    )
    let inlineRunsView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Inline/InlineRunsView.swift"),
        encoding: .utf8
    )
    let nativeLineTextView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Inline/NativeInlineLineTextView.swift"),
        encoding: .utf8
    )
    let coreTextPaintedLineView = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Inline/CoreTextPaintedInlineLineView.swift"),
        encoding: .utf8
    )
    let platformHooks = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Platform/MarkdownPlatformHooks.swift"),
        encoding: .utf8
    )
    let sourceFiles = try swiftSourceFiles(under: root.appending(path: "Sources/SiriusMarkdownSwiftUI"))
    let directSelectionOffenders = try sourceFiles.filter { file in
        guard file.lastPathComponent != "MarkdownNativeTextSelection.swift" else {
            return false
        }
        return try String(contentsOf: file, encoding: .utf8).contains(".textSelection(.enabled)")
    }

    #expect(helper.occurrences(of: ".textSelection(.enabled)") == 1)
    #expect(helper.contains("#if os(macOS)"))
    #expect(helper.contains("#elseif os(tvOS) || os(watchOS)"))
    #expect(platformHooks.contains("#elseif canImport(UIKit) && !os(tvOS) && !os(watchOS)"))
    #expect(platformHooks.contains("#elseif canImport(UIKit) && !os(watchOS)"))
    #expect(coreTextPaintedLineView.contains("canImport(UIKit) && !os(watchOS)"))
    #expect(directSelectionOffenders.isEmpty)
    #expect(!blockView.contains(".textSelection(.enabled)"))
    #expect(!mermaidView.contains(".textSelection(.enabled)"))
    #expect(!mermaidView.contains(".markdownNativeTextSelection("))
    #expect(!documentView.contains(".markdownNativeTextSelection("))
    #expect(!surfaceView.contains(".markdownNativeTextSelection("))
    #expect(blockView.contains("MarkdownSelectableText("))
    #expect(blockView.contains("selectionMode: configuration.nativeTextSelection"))
    #expect(blockView.contains("nativeTextSelection: selectionMode"))
    #expect(blockView.contains("nativeTextSelection: selectionModeInsideLeadingLayout"))
    #expect(blockView.contains("nativeTextSelection: selectionModeInsideCompositeGrid"))
    #expect(blockView.contains("private var selectionModeInsideLeadingLayout: MarkdownNativeTextSelection"))
    #expect(blockView.contains("private var selectionModeInsideCompositeGrid: MarkdownNativeTextSelection"))
    #expect(blockView.occurrences(
        of: "selectionModeInsideLeadingLayout: MarkdownNativeTextSelection {\n        configuration.nativeTextSelection\n    }"
    ) == 2)
    #expect(blockView.contains(
        "selectionModeInsideCompositeGrid: MarkdownNativeTextSelection {\n        configuration.nativeTextSelection\n    }"
    ))
    #expect(inlineRunsView.contains("nativeTextSelection: MarkdownNativeTextSelection = .disabled"))
    #expect(inlineRunsView.contains("MarkdownSelectableText("))
    #expect(inlineRunsView.contains("nativeTextSelection: nativeTextSelection"))
    #expect(nativeLineTextView.contains("MarkdownSelectableText("))
    #expect(nativeLineTextView.contains("wraps: false"))
    #expect(nativeLineTextView.contains("private var shouldPaintWithCoreText: Bool"))
    #expect(nativeLineTextView.contains("nativeTextSelection != .enabled"))
}

@Test
func defaultJavaScriptResourceLoadingUsesNonTrappingLookup() throws {
    let root = packageRootURL()
    let sourceFiles = try swiftSourceFiles(under: root.appending(path: "Sources/SiriusMarkdownSwiftUI"))
    let offenders = try sourceFiles.filter { file in
        try String(contentsOf: file, encoding: .utf8).contains("Bundle.module")
    }

    #expect(offenders.isEmpty)
}

@Test
func releaseAndProductChecksKeepRenderProbeVisualsOptIn() throws {
    let root = packageRootURL()
    let currentReleaseVersion = "0.6.0"
    let releaseCheck = try String(
        contentsOf: root.appending(path: "Tools/release-check.sh"),
        encoding: .utf8
    )
    let productCheck = try String(
        contentsOf: root.appending(path: "Tools/product-check.sh"),
        encoding: .utf8
    )
    let readme = try String(
        contentsOf: root.appending(path: "README.md"),
        encoding: .utf8
    )
    let docC = try String(
        contentsOf: root.appending(path: "Docs/SiriusMarkdown.docc/SiriusMarkdown.md"),
        encoding: .utf8
    )
    let architecture = try String(
        contentsOf: root.appending(path: "Docs/architecture.md"),
        encoding: .utf8
    )
    let runbook = try String(
        contentsOf: root.appending(path: "runbook.md"),
        encoding: .utf8
    )
    let renderProbe = try String(
        contentsOf: root.appending(path: "Tools/RenderProbe/Sources/SiriusMarkdownRenderProbe/main.swift"),
        encoding: .utf8
    )
    let forbiddenOrderFront = "." + "orderFront" + "Regardless()"

    for script in [releaseCheck, productCheck] {
        #expect(script.contains("SIRIUS_MARKDOWN_RUN_VISUAL_PROBES"))
        #expect(script.contains("Skipping RenderProbe visual checks."))
        #expect(script.contains("swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe"))
    }

    #expect(readme.contains("By default the gate skips the AppKit render probe"))
    #expect(readme.contains("SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1"))
    #expect(!readme.contains("The gate runs the AppKit render probe"))

    #expect(docC.contains("AppKit render probes remain available as an explicit `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` opt-in"))
    #expect(docC.contains("render probes are opt-in visual checks"))
    #expect(!docC.contains("release gate covering strict Swift-vs-Pretext fixture comparison, AppKit render probes"))

    #expect(architecture.contains("opt-in `Tools/RenderProbe` offscreen AppKit host"))
    #expect(architecture.contains("SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1"))

    #expect(readme.contains(".package(url: \"https://github.com/mikhutchinson/SiriusMarkdown.git\", from: \"\(currentReleaseVersion)\")"))
    #expect(readme.contains("pushed as `\(currentReleaseVersion)`"))
    #expect(runbook.contains("current public package release, use `\(currentReleaseVersion)` as the tag"))
    #expect(runbook.contains("git tag -a \(currentReleaseVersion) -m \"SiriusMarkdown \(currentReleaseVersion)\""))
    #expect(releaseCheck.contains("--fallback-bundle-version \(currentReleaseVersion)"))

    #expect(!renderProbe.contains(forbiddenOrderFront))
}

@Test
func swiftUITestTargetDoesNotOrderHostedWindowsOnScreen() throws {
    let root = packageRootURL()
    let testsRoot = root.appending(path: "Tests/SiriusMarkdownSwiftUITests")
    let fileManager = FileManager.default
    let enumerator = try #require(fileManager.enumerator(
        at: testsRoot,
        includingPropertiesForKeys: nil
    ))
    var offenders: [String] = []
    let forbiddenCall = "." + "orderFront" + "Regardless()"

    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let source = try String(contentsOf: url, encoding: .utf8)
        if source.contains(forbiddenCall) {
            offenders.append(url.lastPathComponent)
        }
    }

    #expect(offenders.isEmpty)
}

@Test
func macOSDemoBundlerCopiesSwiftPMResourceBundlesIntoApps() throws {
    let root = packageRootURL()
    let script = try String(
        contentsOf: root.appending(path: "Examples/scripts/bundle-macos-demos.sh"),
        encoding: .utf8
    )

    #expect(script.contains("for bundle in \"${bin_root}\"/*.bundle"))
    #expect(script.contains("[[ -d \"${bundle}\" ]] || continue"))
    #expect(script.contains("cp -R \"${bundle}\" \"${resources}/\""))
    #expect(script.contains("local resources=\"${contents}/Resources\""))
}

@Test
func defaultDocumentSelectionEmitsTextLeafRectsForListRows() throws {
    let markdown = """
    - List selection should be bounded to the text leaf instead of the full transcript row.
    - A second wrapped list item proves row-width bands do not come from the parent list rect.
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let item = try #require(content.listItems.first)
    let inlineLayout = try #require(item.inlineLayout)
    let textLeafRect = CGRect(x: 36, y: 10, width: 260, height: 90)
    let layout = inlineLayout.layout(
        containerWidth: InlineRunsView.nativeLineLayoutWidth(
            for: inlineLayout,
            containerWidth: Double(textLeafRect.width)
        ),
        allowsOverwideFallback: true
    )
    let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
        blockID: block.id,
        prepared: inlineLayout,
        layout: layout,
        rect: textLeafRect,
        idPrefix: "text-leaf"
    )

    #expect(!fragments.isEmpty)
    #expect(fragments.allSatisfy { $0.id.hasPrefix("text-leaf:") })
    #expect(fragments.allSatisfy { $0.rect.minX == textLeafRect.minX })
    #expect(fragments.allSatisfy { $0.rect.width < textLeafRect.width })
}

#if canImport(AppKit)
@Suite(.serialized)
struct MarkdownNativeTextSelectionAppKitTests {
@Test
@MainActor
func enabledNativeTextSelectionMountsAppKitSelectableTextLeafOnMacOS() throws {
    let view = MarkdownSelectableText(
        attributed: AttributedString("Selectable native text"),
        font: .body,
        fontSize: 16,
        lineHeight: 22,
        fontProfile: .system(),
        textColor: .primary,
        nativeTextSelection: .enabled
    )
    .frame(width: 240, alignment: .leading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 240, height: 80))
    pumpLayout(hostingView)

    let textView = try #require(appKitTextViews(in: hostingView).first)
    #expect(textView.isSelectable)
    #expect(!textView.isEditable)
    #expect(textView.textContainerInset == .zero)
}

@Test
@MainActor
func enabledNativeTextSelectionReachesCompositeMarkdownLeavesOnMacOS() throws {
    let markdown = """
    > Quote selectable text

    - List selectable text
      - Nested selectable text

    | Header |
    | - |
    | Table selectable text |
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.nativeTextSelection = .enabled
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let view = MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
        .frame(width: 520, height: 420, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 520, height: 420))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let textViews = appKitTextViews(in: hostingView)
    let renderedText = textViews.map(\.string).joined(separator: "\n")
    let expectedLeaves = [
        "Quote selectable text",
        "List selectable text",
        "Nested selectable text",
        "Header",
        "Table selectable text",
    ]

    #expect(textViews.count >= expectedLeaves.count)
    for expected in expectedLeaves {
        #expect(renderedText.contains(expected))
        let leaf = try #require(textViews.first { $0.string.contains(expected) })
        #expect(leaf.isSelectable)
        #expect(!leaf.isEditable)
    }
}

@Test
@MainActor
func enabledNativeTextSelectionCanSelectAndCopyListTextLeafOnMacOS() throws {
    let markdown = "- List selectable text copy proof"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.nativeTextSelection = .enabled
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let view = StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
        .frame(width: 360, height: 160, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: 160))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let textView = try #require(appKitTextViews(in: hostingView).first {
        $0.string.contains("List selectable text copy proof")
    })
    let copied = try copySelectedText("List selectable text", from: textView)

    #expect(textView.isSelectable)
    #expect(copied == "List selectable text")
}

@Test
@MainActor
func defaultDocumentSelectionResolvesWrappedLineDragToExactSourceOnMacOS() throws {
    let markdown = """
    Wrapped paragraph selection starts here and continues with enough words to wrap across several prepared native visual lines in a narrow streaming transcript column.
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    #expect(configuration.documentSelection == .enabled)
    #expect(configuration.nativeTextSelection == .disabled)

    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let block = try #require(stream.snapshot().blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragments = MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 180, height: 180)
    ).sortedForTestSelection()
    let first = try #require(fragments.first)
    let last = try #require(fragments.last)
    let selection = MarkdownDocumentSelectionFragment.selection(from: first, to: last, in: fragments)
    let reversedSelection = MarkdownDocumentSelectionFragment.selection(from: last, to: first, in: fragments)

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(stream.snapshot())
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)

    #expect(fragments.count > 1)
    #expect(reversedSelection.ranges == selection.ranges)
    #expect(reversedSelection.blockIDs == selection.blockIDs)
    #expect(controller.selectedBlockIDs == [block.id])
    #expect(controller.selectedSourceRanges == selection.ranges)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == markdown)
}

@Test
@MainActor
func defaultDocumentSelectionCopiesParagraphBreakLineSourceExactlyOnMacOS() throws {
    let markdown = "alpha soft\nbeta hard  \ngamma after"
    let softLineRange = try utf8Range(of: "alpha soft\n", in: markdown)
    let hardLineRange = try utf8Range(of: "beta hard  \n", in: markdown)
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragments = MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 140)
    ).filter { $0.textGeometry != nil }

    let softLine = try #require(fragments.first { $0.sourceRange.byteRange == softLineRange })
    let hardLine = try #require(fragments.first { $0.sourceRange.byteRange == hardLineRange })
    let softSelection = MarkdownDocumentSelectionFragment.selection(from: softLine, to: softLine, in: fragments)
    let hardSelection = MarkdownDocumentSelectionFragment.selection(from: hardLine, to: hardLine, in: fragments)
    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)

    controller.selectSourceRanges(softSelection.ranges, selectedBlockIDs: softSelection.blockIDs)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == "alpha soft\n")

    controller.selectSourceRanges(hardSelection.ranges, selectedBlockIDs: hardSelection.blockIDs)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == "beta hard  \n")
}

@Test
@MainActor
func defaultDocumentSelectionClipsHighlightsToPartialPreparedLineRangesOnMacOS() throws {
    let markdown = "Partial selection should paint only the selected glyph span, not the whole prepared line."
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { $0.textGeometry != nil })

    let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.25, y: fragment.rect.midY))
    let end = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.75, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
    let selectedRange = try #require(selection.ranges.first)
    let highlight = try #require(fragment.highlightRects(for: selection.ranges).first)

    #expect(selectedRange.byteRange.lowerBound > fragment.sourceRange.byteRange.lowerBound)
    #expect(selectedRange.byteRange.upperBound < fragment.sourceRange.byteRange.upperBound)
    #expect(highlight.rect.minX > fragment.rect.minX)
    #expect(highlight.rect.maxX < fragment.rect.maxX)
    #expect(highlight.rect.width < fragment.rect.width * 0.8)
}

@Test
@MainActor
func defaultDocumentSelectionTextGeometryPreservesPresentationForStyledLinks() throws {
    let markdown = "[**Styled link**](https://example.com)"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let run = try #require(block.inlines.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { $0.textGeometry != nil })
    let textGeometry = try #require(fragment.textGeometry)
    let fontRun = try #require(textGeometry.fontRuns.first)

    #expect(run.kind == .link)
    #expect(run.presentation.contains(.strong))
    #expect(fontRun.kind == .link)
    #expect(fontRun.presentation.contains(.strong))
}

@Test
@MainActor
func defaultDocumentSelectionOverwideLineEndpointStopsAtVisibleGlyphPositionOnMacOS() throws {
    let markdown = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let inlineLayout = try #require(content.inlineLayout)
    let visibleByteCount = inlineLayout.prepared.naturalText.utf8.count
    let fragment = try #require(MarkdownDocumentSelectionFragment.inlineLineFragments(
        blockID: block.id,
        prepared: inlineLayout,
        layout: InlineLayoutResult(
            lines: [InlineLineRange(byteRange: 0..<visibleByteCount, width: 320)],
            naturalWidth: 320,
            height: inlineLayout.lineHeight
        ),
        rect: CGRect(x: 0, y: 0, width: 96, height: 80),
        idPrefix: "overwide-test"
    ).first { $0.textGeometry != nil })
    let textGeometry = try #require(fragment.textGeometry)

    #expect(textGeometry.lineWidth > fragment.rect.width)

    let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX, y: fragment.rect.midY))
    let visibleEdge = fragment.endpoint(at: CGPoint(x: fragment.rect.maxX, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: visibleEdge, in: [fragment])
    let selectedRange = try #require(selection.ranges.first)

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    let selectedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider)

    #expect(selectedRange.byteRange.lowerBound == fragment.sourceRange.byteRange.lowerBound)
    #expect(selectedRange.byteRange.upperBound < fragment.sourceRange.byteRange.upperBound)
    #expect(selectedMarkdown.utf8.count < markdown.utf8.count)
    #expect(markdown.hasPrefix(selectedMarkdown))
}

@Test
@MainActor
func defaultDocumentSelectionOverwideLineDoesNotPaintHiddenOnlyRangesOnMacOS() throws {
    let markdown = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let inlineLayout = try #require(content.inlineLayout)
    let visibleByteCount = inlineLayout.prepared.naturalText.utf8.count
    let fragment = try #require(MarkdownDocumentSelectionFragment.inlineLineFragments(
        blockID: block.id,
        prepared: inlineLayout,
        layout: InlineLayoutResult(
            lines: [InlineLineRange(byteRange: 0..<visibleByteCount, width: 320)],
            naturalWidth: 320,
            height: inlineLayout.lineHeight
        ),
        rect: CGRect(x: 0, y: 0, width: 96, height: 80),
        idPrefix: "overwide-test"
    ).first { $0.textGeometry != nil })
    let textGeometry = try #require(fragment.textGeometry)
    let visibleEdgeOffset = textGeometry.sourceByteOffset(atX: fragment.rect.width)
    let hiddenLower = max(visibleEdgeOffset + 1, fragment.sourceRange.byteRange.lowerBound)
    let hiddenUpper = min(hiddenLower + 2, fragment.sourceRange.byteRange.upperBound)
    let hiddenRange = MarkdownSourceRange(
        byteRange: hiddenLower..<hiddenUpper,
        lineRange: fragment.sourceRange.lineRange
    )

    #expect(textGeometry.lineWidth > fragment.rect.width)
    #expect(hiddenRange.byteRange.lowerBound < hiddenRange.byteRange.upperBound)
    #expect(textGeometry.xOffset(forSourceByteOffset: hiddenRange.byteRange.lowerBound) > fragment.rect.width)
    #expect(fragment.highlightRects(for: [hiddenRange]).isEmpty)
}

@Test
@MainActor
func defaultDocumentSelectionRTLEdgeEndpointsFollowCoreTextVisualOrderOnMacOS() throws {
    let markdown = "שלום עולם"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { $0.textGeometry != nil })

    let leftEdge = fragment.endpoint(at: CGPoint(x: fragment.rect.minX, y: fragment.rect.midY))
    let rightEdge = fragment.endpoint(at: CGPoint(x: fragment.rect.maxX, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: leftEdge, to: rightEdge, in: [fragment])

    #expect(leftEdge.sourceByteOffset == fragment.sourceRange.byteRange.upperBound)
    #expect(rightEdge.sourceByteOffset == fragment.sourceRange.byteRange.lowerBound)
    #expect(selection.ranges.first?.byteRange == fragment.sourceRange.byteRange)
}

@Test
@MainActor
func defaultDocumentSelectionOverwideRTLLineDoesNotPaintHiddenSourcePrefixOnMacOS() throws {
    let markdown = "שלום עולם שלום עולם שלום עולם שלום עולם"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.compactChat
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let inlineLayout = try #require(content.inlineLayout)
    let visibleByteCount = inlineLayout.prepared.naturalText.utf8.count
    let fragment = try #require(MarkdownDocumentSelectionFragment.inlineLineFragments(
        blockID: block.id,
        prepared: inlineLayout,
        layout: InlineLayoutResult(
            lines: [InlineLineRange(byteRange: 0..<visibleByteCount, width: 360)],
            naturalWidth: 360,
            height: inlineLayout.lineHeight
        ),
        rect: CGRect(x: 0, y: 0, width: 96, height: 80),
        idPrefix: "overwide-rtl-test"
    ).first { $0.textGeometry != nil })
    let textGeometry = try #require(fragment.textGeometry)
    let visibleBoundary = textGeometry.sourceByteOffset(atX: fragment.rect.width)
    let hiddenBoundary = textGeometry.sourceByteOffset(
        atX: min(textGeometry.lineWidth, fragment.rect.width + 80)
    )
    let hiddenUpper = max(fragment.sourceRange.byteRange.lowerBound + 1, hiddenBoundary)
    let hiddenRange = MarkdownSourceRange(
        byteRange: fragment.sourceRange.byteRange.lowerBound..<hiddenUpper,
        lineRange: fragment.sourceRange.lineRange
    )

    #expect(textGeometry.lineWidth > fragment.rect.width)
    #expect(visibleBoundary > fragment.sourceRange.byteRange.lowerBound)
    #expect(visibleBoundary < fragment.sourceRange.byteRange.upperBound)
    #expect(hiddenBoundary > fragment.sourceRange.byteRange.lowerBound)
    #expect(hiddenBoundary < visibleBoundary)
    #expect(textGeometry.xOffset(forSourceByteOffset: hiddenRange.byteRange.upperBound) > fragment.rect.width)
    #expect(fragment.highlightRects(for: [hiddenRange]).isEmpty)
}

@Test
@MainActor
func defaultDocumentSelectionSnapsInlineCodeDragToWholeMarkdownSourceRunOnMacOS() throws {
    let markdown = "Before `code value` after"
    let codeRange = try utf8Range(of: "`code value`", in: markdown)
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { fragment in
        fragment.textGeometry?.sourceRuns.contains { $0.sourceRange.byteRange == codeRange } == true
    })
    let textGeometry = try #require(fragment.textGeometry)
    let lowerX = textGeometry.xOffset(forSourceByteOffset: codeRange.lowerBound)
    let upperX = textGeometry.xOffset(forSourceByteOffset: codeRange.upperBound)
    let runWidth = upperX - lowerX

    #expect(runWidth > 4)

    let start = fragment.endpoint(at: CGPoint(
        x: fragment.rect.minX + lowerX + runWidth * 0.25,
        y: fragment.rect.midY
    ))
    let end = fragment.endpoint(at: CGPoint(
        x: fragment.rect.minX + lowerX + runWidth * 0.75,
        y: fragment.rect.midY
    ))
    let forwardSelection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
    let reversedSelection = MarkdownDocumentSelectionFragment.selection(from: end, to: start, in: [fragment])

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(forwardSelection.ranges, selectedBlockIDs: forwardSelection.blockIDs)

    #expect(forwardSelection.ranges.first?.byteRange == codeRange)
    #expect(reversedSelection.ranges.first?.byteRange == codeRange)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == "`code value`")
}

@Test
@MainActor
func defaultDocumentSelectionEmitsPreciseCodeBlockTextFragmentsOnMacOS() throws {
    let markdown = """
    ```swift
    swift
    let second = 2
    ```
    """
    let selectedLineRange = try utf8Range(of: "let second = 2\n", in: markdown)
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let selectionInline = try #require(content.selectionInlineLayout)
    let codeSourceRange = try #require(block.inlines.first?.sourceRange)
    let openingFenceRange = try utf8Range(of: "```swift", in: markdown)

    #expect(codeSourceRange.byteRange.lowerBound > openingFenceRange.upperBound)
    #expect(selectionInline.prepared.sourceRange == codeSourceRange)

    let recorder = SelectionPreferenceRecorder()
    let view = MarkdownBlockView(
        block: block,
        configuration: configuration,
        preparedContent: content
    )
    .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
    .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
    .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
        recorder.fragments = fragments
    }
    .frame(width: 420, height: 180, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 420, height: 180))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let fragments = recorder.fragments.sortedForTestSelection()
    let selectedLineFragment = try #require(fragments.first { fragment in
        fragment.sourceRange.byteRange == selectedLineRange
    })
    let selection = MarkdownDocumentSelectionFragment.selection(
        from: selectedLineFragment,
        to: selectedLineFragment,
        in: fragments
    )
    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)

    #expect(fragments.count >= 2)
    #expect(selectedLineFragment.textGeometry != nil)
    #expect(selection.ranges.first?.byteRange == selectedLineRange)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == "let second = 2\n")
}

@Test
@MainActor
func defaultDocumentSelectionUsesRenderedTableCellGeometryForExactCopyOnMacOS() throws {
    let markdown = """
    | Column | Value |
    | --- | --- |
    | first | cell exact |
    | second | other |
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let table = try #require(content.table)
    let firstCell = try #require(table.rows.first?.cells.first)
    let targetCell = try #require(table.rows.first?.cells.dropFirst().first)
    let expectedMarkdown = try #require(configuration.copyProvider?.markdown(targetCell.sourceRange))

    let recorder = SelectionPreferenceRecorder()
    let view = MarkdownBlockView(
        block: block,
        configuration: configuration,
        preparedContent: content
    )
    .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
    .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
    .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
        recorder.fragments = fragments
    }
    .frame(width: 520, height: 180, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 520, height: 180))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let fragments = recorder.fragments.sortedForTestSelection()
    let firstCellFragment = try #require(fragments.first {
        $0.sourceRange == firstCell.sourceRange && $0.textGeometry != nil
    })
    let targetFragment = try #require(fragments.first {
        $0.sourceRange == targetCell.sourceRange && $0.textGeometry != nil
    })
    let selection = MarkdownDocumentSelectionFragment.selection(
        from: targetFragment,
        to: targetFragment,
        in: fragments
    )
    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)

    #expect(fragments.count >= 6)
    #expect(targetFragment.rect.minX > firstCellFragment.rect.maxX)
    #expect(targetFragment.rect.width < 520)
    #expect(selection.ranges.first?.byteRange == targetCell.sourceRange.byteRange)
    #expect(expectedMarkdown.contains("cell exact"))
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == expectedMarkdown)
}

@Test
@MainActor
func defaultDocumentSelectionFullLineHighlightCoversStyledMarkdownSourceOnMacOS() throws {
    let markdown = "**Styled line with source delimiters**"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { $0.textGeometry != nil })
    let selection = MarkdownDocumentSelectionFragment.selection(from: fragment, to: fragment, in: [fragment])
    let highlight = try #require(fragment.highlightRects(for: selection.ranges).first)

    #expect(fragment.sourceRange.byteRange == 0..<markdown.utf8.count)
    #expect(selection.ranges.first?.byteRange == 0..<markdown.utf8.count)
    #expect(highlight.rect.width > fragment.rect.width * 0.9)
}

@Test
@MainActor
func defaultDocumentSelectionResolvesDragAndCmdCCopyAcrossBlockBoundariesOnMacOS() throws {
    let markdown = """
    Paragraph boundary selection.

    - List item boundary selection.

    > Quote boundary selection.

    ```swift
    let copied = "code boundary"
    ```

    | Region | Evidence |
    | - | - |
    | Table | cell boundary selection |
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let controller = MarkdownSelectionController()
    let copySpy = MarkdownCopySpy()
    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    configuration.affordanceActionHandler = MarkdownAffordanceActionHandler { string in
        copySpy.copied = string
    }
    #expect(configuration.documentSelection == .enabled)
    #expect(configuration.nativeTextSelection == .disabled)

    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let fragments = selectionFragments(for: snapshot, prepared: prepared, width: 560)
    let first = try #require(fragments.first)
    let last = try #require(fragments.last)
    let selection = MarkdownDocumentSelectionFragment.selection(from: first, to: last, in: fragments)

    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    let selectedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider)
    let selectedRange = try #require(selection.ranges.first)
    let expectedMarkdown = try #require(configuration.copyProvider?.markdown(selectedRange))
    let copyContext = MarkdownDocumentSelectionCopyContext(
        selectionController: controller,
        preparedSnapshot: prepared,
        copyProvider: configuration.copyProvider,
        affordanceActionHandler: configuration.affordanceActionHandler
    )
    let coordinator = MarkdownDocumentSelectionKeyHandler.Coordinator(copyContext: copyContext)
    let keyView = MarkdownDocumentSelectionKeyHandler.CopyKeyView()
    keyView.coordinator = coordinator
    keyView.keyDown(with: commandCEvent())

    #expect(controller.selectedBlockIDs.count == snapshot.blocks.count)
    #expect(controller.selectedSourceRanges.count == 1)
    #expect(expectedMarkdown.contains("Paragraph boundary selection."))
    #expect(expectedMarkdown.contains("List item boundary selection."))
    #expect(expectedMarkdown.contains("Quote boundary selection."))
    #expect(expectedMarkdown.contains("let copied = \"code boundary\""))
    #expect(expectedMarkdown.contains("cell boundary selection"))
    #expect(selectedMarkdown == expectedMarkdown)
    #expect(copySpy.copied == expectedMarkdown)
}

@Test
@MainActor
func defaultDocumentSelectionCommandASelectsAndCopiesFullDocumentMarkdownOnMacOS() throws {
    let markdown = """
    # Full selection

    Paragraph before list.

    - first
    - second

    ```swift
    let all = true
    ```

    | Key | Value |
    | - | - |
    | copy | exact |
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let controller = MarkdownSelectionController(maximumSelectedBlockCount: 2)
    let copySpy = MarkdownCopySpy()
    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    configuration.affordanceActionHandler = MarkdownAffordanceActionHandler { string in
        copySpy.copied = string
    }

    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    controller.updateSnapshot(snapshot)
    let copyContext = MarkdownDocumentSelectionCopyContext(
        selectionController: controller,
        preparedSnapshot: prepared,
        copyProvider: configuration.copyProvider,
        affordanceActionHandler: configuration.affordanceActionHandler
    )
    let coordinator = MarkdownDocumentSelectionKeyHandler.Coordinator(copyContext: copyContext)
    let keyView = MarkdownDocumentSelectionKeyHandler.CopyKeyView()
    keyView.coordinator = coordinator

    keyView.keyDown(with: commandAEvent())
    controller.updateSnapshot(snapshot)
    keyView.keyDown(with: commandCEvent())

    #expect(controller.selectedSourceRanges.map(\.byteRange) == [0..<markdown.utf8.count])
    #expect(controller.selectedBlockIDs.count == snapshot.blocks.count)
    #expect(controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider) == markdown)
    #expect(copySpy.copied == markdown)
}

@Test
@MainActor
func imageBackedDisplayMathBlocksPrepareSourceBackedSelectionFragments() throws {
    let markdown = """
    \\[
    x^2 + y^2
    \\]
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration(mathRenderer: CountingImageMathRenderer())
    let snapshot = stream.snapshot()
    let block = try #require(snapshot.blocks.first { $0.kind == .mathBlock })
    let content = configuration.prepare(block: block)
    guard case .image = content.mathRender else {
        Issue.record("Expected image-backed display math.")
        return
    }

    let selectionInline = try #require(content.selectionInlineLayout)
    let mathSourceRange = try #require(block.inlines.first { $0.kind == .math }?.sourceRange)
    let layoutWidth = max(
        InlineRunsView.nativeLineLayoutWidth(
            for: selectionInline,
            containerWidth: 320
        ),
        selectionInline.measured.naturalWidth
    )
    let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
        blockID: block.id,
        prepared: selectionInline,
        layout: selectionInline.layout(
            containerWidth: layoutWidth,
            allowsOverwideFallback: false
        ),
        rect: CGRect(x: 0, y: 0, width: 320, height: 80),
        idPrefix: "test-math-image"
    )

    #expect(content.emitsTextLeafSelectionFragments)
    #expect(selectionInline.prepared.sourceRange == mathSourceRange)
    #expect(selectionInline.prepared.naturalText == "x^2 + y^2")
    #expect(fragments.count == 1)
    #expect(fragments.first?.sourceRange == mathSourceRange)
    #expect(fragments.first?.textGeometry != nil)
}

@Test
@MainActor
func defaultDocumentSelectionReceivesTextLeafFragmentForImageBackedInlineMath() throws {
    let markdown = "Before $x^2$ after"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration(mathRenderer: CountingImageMathRenderer())
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let inlineLayout = try #require(content.inlineLayout)
    #expect(inlineLayout.mathTextPieces != nil)

    let recorder = SelectionPreferenceRecorder()
    let view = InlineRunsView(
        prepared: inlineLayout,
        theme: configuration.theme,
        baseFont: configuration.theme.paragraphFont,
        linkAction: configuration.linkAction,
        inlineRenderingMode: configuration.inlineRenderingMode,
        nativeTextSelection: configuration.nativeTextSelection
    )
    .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
    .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
    .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
        recorder.fragments = fragments
    }
    .frame(width: 320, height: 80, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let fragments = recorder.fragments.sortedForTestSelection()
    let fragment = try #require(fragments.first)
    #expect(fragments.count == 1)
    #expect(fragment.id.hasPrefix("text-leaf-math:"))
    #expect(fragment.blockID == block.id)
    #expect(fragment.sourceRange == block.sourceRange)
    #expect(fragment.textGeometry != nil)
    #expect(fragment.rect.width > 0)
    #expect(fragment.rect.height > 0)

    let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.20, y: fragment.rect.midY))
    let end = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.45, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
    let selectedRange = try #require(selection.ranges.first)
    let highlight = try #require(fragment.highlightRects(for: selection.ranges).first)

    #expect(selectedRange.byteRange.lowerBound > block.sourceRange.byteRange.lowerBound)
    #expect(selectedRange.byteRange.upperBound < block.sourceRange.byteRange.upperBound)
    #expect(highlight.rect.minX > fragment.rect.minX)
    #expect(highlight.rect.maxX < fragment.rect.maxX)
    #expect(highlight.rect.width < fragment.rect.width * 0.6)
}

@Test
@MainActor
func defaultDocumentSelectionEmitsPreciseTextMathBlockFragmentsOnMacOS() throws {
    let markdown = """
    \\[
    alpha + beta + gamma
    \\]
    """
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first { $0.kind == .mathBlock })
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let selectionInline = try #require(content.selectionInlineLayout)
    let mathSourceRange = try #require(block.inlines.first { $0.kind == .math }?.sourceRange)

    #expect(selectionInline.prepared.sourceRange == mathSourceRange)
    #expect(mathSourceRange.byteRange.lowerBound > block.sourceRange.byteRange.lowerBound)
    #expect(mathSourceRange.byteRange.upperBound < block.sourceRange.byteRange.upperBound)

    let recorder = SelectionPreferenceRecorder()
    let view = MarkdownBlockView(
        block: block,
        configuration: configuration,
        preparedContent: content
    )
    .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
    .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
    .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
        recorder.fragments = fragments
    }
    .frame(width: 420, height: 120, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 420, height: 120))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let fragment = try #require(recorder.fragments.sortedForTestSelection().first { $0.textGeometry != nil })
    let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.20, y: fragment.rect.midY))
    let end = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width * 0.80, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
    let selectedRange = try #require(selection.ranges.first)
    let highlight = try #require(fragment.highlightRects(for: selection.ranges).first)

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    let selectedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider)

    #expect(fragment.sourceRange.byteRange.lowerBound >= mathSourceRange.byteRange.lowerBound)
    #expect(fragment.sourceRange.byteRange.upperBound <= mathSourceRange.byteRange.upperBound)
    #expect(selectedRange.byteRange.lowerBound > fragment.sourceRange.byteRange.lowerBound)
    #expect(selectedRange.byteRange.upperBound < fragment.sourceRange.byteRange.upperBound)
    #expect(highlight.rect.minX > fragment.rect.minX)
    #expect(highlight.rect.maxX < fragment.rect.maxX)
    #expect(!selectedMarkdown.isEmpty)
	#expect(!selectedMarkdown.contains("\\["))
	#expect(!selectedMarkdown.contains("\\]"))
}

@Test
@MainActor
func defaultDocumentSelectionEmitsPreciseAllowedHTMLBlockFragmentsOnMacOS() throws {
    let markdown = "<section><span>alpha beta gamma delta</span></section>"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.htmlPolicy = AllowHTMLPolicy()
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first { $0.kind == .htmlBlock })
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let selectionInline = try #require(content.selectionInlineLayout)

    #expect(selectionInline.prepared.sourceRange == block.sourceRange)
    #expect(selectionInline.prepared.naturalText == markdown)
    #expect(block.sourceRange.byteRange == 0..<markdown.utf8.count)

    let recorder = SelectionPreferenceRecorder()
    let view = MarkdownBlockView(
        block: block,
        configuration: configuration,
        preparedContent: content
    )
    .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
    .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
    .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
        recorder.fragments = fragments
    }
    .frame(width: 520, height: 90, alignment: .topLeading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 520, height: 90))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    let selectedHTMLRange = try utf8Range(of: "alpha", in: markdown)
    let fragment = try #require(recorder.fragments.sortedForTestSelection().first {
        $0.textGeometry != nil &&
            $0.sourceRange.byteRange.lowerBound <= selectedHTMLRange.lowerBound &&
            selectedHTMLRange.upperBound <= $0.sourceRange.byteRange.upperBound
    })
    let textGeometry = try #require(fragment.textGeometry)
    let lowerX = textGeometry.xOffset(forSourceByteOffset: selectedHTMLRange.lowerBound)
    let upperX = textGeometry.xOffset(forSourceByteOffset: selectedHTMLRange.upperBound)
    #expect(upperX - lowerX > 4)

    let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + lowerX + 1, y: fragment.rect.midY))
    let end = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + upperX - 1, y: fragment.rect.midY))
    let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
    let selectedRange = try #require(selection.ranges.first)
    let highlight = try #require(fragment.highlightRects(for: selection.ranges).first)

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(snapshot)
    controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    let selectedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: configuration.copyProvider)

    #expect(fragment.blockID == block.id)
    #expect(fragment.sourceRange.byteRange.lowerBound >= block.sourceRange.byteRange.lowerBound)
    #expect(fragment.sourceRange.byteRange.upperBound <= block.sourceRange.byteRange.upperBound)
    #expect(selectedRange.byteRange.lowerBound > fragment.sourceRange.byteRange.lowerBound)
    #expect(selectedRange.byteRange.upperBound < fragment.sourceRange.byteRange.upperBound)
    #expect(highlight.rect.minX > fragment.rect.minX)
    #expect(highlight.rect.maxX < fragment.rect.maxX)
    #expect(!selectedMarkdown.isEmpty)
    #expect(selectedMarkdown != markdown)
}
}
#endif

@Test
func nativeTextSelectionDocsTrackBoundedEnabledSelectionPath() throws {
    let root = packageRootURL()
    let docComment = try String(
        contentsOf: root.appending(path: "Sources/SiriusMarkdownSwiftUI/Interaction/MarkdownNativeTextSelection.swift"),
        encoding: .utf8
    )
    let readme = try String(contentsOf: root.appending(path: "README.md"), encoding: .utf8)
    let runbook = try String(contentsOf: root.appending(path: "runbook.md"), encoding: .utf8)
    let bugfix = try String(contentsOf: root.appending(path: "bugfix.md"), encoding: .utf8)
    let changelog = try String(contentsOf: root.appending(path: "changelog.md"), encoding: .utf8)
    let renderProbe = try String(
        contentsOf: root.appending(path: "Tools/RenderProbe/Sources/SiriusMarkdownRenderProbe/main.swift"),
        encoding: .utf8
    )
    let combined = [docComment, readme, runbook, bugfix, changelog, renderProbe].joined(separator: "\n")

    #expect(combined.contains("nativeTextSelection"))
    #expect(combined.contains("bounded text leaves"))
    #expect(combined.contains("SelectionOverlay.updateNSView"))
    #expect(combined.contains("GraphHost.flushTransactions"))
    #expect(combined.contains("NSTextField setFont:"))
    #expect(combined.contains("_invalidateEffectiveFont"))
    #expect(combined.contains("MarkdownSelectionController"))
    #expect(combined.contains("enabled-selection AppKit"))
    #expect(!combined.contains("Sirius samples"))
    #expect(!combined.contains("Sirius hang"))
    #expect(!combined.contains("sample Sirius"))
    #expect(!combined.contains("macOS 26/Sirius"))
    #expect(!combined.contains("Sirius DiffTree"))
    #expect(!combined.contains("Sirius host"))
    #expect(!combined.contains("Sirius-style"))
    #expect(!combined.contains("Sirius transcript"))
    #expect(!combined.contains("sirius-selection-overlay"))
    #expect(!combined.contains("DiffTree"))
    #expect(!combined.contains("right-panel"))
}

@Test
func preparedNativeLinesPreserveInlineAttributesAcrossLineSlices() throws {
    var stream = MarkdownStream()
    stream.append("alpha [linked text](https://example.com) and `code value` after")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 112)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)
    let renderedText = lines.map { String($0.characters) }.joined()

    #expect(lines.count > 1)
    #expect(renderedText == inlineLayout.prepared.naturalText)
    #expect(lines.contains { line in line.runs.contains { $0.link != nil } })
    #expect(lines.contains { line in line.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true } })
}

@Test
func preparedNativeLinesPreserveMathRenderedTextAndImagePlaceholderText() throws {
    var stream = MarkdownStream()
    stream.append("Math $x^2$ and image ![diagram](diagram.png) after")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines,
        mathRenderer: InlineFixtureMathRenderer()
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 112)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)
    let renderedText = lines.map { String($0.characters) }.joined()

    #expect(lines.count > 1)
    #expect(renderedText == inlineLayout.prepared.naturalText)
    #expect(renderedText.contains("math[x^2]"))
    #expect(renderedText.contains("diagram"))
    #expect(inlineLayout.images.first?.source == "diagram.png")
}

@Test
func preparedInlineImageUsesResolverPlaceholderWhenAltTextIsEmpty() throws {
    var stream = MarkdownStream()
    stream.append("Image ![](diagram.png) after")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(inlineRenderingMode: .preparedNativeLines)

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)

    #expect(inlineLayout.images.first?.source == "diagram.png")
    #expect(inlineLayout.prepared.naturalText.contains("Image loading is disabled by default."))
}

@Test
func preparedInlineImagesWithoutSourceRangesPreserveRunOrder() throws {
    let sourceRange = MarkdownSourceRange(byteRange: 0..<38, lineRange: 1..<2)
    let block = MarkdownBlock(
        id: MarkdownBlockID("manual-images"),
        kind: .paragraph,
        sourceRange: sourceRange,
        text: "![first](same.png) ![second](same.png)",
        inlines: [
            MarkdownInlineRun(
                kind: .image,
                text: "first",
                destination: "same.png",
                imageSource: "same.png"
            ),
            MarkdownInlineRun(kind: .text, text: " "),
            MarkdownInlineRun(
                kind: .image,
                text: "second",
                destination: "same.png",
                imageSource: "same.png"
            )
        ],
        isSealed: true
    )

    let prepared = MarkdownRendererConfiguration().prepare(block: block)
    let inlineLayout = try #require(prepared.inlineLayout)

    #expect(inlineLayout.images.map(\.altText) == ["first", "second"])
    #expect(inlineLayout.prepared.runs.map(\.text).joined() == "first second")
    #expect(String(inlineLayout.attributed.characters) == "first second")
}

@Test
func deniedPreparedImagesDoNotInvokeResolver() throws {
    let block = try firstBlock("Remote ![diagram](https://example.com/diagram.png)")
    let deniedResolver = RecordingImageResolver()
    let deniedConfiguration = MarkdownRendererConfiguration(
        imagePolicy: IdentityImagePolicy(identity: "deny", decision: .deny(reason: "blocked")),
        imageResolver: deniedResolver
    )

    let denied = deniedConfiguration.prepare(block: block)
    let deniedImage = try #require(denied.inlineLayout?.images.first)

    #expect(deniedResolver.count == 0)
    #expect(deniedImage.preparedSource == .placeholder(reason: "blocked"))

    let allowedResolver = RecordingImageResolver()
    let allowedConfiguration = MarkdownRendererConfiguration(
        imagePolicy: IdentityImagePolicy(identity: "allow", decision: .allow),
        imageResolver: allowedResolver
    )

    _ = allowedConfiguration.prepare(block: block)

    #expect(allowedResolver.count == 1)
}

@Test
func preparedImagePolicyEvaluatesOncePerSourceBackedRun() throws {
    let block = try firstBlock("Remote ![](https://example.com/diagram.png)")
    let imagePolicy = NonIdentifyingImagePolicy(decision: .deny(reason: "blocked"))
    let resolver = NonIdentifyingImageResolver()
    let configuration = MarkdownRendererConfiguration(
        imagePolicy: imagePolicy,
        imageResolver: resolver
    )

    let prepared = configuration.prepare(block: block)

    #expect(plainString(prepared.inline) == "Remote [image: blocked]")
    #expect(prepared.inlineLayout?.images.first?.preparedSource == .placeholder(reason: "blocked"))
    #expect(resolver.count == 0)
    #expect(imagePolicy.count == 1)
}

@Test
func deniedPreparedImageCacheDoesNotRequireResolverIdentity() throws {
    let block = try firstBlock("Remote ![diagram](https://example.com/diagram.png)")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let resolver = NonIdentifyingImageResolver()
    let configuration = MarkdownRendererConfiguration(
        imagePolicy: IdentityImagePolicy(identity: "deny", decision: .deny(reason: "blocked")),
        imageResolver: resolver,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    let first = configuration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    let second = configuration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(first.inlineLayout?.images.first?.preparedSource == .placeholder(reason: "blocked"))
    #expect(second.inlineLayout?.images.first?.preparedSource == .placeholder(reason: "blocked"))
    #expect(resolver.count == 0)
    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
}

@Test
func imageOnlyInlineCacheDoesNotRequireLinkPolicyIdentity() throws {
    let block = try firstBlock("Remote ![diagram](https://example.com/diagram.png)")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let resolver = NonIdentifyingImageResolver()
    let configuration = MarkdownRendererConfiguration(
        linkPolicy: NonIdentifyingLinkPolicy(decision: .deny(reason: "links disabled")),
        imagePolicy: IdentityImagePolicy(identity: "deny-image", decision: .deny(reason: "blocked")),
        imageResolver: resolver,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    let first = configuration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    let second = configuration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(first.inlineLayout?.images.first?.preparedSource == .placeholder(reason: "blocked"))
    #expect(second.inlineLayout?.images.first?.preparedSource == .placeholder(reason: "blocked"))
    #expect(resolver.count == 0)
    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
}

@Test
func sourcelessImageInlineCacheDoesNotRequireImagePolicyIdentity() throws {
    let range = MarkdownSourceRange(byteRange: 0..<8, lineRange: 1..<2)
    let block = MarkdownBlock(
        id: MarkdownBlockID("sourceless-image"),
        kind: .paragraph,
        sourceRange: range,
        text: "diagram",
        inlines: [
            MarkdownInlineRun(
                kind: .image,
                text: "diagram",
                sourceRange: range,
                imageSource: nil
            )
        ],
        isSealed: true
    )
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let imagePolicy = NonIdentifyingImagePolicy(decision: .deny(reason: "blocked"))
    let configuration = MarkdownRendererConfiguration(
        imagePolicy: imagePolicy,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    let first = configuration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    let second = configuration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(plainString(first.inline) == "diagram")
    #expect(plainString(second.inline) == "diagram")
    #expect(first.inlineLayout?.images.isEmpty == true)
    #expect(second.inlineLayout?.images.isEmpty == true)
    #expect(imagePolicy.count == 0)
    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
}

@Test
func preparedNativeLinesPreserveHardBreakLineSlices() throws {
    var stream = MarkdownStream()
    stream.append("first  \nsecond  \nthird")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 320)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)

    #expect(lines.map { String($0.characters) } == ["first", "second", "third"])
    #expect(layout.lines.count == 3)
}

@Test
func preparedNativeLineRendererUsesSingleAttributedTextPayload() throws {
    var stream = MarkdownStream()
    stream.append("alpha beta gamma delta epsilon zeta eta theta")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 92)
    let renderedAttributed = InlineRunsView.renderingAttributedString(for: inlineLayout)
    let renderedLines = InlineRunsView.nativeLineAttributedString(
        for: inlineLayout,
        attributed: renderedAttributed,
        layout: layout
    )
    let renderedText = String(renderedLines.characters)

    #expect(layout.lines.count > 1)
    #expect(renderedText.contains("\n"))
    #expect(renderedText.replacingOccurrences(of: "\n", with: "") == inlineLayout.prepared.naturalText)
}

@Test
func preparedNativeLinesPreserveUTF8BoundariesAcrossLineSlices() throws {
    var stream = MarkdownStream()
    stream.append("English 日本語 العربية emoji 😀 code `値` tail")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines
    )

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 96)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: layout)
    let renderedText = lines.map { String($0.characters) }.joined()

    #expect(lines.count > 1)
    #expect(renderedText == inlineLayout.prepared.naturalText)
    #expect(renderedText.contains("日本語"))
    #expect(renderedText.contains("العربية"))
    #expect(renderedText.contains("😀"))
    #expect(renderedText.contains("値"))
    #expect(renderedText.contains("�") == false)
}

@Test
func preparedInlineRenderingUsesCachedBackendLayout() throws {
    var stream = MarkdownStream()
    stream.append("alpha beta gamma delta epsilon zeta eta theta")
    stream.finish()
    let snapshot = stream.snapshot()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let beforeLayout = recorder.snapshot()

    _ = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 80)
    let afterFirstLayout = recorder.snapshot()
    _ = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 80)
    let afterCachedLayout = recorder.snapshot()
    _ = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 140)
    let afterSecondWidth = recorder.snapshot()

    #expect(afterFirstLayout.layoutCount == beforeLayout.layoutCount + 1)
    #expect(afterFirstLayout.widthRelayoutCount == beforeLayout.widthRelayoutCount + 1)
    #expect(afterCachedLayout.layoutCount == afterFirstLayout.layoutCount)
    #expect(afterCachedLayout.widthRelayoutCount == afterFirstLayout.widthRelayoutCount)
    #expect(afterCachedLayout.cacheHitCount == afterFirstLayout.cacheHitCount + 1)
    #expect(afterSecondWidth.layoutCount == afterFirstLayout.layoutCount + 1)
    #expect(afterSecondWidth.widthRelayoutCount == afterFirstLayout.widthRelayoutCount + 1)
}

@Test
func rendererPreparationDoesNotEagerlyPopulatePerCharacterUnits() throws {
    var stream = MarkdownStream()
    stream.append("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration()

    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    let beforeLayoutUnits = inlineLayout.measured.segments.flatMap(\.units)
    let wrapped = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 32)
    let afterLayoutUnits = inlineLayout.measured.segments.flatMap(\.units)

    #expect(beforeLayoutUnits.isEmpty)
    #expect(afterLayoutUnits.isEmpty)
    #expect(wrapped.lines.isEmpty == false)
}

@Test
func rendererPreparationCacheSeparatesIncompatibleFontProfiles() throws {
    let block = try firstBlock("alpha beta gamma delta")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let helveticaTheme = MarkdownTheme(
        paragraphFontProfiles: MarkdownInlineFontProfiles(uniform: .named("Helvetica"))
    )
    let menloTheme = MarkdownTheme(
        paragraphFontProfiles: MarkdownInlineFontProfiles(uniform: .named("Menlo"))
    )
    let helveticaConfiguration = MarkdownRendererConfiguration(
        theme: helveticaTheme,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let menloConfiguration = MarkdownRendererConfiguration(
        theme: menloTheme,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    _ = helveticaConfiguration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    _ = helveticaConfiguration.prepare(block: block)
    let afterSecond = recorder.snapshot()
    _ = menloConfiguration.prepare(block: block)
    let afterProfileChange = recorder.snapshot()

    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
    #expect(afterProfileChange.prepareCount == afterFirst.prepareCount + 1)
}

@Test
func preparedInlineLayoutIdentityChangesWhenSemanticMeasurementChanges() {
    let range = MarkdownSourceRange(byteRange: 0..<11, lineRange: 1..<2)
    let plain = preparedInlineIdentityFixture(
        runs: [
            MarkdownInlineRun(kind: .text, text: "alpha beta", sourceRange: range)
        ],
        sourceRange: range
    )
    let code = preparedInlineIdentityFixture(
        runs: [
            MarkdownInlineRun(kind: .code, text: "alpha beta", sourceRange: range)
        ],
        sourceRange: range
    )

    let plainIdentity = PreparedInlineLayoutIdentity(
        measured: plain.measured,
        lineHeight: plain.lineHeight,
        fontProfilesCacheKey: plain.fontProfiles.cacheKey
    )
    let codeIdentity = PreparedInlineLayoutIdentity(
        measured: code.measured,
        lineHeight: code.lineHeight,
        fontProfilesCacheKey: code.fontProfiles.cacheKey
    )

    #expect(plain.prepared.sourceRange == code.prepared.sourceRange)
    #expect(plain.prepared.naturalText == code.prepared.naturalText)
    #expect(plain.fontSize == code.fontSize)
    #expect(plain.lineHeight == code.lineHeight)
    #expect(plainIdentity != codeIdentity)
}

@Test
func headingStylesResolveEveryHeadingLevelThroughTheme() throws {
    let styles = testHeadingStyles()
    let configuration = MarkdownRendererConfiguration(theme: MarkdownTheme(headings: styles))

    for level in 1...6 {
        let block = try firstBlock("\(String(repeating: "#", count: level)) Heading \(level)")
        let inlineLayout = try #require(configuration.prepare(block: block).inlineLayout)
        let expected = styles.style(for: level)

        #expect(inlineLayout.fontSize == expected.fontSize)
        #expect(inlineLayout.lineHeight == expected.lineHeight)
        #expect(inlineLayout.fontProfiles == expected.fontProfiles)
        #expect(inlineLayout.measured.fontSize == expected.fontSize)
        #expect(InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 320).height == expected.lineHeight)
    }
}

@Test
func customHeadingStylesReplaceHardcodedDefaultMetrics() throws {
    let styles = testHeadingStyles()
    let configuration = MarkdownRendererConfiguration(theme: MarkdownTheme(headings: styles))
    let hardcodedDefaults = [
        1: 34.0,
        2: 28.0,
        4: 18.0,
        5: 16.0,
        6: 14.0
    ]

    for level in [1, 2, 4, 5, 6] {
        let block = try firstBlock("\(String(repeating: "#", count: level)) Custom")
        let inlineLayout = try #require(configuration.prepare(block: block).inlineLayout)

        #expect(inlineLayout.fontSize == styles.style(for: level).fontSize)
        #expect(inlineLayout.lineHeight == styles.style(for: level).lineHeight)
        #expect(inlineLayout.fontSize != hardcodedDefaults[level])
    }
}

@Test
func headingStyleCacheSeparatesIncompatibleLevelMetricsAndProfiles() {
    let range = MarkdownSourceRange(byteRange: 0..<7, lineRange: 1..<2)
    let runs = [MarkdownInlineRun(kind: .text, text: "Title", sourceRange: range)]
    let h1 = MarkdownBlock(
        id: MarkdownBlockID("same-source-h1"),
        kind: .heading,
        sourceRange: range,
        text: "Title",
        inlines: runs,
        headingLevel: 1,
        isSealed: true
    )
    let h2 = MarkdownBlock(
        id: MarkdownBlockID("same-source-h2"),
        kind: .heading,
        sourceRange: range,
        text: "Title",
        inlines: runs,
        headingLevel: 2,
        isSealed: true
    )
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        theme: MarkdownTheme(headings: testHeadingStyles()),
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    _ = configuration.prepare(block: h1)
    let afterH1 = recorder.snapshot()
    _ = configuration.prepare(block: h1)
    let afterH1Repeat = recorder.snapshot()
    _ = configuration.prepare(block: h2)
    let afterH2 = recorder.snapshot()

    #expect(afterH1.prepareCount == 1)
    #expect(afterH1Repeat.prepareCount == afterH1.prepareCount)
    #expect(afterH1Repeat.cacheHitCount == afterH1.cacheHitCount + 1)
    #expect(afterH2.prepareCount == afterH1.prepareCount + 1)
}

@Test
func uniformHeadingStylesSupportCompactConsumerThemes() throws {
    let compactHeading = MarkdownTextStyle(
        font: .system(size: 12, weight: .semibold),
        fontSize: 12,
        lineHeight: 16,
        fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .semibold))
    )
    let configuration = MarkdownRendererConfiguration(
        theme: MarkdownTheme(headings: .uniform(compactHeading))
    )

    for level in 1...6 {
        let block = try firstBlock("\(String(repeating: "#", count: level)) Compact")
        let inlineLayout = try #require(configuration.prepare(block: block).inlineLayout)

        #expect(inlineLayout.fontSize == compactHeading.fontSize)
        #expect(inlineLayout.lineHeight == compactHeading.lineHeight)
        #expect(inlineLayout.fontProfiles == compactHeading.fontProfiles)
    }
}

@Test
func headingStyleFallbacksUseH3ForMissingOrInvalidLevels() {
    let styles = testHeadingStyles()
    var mutable = styles
    let replacement = MarkdownTextStyle(
        font: .system(size: 31, weight: .bold),
        fontSize: 31,
        lineHeight: 39,
        fontProfiles: MarkdownInlineFontProfiles(uniform: .named("Courier"))
    )

    mutable[0] = replacement

    #expect(styles.style(for: nil).fontSize == styles.h3.fontSize)
    #expect(styles.style(for: 0).fontSize == styles.h3.fontSize)
    #expect(styles.style(for: 7).fontSize == styles.h3.fontSize)
    #expect(mutable.h3.fontSize == replacement.fontSize)
    #expect(mutable.style(for: 99).fontProfiles == replacement.fontProfiles)
}

@Test
func codeLanguageNormalizesFenceInfoStringsAndAliases() {
    let cases: [(String?, String?, MarkdownCodeLanguage.Classification)] = [
        ("swift", "swift", .supported),
        ("language-swift", "swift", .supported),
        ("py", "python", .supported),
        ("python", "python", .supported),
        ("js", "javascript", .supported),
        ("javascript", "javascript", .supported),
        ("ts", "typescript", .supported),
        ("typescript", "typescript", .supported),
        ("sh", "bash", .supported),
        ("bash", "bash", .supported),
        ("zsh", "bash", .supported),
        ("yaml", "yaml", .supported),
        ("yml", "yaml", .supported),
        ("md", "markdown", .supported),
        ("markdown", "markdown", .supported),
        ("objc", "objectivec", .supported),
        ("objective-c", "objectivec", .supported),
        ("cpp", "cpp", .supported),
        ("c++", "cpp", .supported),
        ("text", nil, .plaintext),
        ("plaintext", nil, .plaintext),
        ("nohighlight", nil, .plaintext),
        ("mermaid", nil, .unsupported),
        (nil, nil, .unspecified)
    ]

    for testCase in cases {
        let language = MarkdownCodeLanguage(infoString: testCase.0)

        #expect(language.backendName == testCase.1)
        #expect(language.classification == testCase.2)
    }
}

@Test
func codeLanguageProvidesGenericDisplayNames() {
    let cases: [(String?, String?)] = [
        ("language-swift", "Swift"),
        ("py", "Python"),
        ("js", "JavaScript"),
        ("ts", "TypeScript"),
        ("html", "HTML"),
        ("objective-c", "Objective-C"),
        ("c++", "C++"),
        ("plaintext", "Plain text"),
        ("mermaid", "Mermaid"),
        (nil, nil)
    ]

    for testCase in cases {
        #expect(MarkdownCodeLanguage(infoString: testCase.0).displayName == testCase.1)
    }
}

@Test
func codeLanguageRecognizesMermaidAsSpecialRendererLanguage() {
    let mermaid = MarkdownCodeLanguage(infoString: "mermaid")
    let swift = MarkdownCodeLanguage(infoString: "swift")

    #expect(mermaid.isMermaid)
    #expect(swift.isMermaid == false)
}

@Test
func mermaidSVGGeometryParserHandlesDimensionsViewBoxAndInvalidValues() throws {
    let sized = try #require(MermaidSVGGeometryParser.geometry(
        in: #"<svg viewBox="0 0 271.18 116.9" width="271.18" height="116.9"></svg>"#
    ))
    #expect(sized.width == 271.18)
    #expect(sized.height == 116.9)
    #expect(sized.viewBox?.width == 271.18)
    #expect(sized.viewBox?.height == 116.9)

    let pxSized = try #require(MermaidSVGGeometryParser.geometry(
        in: #"<svg width="300px" height="160px"></svg>"#
    ))
    #expect(pxSized.width == 300)
    #expect(pxSized.height == 160)

    let viewBoxOnly = try #require(MermaidSVGGeometryParser.geometry(
        in: #"<svg viewBox="-10 -20 480 240"></svg>"#
    ))
    #expect(viewBoxOnly.width == 480)
    #expect(viewBoxOnly.height == 240)
    #expect(viewBoxOnly.viewBox?.minX == -10)
    #expect(viewBoxOnly.viewBox?.minY == -20)

    let invalidViewBoxWithExplicitSize = try #require(MermaidSVGGeometryParser.geometry(
        in: #"<svg viewBox="NaN 0 480 240" width="480" height="240"></svg>"#
    ))
    #expect(invalidViewBoxWithExplicitSize.width == 480)
    #expect(invalidViewBoxWithExplicitSize.height == 240)
    #expect(invalidViewBoxWithExplicitSize.viewBox == nil)

    let invalidSVGs = [
        #"<svg width="0" height="160"></svg>"#,
        #"<svg width="-1" height="160"></svg>"#,
        #"<svg width="NaN" height="160"></svg>"#,
        #"<svg width="Infinity" height="160"></svg>"#,
        #"<svg width="100%" height="160"></svg>"#,
        #"<svg viewBox="NaN 0 120 80"></svg>"#,
        #"<svg viewBox="Infinity 0 120 80"></svg>"#,
        #"<svg viewBox="0 -Infinity 120 80"></svg>"#,
        #"<svg viewBox="0 0 0 120"></svg>"#,
        #"<svg viewBox="0 0 120 -4"></svg>"#,
        #"<not-svg width="120" height="80"></not-svg>"#
    ]

    for invalid in invalidSVGs {
        #expect(MermaidSVGGeometryParser.geometry(in: invalid) == nil)
    }
}

@Test
func mermaidAffordanceRenderBoundsClampInvalidPublicThemeValues() {
    var invalid = MarkdownMermaidDiagramAffordances()
    invalid.minimumScale = .nan
    invalid.maximumScale = .infinity
    invalid.scaleStep = -1
    invalid.minimumViewportHeight = .nan
    invalid.maximumViewportHeight = -.infinity

    #expect(invalid.renderScaleBounds.lowerBound == 0.5)
    #expect(invalid.renderScaleBounds.upperBound == 3.0)
    #expect(invalid.renderScaleStep == 0.2)
    #expect(invalid.renderViewportHeightBounds.lowerBound == 120)
    #expect(invalid.renderViewportHeightBounds.upperBound == 420)

    var inverted = MarkdownMermaidDiagramAffordances()
    inverted.minimumScale = 2
    inverted.maximumScale = 1
    inverted.minimumViewportHeight = 500
    inverted.maximumViewportHeight = 100

    #expect(inverted.renderScaleBounds.lowerBound == 1)
    #expect(inverted.renderScaleBounds.upperBound == 2)
    #expect(inverted.renderViewportHeightBounds.lowerBound == 100)
    #expect(inverted.renderViewportHeightBounds.upperBound == 500)
}

@Test
func mermaidViewportGeometryRejectsInvalidCustomRendererDimensions() {
    let valid = MarkdownMermaidDiagramGeometry(width: 120, height: 80)
    let invalid = [
        MarkdownMermaidDiagramGeometry(width: 0, height: 80),
        MarkdownMermaidDiagramGeometry(width: -1, height: 80),
        MarkdownMermaidDiagramGeometry(width: .infinity, height: 80),
        MarkdownMermaidDiagramGeometry(width: .nan, height: 80),
        MarkdownMermaidDiagramGeometry(width: 120, height: 0),
        MarkdownMermaidDiagramGeometry(width: 120, height: -.infinity)
    ]

    #expect(valid.isRenderableViewportGeometry)
    for geometry in invalid {
        #expect(!geometry.isRenderableViewportGeometry)
    }
}

@Test
func mermaidToolbarRequiresRenderableViewportGeometry() throws {
    let source = try String(
        contentsOf: packageRootURL().appending(path: "Sources/SiriusMarkdownSwiftUI/Blocks/MarkdownMermaidDiagramView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("mermaid.geometry?.isRenderableViewportGeometry == true"))
    #expect(!source.contains("platformImage != nil &&\n            mermaid.geometry != nil"))
}

@Test
func codeHighlightCacheKeysIncludeLanguagePaletteAndHighlighterIdentity() throws {
    let swiftBlock = try firstBlock("```swift\nlet x = 1\n```")
    let pythonBlock = try firstBlock("```python\nlet x = 1\n```")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let highlighter = IdentityCodeHighlighter(identity: "one")
    let baseConfiguration = MarkdownRendererConfiguration(
        codeHighlighter: highlighter,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    _ = baseConfiguration.prepare(block: swiftBlock)
    let afterFirst = recorder.snapshot()
    _ = baseConfiguration.prepare(block: swiftBlock)
    let afterCached = recorder.snapshot()
    _ = baseConfiguration.prepare(block: pythonBlock)
    let afterLanguageChange = recorder.snapshot()

    let changedPaletteTheme = MarkdownTheme(
        syntaxHighlightingPalette: MarkdownSyntaxHighlightingPalette(keyword: .red)
    )
    let changedPaletteConfiguration = MarkdownRendererConfiguration(
        theme: changedPaletteTheme,
        codeHighlighter: highlighter,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    _ = changedPaletteConfiguration.prepare(block: swiftBlock)
    let afterPaletteChange = recorder.snapshot()

    let changedIdentityHighlighter = IdentityCodeHighlighter(identity: "two")
    let changedIdentityConfiguration = MarkdownRendererConfiguration(
        codeHighlighter: changedIdentityHighlighter,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    _ = changedIdentityConfiguration.prepare(block: swiftBlock)
    let afterIdentityChange = recorder.snapshot()

    #expect(afterFirst.codeHighlightCount == 1)
    #expect(afterCached.codeHighlightCount == afterFirst.codeHighlightCount)
    #expect(afterCached.cacheHitCount >= afterFirst.cacheHitCount + 1)
    #expect(afterLanguageChange.codeHighlightCount == afterFirst.codeHighlightCount + 1)
    #expect(afterPaletteChange.codeHighlightCount == afterLanguageChange.codeHighlightCount + 1)
    #expect(afterIdentityChange.codeHighlightCount == afterPaletteChange.codeHighlightCount + 1)
    #expect(highlighter.count == 3)
    #expect(changedIdentityHighlighter.count == 1)
}

@Test
func mermaidPreparationCacheKeysIncludeRendererIdentityAndSupportOptOut() throws {
    let mermaidBlock = try firstBlock("```mermaid\ngraph LR\nA[Start] --> B[Done]\n```")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let renderer = IdentityMermaidRenderer(identity: "one", ascii: "diagram-one")
    let baseConfiguration = MarkdownRendererConfiguration(
        mermaidRenderer: renderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    let firstPrepared = baseConfiguration.prepare(block: mermaidBlock)
    let afterFirst = recorder.snapshot()
    let secondPrepared = baseConfiguration.prepare(block: mermaidBlock)
    let afterCached = recorder.snapshot()

    let changedIdentityRenderer = IdentityMermaidRenderer(identity: "two", ascii: "diagram-two")
    let changedIdentityConfiguration = MarkdownRendererConfiguration(
        mermaidRenderer: changedIdentityRenderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let changedPrepared = changedIdentityConfiguration.prepare(block: mermaidBlock)
    let afterIdentityChange = recorder.snapshot()

    let disabledConfiguration = MarkdownRendererConfiguration(
        mermaidRenderer: nil,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let disabledPrepared = disabledConfiguration.prepare(block: mermaidBlock)

    #expect(firstPrepared.mermaid?.ascii == "diagram-one")
    #expect(secondPrepared.mermaid?.ascii == "diagram-one")
    #expect(changedPrepared.mermaid?.ascii == "diagram-two")
    #expect(afterFirst.mermaidRenderCount == 1)
    #expect(afterCached.mermaidRenderCount == afterFirst.mermaidRenderCount)
    #expect(afterCached.cacheHitCount == afterFirst.cacheHitCount + 1)
    #expect(afterIdentityChange.mermaidRenderCount == afterCached.mermaidRenderCount + 1)
    #expect(renderer.count == 1)
    #expect(changedIdentityRenderer.count == 1)
    #expect(disabledPrepared.mermaid == nil)
    #expect(disabledPrepared.code != nil)
}

@Test
func mermaidPreparationCacheKeysIncludeThemeIdentity() throws {
    let mermaidBlock = try firstBlock("```mermaid\ngraph LR\nA[Start] --> B[Done]\n```")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let renderer = ThemeEchoMermaidRenderer()
    let firstTheme = MarkdownTheme()
    var secondTheme = firstTheme
    secondTheme.syntaxHighlightingPalette.section = .red

    let firstConfiguration = MarkdownRendererConfiguration(
        theme: firstTheme,
        mermaidRenderer: renderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let firstPrepared = firstConfiguration.prepare(block: mermaidBlock)
    let afterFirst = recorder.snapshot()

    let cachedFirstPrepared = firstConfiguration.prepare(block: mermaidBlock)
    let afterCachedFirst = recorder.snapshot()

    let secondConfiguration = MarkdownRendererConfiguration(
        theme: secondTheme,
        mermaidRenderer: renderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let secondPrepared = secondConfiguration.prepare(block: mermaidBlock)
    let afterSecondTheme = recorder.snapshot()

    #expect(firstTheme.renderCacheIdentity != secondTheme.renderCacheIdentity)
    #expect(firstPrepared.mermaid?.ascii == firstTheme.renderCacheIdentity)
    #expect(cachedFirstPrepared.mermaid?.ascii == firstPrepared.mermaid?.ascii)
    #expect(secondPrepared.mermaid?.ascii == secondTheme.renderCacheIdentity)
    #expect(afterFirst.mermaidRenderCount == 1)
    #expect(afterCachedFirst.mermaidRenderCount == afterFirst.mermaidRenderCount)
    #expect(afterCachedFirst.cacheHitCount == afterFirst.cacheHitCount + 1)
    #expect(afterSecondTheme.mermaidRenderCount == afterCachedFirst.mermaidRenderCount + 1)
    #expect(renderer.count == 2)
}

@Test
func themeRenderCacheIdentityLengthPrefixesPublicFontProfileFields() {
    let trickyName = "Body|codeProfiles=named:other"
    var theme = MarkdownTheme()
    theme.paragraphFontProfiles = MarkdownInlineFontProfiles(uniform: .named(trickyName, weight: .semibold))

    let profileKey = theme.paragraphFontProfiles.cacheKey
    let identity = theme.renderCacheIdentity

    #expect(identity.contains("paragraphProfiles#\(profileKey.utf8.count):\(profileKey)"))
    #expect(identity.contains("syntax#\(theme.syntaxHighlightingPalette.cacheIdentity.utf8.count):\(theme.syntaxHighlightingPalette.cacheIdentity)"))
}

@Test
func inlinePreparationCacheKeysIncludePolicyIdentity() throws {
    let linkBlock = try firstBlock("[safe](https://example.com)")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()

    let allowConfiguration = MarkdownRendererConfiguration(
        linkPolicy: IdentityLinkPolicy(identity: "allow", decision: .allow),
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let allowed = allowConfiguration.prepare(block: linkBlock)
    let afterAllow = recorder.snapshot()

    let denyConfiguration = MarkdownRendererConfiguration(
        linkPolicy: IdentityLinkPolicy(identity: "deny", decision: .deny(reason: "blocked")),
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let denied = denyConfiguration.prepare(block: linkBlock)
    let afterDeny = recorder.snapshot()

    #expect(attributedStringContainsLink(allowed.inline) == true)
    #expect(attributedStringContainsLink(denied.inline) == false)
    #expect(afterDeny.cacheMissCount == afterAllow.cacheMissCount + 1)
}

@Test
func inlinePreparationCacheKeysIncludeRunSourceRanges() throws {
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let blockRange = MarkdownSourceRange(byteRange: 0..<16, lineRange: 1..<2)
    let firstRunRange = MarkdownSourceRange(byteRange: 2..<6, lineRange: 1..<2)
    let secondRunRange = MarkdownSourceRange(byteRange: 8..<12, lineRange: 1..<2)
    let firstBlock = MarkdownBlock(
        id: MarkdownBlockID("same-block"),
        kind: .paragraph,
        sourceRange: blockRange,
        text: "same rendered",
        inlines: [
            MarkdownInlineRun(kind: .strong, text: "same", sourceRange: firstRunRange)
        ],
        contentHash: 1,
        isSealed: false
    )
    let secondBlock = MarkdownBlock(
        id: MarkdownBlockID("same-block"),
        kind: .paragraph,
        sourceRange: blockRange,
        text: "same rendered",
        inlines: [
            MarkdownInlineRun(kind: .strong, text: "same", sourceRange: secondRunRange)
        ],
        contentHash: 2,
        isSealed: false
    )

    let first = try #require(configuration.prepare(block: firstBlock).inlineLayout)
    let afterFirst = recorder.snapshot()
    let second = try #require(configuration.prepare(block: secondBlock).inlineLayout)
    let afterSecond = recorder.snapshot()

    #expect(first.prepared.runs.first?.sourceRange == firstRunRange)
    #expect(second.prepared.runs.first?.sourceRange == secondRunRange)
    #expect(afterSecond.cacheMissCount == afterFirst.cacheMissCount + 1)
}

@Test
func inlinePreparationCacheKeysSeparateRunFieldBoundaries() throws {
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        linkPolicy: IdentityLinkPolicy(identity: "allow", decision: .allow),
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let blockRange = MarkdownSourceRange(byteRange: 0..<3, lineRange: 1..<2)
    let firstBlock = MarkdownBlock(
        id: MarkdownBlockID("same-block"),
        kind: .paragraph,
        sourceRange: blockRange,
        text: "a",
        inlines: [
            MarkdownInlineRun(kind: .link, text: "a", destination: "bc")
        ],
        contentHash: 1,
        isSealed: false
    )
    let secondBlock = MarkdownBlock(
        id: MarkdownBlockID("same-block"),
        kind: .paragraph,
        sourceRange: blockRange,
        text: "ab",
        inlines: [
            MarkdownInlineRun(kind: .link, text: "ab", destination: "c")
        ],
        contentHash: 2,
        isSealed: false
    )

    let first = try #require(configuration.prepare(block: firstBlock).inlineLayout)
    let afterFirst = recorder.snapshot()
    let second = try #require(configuration.prepare(block: secondBlock).inlineLayout)
    let afterSecond = recorder.snapshot()

    #expect(first.prepared.runs.first?.text == "a")
    #expect(first.prepared.runs.first?.destination == "bc")
    #expect(second.prepared.runs.first?.text == "ab")
    #expect(second.prepared.runs.first?.destination == "c")
    #expect(plainString(configuration.prepare(block: secondBlock).inline) == "ab")
    #expect(afterSecond.cacheMissCount == afterFirst.cacheMissCount + 1)
}

@Test
func preparedSnapshotReuseIgnoresSealStateOnlyChanges() throws {
    var stream = MarkdownStream()
    stream.append("Streaming **text**")
    let activeSnapshot = stream.snapshot()
    let activeBlock = try #require(activeSnapshot.blocks.first)
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    let activePrepared = configuration.prepare(snapshot: activeSnapshot)
    let afterActivePrepare = recorder.snapshot()

    stream.append("\n\n")
    let sealedSnapshot = stream.snapshot()
    let sealedBlock = try #require(sealedSnapshot.blocks.first)
    let sealedPrepared = configuration.prepare(snapshot: sealedSnapshot, reusing: activePrepared)
    let afterSealedPrepare = recorder.snapshot()

    #expect(activeBlock.id == sealedBlock.id)
    #expect(activeBlock.sourceRange == sealedBlock.sourceRange)
    #expect(activeBlock.isSealed == false)
    #expect(sealedBlock.isSealed)
    #expect(sealedPrepared.preparedContentByBlockID[sealedBlock.id]?.inlineLayout?.prepared.naturalText == "Streaming text")
    #expect(afterSealedPrepare.renderPreparationCount == afterActivePrepare.renderPreparationCount)
    #expect(afterSealedPrepare.prepareCount == afterActivePrepare.prepareCount)
}

@Test
func preparedInlineLinksUsePolicyNormalizedDestinations() throws {
    var stream = MarkdownStream()
    stream.append("[https](https&#58//example.com/path)\n\n[relative](docs&#47safe)\n")
    stream.finish()

    let prepared = MarkdownRendererConfiguration.document.prepare(snapshot: stream.snapshot())
    let links = prepared.preparedContentByBlockID.values.flatMap { content in
        content.inlineLayout?.attributed.runs.compactMap(\.link) ?? []
    }

    #expect(links.contains(URL(string: "https://example.com/path")!))
    #expect(links.contains(URL(string: "docs/safe")!))
    #expect(links.count == 2)
}

@Test
func mathPreparationCacheKeysIncludeRendererIdentity() throws {
    let inlineMathBlock = try firstBlock("Before $x^2$ after")
    let blockMathBlock = try firstBlock("$$\nx^2\n$$")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let rendererOne = IdentityMathRenderer(identity: "one", prefix: "one")
    let rendererTwo = IdentityMathRenderer(identity: "two", prefix: "two")

    let configOne = MarkdownRendererConfiguration(
        mathRenderer: rendererOne,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let inlineOne = configOne.prepare(block: inlineMathBlock)
    let blockOne = configOne.prepare(block: blockMathBlock)
    let afterOne = recorder.snapshot()

    let configTwo = MarkdownRendererConfiguration(
        mathRenderer: rendererTwo,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let inlineTwo = configTwo.prepare(block: inlineMathBlock)
    let blockTwo = configTwo.prepare(block: blockMathBlock)
    let afterTwo = recorder.snapshot()

    #expect(plainString(inlineOne.inline).contains("one:x^2"))
    #expect(plainString(inlineTwo.inline).contains("two:x^2"))
    #expect(plainString(blockOne.math).contains("one:x^2"))
    #expect(plainString(blockTwo.math).contains("two:x^2"))
    #expect(afterTwo.mathRenderCount == afterOne.mathRenderCount + 2)
    #expect(rendererOne.count == 2)
    #expect(rendererTwo.count == 2)
}

@Test
func mathPreparationCacheNamespacesSeparatePolicyAndRendererFields() throws {
    let block = try firstBlock("$$\nx^2\n$$")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let firstRenderer = IdentityMathRenderer(identity: "m", prefix: "one")
    let secondRenderer = IdentityMathRenderer(identity: "r:renderer=m", prefix: "two")

    let firstConfiguration = MarkdownRendererConfiguration(
        mathPolicy: IdentityMathPolicy(identity: "p:renderer=r", decision: .allow),
        mathRenderer: firstRenderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let first = firstConfiguration.prepare(block: block)
    let afterFirst = recorder.snapshot()

    let secondConfiguration = MarkdownRendererConfiguration(
        mathPolicy: IdentityMathPolicy(identity: "p", decision: .allow),
        mathRenderer: secondRenderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let second = secondConfiguration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(plainString(first.math).contains("one:x^2"))
    #expect(plainString(second.math).contains("two:x^2"))
    #expect(afterSecond.mathRenderCount == afterFirst.mathRenderCount + 1)
    #expect(secondRenderer.count == 1)
}

@Test
func deniedInlineMathCacheDoesNotRequireRendererIdentity() throws {
    let block = try firstBlock("Before $x^2$ after")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let renderer = NonIdentifyingMathRenderer()
    let configuration = MarkdownRendererConfiguration(
        mathPolicy: IdentityMathPolicy(identity: "deny", decision: .deny(reason: "math denied")),
        mathRenderer: renderer,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )

    let first = configuration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    let second = configuration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(plainString(first.inline).contains("$x^2$") || plainString(first.inline).contains("x^2"))
    #expect(plainString(second.inline).contains("$x^2$") || plainString(second.inline).contains("x^2"))
    #expect(renderer.count == 0)
    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
}

@Test
func imageBackedInlineMathPreparationDoesNotCallRenderedFallback() throws {
    let block = try firstBlock("[value $x^2$](https://example.com/math)")
    let renderer = CountingImageMathRenderer()
    let configuration = MarkdownRendererConfiguration(mathRenderer: renderer)

    let inline = try #require(configuration.prepare(block: block).inlineLayout)
    let mathPieces = try #require(inline.mathTextPieces)
    let linkedMathRun = inline.prepared.runs.first { run in
        run.kind == .math || run.presentation.contains(.math)
    }

    #expect(mathPieces.contains { piece in
        if case .math = piece { return true }
        return false
    })
    #expect(linkedMathRun?.destination == "https://example.com/math")
    #expect(renderer.preparedCount == 1)
    #expect(renderer.renderedCount == 0)
}

@Test
func bareTexInlineMathPreparationUsesConfiguredImageRenderer() throws {
    let block = try firstBlock("Timing uses Z \\approx 0 and volatility uses \\sqrt{t}.")
    let renderer = CountingImageMathRenderer()
    let configuration = MarkdownRendererConfiguration(mathRenderer: renderer)

    let inline = try #require(configuration.prepare(block: block).inlineLayout)
    let mathPieces = try #require(inline.mathTextPieces)
    let mathImageCount = mathPieces.filter { piece in
        if case .math = piece { return true }
        return false
    }.count

    #expect(inline.prepared.runs.filter { $0.presentation.contains(.math) }.map(\.text) == ["Z \\approx 0", "\\sqrt{t}"])
    #expect(mathImageCount == 2)
    #expect(renderer.preparedCount == 2)
    #expect(renderer.renderedCount == 0)
}

@Test
@MainActor
func imageBackedInlineMathTextUsesConfiguredLinkAction() {
    var linkedText = AttributedString("x^2")
    linkedText.link = URL(string: "https://example.com/math")!
    let recorder = LinkActionRecorder()
    let view = InlineMathTextView(
        pieces: [.text(linkedText)],
        font: .body,
        color: .primary,
        fontSize: 14,
        linkAction: MarkdownLinkAction { destination in
            recorder.record(destination)
        }
    )

    view.openURLAction(URL(string: "https://example.com/math")!)

    #expect(recorder.destinations == ["https://example.com/math"])
}

@Test
func inlineMathNestedInsideLinkUsesMathRendererAndKeepsLink() throws {
    let block = try firstBlock("[value $x^2$](https://example.com/math)")
    let renderer = IdentityMathRenderer(identity: "linked-inline-math", prefix: "rendered")
    let configuration = MarkdownRendererConfiguration(mathRenderer: renderer)

    let inline = try #require(configuration.prepare(block: block).inlineLayout)
    let renderedText = String(inline.attributed.characters)
    let linkedMathRun = inline.prepared.runs.first { run in
        run.kind == .link && run.presentation.contains(.math)
    }

    #expect(renderedText.contains("rendered:x^2"))
    #expect(attributedStringContainsLink(inline.attributed))
    #expect(linkedMathRun?.destination == "https://example.com/math")
    #expect(linkedMathRun?.text.contains("rendered:x^2") == true)
    #expect(renderer.count == 1)
}

@Test
func customCodeHighlightersWithoutCacheIdentityDoNotReuseStaleOutput() throws {
    let block = try firstBlock("```swift\nlet x = 1\n```")
    let cache = MarkdownRenderPreparationCache()
    let firstHighlighter = PrefixCodeHighlighter(prefix: "one")
    let secondHighlighter = PrefixCodeHighlighter(prefix: "two")

    let first = MarkdownRendererConfiguration(
        codeHighlighter: firstHighlighter,
        preparationCache: cache
    ).prepare(block: block)
    let second = MarkdownRendererConfiguration(
        codeHighlighter: secondHighlighter,
        preparationCache: cache
    ).prepare(block: block)

    #expect(plainString(first.code).contains("one:let x = 1"))
    #expect(plainString(second.code).contains("two:let x = 1"))
    #expect(firstHighlighter.count == 1)
    #expect(secondHighlighter.count == 1)
}

@Test
func customMermaidRenderersWithoutCacheIdentityDoNotReuseStaleOutput() throws {
    let block = try firstBlock("```mermaid\ngraph LR\nA --> B\n```")
    let cache = MarkdownRenderPreparationCache()
    let firstRenderer = PrefixMermaidRenderer(ascii: "one")
    let secondRenderer = PrefixMermaidRenderer(ascii: "two")

    let first = MarkdownRendererConfiguration(
        mermaidRenderer: firstRenderer,
        preparationCache: cache
    ).prepare(block: block)
    let second = MarkdownRendererConfiguration(
        mermaidRenderer: secondRenderer,
        preparationCache: cache
    ).prepare(block: block)

    #expect(first.mermaid?.ascii == "one")
    #expect(second.mermaid?.ascii == "two")
    #expect(firstRenderer.count == 1)
    #expect(secondRenderer.count == 1)
}

@Test
func defaultPlainAndUnsupportedFencesDoNotRecordHighlightWork() throws {
    let supportedBlock = try firstBlock("```swift\nlet x = 1\n```")
    let plaintextBlock = try firstBlock("```plaintext\n2026-05-02 12:00:00 \"plain\"\n```")
    let unsupportedBlock = try firstBlock("```memory-diagnostics\nid=7a0f value=\"plain\"\n```")
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)

    _ = configuration.prepare(block: plaintextBlock)
    let afterPlaintext = recorder.snapshot()
    _ = configuration.prepare(block: unsupportedBlock)
    let afterUnsupported = recorder.snapshot()
    _ = configuration.prepare(block: supportedBlock)
    let afterSupported = recorder.snapshot()
    _ = configuration.prepare(block: supportedBlock)
    let afterCachedSupported = recorder.snapshot()

    #expect(afterPlaintext.codeHighlightCount == 0)
    #expect(afterUnsupported.codeHighlightCount == 0)
    #expect(afterSupported.codeHighlightCount == 1)
    #expect(afterCachedSupported.codeHighlightCount == afterSupported.codeHighlightCount)
}

@Test
func defaultCodeHighlighterPreservesEmbeddedNULAndTailText() {
    let code = "let first = \"a\0b\"\nlet second = 2"
    let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(code, infoString: "swift")
    let rendered = String(highlighted.characters)

    #expect(rendered.contains("a\0b"))
    #expect(rendered.contains("let second = 2"))
}

@Test
func selectionSourceRunMarksFormattedRunAsNonOneToOne() {
    let mapper = MarkdownDocumentSelectionSourceRun(
        visibleByteRange: 0..<4,
        sourceRange: MarkdownSourceRange(byteRange: 10..<18, lineRange: 1..<2)
    )

    #expect(mapper.mapsOneToOne == false)
}

@Test
func documentSelectionDragActivationIgnoresTapSizedMovement() {
    let activation = MarkdownDocumentSelectionDragActivation()
    let start = CGPoint(x: 20, y: 12)

    #expect(activation.hasActivated(start: start, current: CGPoint(x: 20, y: 12)) == false)
    #expect(activation.hasActivated(start: start, current: CGPoint(x: 23, y: 12)) == false)
    #expect(activation.hasActivated(start: start, current: CGPoint(x: 24, y: 12)))
    #expect(activation.hasActivated(start: start, current: CGPoint(x: 20, y: 16)))
}

@Test
func documentSelectionHitFragmentDoesNotFallBackToVerticallyDistantText() {
    let fragment = MarkdownDocumentSelectionFragment(
        id: "line:1",
        blockID: MarkdownBlockID("block-1"),
        sourceRange: MarkdownSourceRange(byteRange: 0..<11, lineRange: 1..<2),
        rect: CGRect(x: 24, y: 20, width: 140, height: 18)
    )

    #expect(MarkdownDocumentSelectionFragment.hitFragment(
        at: CGPoint(x: 80, y: 24),
        in: [fragment],
        hitSlop: 4
    ) == fragment)
    #expect(MarkdownDocumentSelectionFragment.hitFragment(
        at: CGPoint(x: 260, y: 28),
        in: [fragment],
        hitSlop: 4
    ) == fragment)
    #expect(MarkdownDocumentSelectionFragment.hitFragment(
        at: CGPoint(x: 80, y: 120),
        in: [fragment],
        hitSlop: 4
    ) == nil)
}

@Test
func selectionSourceRunSnapsNonOneToOneRunsToSourceBoundaries() {
    let mapper = MarkdownDocumentSelectionSourceRun(
        visibleByteRange: 0..<4,
        sourceRange: MarkdownSourceRange(byteRange: 10..<18, lineRange: 1..<2)
    )

    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 0) == 10)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 1) == 10)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 2) == 10)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 3) == 18)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 4) == 18)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 10) == 0)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 11) == 2)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 17) == 2)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 18) == 4)
}

@Test
func selectionSourceRunSnapsAtomicRunsToSourceBoundaries() {
    let mapper = MarkdownDocumentSelectionSourceRun(
        visibleByteRange: 10..<30,
        sourceRange: MarkdownSourceRange(byteRange: 100..<145, lineRange: 1..<2),
        isAtomic: true
    )

    #expect(mapper.mapsOneToOne == false)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 10) == 100)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 19) == 100)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 20) == 100)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 21) == 145)
    #expect(mapper.sourceByteOffset(forVisibleByteOffset: 30) == 145)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 100) == 10)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 120) == 20)
    #expect(mapper.visibleByteOffset(forSourceByteOffset: 145) == 30)
}

@Test
func preparedImageSelectionSourceRunIsAtomic() throws {
    let markdown = "Image ![](diagram.png) after"
    let imageByteRange = try utf8Range(of: "![](diagram.png)", in: markdown)
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let content = try #require(prepared.preparedContentByBlockID[block.id])
    let fragment = try #require(MarkdownDocumentSelectionFragment.fragments(
        for: block,
        preparedContent: content,
        rect: CGRect(x: 0, y: 0, width: 700, height: 80)
    ).first { $0.textGeometry != nil })
    let sourceRun = try #require(fragment.textGeometry?.sourceRuns.first { sourceRun in
        sourceRun.sourceRange.byteRange == imageByteRange
    })

    #expect(sourceRun.isAtomic)
    #expect(sourceRun.sourceByteOffset(forVisibleByteOffset: sourceRun.visibleByteRange.lowerBound) == imageByteRange.lowerBound)
    #expect(sourceRun.sourceByteOffset(forVisibleByteOffset: sourceRun.visibleByteRange.upperBound) == imageByteRange.upperBound)
}

@Test
func preparedNativeLineLayoutUsesOverwideFallbackForLongPlainWords() throws {
    var stream = MarkdownStream()
    stream.append("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")
    stream.finish()
    let snapshot = stream.snapshot()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines,
        diagnosticsRecorder: recorder
    )
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)

    let result = InlineRunsView.lineLayout(
        for: inlineLayout,
        containerWidth: 48,
        allowsOverwideFallback: true
    )

    #expect(result.lines.count > 1)
    #expect(result.lines.allSatisfy { $0.width <= 48.5 })
    #expect(recorder.snapshot().overwideUnitFallbackCount > 0)
}

@Test
func preparedNativeLineLayoutWrapsInlineCodePathsByDefault() throws {
    var stream = MarkdownStream()
    stream.append("See `/opt/example/workspaces/sample-project/build-artifacts/transcript_renderer_wrap_probe.log`")
    stream.finish()
    let snapshot = stream.snapshot()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        inlineRenderingMode: .preparedNativeLines,
        diagnosticsRecorder: recorder
    )
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)

    let result = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 132)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: result)

    #expect(result.lines.count > 1)
    #expect(result.lines.allSatisfy { $0.width <= 132.5 })
    #expect(lines.map { String($0.characters) }.joined() == inlineLayout.prepared.naturalText)
    #expect(lines.contains { line in line.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true } })
    #expect(recorder.snapshot().overwideUnitFallbackCount > 0)
}

@Test
func nestedListAndQuoteInlinePathsStayWithinEffectiveContentWidth() throws {
    let source = """
    > Quote with `/opt/example/workspaces/sample-project/build-artifacts/transcript_renderer_wrap_probe.log`

    - parent item
      - `/var/tmp/example_render_pipeline/transcript_renderer_wrap_probe_20260503_211600.log`
    """
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(snapshot: snapshot)
    let quote = try #require(prepared.items.compactMap { item -> MarkdownPreparedBlockContent? in
        guard case let .block(block, content) = item, block.kind == .blockQuote else {
            return nil
        }
        return content
    }.first)
    let list = try #require(prepared.items.compactMap { item -> MarkdownPreparedBlockContent? in
        guard case let .block(block, content) = item, block.kind == .unorderedList else {
            return nil
        }
        return content
    }.first)
    let quoteInline = try #require(quote.inlineLayout)
    let childInline = try #require(list.listItems.first?.childItems.first?.inlineLayout)

    let quoteLayout = InlineRunsView.lineLayout(for: quoteInline, containerWidth: 205)
    let childLayout = InlineRunsView.lineLayout(for: childInline, containerWidth: 118)

    #expect(quoteLayout.lines.count > 1)
    #expect(quoteLayout.lines.allSatisfy { $0.width <= 205.5 })
    #expect(childLayout.lines.count > 1)
    #expect(childLayout.lines.allSatisfy { $0.width <= 118.5 })
}

@Test
func tableCellInlinePathsStayWithinCellContentWidth() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        | Kind | Evidence |
        | - | - |
        | Log | `/var/tmp/example_render_pipeline/transcript_renderer_wrap_probe_20260503_211600.log` |
        """
    )
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration.document
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let table = try #require(prepared.preparedContentByBlockID[block.id]?.table)
    let evidence = try #require(table.rows.first?.cells.dropFirst().first?.inlineLayout)

    let result = InlineRunsView.lineLayout(for: evidence, containerWidth: 132)

    #expect(result.lines.count > 1)
    #expect(result.lines.allSatisfy { $0.width <= 132.5 })
}

@Test
func preparedNativeLineLayoutUsesPaintGuardForSiriusTranscriptCommand() throws {
    let inlineLayout = try screenshotCommandInlineLayout()
    let containerWidth = 420.0
    let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
        for: inlineLayout,
        containerWidth: containerWidth
    )
    let result = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: layoutWidth)
    let lines = InlineRunsView.attributedLines(for: inlineLayout, layout: result)
    let renderedText = lines.map { String($0.characters) }.joined()

    #expect(layoutWidth <= containerWidth - 3)
    #expect(result.lines.count > 1)
    #expect(result.lines.allSatisfy { $0.width <= layoutWidth + 0.5 })
    #expect(renderedText.contains("created"))
    #expect(renderedText == inlineLayout.prepared.naturalText)
}

@Test
func siriusTranscriptStyleProfilesUseSystemMonospacedInlineCode() throws {
    let theme = siriusTranscriptLikeTheme()
    let configuration = MarkdownRendererConfiguration(
        theme: theme,
        inlineRenderingMode: .preparedNativeLines
    )
    let block = try firstBlock("Command `created` text")
    let inlineLayout = try #require(configuration.prepare(block: block).inlineLayout)

    #expect(theme.paragraphFontProfiles.code == .system(design: .monospaced))
    #expect(theme.codeFontProfiles == MarkdownInlineFontProfiles(uniform: .system(design: .monospaced)))
    #expect(inlineLayout.fontProfiles == theme.paragraphFontProfiles)
    #expect(inlineLayout.fontSize == 12)
}

@Test
@MainActor
func transcriptLikePreparedNativeViewFittingWidthStaysWithinHostColumn() throws {
    #if canImport(AppKit)
    let source = """
    - File changed:
      - `/opt/example/workspaces/sample-project/build-artifacts/transcript_renderer_wrap_probe.log`
    - Verification command:
      - `./.venv/bin/python experiment_honest_ensemble.py | tee /tmp/example_render_pipeline/transcript_renderer_wrap_probe_20260503_211600.log`
    """
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let width = CGFloat(220)
    let view = StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
        .frame(width: width, alignment: .leading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1_000))
    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width <= width + 1)
    #endif
}

@Test
@MainActor
func siriusTranscriptCommandRenderedLineWidthsFitClippedFrame() throws {
    #if canImport(AppKit)
    let inlineLayout = try screenshotCommandInlineLayout()
    let containerWidth = 420.0
    let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
        for: inlineLayout,
        containerWidth: containerWidth
    )
    let layout = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: layoutWidth)
    let renderedAttributed = InlineRunsView.renderingAttributedString(for: inlineLayout)
    let renderedLines = InlineRunsView.attributedLines(
        for: inlineLayout,
        attributed: renderedAttributed,
        layout: layout
    )

    #expect(renderedLines.map { String($0.characters) }.joined().contains("created"))
    for line in renderedLines where !line.characters.isEmpty {
        let renderedWidth = hostedNativeLineWidth(
            line,
            baseFont: siriusTranscriptLikeTheme().paragraphFont
        )
        #expect(Double(renderedWidth) <= containerWidth + 0.75)
    }
    #endif
}

@Test
@MainActor
func siriusTranscriptCommandHostedLayoutRecomputesAfterWidthNarrowing() throws {
    #if canImport(AppKit)
    let source = screenshotCommandMarkdown()
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()

    let configuration = MarkdownRendererConfiguration(
        theme: siriusTranscriptLikeTheme(),
        inlineRenderingMode: .preparedNativeLines
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let wideWidth = CGFloat(420)
    let narrowWidth = CGFloat(260)
    let view = StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)

    let hostingView = NSHostingView(
        rootView: view.frame(width: wideWidth, alignment: .leading)
    )
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: wideWidth, height: 1_000))
    hostingView.layoutSubtreeIfNeeded()
    #expect(hostingView.fittingSize.width <= wideWidth + 1)

    hostingView.rootView = view.frame(width: narrowWidth, alignment: .leading)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: narrowWidth, height: 1_000))
    hostingView.layoutSubtreeIfNeeded()
    #expect(hostingView.fittingSize.width <= narrowWidth + 1)
    #endif
}

@Test
@MainActor
func wideCodeBlockHostedFittingWidthStaysWithinHostColumn() throws {
    #if canImport(AppKit)
    let source = """
    ```plaintext
    Here is a long diagnostic line that must remain horizontally scrollable without forcing the host transcript column to adopt its natural width: abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz
    ```
    """
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()

    let configuration = MarkdownRendererConfiguration(
        theme: siriusTranscriptLikeTheme(),
        inlineRenderingMode: .preparedNativeLines
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let width = CGFloat(320)
    let view = StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
        .frame(width: width, alignment: .leading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 240))
    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width <= width + 1)
    #expect(hostingView.fittingSize.height < 140)
    #expect(hostingView.fittingSize.height > CGFloat(configuration.theme.codeLineHeight))
    #endif
}

@Test
@MainActor
func preparedNativeResizeRenderKeepsPaintInsideNarrowedColumn() throws {
    #if canImport(AppKit)
    let configuration = MarkdownRendererConfiguration.document
    var stream = MarkdownStream()
    stream.append(resizeProbeMarkdown())
    stream.finish()
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let initialWidth = CGFloat(560)
    let finalWidth = CGFloat(220)
    let model = TestPreparedNativeResizeProbeModel(columnWidth: initialWidth)
    let root = TestPreparedNativeResizeProbeHarness(
        model: model,
        preparedSnapshot: prepared,
        configuration: configuration
    )
    .frame(width: 360, height: 420, alignment: .topLeading)
    .background(Color.white)
    .environment(\.colorScheme, .light)

    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: 420))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    model.columnWidth = finalWidth
    pumpLayout(hostingView)

    let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    let scale = Double(bitmap.pixelsWide) / Double(hostingView.bounds.width)
    let rightmost = darkRightmostX(in: bitmap)

    #expect(rightmost <= Int(Double(finalWidth - 4) * scale))
    #endif
}

@Test
@MainActor
func preparedNativeParagraphBlockInitialHostedLayoutDoesNotCollapseToZeroHeight() throws {
    #if canImport(AppKit)
    let block = try firstBlock("Wide code should remain inspectable without forcing the entire document surface to grow.")
    let configuration = MarkdownRendererConfiguration.document
    let prepared = configuration.prepare(block: block)
    let width = CGFloat(320)
    let hostingView = NSHostingView(
        rootView: MarkdownBlockView(
            block: block,
            configuration: configuration,
            preparedContent: prepared
        )
        .frame(width: width, alignment: .leading)
    )
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 240))
    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.height >= CGFloat(configuration.theme.paragraphLineHeight) - 1)
    #endif
}

@Test
@MainActor
func preparedNativeParagraphRecomputesWhenPreparedContentChangesAtFixedWidth() throws {
    #if canImport(AppKit)
    let configuration = MarkdownRendererConfiguration.document
    let initialBlock = try firstBlock("A single paragraph can mix **strong text**, *emphasis*, ~~strikethrough~~, `inline code`, a [safe HTTPS link](https://example.com/safe), a [relative link](/docs/local), and an unsafe [JavaScript link](javascript:alert('blocked')).")
    let replacementBlock = try firstBlock("Wide code should remain inspectable without forcing the entire document surface to grow.")
    let model = PreparedParagraphSwitchModel(
        block: initialBlock,
        preparedContent: configuration.prepare(block: initialBlock),
        configuration: configuration
    )
    let width = CGFloat(620)
    let hostingView = NSHostingView(
        rootView: PreparedParagraphSwitchHost(model: model)
            .frame(width: width, alignment: .leading)
    )
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 300))
    hostingView.layoutSubtreeIfNeeded()
    let initialHeight = hostingView.fittingSize.height

    model.update(
        block: replacementBlock,
        preparedContent: configuration.prepare(block: replacementBlock)
    )
    hostingView.layoutSubtreeIfNeeded()
    let replacementHeight = hostingView.fittingSize.height

    #expect(initialHeight > 0)
    #expect(replacementHeight >= CGFloat(configuration.theme.paragraphLineHeight) - 1)
    #endif
}

@Test
@MainActor
func documentSurfaceInitialHostedLayoutIncludesWideBlocksParagraphBeforeResize() {
    #if canImport(AppKit)
    let withParagraphMarkdown = """
    Wide code should remain inspectable without forcing the entire document surface to grow.

    ```json
    {"renderer":"SiriusMarkdown","mode":"document","features":["native-swiftui","streaming-aware","prepared-inline-layout","bounded-caches","policy-hooks","host-boundaries"],"longValue":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}
    ```

    ```swift
    let widthChange = "compact -> readable -> wide -> split view"
    let invariant = "layout(preparedSegments, width) must not call parse(markdown)"
    print(widthChange, invariant)
    ```

    | Case | Long Value |
    | :--- | :--- |
    | Cache key | sourceRange + contentHash + rendererConfiguration + theme font traits + policy-relevant inputs |
    | Resize path | cheap layout over prepared segments without parsing, highlighting, or AST conversion |
    | Render path | structured block views consume already prepared table cells, code text, math, and inline runs |
    """
    let withoutParagraphMarkdown = """
    ```json
    {"renderer":"SiriusMarkdown","mode":"document","features":["native-swiftui","streaming-aware","prepared-inline-layout","bounded-caches","policy-hooks","host-boundaries"],"longValue":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}
    ```

    ```swift
    let widthChange = "compact -> readable -> wide -> split view"
    let invariant = "layout(preparedSegments, width) must not call parse(markdown)"
    print(widthChange, invariant)
    ```

    | Case | Long Value |
    | :--- | :--- |
    | Cache key | sourceRange + contentHash + rendererConfiguration + theme font traits + policy-relevant inputs |
    | Resize path | cheap layout over prepared segments without parsing, highlighting, or AST conversion |
    | Render path | structured block views consume already prepared table cells, code text, math, and inline runs |
    """
    let width = CGFloat(620)
    let withParagraphHeight = hostedDocumentSurfaceHeight(markdown: withParagraphMarkdown, width: width)
    let withoutParagraphHeight = hostedDocumentSurfaceHeight(markdown: withoutParagraphMarkdown, width: width)

    #expect(withParagraphHeight > withoutParagraphHeight + 12)
    #endif
}

func repeatedPreparationReusesInlineCodeAndMathCaches() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        Paragraph with **strong** text and [safe link](https://example.com).

        ```swift
        let x = 1
        ```

        $$
        x^2
        $$
        """
    )
    stream.finish()

    let highlighter = CountingCodeHighlighter()
    let mathRenderer = CountingMathRenderer()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        codeHighlighter: highlighter,
        mathRenderer: mathRenderer,
        diagnosticsRecorder: recorder
    )

    let first = configuration.prepare(snapshot: stream.snapshot())
    let afterFirst = recorder.snapshot()
    let second = configuration.prepare(snapshot: stream.snapshot())
    let afterSecond = recorder.snapshot()

    #expect(first.preparedContentByBlockID.keys == second.preparedContentByBlockID.keys)
    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(highlighter.count == 1)
    #expect(mathRenderer.count == 1)
    #expect(afterSecond.codeHighlightCount == afterFirst.codeHighlightCount)
    #expect(afterSecond.mathRenderCount == afterFirst.mathRenderCount)
    #expect(afterSecond.cacheHitCount >= afterFirst.cacheHitCount + 3)
}

@Test
func largeStreamingTranscriptPreparesStableRendererInputs() throws {
    var stream = MarkdownStream()
    for index in 0..<150 {
        stream.append("Paragraph \(index) with **strong text** and [link](https://example.com/\(index)).\n\n")
    }
    stream.append("Active tail with `code` and more text")

    let snapshot = stream.snapshot()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    let prepared = configuration.prepare(snapshot: snapshot)
    let blockItems = prepared.items.compactMap { item -> (MarkdownBlock, MarkdownPreparedBlockContent)? in
        guard case let .block(block, content) = item else {
            return nil
        }
        return (block, content)
    }

    #expect(snapshot.blocks.count == 151)
    #expect(snapshot.blocks.last?.isSealed == false)
    #expect(blockItems.count == snapshot.blocks.count)
    #expect(Set(prepared.items.map(\.id)).count == prepared.items.count)
    #expect(Set(blockItems.map { $0.0.id }).count == blockItems.count)
    #expect(blockItems.allSatisfy { $0.1.blockID == $0.0.id })
    #expect(blockItems.allSatisfy { $0.1.inlineLayout != nil })
    #expect(recorder.snapshot().prepareCount == snapshot.blocks.count)
}

@Test
func copyProviderReturnsExactSourceSlice() throws {
    var stream = MarkdownStream()
    stream.append("- item\n- second\n\n")
    stream.finish()
    let block = try #require(stream.snapshot().blocks.first)
    let copyStream = stream
    let provider = MarkdownCopyProvider { range in
        copyStream.markdown(in: range)
    }

    #expect(provider.markdown(block.sourceRange) == "- item\n- second\n")
}

@Test
func sourceBackedCopyProviderReturnsUTF8SourceSlices() throws {
    let markdown = "# Title\n\nEnglish, 日本語, العربية, emoji 😀\n\n"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let paragraph = try #require(stream.snapshot().blocks.last)
    let provider = MarkdownCopyProvider(markdownSource: markdown)

    #expect(provider.markdown(paragraph.sourceRange) == "English, 日本語, العربية, emoji 😀")
}

@Test
@MainActor
func copyProviderReturnsFullDocumentMarkdown() async throws {
    let markdown = "# Title\n\nBody with `code`.\n"
    let provider = MarkdownCopyProvider(markdownSource: markdown)

    #expect(provider.hasDocumentMarkdown)
    #expect(provider.markdownForDocument() == markdown)

    let session = MarkdownRenderSession(configuration: .document)
    session.append(markdown)
    session.finish()
    await session.waitUntilIdle()

    #expect(session.configuration.copyProvider?.hasDocumentMarkdown == true)
    #expect(session.configuration.copyProvider?.markdownForDocument() == markdown)
}

@Test
func documentSurfaceRenderPlanReflectsSourceBackedAffordanceCapability() throws {
    let markdown = "# Title\n\nBody.\n"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let sourceBackedConfiguration = MarkdownRendererConfiguration(
        theme: .document,
        copyProvider: MarkdownCopyProvider(markdownSource: markdown)
    )
    let prepared = sourceBackedConfiguration.prepare(snapshot: stream.snapshot())
    let plan = MarkdownDocumentSurfaceRenderPlan(
        preparedSnapshot: prepared,
        configuration: sourceBackedConfiguration
    )

    #expect(plan.documentCopyButtonVisible)
    #expect(plan.documentExportButtonVisible)
    #expect(plan.documentCollapseButtonVisible)
    #expect(plan.blockCount == 2)

    let noSourcePlan = MarkdownDocumentSurfaceRenderPlan(
        preparedSnapshot: prepared,
        configuration: MarkdownRendererConfiguration.document
    )

    #expect(noSourcePlan.documentCopyButtonVisible == false)
    #expect(noSourcePlan.documentExportButtonVisible == false)
    #expect(noSourcePlan.documentCollapseButtonVisible)
}

@Test
func documentSurfaceCollapsedPlanPreservesPreparedIdentityWithoutRepreparing() throws {
    let markdown = "# Title\n\nBody with **strong** and `code`.\n"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        theme: .document,
        copyProvider: MarkdownCopyProvider(markdownSource: markdown),
        diagnosticsRecorder: recorder
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let afterPrepare = recorder.snapshot()

    let collapsed = MarkdownDocumentSurfaceRenderPlan(
        preparedSnapshot: prepared,
        configuration: configuration,
        isCollapsed: true
    )
    let expanded = MarkdownDocumentSurfaceRenderPlan(
        preparedSnapshot: prepared,
        configuration: configuration,
        isCollapsed: false
    )
    let afterPlans = recorder.snapshot()

    #expect(collapsed.itemIDs == expanded.itemIDs)
    #expect(collapsed.snapshotGeneration == expanded.snapshotGeneration)
    #expect(collapsed.isCollapsed)
    #expect(expanded.isCollapsed == false)
    #expect(afterPlans.renderPreparationCount == afterPrepare.renderPreparationCount)
    #expect(afterPlans.prepareCount == afterPrepare.prepareCount)
    #expect(afterPlans.codeHighlightCount == afterPrepare.codeHighlightCount)
    #expect(afterPlans.mathRenderCount == afterPrepare.mathRenderCount)
}

@Test
@MainActor
func documentSurfaceSupportsControlledCollapseBinding() throws {
    let markdown = "# Controlled\n\nBody.\n"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
    let prepared = configuration.prepare(snapshot: stream.snapshot())

    var collapsed = true
    let binding = Binding(
        get: { collapsed },
        set: { collapsed = $0 }
    )
    _ = MarkdownDocumentSurface(
        title: "Controlled",
        suggestedFilename: "controlled.md",
        preparedSnapshot: prepared,
        configuration: configuration,
        isCollapsed: binding,
        onCollapseChanged: { collapsed = $0 }
    )

    let plan = MarkdownDocumentSurfaceRenderPlan(
        preparedSnapshot: prepared,
        configuration: configuration,
        isCollapsed: binding.wrappedValue
    )
    #expect(plan.isCollapsed)
}

@Test
func blockAccessibilityLabelsDescribeStructuredBlocks() throws {
    let heading = try firstBlock("## Title")
    let table = try firstBlock("| A | B |\n| - | - |\n| 1 | 2 |")
    let code = try firstBlock("```swift\nlet x = 1\n```")

    #expect(MarkdownBlockView.accessibilityLabel(for: heading) == "Heading 2: Title")
    #expect(MarkdownBlockView.accessibilityLabel(for: table) == "Table with 2 columns and 1 rows")
    #expect(MarkdownBlockView.accessibilityLabel(for: code) == "Code block")
}

@Test
func blockRenderPlanUsesProtocolPoliciesForCodeMathAndHTML() throws {
    let code = try firstBlock("```swift\nlet x = 1\n```")
    let deniedCode = MarkdownBlockView.renderPlan(
        for: code,
        configuration: MarkdownRendererConfiguration(codePolicy: DenyCodePolicy())
    )
    #expect(deniedCode.codeAllowed == false)
    #expect(deniedCode.policyDenialReason == "code denied")
    #expect(deniedCode.codeCopyButtonVisible == false)
    #expect(deniedCode.codeLanguageLabel == nil)

    let math = try firstBlock("$$\nx^2\n$$")
    let deniedMath = MarkdownBlockView.renderPlan(
        for: math,
        configuration: MarkdownRendererConfiguration(mathPolicy: DenyMathPolicy())
    )
    #expect(deniedMath.mathAllowed == false)
    #expect(deniedMath.policyDenialReason == "math denied")

    let html = try firstBlock("<div>raw</div>")
    let defaultHTML = MarkdownBlockView.renderPlan(for: html)
    #expect(defaultHTML.htmlAllowed == false)

    let allowedHTML = MarkdownBlockView.renderPlan(
        for: html,
        configuration: MarkdownRendererConfiguration(htmlPolicy: AllowHTMLPolicy())
    )
    #expect(allowedHTML.htmlAllowed == true)
}

@Test
func blockRenderPlanEvaluatesMathAndHTMLPoliciesOnce() throws {
    let math = try firstBlock("$$\nx^2\n$$")
    let mathPolicy = CountingMathPolicy()
    let deniedMath = MarkdownBlockView.renderPlan(
        for: math,
        configuration: MarkdownRendererConfiguration(mathPolicy: mathPolicy)
    )
    #expect(deniedMath.mathAllowed == false)
    #expect(deniedMath.policyDenialReason == "counted math denied")
    #expect(mathPolicy.count == 1)

    let html = try firstBlock("<div>raw</div>")
    let htmlPolicy = CountingHTMLPolicy()
    let deniedHTML = MarkdownBlockView.renderPlan(
        for: html,
        configuration: MarkdownRendererConfiguration(htmlPolicy: htmlPolicy)
    )
    #expect(deniedHTML.htmlAllowed == false)
    #expect(deniedHTML.policyDenialReason == "counted html denied")
    #expect(htmlPolicy.count == 1)
}

@Test
func codeBlockRenderPlanExposesLanguageAndCopyAffordance() throws {
    let code = try firstBlock("```language-swift\nlet x = 1\n```")
    let plan = MarkdownBlockView.renderPlan(for: code)

    #expect(plan.codeAllowed == true)
    #expect(plan.codeLanguageLabel == "Swift")
    #expect(plan.codeCopyButtonVisible == true)
    #expect(plan.codeExportButtonVisible == true)
    #expect(plan.codeCollapseButtonVisible == true)
    #expect(plan.codeInitiallyCollapsed == false)
    #expect(MarkdownBlockView.codeBlockLanguageLabel(for: code) == "Swift")
    #expect(MarkdownBlockView.codeCopyText(for: code) == "let x = 1\n")
    #expect(MarkdownBlockView.codeExportFilename(for: code) == "CodeBlock.swift")
}

@Test
func codeBlockChromeCanBeDisabledByConfiguration() throws {
    let code = try firstBlock("```python\nprint('hi')\n```")
    var theme = MarkdownTheme()
    theme.codeBlockAffordances = .hidden
    let configuration = MarkdownRendererConfiguration(theme: theme)
    let plan = MarkdownBlockView.renderPlan(for: code, configuration: configuration)

    #expect(plan.codeAllowed == true)
    #expect(plan.codeLanguageLabel == nil)
    #expect(plan.codeCopyButtonVisible == false)
    #expect(plan.codeExportButtonVisible == false)
    #expect(plan.codeCollapseButtonVisible == false)
    #expect(plan.codeInitiallyCollapsed == false)
    #expect(MarkdownBlockView.codeCopyText(for: code) == "print('hi')\n")
}

@Test
func codeBlockAffordancePlanIncludesExportAndInitialCollapse() throws {
    let code = try firstBlock("```json\n{\"ok\": true}\n```")
    var theme = MarkdownTheme()
    theme.codeBlockAffordances = MarkdownCodeBlockAffordances(startsCollapsed: true)
    let plan = MarkdownBlockView.renderPlan(
        for: code,
        configuration: MarkdownRendererConfiguration(theme: theme)
    )

    #expect(plan.codeAllowed == true)
    #expect(plan.codeLanguageLabel == "JSON")
    #expect(plan.codeCopyButtonVisible)
    #expect(plan.codeExportButtonVisible)
    #expect(plan.codeCollapseButtonVisible)
    #expect(plan.codeInitiallyCollapsed)
    #expect(MarkdownBlockView.codeExportFilename(for: code) == "CodeBlock.json")
}

@Test
@MainActor
func preparedBlockContentMovesCodeAndMathRenderingOutOfBlockBody() throws {
    let code = try firstBlock("```swift\nlet x = 1\n```")
    let highlighter = CountingCodeHighlighter()
    let codeConfiguration = MarkdownRendererConfiguration(codeHighlighter: highlighter)

    _ = MarkdownBlockView.renderPlan(for: code, configuration: codeConfiguration)
    #expect(highlighter.count == 0)

    _ = MarkdownBlockView(block: code, configuration: codeConfiguration, preparedContent: nil)
    #expect(highlighter.count == 0)

    let preparedCode = codeConfiguration.prepare(block: code)
    #expect(highlighter.count == 1)
    _ = codeConfiguration.prepare(block: code)
    #expect(highlighter.count == 1)

    _ = MarkdownBlockView(
        block: code,
        configuration: codeConfiguration,
        preparedContent: preparedCode
    )
    #expect(highlighter.count == 1)

    let math = try firstBlock("$$\nx^2\n$$")
    let mathRenderer = CountingMathRenderer()
    let mathConfiguration = MarkdownRendererConfiguration(mathRenderer: mathRenderer)
    let preparedMath = mathConfiguration.prepare(block: math)
    #expect(mathRenderer.count == 1)
    _ = mathConfiguration.prepare(block: math)
    #expect(mathRenderer.count == 1)

    _ = MarkdownBlockView(
        block: math,
        configuration: mathConfiguration,
        preparedContent: preparedMath
    )
    #expect(mathRenderer.count == 1)
}

@Test
@MainActor
func preparedBlockContentMovesMermaidRenderingOutOfBlockBody() throws {
    let mermaidBlock = try firstBlock("```mermaid\ngraph LR\nA --> B\n```")
    let renderer = CountingMermaidRenderer(ascii: "A -> B")
    let configuration = MarkdownRendererConfiguration(mermaidRenderer: renderer)

    _ = MarkdownBlockView.renderPlan(for: mermaidBlock, configuration: configuration)
    #expect(renderer.count == 0)

    let preparedMermaid = configuration.prepare(block: mermaidBlock)
    #expect(renderer.count == 1)
    _ = configuration.prepare(block: mermaidBlock)
    #expect(renderer.count == 1)

    _ = MarkdownBlockView(
        block: mermaidBlock,
        configuration: configuration,
        preparedContent: preparedMermaid
    )
    #expect(renderer.count == 1)
    #expect(preparedMermaid.mermaid?.ascii == "A -> B")
}

@Test
func representativeDocumentPreparesStructuredRendererInputs() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        # Title

        Paragraph with **strong**, *emphasis*, `code`, [link](https://example.com), and ![alt](image.png).

        - [ ] task
        - [x] done

        > Quote

        ```swift
        let veryLongIdentifierName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        ```

        | A | B |
        | - | - |
        | 1 | 2 |

        $$
        x^2
        $$
        """
    )
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(theme: .document)
    let prepared = configuration.prepare(snapshot: snapshot)
    let preparedBlocks = prepared.items.compactMap { item -> (MarkdownBlock, MarkdownPreparedBlockContent)? in
        guard case let .block(block, content) = item else {
            return nil
        }
        return (block, content)
    }

    #expect(preparedBlocks.count == snapshot.blocks.count)
    #expect(Set(prepared.items.map(\.id)).count == prepared.items.count)
    #expect(preparedBlocks.allSatisfy { $0.1.blockID == $0.0.id })

    let kinds = Set(preparedBlocks.map { $0.0.kind })
    #expect(kinds.isSuperset(of: [.heading, .paragraph, .taskList, .blockQuote, .codeBlock, .table, .mathBlock]))

    let paragraph = try #require(preparedBlocks.first { $0.0.kind == .paragraph })
    let inlineLayout = try #require(paragraph.1.inlineLayout)
    let wrapped = InlineRunsView.lineLayout(for: inlineLayout, containerWidth: 160)
    #expect(wrapped.lines.count > 1)

    let taskList = try #require(preparedBlocks.first { $0.0.kind == .taskList })
    #expect(taskList.1.listItems.count == 2)
    #expect(taskList.1.listItems.allSatisfy { $0.inlineLayout != nil })

    let table = try #require(preparedBlocks.first { $0.0.kind == .table })
    let preparedTable = try #require(table.1.table)
    #expect(preparedTable.header.count == 2)
    #expect(preparedTable.rows.count == 1)
    #expect(preparedTable.header.allSatisfy { $0.inlineLayout != nil })
    #expect(preparedTable.rows.flatMap(\.cells).allSatisfy { $0.inlineLayout != nil })

    let code = try #require(preparedBlocks.first { $0.0.kind == .codeBlock })
    #expect(code.1.code != nil)

    let math = try #require(preparedBlocks.first { $0.0.kind == .mathBlock })
    #expect(math.1.math != nil)
}

private func firstBlock(_ markdown: String) throws -> MarkdownBlock {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return try #require(stream.snapshot().blocks.first)
}

private func attributedStringContainsLink(_ attributed: AttributedString?) -> Bool {
    guard let attributed else {
        return false
    }

    return attributed.runs.contains { run in
        run.link != nil
    }
}

private func plainString(_ attributed: AttributedString?) -> String {
    guard let attributed else {
        return ""
    }
    return String(attributed.characters)
}

private struct SemanticWidthMeasurer: InlineMeasuring {
    var measurementCacheKey: String {
        "semantic-width-measurer"
    }

    func width(of text: String, fontSize _: Double) -> Double {
        Double(text.utf8.count)
    }

    func width(of segment: PreparedInlineSegment, fontSize _: Double) -> Double {
        let scale = segment.kind == .code || segment.presentation.contains(.code) ? 2.0 : 1.0
        return Double(segment.text.utf8.count) * scale
    }
}

private func preparedInlineIdentityFixture(
    runs: [MarkdownInlineRun],
    sourceRange: MarkdownSourceRange
) -> MarkdownPreparedInlineContent {
    let prepared = PreparedInlineContent(runs: runs, sourceRange: sourceRange)
    let measured = VariableWidthLineWalker(measurer: SemanticWidthMeasurer())
        .prepare(prepared, fontSize: 12)
    return MarkdownPreparedInlineContent(
        attributed: InlineRunsView.attributedString(for: runs),
        prepared: prepared,
        measured: measured,
        fontSize: 12,
        lineHeight: 16,
        fontProfiles: .paragraphDefault
    )
}

private func screenshotCommandMarkdown() -> String {
    """
    - Command used:
      - `apple_mail(action="save_draft", subject="Regression test draft", body="This is a test draft created to check for regressions after the version bump.", visible=true, send_now=false, timeout_seconds=120)`
    """
}

private func resizeProbeMarkdown() -> String {
    """
    Resize probe paragraph with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content that must rewrap when the host column shrinks.

    - Resize list item with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content.
    - Another item with [linked prepared native text](https://example.com) and `inline code` that should stay inside the narrowed column.
    """
}

private func screenshotCommandInlineLayout() throws -> MarkdownPreparedInlineContent {
    var stream = MarkdownStream()
    stream.append(screenshotCommandMarkdown())
    stream.finish()
    let configuration = MarkdownRendererConfiguration(
        theme: siriusTranscriptLikeTheme(),
        inlineRenderingMode: .preparedNativeLines
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let list = try #require(prepared.items.compactMap { item -> MarkdownPreparedBlockContent? in
        guard case let .block(block, content) = item,
              block.kind == .unorderedList
        else {
            return nil
        }
        return content
    }.first)
    return try #require(list.listItems.first?.childItems.first?.inlineLayout)
}

private func siriusTranscriptLikeTheme() -> MarkdownTheme {
    let paragraphProfiles = MarkdownInlineFontProfiles(
        body: .system(),
        emphasis: .system(),
        strong: .system(weight: .bold),
        code: .system(design: .monospaced),
        math: .system(design: .monospaced),
        imagePlaceholder: .system()
    )
    let codeProfiles = MarkdownInlineFontProfiles(uniform: .system(design: .monospaced))
    let compactHeading = MarkdownTextStyle(
        font: .system(size: 12, weight: .semibold),
        fontSize: 12,
        lineHeight: 16,
        fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .semibold))
    )

    return MarkdownTheme(
        paragraphFont: .system(size: 12),
        codeFont: .system(size: 11, design: .monospaced),
        codeBackground: Color.gray.opacity(0.12),
        quoteAccent: Color.gray.opacity(0.55),
        tableBackground: Color.gray.opacity(0.06),
        tableHeaderBackground: Color.accentColor.opacity(0.08),
        tableAlternateRowBackground: Color.gray.opacity(0.025),
        tableCornerRadius: 6,
        tableHorizontalCellPadding: 10,
        tableVerticalCellPadding: 7,
        blockSpacing: 8,
        paragraphFontSize: 12,
        paragraphLineHeight: 17,
        codeFontSize: 11,
        codeLineHeight: 16,
        paragraphFontProfiles: paragraphProfiles,
        codeFontProfiles: codeProfiles,
        headings: .uniform(compactHeading)
    )
}

private func testHeadingStyles() -> MarkdownHeadingStyles {
    MarkdownHeadingStyles(
        h1: MarkdownTextStyle(
            font: .system(size: 11, weight: .bold),
            fontSize: 11,
            lineHeight: 15,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .named("Helvetica", weight: .bold))
        ),
        h2: MarkdownTextStyle(
            font: .system(size: 12, weight: .bold),
            fontSize: 12,
            lineHeight: 16,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .named("Menlo", weight: .bold))
        ),
        h3: MarkdownTextStyle(
            font: .system(size: 13, weight: .bold),
            fontSize: 13,
            lineHeight: 17,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .bold))
        ),
        h4: MarkdownTextStyle(
            font: .system(size: 19, weight: .semibold),
            fontSize: 19,
            lineHeight: 25,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .semibold, design: .rounded))
        ),
        h5: MarkdownTextStyle(
            font: .system(size: 21, weight: .semibold),
            fontSize: 21,
            lineHeight: 29,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .named("Courier", weight: .semibold))
        ),
        h6: MarkdownTextStyle(
            font: .system(size: 23, weight: .semibold),
            fontSize: 23,
            lineHeight: 31,
            fontProfiles: MarkdownInlineFontProfiles(uniform: .monospacedSystem(weight: .semibold))
        )
    )
}

private func mirroredConfiguration(from view: MarkdownBlockView) -> MarkdownRendererConfiguration? {
    Mirror(reflecting: view)
        .children
        .first { $0.label == "configuration" }?
        .value as? MarkdownRendererConfiguration
}

#if canImport(AppKit)
@MainActor
private final class TestPreparedNativeResizeProbeModel: ObservableObject {
    @Published var columnWidth: CGFloat

    init(columnWidth: CGFloat) {
        self.columnWidth = columnWidth
    }
}

private struct TestPreparedNativeResizeProbeHarness: View {
    @ObservedObject var model: TestPreparedNativeResizeProbeModel
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration

    var body: some View {
        HStack(spacing: 0) {
            StreamingMarkdownView(preparedSnapshot: preparedSnapshot, configuration: configuration)
                .frame(width: model.columnWidth, alignment: .leading)
            Color.white
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private func hostedNativeLineWidth(_ line: AttributedString, baseFont: Font) -> CGFloat {
    let view = Text(line)
        .font(baseFont)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 1_000, height: 80))
    hostingView.layoutSubtreeIfNeeded()
    return hostingView.fittingSize.width
}

@MainActor
private func offscreenTestWindow<V: View>(_ hostingView: NSHostingView<V>) -> NSWindow {
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    return window
}

@MainActor
private func pumpLayout<V: View>(_ hostingView: NSHostingView<V>) {
    for _ in 0..<6 {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func tearDownWindow(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
    for _ in 0..<3 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private final class MarkdownCopySpy {
    var copied: String?
}

@MainActor
private final class SelectionPreferenceRecorder {
    var fragments: [MarkdownDocumentSelectionFragment] = []
}

private func selectionFragments(
    for snapshot: MarkdownSnapshot,
    prepared: MarkdownPreparedSnapshot,
    width: CGFloat
) -> [MarkdownDocumentSelectionFragment] {
    var offset: CGFloat = 0
    var fragments: [MarkdownDocumentSelectionFragment] = []
    for block in snapshot.blocks {
        guard let content = prepared.preparedContentByBlockID[block.id] else {
            continue
        }
        let rect = CGRect(x: 0, y: offset, width: width, height: 80)
        fragments.append(contentsOf: MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: rect
        ))
        offset += 96
    }
    return fragments.sortedForTestSelection()
}

@MainActor
private func commandCEvent() -> NSEvent {
    commandKeyEvent("c", keyCode: 8)
}

@MainActor
private func commandAEvent() -> NSEvent {
    commandKeyEvent("a", keyCode: 0)
}

@MainActor
private func commandKeyEvent(_ character: String, keyCode: UInt16) -> NSEvent {
    guard let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: character,
        charactersIgnoringModifiers: character,
        isARepeat: false,
        keyCode: keyCode
    ) else {
        Issue.record("Unable to create command-\(character.uppercased()) event")
        fatalError("Unable to create command-\(character.uppercased()) event")
    }
    return event
}

private extension Array where Element == MarkdownDocumentSelectionFragment {
    func sortedForTestSelection() -> [MarkdownDocumentSelectionFragment] {
        sorted {
            if $0.sourceRange.byteRange.lowerBound == $1.sourceRange.byteRange.lowerBound {
                return $0.sourceRange.byteRange.upperBound < $1.sourceRange.byteRange.upperBound
            }
            return $0.sourceRange.byteRange.lowerBound < $1.sourceRange.byteRange.lowerBound
        }
    }
}

@MainActor
private func appKitTextViews(in view: NSView) -> [NSTextView] {
    var matches: [NSTextView] = []
    if let textView = view as? NSTextView {
        matches.append(textView)
    }
    for subview in view.subviews {
        matches.append(contentsOf: appKitTextViews(in: subview))
    }
    return matches
}

@MainActor
private func appKitCoreTextPaintedViews(in view: NSView) -> [NSView] {
    var matches: [NSView] = []
    if String(describing: type(of: view)).contains("MarkdownCoreTextPaintedNSView") {
        matches.append(view)
    }
    for subview in view.subviews {
        matches.append(contentsOf: appKitCoreTextPaintedViews(in: subview))
    }
    return matches
}

@MainActor
private func mouseEvent(type: NSEvent.EventType, location: CGPoint, window: NSWindow) -> NSEvent {
    guard let event = NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1
    ) else {
        Issue.record("Unable to create mouse event")
        fatalError("Unable to create mouse event")
    }
    return event
}

@MainActor
private func copySelectedText(_ text: String, from textView: NSTextView) throws -> String {
    let range = (textView.string as NSString).range(of: text)
    #expect(range.location != NSNotFound)
    _ = textView.window?.makeFirstResponder(textView)
    textView.setSelectedRange(range)
    NSPasteboard.general.clearContents()
    textView.copy(nil)
    return try #require(NSPasteboard.general.string(forType: .string))
}

private func darkRightmostX(in bitmap: NSBitmapImageRep) -> Int {
    var rightmost = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }

            if color.redComponent < 0.35,
               color.greenComponent < 0.35,
               color.blueComponent < 0.35 {
                rightmost = max(rightmost, x)
            }
        }
    }
    return rightmost
}

@MainActor
private func hostedDocumentSurfaceHeight(markdown: String, width: CGFloat) -> CGFloat {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let configuration = MarkdownRendererConfiguration.document
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let view = MarkdownDocumentSurface(
        title: "Rendered Document",
        subtitle: "\(prepared.snapshot.blocks.count.formatted()) blocks prepared through the public document renderer.",
        suggestedFilename: "wide-blocks.md",
        preparedSnapshot: prepared,
        configuration: configuration
    )
    .frame(width: width, alignment: .leading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 2_000))
    hostingView.layoutSubtreeIfNeeded()
    return hostingView.fittingSize.height
}

@MainActor
private final class PreparedParagraphSwitchModel: ObservableObject {
    @Published var block: MarkdownBlock
    @Published var preparedContent: MarkdownPreparedBlockContent
    let configuration: MarkdownRendererConfiguration

    init(
        block: MarkdownBlock,
        preparedContent: MarkdownPreparedBlockContent,
        configuration: MarkdownRendererConfiguration
    ) {
        self.block = block
        self.preparedContent = preparedContent
        self.configuration = configuration
    }

    func update(block: MarkdownBlock, preparedContent: MarkdownPreparedBlockContent) {
        self.block = block
        self.preparedContent = preparedContent
    }
}

private struct PreparedParagraphSwitchHost: View {
    @ObservedObject var model: PreparedParagraphSwitchModel

    var body: some View {
        MarkdownBlockView(
            block: model.block,
            configuration: model.configuration,
            preparedContent: model.preparedContent
        )
    }
}
#endif

private struct DenyCodePolicy: MarkdownCodePolicy {
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision {
        .deny(reason: "code denied")
    }
}

private struct DenyMathPolicy: MarkdownMathPolicy {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .deny(reason: "math denied")
    }
}

private struct AllowHTMLPolicy: MarkdownHTMLPolicy {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        .allow
    }
}

private final class CountingMathPolicy: MarkdownMathPolicy, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        lock.withLock {
            callCount += 1
        }
        return .deny(reason: "counted math denied")
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private struct IdentityMathPolicy: MarkdownMathPolicy, MarkdownMathPolicyCacheIdentifying {
    var mathPolicyCacheIdentity: String
    var decision: MarkdownPolicyDecision

    init(identity: String, decision: MarkdownPolicyDecision) {
        self.mathPolicyCacheIdentity = identity
        self.decision = decision
    }

    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        _ = source
        _ = isBlock
        return decision
    }
}

private final class CountingHTMLPolicy: MarkdownHTMLPolicy, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        lock.withLock {
            callCount += 1
        }
        return .deny(reason: "counted html denied")
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private struct InlineFixtureMathRenderer: MarkdownMathRenderer {
    func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        AttributedString("math[\(source)]")
    }
}

private final class CountingCodeHighlighter: MarkdownCodeHighlighter, MarkdownCodeHighlighterCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var codeHighlighterCacheIdentity: String {
        "test.counting-code"
    }

    func highlightedCode(_ code: String, infoString: String?) -> AttributedString {
        lock.withLock {
            callCount += 1
        }
        return AttributedString(code)
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class PrefixCodeHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func highlightedCode(_ code: String, infoString: String?) -> AttributedString {
        _ = infoString
        lock.withLock {
            callCount += 1
        }
        return AttributedString("\(prefix):\(code)")
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class IdentityCodeHighlighter: MarkdownCodeHighlighter, MarkdownCodeHighlighterCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    let codeHighlighterCacheIdentity: String

    init(identity: String) {
        self.codeHighlighterCacheIdentity = identity
    }

    func highlightedCode(_ code: String, infoString: String?) -> AttributedString {
        lock.withLock {
            callCount += 1
        }
        return AttributedString(code)
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private struct IdentityLinkPolicy: MarkdownLinkPolicy, MarkdownLinkPolicyCacheIdentifying {
    var linkPolicyCacheIdentity: String
    var decision: MarkdownPolicyDecision

    init(identity: String, decision: MarkdownPolicyDecision) {
        self.linkPolicyCacheIdentity = identity
        self.decision = decision
    }

    func evaluateLink(destination: String) -> MarkdownPolicyDecision {
        _ = destination
        return decision
    }
}

private struct NonIdentifyingLinkPolicy: MarkdownLinkPolicy {
    var decision: MarkdownPolicyDecision

    func evaluateLink(destination: String) -> MarkdownPolicyDecision {
        _ = destination
        return decision
    }
}

private final class NonIdentifyingImagePolicy: MarkdownImagePolicy, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    var decision: MarkdownPolicyDecision

    init(decision: MarkdownPolicyDecision) {
        self.decision = decision
    }

    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision {
        _ = source
        _ = altText
        lock.withLock {
            callCount += 1
        }
        return decision
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private struct IdentityImagePolicy: MarkdownImagePolicy, MarkdownImagePolicyCacheIdentifying {
    var imagePolicyCacheIdentity: String
    var decision: MarkdownPolicyDecision

    init(identity: String, decision: MarkdownPolicyDecision) {
        self.imagePolicyCacheIdentity = identity
        self.decision = decision
    }

    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision {
        _ = source
        _ = altText
        return decision
    }
}

private final class RecordingImageResolver: MarkdownImageResolver, MarkdownImageResolverCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var imageResolverCacheIdentity: String {
        "test.recording-image-resolver"
    }

    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: .placeholder(reason: "\(policyDecision)")
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class NonIdentifyingImageResolver: MarkdownImageResolver, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: .placeholder(reason: "\(policyDecision)")
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class CountingMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var mathRendererCacheIdentity: String {
        "test.counting-math"
    }

    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        lock.withLock {
            callCount += 1
        }
        return AttributedString(source)
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class IdentityMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    let mathRendererCacheIdentity: String
    private let prefix: String

    init(identity: String, prefix: String) {
        self.mathRendererCacheIdentity = identity
        self.prefix = prefix
    }

    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        _ = isBlock
        lock.withLock {
            callCount += 1
        }
        var attributed = AttributedString("\(prefix):\(source)")
        attributed.inlinePresentationIntent = .code
        return attributed
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class NonIdentifyingMathRenderer: MarkdownMathRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        _ = isBlock
        lock.withLock {
            callCount += 1
        }
        return AttributedString("rendered:\(source)")
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class CountingImageMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var preparedCallCount = 0
    private var renderedCallCount = 0

    var mathRendererCacheIdentity: String {
        "test.counting-image-math"
    }

    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        _ = isBlock
        lock.withLock {
            renderedCallCount += 1
        }
        return AttributedString("fallback:\(source)")
    }

    func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
        _ = isBlock
        _ = fontSize
        lock.withLock {
            preparedCallCount += 1
        }
        return .image(
            MarkdownPreparedMathImage(
                imageData: Data([0]),
                scale: 1,
                pointWidth: 8,
                pointHeight: 8,
                ascent: 6,
                descent: 2,
                latex: source
            )
        )
    }

    var preparedCount: Int {
        lock.withLock {
            preparedCallCount
        }
    }

    var renderedCount: Int {
        lock.withLock {
            renderedCallCount
        }
    }
}

private final class LinkActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ destination: String) {
        lock.withLock {
            values.append(destination)
        }
    }

    var destinations: [String] {
        lock.withLock {
            values
        }
    }
}

private final class CountingMermaidRenderer: MarkdownMermaidRenderer, MarkdownMermaidRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let ascii: String

    var mermaidRendererCacheIdentity: String {
        "test.counting-mermaid"
    }

    init(ascii: String) {
        self.ascii = ascii
    }

    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        _ = theme
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: ascii
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class PrefixMermaidRenderer: MarkdownMermaidRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let ascii: String

    init(ascii: String) {
        self.ascii = ascii
    }

    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        _ = theme
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: ascii
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private func coreTextPaintedTestInlineLayouts(in prepared: MarkdownPreparedSnapshot) -> [MarkdownPreparedInlineContent] {
    var layouts: [MarkdownPreparedInlineContent] = []

    func appendListItems(_ items: [MarkdownPreparedListItem]) {
        for item in items {
            if let inlineLayout = item.inlineLayout {
                layouts.append(inlineLayout)
            }
            appendListItems(item.childItems)
        }
    }

    for content in prepared.preparedContentByBlockID.values {
        if let inlineLayout = content.inlineLayout {
            layouts.append(inlineLayout)
        }
        appendListItems(content.listItems)
        if let table = content.table {
            for cell in table.header {
                if let inlineLayout = cell.inlineLayout {
                    layouts.append(inlineLayout)
                }
            }
            for row in table.rows {
                for cell in row.cells {
                    if let inlineLayout = cell.inlineLayout {
                        layouts.append(inlineLayout)
                    }
                }
            }
        }
    }

    return layouts
}

#if canImport(CoreText)
private func coreTextPaintedTestWidth(
    of text: String,
    prepared: MarkdownPreparedInlineContent
) -> CGFloat {
    let attributed = NSMutableAttributedString(string: text)
    attributed.addAttribute(
        NSAttributedString.Key(kCTFontAttributeName as String),
        value: MarkdownCoreTextFontBridge.font(
            profile: prepared.fontProfiles.body,
            kind: .text,
            presentation: [],
            size: prepared.fontSize
        ),
        range: NSRange(location: 0, length: attributed.length)
    )
    let line = CTLineCreateWithAttributedString(attributed)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

private func coreTextPaintedTestAlphaCoverage(
    plan: MarkdownCoreTextPaintedLinePlan,
    width: Int,
    height: Int
) -> Int {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textMatrix = .identity
        for line in plan.lines {
            let lineStride = plan.lineHeight + plan.lineSpacing
            let top = CGFloat(line.index) * lineStride
            let typographicHeight = line.ascent + line.descent + line.leading
            let verticalInset = max(0, (plan.lineHeight - typographicHeight) / 2)
            let baselineFromTop = top + verticalInset + line.ascent
            context.textPosition = CGPoint(x: 0, y: CGFloat(height) - baselineFromTop)
            CTLineDraw(line.ctLine, context)
        }
    }

    return stride(from: 3, to: pixels.count, by: bytesPerPixel).reduce(0) { partial, index in
        partial + Int(pixels[index])
    }
}
#endif

private func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func swiftSourceFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    return try enumerator.compactMap { entry in
        guard let url = entry as? URL,
              url.pathExtension == "swift"
        else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        return values.isRegularFile == true ? url : nil
    }
}

private func utf8Range(of needle: String, in haystack: String) throws -> Range<Int> {
    let range = try #require(haystack.range(of: needle))
    let lower = haystack.utf8.distance(
        from: haystack.utf8.startIndex,
        to: range.lowerBound.samePosition(in: haystack.utf8) ?? haystack.utf8.startIndex
    )
    let upper = haystack.utf8.distance(
        from: haystack.utf8.startIndex,
        to: range.upperBound.samePosition(in: haystack.utf8) ?? haystack.utf8.endIndex
    )
    return lower..<upper
}

private extension String {
    func occurrences(of needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return components(separatedBy: needle).count - 1
    }
}

private final class IdentityMermaidRenderer: MarkdownMermaidRenderer, MarkdownMermaidRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    let mermaidRendererCacheIdentity: String
    private let ascii: String

    init(identity: String, ascii: String) {
        self.mermaidRendererCacheIdentity = identity
        self.ascii = ascii
    }

    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        _ = theme
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: ascii
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class ThemeEchoMermaidRenderer: MarkdownMermaidRenderer, MarkdownMermaidRendererCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var mermaidRendererCacheIdentity: String {
        "theme-echo"
    }

    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        lock.withLock {
            callCount += 1
        }
        return MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: theme.renderCacheIdentity
        )
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}
