import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

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
    let wrapped = InlineRunsView.lineBrokenAttributedString(for: inlineLayout, containerWidth: 32)
    let afterLayoutUnits = inlineLayout.measured.segments.flatMap(\.units)

    #expect(beforeLayoutUnits.isEmpty)
    #expect(afterLayoutUnits.isEmpty)
    #expect(String(wrapped.characters).contains("abcdefghijklmnopqrstuvwxyz"))
}

@Test
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
    let wrapped = InlineRunsView.lineBrokenAttributedString(for: inlineLayout, containerWidth: 160)
    #expect(String(wrapped.characters).contains("\n"))

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
