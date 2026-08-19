import CoreGraphics
import Testing
@testable import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Test
func authorizedHTMLColspanUsesTheCombinedPreparedColumnWidth() throws {
    let table = try preparedHTMLTable(
        """
        <table>
          <thead><tr><th>First</th><th>Second</th></tr></thead>
          <tbody><tr><td colspan="2">Content spanning both columns</td></tr></tbody>
        </table>
        """
    )
    let spanningCell = try #require(table.rows.first?.cells.first)
    let inline = try #require(spanningCell.inlineLayout)

    #expect(spanningCell.columnIndex == 0)
    #expect(spanningCell.colspan == 2)
    #expect(table.columnWidths.count == 2)
    #expect(spanningCell.preparedWidth == table.columnWidths.reduce(0, +))
    #expect(
        inline.defaultLayoutWidth == spanningCell.preparedWidth -
            MarkdownTheme.compactChat.renderTableHorizontalCellPadding * 2
    )
}

@Test
func authorizedHTMLRowspanReservesCoveredColumnsAndCombinedHeight() throws {
    let table = try preparedHTMLTable(
        """
        <table>
          <thead><tr><th>First</th><th>Second</th></tr></thead>
          <tbody>
            <tr><td rowspan="2">Spans two rows</td><td>Upper right</td></tr>
            <tr><td>Lower right</td></tr>
          </tbody>
        </table>
        """
    )
    let firstRow = try #require(table.rows.first)
    let secondRow = try #require(table.rows.last)
    let spanningCell = try #require(firstRow.cells.first)
    let lowerRight = try #require(secondRow.cells.first)
    let firstHeight = try #require(firstRow.preparedLayoutHeight)
    let secondHeight = try #require(secondRow.preparedLayoutHeight)

    #expect(table.hasSpans)
    #expect(spanningCell.columnIndex == 0)
    #expect(spanningCell.rowspan == 2)
    #expect(lowerRight.columnIndex == 1)
    #expect(spanningCell.preparedHeight == firstHeight + secondHeight)
    #expect(lowerRight.preparedColumnOffset == table.columnWidths[0])
    let firstBoundary = try #require(firstRow.separatorSegments)
    #expect(firstBoundary.count == 1)
    #expect(firstBoundary[0].offset == table.columnWidths[0])
    #expect(firstBoundary[0].width == table.columnWidths[1])
    #expect(secondRow.separatorSegments?.first?.offset == 0)
    #expect(secondRow.separatorSegments?.first?.width == table.columnWidths.reduce(0, +))
}

@Test
func malformedHTMLTableSpansRemainBounded() throws {
    let table = try preparedHTMLTable(
        """
        <table><tbody><tr><td colspan="10000">Bounded</td></tr></tbody></table>
        """
    )
    let cell = try #require(table.rows.first?.cells.first ?? table.header.first)

    #expect(table.columnWidths.count <= 256)
    #expect(cell.colspan <= 256)
    #expect(cell.preparedWidth == table.columnWidths.reduce(0, +))
}

@Test
@MainActor
func authorizedHTMLSpanSelectionUsesLogicalCellColumns() throws {
    let context = try preparedHTMLTableContext(
        """
        <table>
          <thead><tr><th>First</th><th>Second</th></tr></thead>
          <tbody>
            <tr><td rowspan="2">Spans two rows</td><td>Upper right</td></tr>
            <tr><td>Lower right</td></tr>
          </tbody>
        </table>
        """
    )
    let lowerRight = try #require(context.table.rows.last?.cells.first)
    let fragments = MarkdownDocumentSelectionFragment.fragments(
        for: context.block,
        preparedContent: context.content,
        rect: CGRect(x: 0, y: 0, width: 400, height: 240)
    )
    let lowerRightFragment = try #require(fragments.first {
        $0.sourceRange.byteRange.overlaps(lowerRight.sourceRange.byteRange)
    })

    #expect(lowerRight.columnIndex == 1)
    #expect(lowerRightFragment.rect.minX >= 200)
}

private func preparedHTMLTable(_ html: String) throws -> MarkdownPreparedTableBlock {
    try preparedHTMLTableContext(html).table
}

private func preparedHTMLTableContext(
    _ html: String
) throws -> (block: MarkdownBlock, content: MarkdownPreparedBlockContent, table: MarkdownPreparedTableBlock) {
    var stream = MarkdownStream()
    stream.append(html)
    stream.finish()
    let outerBlock = try #require(stream.snapshot().blocks.first)
    let preparedOuter = MarkdownRendererConfiguration().prepare(block: outerBlock)
    let richTable = try #require(
        preparedOuter.richContent?.blocks.first { $0.block.kind == .table }
    )
    return (
        richTable.block,
        richTable.preparedContent,
        try #require(richTable.preparedContent.table)
    )
}
