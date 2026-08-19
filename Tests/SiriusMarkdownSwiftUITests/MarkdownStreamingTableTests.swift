import Foundation
import SiriusMarkdownCore
import Testing
@testable import SiriusMarkdownSwiftUI

@Suite("Streaming tables", .serialized)
struct MarkdownStreamingTableTests {
    @Test
    func stableRowRenderTokenTracksPresentationInputsWithoutClosureIdentity() {
        let content = MarkdownContentFingerprint(domain: "row-content")
        let widths = MarkdownContentFingerprint(domain: "row-widths")
        let presentation = MarkdownContentFingerprint(domain: "row-presentation")
        let layout = MarkdownStreamingTableRowLayoutToken(
            id: "row-1",
            contentFingerprint: content,
            columnWidthFingerprint: widths,
            columnWidthRevision: 3,
            layoutContextIdentity: "theme-1",
            inlineRenderingMode: .coreTextPaintedLines,
            nativeTextSelection: .disabled,
            preparedLayoutHeight: 38
        )
        let action = MarkdownLinkAction { _ in }
        let copiedAction = action
        let token = MarkdownStreamingTableRowRenderToken(
            layoutToken: layout,
            presentationFingerprint: presentation,
            columnAlignments: [.left, .right],
            linkActionIdentity: action.renderIdentity
        )
        let copiedToken = MarkdownStreamingTableRowRenderToken(
            layoutToken: layout,
            presentationFingerprint: presentation,
            columnAlignments: [.left, .right],
            linkActionIdentity: copiedAction.renderIdentity
        )
        let replacementToken = MarkdownStreamingTableRowRenderToken(
            layoutToken: layout,
            presentationFingerprint: presentation,
            columnAlignments: [.left, .right],
            linkActionIdentity: MarkdownLinkAction { _ in }.renderIdentity
        )

        #expect(token == copiedToken)
        #expect(token != replacementToken)
        #expect(token != MarkdownStreamingTableRowRenderToken(
            layoutToken: layout,
            presentationFingerprint: presentation,
            columnAlignments: [.center, .right],
            linkActionIdentity: action.renderIdentity
        ))
        #expect(token != MarkdownStreamingTableRowRenderToken(
            layoutToken: layout,
            presentationFingerprint: MarkdownContentFingerprint(domain: "replacement-presentation"),
            columnAlignments: [.left, .right],
            linkActionIdentity: action.renderIdentity
        ))
    }

    @Test
    func partialCellTextIsVisibleBeforeItsRowTerminator() throws {
        var stream = MarkdownStream()
        stream.append(tablePrefix)
        stream.append(
            "| Item 1 with partial text | 1.25 | Sentence 1, with punctuation. | " +
            "[reference 1](https://example.com/items/1"
        )

        let snapshot = stream.snapshot()
        let table = try #require(snapshot.blocks.first(where: { $0.kind == .table })?.table)
        let visibleText = table.rows.flatMap { $0 }.map(\.text).joined(separator: " | ")

        #expect(visibleText.contains("Item 1 with partial text"))
        #expect(visibleText.contains("example.com/items/1"))
        #expect(!snapshot.isFinished)
    }

    @Test
    func completedRowsAndCellsKeepIdentityWhileTailCellGrows() throws {
        let recorder = MarkdownDiagnosticsRecorder()
        let configuration = MarkdownRendererConfiguration(
            diagnosticsRecorder: recorder
        )
        var stream = MarkdownStream()
        stream.append(tablePrefix + tableRow(0))
        var prepared = configuration.prepare(snapshot: stream.snapshot())
        let firstTable = try preparedTable(in: prepared)
        let completedRow = try #require(firstTable.rows.first)
        let completedCellIDs = completedRow.cells.map(\.id)
        let completedCellFingerprints = completedRow.cells.map(\.contentFingerprint)
        let completedPreparedLayoutHeight = completedRow.preparedLayoutHeight

        stream.append("| Item 1 partial")
        prepared = configuration.prepare(snapshot: stream.snapshot(), reusing: prepared)
        let partialTable = try preparedTable(in: prepared)
        let initialTailID = try #require(partialTable.rows.last?.cells.first?.id)

        stream.append(" text continues inside the same cell")
        prepared = configuration.prepare(snapshot: stream.snapshot(), reusing: prepared)
        let grownTable = try preparedTable(in: prepared)
        let reusedCompletedRow = try #require(grownTable.rows.first)
        let grownTailID = try #require(grownTable.rows.last?.cells.first?.id)
        let counters = recorder.snapshot()

        #expect(reusedCompletedRow.id == completedRow.id)
        #expect(reusedCompletedRow.cells.map(\.id) == completedCellIDs)
        #expect(reusedCompletedRow.cells.map(\.contentFingerprint) == completedCellFingerprints)
        #expect(reusedCompletedRow.preparedLayoutHeight == completedPreparedLayoutHeight)
        #expect(grownTailID == initialTailID)
        #expect(counters.tableCellReuseCount >= completedCellIDs.count * 2)
        #expect(counters.tableCellPreparationCount <= counters.tableCellReuseCount)
    }

    @Test
    func finalStreamedTableMatchesOneShotSemanticsAndPreparation() throws {
        let markdown = tablePrefix + (0..<12).map(tableRow).joined() +
            "| uneven final row | 12.75 | Sentence only. |\n"
        let streaming = try runStreamingTable(markdown: markdown, rowCount: 13)

        var oneShotStream = MarkdownStream()
        oneShotStream.append(markdown)
        oneShotStream.finish()
        let oneShot = MarkdownRendererConfiguration.compactChat.prepare(
            snapshot: oneShotStream.snapshot()
        )
        let streamedTable = try preparedTable(in: streaming.prepared)
        let oneShotTable = try preparedTable(in: oneShot)

        #expect(streaming.prepared.snapshot.blocks == oneShot.snapshot.blocks)
        #expect(streamedTable.columnAlignments == oneShotTable.columnAlignments)
        #expect(streamedTable.columnWidths == oneShotTable.columnWidths)
        #expect(streamedTable.header.map(\.id) == oneShotTable.header.map(\.id))
        #expect(streamedTable.rows.map(\.id) == oneShotTable.rows.map(\.id))
        #expect(
            streamedTable.rows.flatMap(\.cells).map(\.contentHash) ==
                oneShotTable.rows.flatMap(\.cells).map(\.contentHash)
        )
        #expect(streamedTable.columnAlignments == [.left, .right, .center, nil, nil, nil])
        #expect(streamedTable.headerPreparedLayoutHeight == oneShotTable.headerPreparedLayoutHeight)
        #expect(
            streamedTable.rows.map(\.preparedLayoutHeight) ==
                oneShotTable.rows.map(\.preparedLayoutHeight)
        )
        #expect(streamedTable.hasPreparedLayoutHeights)

        let linkedCell = try #require(
            streaming.prepared.snapshot.blocks
                .first(where: { $0.kind == .table })?
                .table?.rows.first?[safe: 3]
        )
        #expect(linkedCell.inlines.contains {
            $0.destination == "https://example.com/items/0"
        })
        let preparedLinkedCell = try #require(streamedTable.rows.first?.cells[safe: 3])
        #expect(preparedLinkedCell.inlineLayout?.prepared.sourceRange == linkedCell.sourceRange)
        #expect(preparedLinkedCell.sourceRange.byteRange.lowerBound < preparedLinkedCell.sourceRange.byteRange.upperBound)
    }

    @Test
    func suppliedUserBubbleStressTablePreparesEnoughHeightForEveryWrappedLine() throws {
        var stream = MarkdownStream()
        stream.append(userBubbleStressTable)
        stream.finish()

        var theme = MarkdownTheme.compactChat
        theme.tableHorizontalCellPadding = 12
        theme.tableVerticalCellPadding = 9
        let configuration = MarkdownRendererConfiguration(theme: theme)
        let table = try preparedTable(
            in: configuration.prepare(snapshot: stream.snapshot())
        )
        let firstRow = try #require(table.rows.first)
        let evidence = try #require(firstRow.cells[safe: 2]?.inlineLayout)
        let evidenceWidth = table.columnWidths[2] - Double(theme.tableHorizontalCellPadding * 2)
        let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
            for: evidence,
            containerWidth: evidenceWidth
        )
        let expectedLayout = evidence.layout(containerWidth: layoutWidth)
        let lineCount = expectedLayout.lines.count
        let lineSpacing = Double(InlineRunsView.nativeLineSpacing(for: evidence))
        let requiredHeight = Double(lineCount) * evidence.lineHeight +
            Double(max(0, lineCount - 1)) * lineSpacing +
            Double(theme.tableVerticalCellPadding * 2)

        #expect(table.hasPreparedLayoutHeights)
        #expect(evidence.defaultLayoutWidth == evidenceWidth)
        #expect(evidence.initialLayoutResult == expectedLayout)
        #if canImport(CoreText)
        #expect(evidence.coreTextLinePlan != nil)
        #endif
        #expect(lineCount >= 3)
        #expect((firstRow.preparedLayoutHeight ?? 0) >= requiredHeight)
        #expect(table.rows.dropFirst().allSatisfy { ($0.preparedLayoutHeight ?? 0) >= 38 })
    }

    @Test
    func incompleteDelimiterTransitionFinishAndResetRemainCorrect() async throws {
        var stream = MarkdownStream()
        stream.append("| A | B |\n| :--")
        #expect(!stream.snapshot().blocks.contains { $0.kind == .table })

        stream.append("- | ---: |\n| partial")
        let active = stream.snapshot()
        let activeTableBlock = try #require(active.blocks.first(where: { $0.kind == .table }))
        #expect(activeTableBlock.table?.rows.first?.first?.text == "partial")

        stream.append(" value | 4.2 |\n\nAfter the table")
        let transitioned = stream.snapshot()
        let sealedTableBlock = try #require(transitioned.blocks.first(where: { $0.kind == .table }))
        #expect(sealedTableBlock.id == activeTableBlock.id)
        #expect(sealedTableBlock.isSealed)
        #expect(transitioned.blocks.contains { $0.kind == .paragraph && $0.text.contains("After the table") })

        let session = await MainActor.run { MarkdownRenderSession(configuration: .compactChat) }
        await MainActor.run { session.append(tablePrefix + tableRow(0)) }
        await session.waitUntilIdle()
        let populatedCount = await MainActor.run { session.preparedSnapshot.snapshot.sourceLength }
        #expect(populatedCount > 0)

        await MainActor.run { session.reset() }
        await session.waitUntilIdle()
        let resetSnapshot = await MainActor.run { session.preparedSnapshot.snapshot }
        #expect(resetSnapshot.sourceLength == 0)
        #expect(resetSnapshot.blocks.isEmpty)

        await MainActor.run {
            session.append(tablePrefix + tableRow(1))
            session.finish()
        }
        await session.waitUntilIdle()
        let finished = await MainActor.run { session.preparedSnapshot.snapshot }
        #expect(finished.isFinished)
        #expect(finished.blocks.first?.table?.rows.count == 1)
    }

    @Test
    func tablePreparationWorkIsNearLinearFor120And500Rows() throws {
        // Parse one real GFM table to source the semantic rows, then publish
        // growing snapshots directly. Timing `MarkdownStream.snapshot()` here
        // used to make this purported preparation benchmark spend about 95%
        // of its runtime reparsing the one mutable table tail. Parser/streaming
        // equivalence is covered above; this gate now measures what it names.
        let corpus = try parsedTablePreparationCorpus(rowCount: 500)
        let small = try runTablePreparationPublications(corpus: corpus, rowCount: 120)
        let large = try runTablePreparationPublications(corpus: corpus, rowCount: 500)

        assertBoundedTableWork(small)
        assertBoundedTableWork(large)

        let expectedRowScale = Double(large.rowCount) / Double(small.rowCount)
        let preparationScale = Double(large.counters.tableCellPreparationCount) /
            Double(max(1, small.counters.tableCellPreparationCount))
        let comparisonScale = Double(large.counters.tableCellIncrementalComparisonCount) /
            Double(max(1, small.counters.tableCellIncrementalComparisonCount))
        let scanScale = Double(large.counters.tableColumnWidthScanCount) /
            Double(max(1, small.counters.tableColumnWidthScanCount))
        let wallScale = large.preparationMilliseconds /
            max(0.001, small.preparationMilliseconds)
        print(
            "[streaming-table] 120 rows: publications=\(small.publicationCount) " +
            "cellPrepare=\(small.counters.tableCellPreparationCount) " +
            "cellCompare=\(small.counters.tableCellIncrementalComparisonCount) " +
            "retainedCells=\(small.counters.tableCellReuseCount) " +
            "columnScans=\(small.counters.tableColumnWidthScanCount) " +
            "widthChanges=\(small.counters.tableColumnWidthChangeCount) " +
            "prepareWall=\(formatted(small.preparationMilliseconds))ms"
        )
        print(
            "[streaming-table] 500 rows: publications=\(large.publicationCount) " +
            "cellPrepare=\(large.counters.tableCellPreparationCount) " +
            "cellCompare=\(large.counters.tableCellIncrementalComparisonCount) " +
            "retainedCells=\(large.counters.tableCellReuseCount) " +
            "columnScans=\(large.counters.tableColumnWidthScanCount) " +
            "widthChanges=\(large.counters.tableColumnWidthChangeCount) " +
            "prepareWall=\(formatted(large.preparationMilliseconds))ms " +
            "scale(expected=\(formatted(expectedRowScale)), " +
            "prep=\(formatted(preparationScale)), compare=\(formatted(comparisonScale)), " +
            "scan=\(formatted(scanScale)), wall=\(formatted(wallScale)))"
        )

        let maximumScale = expectedRowScale * 1.25
        #expect(preparationScale < maximumScale)
        #expect(comparisonScale < maximumScale)
        #expect(scanScale < maximumScale)
        #expect(wallScale < expectedRowScale * 1.5)
    }
}

