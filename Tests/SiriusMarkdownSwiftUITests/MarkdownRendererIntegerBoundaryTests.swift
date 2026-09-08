import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite
struct MarkdownRendererIntegerBoundaryTests {
    @Test
    func manuallyPreparedTableSpansAndColumnsAreBounded() throws {
        let cell = MarkdownPreparedTableCell(
            id: "extreme-prepared-cell",
            sourceRange: MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2),
            columnIndex: Int.max,
            colspan: .max,
            rowspan: .max
        )
        let table = MarkdownPreparedTableBlock(columnAlignments: [], header: [cell], rows: [])
        let preparedCell = try #require(table.header.first)
        #expect(table.columnWidths.count == 256)
        #expect(preparedCell.columnIndex == 255)
        #expect(preparedCell.colspan == 1)
        #expect(preparedCell.rowspan == 1)
    }

    @Test
    func publicTableSpansAboveIntMaxAreBoundedBeforeConversion() throws {
        let range = MarkdownSourceRange(byteRange: 0..<7, lineRange: 1..<2)
        let cell = MarkdownTableCell(
            sourceRange: range,
            text: "Bounded",
            inlines: [MarkdownInlineRun(kind: .text, text: "Bounded")],
            colspan: .max,
            rowspan: .max
        )
        let block = MarkdownBlock(
            id: MarkdownBlockID("extreme-spans"),
            kind: .table,
            sourceRange: range,
            text: "Bounded",
            table: MarkdownTableBlock(columnAlignments: [], header: [cell], rows: []),
            isSealed: true
        )
        let table = try #require(MarkdownRendererConfiguration().prepare(block: block).table)
        let preparedCell = try #require(table.header.first)
        #expect(table.columnWidths.count == 256)
        #expect(preparedCell.colspan == 256)
        #expect(preparedCell.rowspan == 1)
        #expect(preparedCell.preparedWidth.isFinite)
    }

    @Test
    func orderedListOrdinalsSaturateWithoutOverflow() {
        #expect(MarkdownOrderedListMarkerStyleConfiguration.resolvedOrdinal(start: nil, index: 2) == 3)
        #expect(MarkdownOrderedListMarkerStyleConfiguration.resolvedOrdinal(start: 7, index: 2) == 9)
        #expect(MarkdownOrderedListMarkerStyleConfiguration.resolvedOrdinal(start: .max, index: 0) == Int.max)
        #expect(MarkdownOrderedListMarkerStyleConfiguration.resolvedOrdinal(start: UInt(Int.max), index: 1) == Int.max)
        #expect(MarkdownOrderedListMarkerStyleConfiguration.resolvedOrdinal(start: 1, index: Int.max) == Int.max)
    }
}
