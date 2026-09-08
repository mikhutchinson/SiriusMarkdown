import SwiftUI

/// One native accessibility surface for the prepared grid. Custom cell styles
/// retain their own accessibility, since their geometry/actions are host-owned.
struct MarkdownTableAccessibilityModifier: ViewModifier {
    let table: MarkdownPreparedTableBlock
    let enabled: Bool
    let linkAction: MarkdownLinkAction?

    @ViewBuilder func body(content: Content) -> some View {
        #if os(macOS)
        if enabled {
            content.accessibilityHidden(true)
                .background(MarkdownTableAccessibilityHost(table: table, linkAction: linkAction))
        } else { content }
        #else
        content
        #endif
    }
}

#if os(macOS)
import AppKit

struct MarkdownTableAccessibilityHost: NSViewRepresentable {
    let table: MarkdownPreparedTableBlock
    let linkAction: MarkdownLinkAction?
    func makeNSView(context: Context) -> MarkdownTableAccessibilityHostView { .init() }
    func updateNSView(_ view: MarkdownTableAccessibilityHostView, context: Context) {
        view.update(table: table, linkAction: linkAction)
    }
}

/// The prepared value is cheap to publish. Rows/cells are materialized only when
/// an accessibility client asks for them, never during SwiftUI body evaluation.
final class MarkdownTableAccessibilityHostView: NSView {
    private var table: MarkdownPreparedTableBlock?
    fileprivate var linkAction: MarkdownLinkAction?
    private var rows: [MarkdownTableAccessibilityElement]?
    private var columns: [MarkdownTableAccessibilityElement] = []
    private var cells: [MarkdownTableAccessibilityElement] = []
    private var headers: [MarkdownTableAccessibilityElement] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(table: MarkdownPreparedTableBlock, linkAction: MarkdownLinkAction?) {
        self.table = table
        self.linkAction = linkAction
        rows = nil
        columns = []
        cells = []
        headers = []
        setAccessibilityElement(true)
        setAccessibilityRole(.table)
    }

    override func accessibilityRowCount() -> Int { (table?.rows.count ?? 0) + ((table?.header.isEmpty ?? true) ? 0 : 1) }
    override func accessibilityColumnCount() -> Int { table?.columnWidths.count ?? 0 }
    override func accessibilityRows() -> [Any]? { materialize(); return rows }
    override func accessibilityColumns() -> [Any]? { materialize(); return columns }
    override func accessibilityChildren() -> [Any]? { materialize(); return rows }
    override func accessibilityColumnHeaderUIElements() -> [Any]? { materialize(); return headers }
    override func accessibilityCell(forColumn column: Int, row: Int) -> Any? {
        guard row >= 0, column >= 0, row < accessibilityRowCount(), column < accessibilityColumnCount() else { return nil }
        materialize()
        return cells.first {
            NSLocationInRange(row, $0.accessibilityRowIndexRange()) &&
            NSLocationInRange(column, $0.accessibilityColumnIndexRange())
        }
    }