private struct StreamingTableRun {
    var rowCount: Int
    var columnCount: Int
    var publicationCount: Int
    var prepared: MarkdownPreparedSnapshot
    var counters: MarkdownDiagnosticsCounters
    var wallMilliseconds: Double
}

private struct TablePreparationRun {
    var rowCount: Int
    var columnCount: Int
    var publicationCount: Int
    var prepared: MarkdownPreparedSnapshot
    var counters: MarkdownDiagnosticsCounters
    var preparationMilliseconds: Double
}

private struct ParsedTablePreparationCorpus {
    var block: MarkdownBlock
    var table: MarkdownTableBlock
}

private let tablePrefix = """
| Item | Decimal | Sentence | Link | Detail | Tail |
| :--- | ---: | :---: | --- | --- | --- |

"""

private let userBubbleStressTable = """
| Feature | Expected | Very long evidence column | Status |
| --- | --- | --- | ---: |
| Code | Horizontal containment | A deliberately long table value that must stay within the finite user bubble instead of widening the transcript | 1 |
| HTML | Native rendering | Sanitized rich blocks and decorated links | 2 |
| Math | Native rendering | x^2 + alpha and a display equation | 3 |

"""

private func tableRow(_ index: Int) -> String {
    "| Item \(index) with varied text \(String(repeating: "x", count: index % 11)) " +
        "| \(index).\(String(format: "%02d", (index * 17) % 100)) " +
        "| Sentence \(index), with punctuation. " +
        "| [reference \(index)](https://example.com/items/\(index)) " +
        "| detail-\(index)-\(String(repeating: "z", count: index % 7)) " +
        "| tail \(index) |\n"
}

