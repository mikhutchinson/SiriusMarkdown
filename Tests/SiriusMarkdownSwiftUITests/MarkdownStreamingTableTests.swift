import Foundation
import SiriusMarkdownCore
import Testing
@testable import SiriusMarkdownSwiftUI

@Suite("Streaming tables", .serialized)
struct MarkdownStreamingTableTests {
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
        let lineCount = evidence.layout(containerWidth: layoutWidth).lines.count
        let lineSpacing = Double(InlineRunsView.nativeLineSpacing(for: evidence))
        let requiredHeight = Double(lineCount) * evidence.lineHeight +
            Double(max(0, lineCount - 1)) * lineSpacing +
            Double(theme.tableVerticalCellPadding * 2)

        #expect(table.hasPreparedLayoutHeights)
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
        let small = try runGeneratedStreamingTable(rowCount: 120)
        let large = try runGeneratedStreamingTable(rowCount: 500)

        assertBoundedTableWork(small)
        assertBoundedTableWork(large)

        let preparationScale = Double(large.counters.tableCellPreparationCount) /
            Double(max(1, small.counters.tableCellPreparationCount))
        let scanScale = Double(large.counters.tableColumnWidthScanCount) /
            Double(max(1, small.counters.tableColumnWidthScanCount))
        print(
            "[streaming-table] 120 rows: publications=\(small.publicationCount) " +
            "cellPrepare=\(small.counters.tableCellPreparationCount) " +
            "cellCompare=\(small.counters.tableCellIncrementalComparisonCount) " +
            "cellReuse=\(small.counters.tableCellReuseCount) " +
            "columnScans=\(small.counters.tableColumnWidthScanCount) " +
            "widthChanges=\(small.counters.tableColumnWidthChangeCount) " +
            "wall=\(formatted(small.wallMilliseconds))ms"
        )
        print(
            "[streaming-table] 500 rows: publications=\(large.publicationCount) " +
            "cellPrepare=\(large.counters.tableCellPreparationCount) " +
            "cellCompare=\(large.counters.tableCellIncrementalComparisonCount) " +
            "cellReuse=\(large.counters.tableCellReuseCount) " +
            "columnScans=\(large.counters.tableColumnWidthScanCount) " +
            "widthChanges=\(large.counters.tableColumnWidthChangeCount) " +
            "wall=\(formatted(large.wallMilliseconds))ms " +
            "scale(prep=\(formatted(preparationScale)), scan=\(formatted(scanScale)))"
        )

        #expect(preparationScale < 5.25)
        #expect(scanScale < 5.25)
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

private func runGeneratedStreamingTable(rowCount: Int) throws -> StreamingTableRun {
    let markdown = tablePrefix + (0..<rowCount).map(tableRow).joined()
    return try runStreamingTable(markdown: markdown, rowCount: rowCount)
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

private func assertBoundedTableWork(_ run: StreamingTableRun) {
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