    private func materialize() {
        guard rows == nil, let table else { return }
        rows = []
        let rowCount = accessibilityRowCount()
        let columnCount = accessibilityColumnCount()
        var offsets = [Double](repeating: 0, count: columnCount + 1)
        for column in 0..<columnCount { offsets[column + 1] = offsets[column] + table.columnWidths[column] }
        let preparedRows = (table.header.isEmpty ? [] : [(table.header, table.headerPreparedLayoutHeight ?? 38)]) +
            table.rows.map { ($0.cells, $0.preparedLayoutHeight ?? 38) }
        var rowOffsets = [Double](repeating: 0, count: rowCount + 1)
        for row in 0..<rowCount { rowOffsets[row + 1] = rowOffsets[row] + preparedRows[row].1 }
        for rowIndex in 0..<rowCount {
            let row = MarkdownTableAccessibilityElement(role: .row, host: self, parent: self,
                rect: CGRect(x: 0, y: rowOffsets[rowIndex], width: offsets[columnCount], height: preparedRows[rowIndex].1))
            row.setAccessibilityIndex(rowIndex)
            var rowCells: [MarkdownTableAccessibilityElement] = []
            for cell in preparedRows[rowIndex].0 {
                let column = cell.columnIndex
                guard column >= 0, column < columnCount else { continue }
                let columnSpan = max(1, min(Int(clamping: cell.colspan), columnCount - column))
                let rowSpan = max(1, min(Int(clamping: cell.rowspan), rowCount - rowIndex))
                let element = MarkdownTableAccessibilityElement(role: .cell, host: self, parent: row,
                    rect: CGRect(x: offsets[column], y: rowOffsets[rowIndex],
                        width: offsets[column + columnSpan] - offsets[column],
                        height: rowOffsets[rowIndex + rowSpan] - rowOffsets[rowIndex]))
                element.setAccessibilityRowIndexRange(NSRange(location: rowIndex, length: rowSpan))
                element.setAccessibilityColumnIndexRange(NSRange(location: column, length: columnSpan))
                let inline = cell.inlineLayout ?? cell.selectionInlineLayout
                let attributed = inline?.attributed ?? cell.inline ?? AttributedString()
                element.setAccessibilityLabel(String(attributed.characters))
                var children: [Any] = []
                for run in attributed.runs {
                    guard let url = run.link else { continue }
                    let link = MarkdownTableAccessibilityElement(role: .link, host: self, parent: element, rect: element.localRect)
                    link.destination = url.absoluteString
                    link.setAccessibilityURL(url)
                    link.setAccessibilityLabel(String(attributed[run.range].characters))
                    children.append(link)
                }
                for piece in inline?.mathTextPieces ?? [] {
                    if case let .math(image) = piece, let tree = image.accessibilityTree {
                        children.append(MarkdownMathAccessibilityElement(node: tree.root, host: self, parent: element,
                            frameProvider: { [weak element] in element?.accessibilityFrame() ?? .zero }))
                    }
                }
                if !children.isEmpty { element.setAccessibilityChildren(children) }
                rowCells.append(element)
                cells.append(element)
                if rowIndex == 0 && !table.header.isEmpty { headers.append(element) }
            }
            row.setAccessibilityChildren(rowCells)
            rows?.append(row)
        }
        for columnIndex in 0..<columnCount {
            let column = MarkdownTableAccessibilityElement(role: .column, host: self, parent: self,
                rect: CGRect(x: offsets[columnIndex], y: 0, width: table.columnWidths[columnIndex], height: rowOffsets[rowCount]))
            column.setAccessibilityIndex(columnIndex)
            let columnHeaders = headers.filter { NSLocationInRange(columnIndex, $0.accessibilityColumnIndexRange()) }
            column.setAccessibilityHeader(columnHeaders.first)
            column.setAccessibilityChildren(cells.filter { NSLocationInRange(columnIndex, $0.accessibilityColumnIndexRange()) })
            columns.append(column)
        }
        for cell in cells where cell.accessibilityRowIndexRange().location > 0 {
            let range = cell.accessibilityColumnIndexRange()
            cell.setAccessibilityColumnHeaderUIElements(headers.filter { NSIntersectionRange(range, $0.accessibilityColumnIndexRange()).length > 0 })
        }
    }
}

// These native UI elements are confined to the main thread. Objective-C
// accessibility overrides assert that boundary before accessing actor state.
@MainActor
final class MarkdownTableAccessibilityElement: NSAccessibilityElement {
    private weak var host: MarkdownTableAccessibilityHostView?
    let localRect: CGRect
    var destination: String?
    init(role: NSAccessibility.Role, host: MarkdownTableAccessibilityHostView, parent: Any, rect: CGRect) {
        self.host = host
        self.localRect = rect
        super.init()
        setAccessibilityRole(role)
        setAccessibilityParent(parent)
    }
    nonisolated override func accessibilityFrame() -> NSRect {
        let reference = MarkdownAccessibilityMainThreadReference(value: self)
        return MainActor.assumeIsolated {
            guard let host = reference.value.host, let window = host.window else { return .zero }
            return window.convertToScreen(host.convert(reference.value.localRect, to: nil))
        }
    }
    nonisolated override func accessibilityPerformPress() -> Bool {
        let reference = MarkdownAccessibilityMainThreadReference(value: self)
        return MainActor.assumeIsolated {
            guard let host = reference.value.host, let destination = reference.value.destination else { return false }
            if let action = host.linkAction { action.open(destination) }
            else { MarkdownURLOpener.open(destination) }
            return true
        }
    }
}
#endif