private func rowChunks(_ row: String) -> [String] {
    let urlMarker = "https://example.com/items/"
    let urlStart = row.range(of: urlMarker).map {
        row.distance(from: row.startIndex, to: $0.lowerBound)
    } ?? row.count / 2
    let cutOffsets = Set([
        min(row.count, 9),
        min(row.count, urlStart + "https://example".count),
        row.count
    ]).sorted()

    var chunks: [String] = []
    var lower = row.startIndex
    for offset in cutOffsets where offset > row.distance(from: row.startIndex, to: lower) {
        let upper = row.index(row.startIndex, offsetBy: offset)
        chunks.append(String(row[lower..<upper]))
        lower = upper
    }
    return chunks
}

private func runStreamingTable(markdown: String, rowCount: Int) throws -> StreamingTableRun {
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        diagnosticsRecorder: recorder
    )
    var stream = MarkdownStream()
    var publicationCount = 0
    var prepared: MarkdownPreparedSnapshot?
    let clock = ContinuousClock()
    let start = clock.now

    stream.append(tablePrefix)
    prepared = configuration.prepare(snapshot: stream.snapshot(), reusing: prepared)
    publicationCount += 1

    let suffix = String(markdown.dropFirst(tablePrefix.count))
    for row in suffix.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
        let rowWithNewline = String(row) + "\n"
        for chunk in rowChunks(rowWithNewline) {
            stream.append(chunk)
            prepared = configuration.prepare(snapshot: stream.snapshot(), reusing: prepared)
            publicationCount += 1
        }
    }

    stream.finish()
    prepared = configuration.prepare(snapshot: stream.snapshot(), reusing: prepared)
    publicationCount += 1
    let elapsed = clock.now - start
    let finalPrepared = try #require(prepared)
    let table = try preparedTable(in: finalPrepared)
    #expect(table.rows.count == rowCount)

    return StreamingTableRun(
        rowCount: rowCount,
        columnCount: table.columnWidths.count,
        publicationCount: publicationCount,
        prepared: finalPrepared,
        counters: recorder.snapshot(),
        wallMilliseconds: milliseconds(elapsed)
    )
}

