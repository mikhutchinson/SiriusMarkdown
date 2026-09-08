import Foundation
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if os(macOS)
import AppKit
import SwiftUI

@Suite(.serialized)
@MainActor
struct MarkdownTableAccessibilityTests {
    @Test
    func mountedPreparedTableExposesRowsColumnsHeadersAndLinkActions() async throws {
        let recorder = TableAccessibilityLinkRecorder()
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        configuration.linkAction = MarkdownLinkAction { recorder.append($0) }
        var stream = MarkdownStream()
        stream.append("| Name | Site |\n| --- | --- |\n| Alpha | [Visit](https://example.com) |\n")
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let host = NSHostingView(rootView: AnyView(MarkdownDocumentView(
            preparedSnapshot: prepared, configuration: configuration).frame(width: 600, height: 250)))
        let window = mount(host)
        defer { close(host, window) }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
        let table = try #require(descendants(host).compactMap { $0 as? MarkdownTableAccessibilityHostView }.first)
        #expect(table.accessibilityRole() == .table)
        #expect(table.accessibilityRowCount() == 2)
        #expect(table.accessibilityColumnCount() == 2)
        let rows = try #require(table.accessibilityRows() as? [MarkdownTableAccessibilityElement])
        let columns = try #require(table.accessibilityColumns() as? [MarkdownTableAccessibilityElement])
        #expect(rows.count == 2 && columns.count == 2)
        #expect(rows[1].accessibilityRole() == .row)
        #expect(columns[1].accessibilityRole() == .column)
        let cell = try #require(table.accessibilityCell(forColumn: 1, row: 1) as? MarkdownTableAccessibilityElement)
        #expect(cell.accessibilityRole() == .cell)
        #expect(cell.accessibilityRowIndexRange() == NSRange(location: 1, length: 1))
        #expect(cell.accessibilityColumnIndexRange() == NSRange(location: 1, length: 1))
        #expect(cell.accessibilityFrame().width > 0)
        let headers = try #require(cell.accessibilityColumnHeaderUIElements() as? [MarkdownTableAccessibilityElement])
        #expect(headers.map { $0.accessibilityLabel() } == ["Site"])
        let link = try #require((cell.accessibilityChildren() as? [MarkdownTableAccessibilityElement])?.first)
        #expect(link.accessibilityRole() == .link)
        #expect(link.accessibilityPerformPress())
        for _ in 0..<20 where recorder.values.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.values == ["https://example.com"])
    }

    @Test
    func mountedTableAccessibilityResolvesSpansAndRefreshesReplacement() throws {
        func cell(_ id: String, _ label: String, column: Int, colspan: UInt = 1, rowspan: UInt = 1) -> MarkdownPreparedTableCell {
            .init(id: id, sourceRange: MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2), inline: AttributedString(label),
                  columnIndex: column, colspan: colspan, rowspan: rowspan)
        }
        let table = MarkdownPreparedTableBlock(columnAlignments: [nil, nil],
            header: [cell("h", "Combined", column: 0, colspan: 2)],
            rows: [.init(id: "r1", cells: [cell("a", "Spanning", column: 0, rowspan: 2), cell("b", "Upper", column: 1)]),
                   .init(id: "r2", cells: [cell("c", "Lower", column: 1)])], columnWidths: [100, 120])
        let native = MarkdownTableAccessibilityHostView(frame: NSRect(x: 0, y: 0, width: 220, height: 114))
        let window = NSWindow(contentRect: native.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = native
        defer { window.contentView = nil; window.close() }
        native.update(table: table, linkAction: nil)
        let span = try #require(native.accessibilityCell(forColumn: 0, row: 1) as? MarkdownTableAccessibilityElement)
        #expect(span === (native.accessibilityCell(forColumn: 0, row: 2) as? MarkdownTableAccessibilityElement))
        #expect(span.accessibilityRowIndexRange() == NSRange(location: 1, length: 2))
        let h1 = try #require(native.accessibilityCell(forColumn: 0, row: 0) as? MarkdownTableAccessibilityElement)
        #expect(h1 === (native.accessibilityCell(forColumn: 1, row: 0) as? MarkdownTableAccessibilityElement))
        #expect(span.accessibilityFrame().height == 76)
        #expect(native.accessibilityCell(forColumn: 2, row: 0) == nil)
        let replacement = MarkdownPreparedTableBlock(columnAlignments: [nil], header: [],
            rows: [.init(id: "replacement", cells: [cell("new", "New", column: 0)])], columnWidths: [80])
        native.update(table: replacement, linkAction: nil)
        #expect(native.accessibilityRowCount() == 1)
        #expect(native.accessibilityColumnCount() == 1)
        #expect((native.accessibilityCell(forColumn: 0, row: 0) as? MarkdownTableAccessibilityElement)?.accessibilityLabel() == "New")
        #expect(native.accessibilityColumnHeaderUIElements()?.isEmpty == true)
    }

    private func mount(_ host: NSHostingView<AnyView>) -> NSWindow {
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 250)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        return window
    }
    private func close(_ host: NSHostingView<AnyView>, _ window: NSWindow) {
        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

private final class TableAccessibilityLinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.withLock { storage.append(value) } }
    var values: [String] { lock.withLock { storage } }
}
#endif
