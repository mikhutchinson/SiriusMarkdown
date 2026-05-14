import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
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
                destination: "https://example.com/image.png"
            )
        ]
    )
    #expect(hiddenImage == "[image]")
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
@MainActor
func packagedPresetsUsePreparedNativeLinesWhileRawConfigKeepsCompatibilityFallback() throws {
    #expect(MarkdownRendererConfiguration.compactChat.inlineRenderingMode == .preparedNativeLines)
    #expect(MarkdownRendererConfiguration.document.inlineRenderingMode == .preparedNativeLines)
    #expect(MarkdownRendererConfiguration().inlineRenderingMode == .systemText)
    #expect(MarkdownRendererConfiguration(inlineRenderingMode: .systemText).inlineRenderingMode == .systemText)
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
    let view = MarkdownBlockView(block: block)
    let configuration = try #require(mirroredConfiguration(from: view))
    #expect(configuration.inlineRenderingMode == .preparedNativeLines)
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
    let sourceFiles = try swiftSourceFiles(under: root.appending(path: "Sources/SiriusMarkdownSwiftUI"))
    let directSelectionOffenders = try sourceFiles.filter { file in
        guard file.lastPathComponent != "MarkdownNativeTextSelection.swift" else {
            return false
        }
        return try String(contentsOf: file, encoding: .utf8).contains(".textSelection(.enabled)")
    }

    #expect(helper.occurrences(of: ".textSelection(.enabled)") == 1)
    #expect(directSelectionOffenders.isEmpty)
    #expect(!blockView.contains(".textSelection(.enabled)"))
    #expect(!mermaidView.contains(".textSelection(.enabled)"))
    #expect(!mermaidView.contains(".markdownNativeTextSelection("))
    #expect(!documentView.contains(".markdownNativeTextSelection("))
    #expect(!surfaceView.contains(".markdownNativeTextSelection("))
    #expect(blockView.contains(".markdownNativeTextSelection(configuration.nativeTextSelection)"))
    #expect(blockView.contains("nativeTextSelection: configuration.nativeTextSelection"))
    #expect(inlineRunsView.contains("nativeTextSelection: MarkdownNativeTextSelection = .disabled"))
    #expect(inlineRunsView.contains(".markdownNativeTextSelection(nativeTextSelection)"))
    #expect(nativeLineTextView.contains(".markdownNativeTextSelection(nativeTextSelection)"))
}

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
    let combined = [docComment, readme, runbook, bugfix].joined(separator: "\n")

    #expect(combined.contains("nativeTextSelection"))
    #expect(combined.contains("bounded text leaves"))
    #expect(combined.contains("SelectionOverlay.updateNSView"))
    #expect(combined.contains("GraphHost.flushTransactions"))
    #expect(combined.contains("NSTextField setFont:"))
    #expect(combined.contains("_invalidateEffectiveFont"))
    #expect(combined.contains("MarkdownSelectionController"))
    #expect(combined.contains("enabled-selection AppKit"))
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

    let invalidSVGs = [
        #"<svg width="0" height="160"></svg>"#,
        #"<svg width="-1" height="160"></svg>"#,
        #"<svg width="NaN" height="160"></svg>"#,
        #"<svg width="Infinity" height="160"></svg>"#,
        #"<svg width="100%" height="160"></svg>"#,
        #"<svg viewBox="0 0 0 120"></svg>"#,
        #"<svg viewBox="0 0 120 -4"></svg>"#,
        #"<not-svg width="120" height="80"></not-svg>"#
    ]

    for invalid in invalidSVGs {
        #expect(MermaidSVGGeometryParser.geometry(in: invalid) == nil)
    }
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
    #expect(afterCached.cacheHitCount == afterFirst.cacheHitCount + 1)
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
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.orderFrontRegardless()
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
func copyProviderReturnsFullDocumentMarkdown() throws {
    let markdown = "# Title\n\nBody with `code`.\n"
    let provider = MarkdownCopyProvider(markdownSource: markdown)

    #expect(provider.hasDocumentMarkdown)
    #expect(provider.markdownForDocument() == markdown)

    let session = MarkdownRenderSession(configuration: .document)
    session.append(markdown)
    session.finish()

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
private func pumpLayout<V: View>(_ hostingView: NSHostingView<V>) {
    for _ in 0..<6 {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
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

private struct InlineFixtureMathRenderer: MarkdownMathRenderer {
    func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        AttributedString("math[\(source)]")
    }
}

private final class CountingCodeHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

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

private final class CountingMathRenderer: MarkdownMathRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

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

private final class CountingMermaidRenderer: MarkdownMermaidRenderer, @unchecked Sendable {
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