private func parsedTablePreparationCorpus(rowCount: Int) throws -> ParsedTablePreparationCorpus {
    let markdown = tablePrefix + (0..<rowCount).map(tableRow).joined()
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    let snapshot = stream.snapshot()
    let block = try #require(snapshot.blocks.first(where: { $0.kind == .table }))
    let table = try #require(block.table)
    #expect(table.rows.count == rowCount)
    return ParsedTablePreparationCorpus(block: block, table: table)
}

private func runTablePreparationPublications(
    corpus: ParsedTablePreparationCorpus,
    rowCount: Int
) throws -> TablePreparationRun {
    try #require(rowCount > 0 && rowCount <= corpus.table.rows.count)
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    let clock = ContinuousClock()
    var prepared: MarkdownPreparedSnapshot?
    var preparationMilliseconds = 0.0

    func sourceEnd(for publishedRowCount: Int) -> (byte: Int, line: Int) {
        if publishedRowCount < corpus.table.rows.count,
           let nextCell = corpus.table.rows[publishedRowCount].first
        {
            return (
                nextCell.sourceRange.byteRange.lowerBound,
                nextCell.sourceRange.lineRange.lowerBound
            )
        }
        return (
            corpus.block.sourceRange.byteRange.upperBound,
            corpus.block.sourceRange.lineRange.upperBound
        )
    }

    func publish(rows publishedRowCount: Int, isFinished: Bool) {
        var table = corpus.table
        table.rows = Array(corpus.table.rows.prefix(publishedRowCount))
        var block = corpus.block
        block.table = table
        block.isSealed = isFinished
        block.contentHash = UInt64(publishedRowCount)
        let end = sourceEnd(for: publishedRowCount)
        block.sourceRange = MarkdownSourceRange(
            byteRange: block.sourceRange.byteRange.lowerBound..<end.byte,
            lineRange: block.sourceRange.lineRange.lowerBound..<end.line
        )
        let snapshot = MarkdownSnapshot(
            blocks: [block],
            sourceLength: end.byte,
            generation: publishedRowCount + (isFinished ? 1 : 0),
            isFinished: isFinished
        )

        let start = clock.now
        prepared = configuration.prepare(snapshot: snapshot, reusing: prepared)
        preparationMilliseconds += milliseconds(clock.now - start)
    }

    publish(rows: 0, isFinished: false)
    for publishedRowCount in 1...rowCount {
        publish(rows: publishedRowCount, isFinished: false)
    }
    publish(rows: rowCount, isFinished: true)

    let finalPrepared = try #require(prepared)
    let finalTable = try preparedTable(in: finalPrepared)
    let oneShotTable = try preparedTable(
        in: MarkdownRendererConfiguration().prepare(snapshot: finalPrepared.snapshot)
    )
    #expect(finalTable.rows.count == rowCount)
    #expect(finalTable.rows.map(\.id).allSatisfy { !$0.isEmpty })
    #expect(finalTable.header.map(\.id) == oneShotTable.header.map(\.id))
    #expect(finalTable.rows.map(\.id) == oneShotTable.rows.map(\.id))
    #expect(finalTable.rows.flatMap(\.cells).map(\.contentHash) ==
        oneShotTable.rows.flatMap(\.cells).map(\.contentHash))
    #expect(finalTable.columnWidths == oneShotTable.columnWidths)
    #expect(finalTable.rows.map(\.preparedLayoutHeight) ==
        oneShotTable.rows.map(\.preparedLayoutHeight))

    return TablePreparationRun(
        rowCount: rowCount,
        columnCount: finalTable.columnWidths.count,
        publicationCount: rowCount + 2,
        prepared: finalPrepared,
        counters: recorder.snapshot(),
        preparationMilliseconds: preparationMilliseconds
    )
}

private func assertBoundedTableWork(_ run: TablePreparationRun) {
    let finalCellCount = (run.rowCount + 1) * run.columnCount
    #expect(run.counters.tableCellPreparationCount <= finalCellCount * 5)
    #expect(run.counters.tableCellIncrementalComparisonCount <= finalCellCount * 5)
    #expect(run.counters.tableColumnWidthScanCount <= finalCellCount * 6)
    #expect(run.counters.tableColumnWidthChangeCount <= run.columnCount * 6 + 2)
    #expect(run.counters.tableCellReuseCount > run.counters.tableCellPreparationCount)
}

private func preparedTable(in snapshot: MarkdownPreparedSnapshot) throws -> MarkdownPreparedTableBlock {
    for item in snapshot.items {
        if case let .block(block, content) = item, block.kind == .table {
            return try #require(content.table)
        }
    }
    Issue.record("Expected a prepared table block")
    throw StreamingTableTestError.missingTable
}

private enum StreamingTableTestError: Error {
    case missingTable
}

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 +
        Double(duration.components.attoseconds) / 1e15
}

private func formatted(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
