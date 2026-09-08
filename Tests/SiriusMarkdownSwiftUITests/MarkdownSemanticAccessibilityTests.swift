#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownSemanticAccessibilityTests {
    @Test(arguments: ["A long linked label that wraps across several lines", "שלום"],
          ["https://example.com/access", "#conclusion"])
    func paintedSemanticLinksExposeOneAccessibleAction(label: String, destination: String) throws {
        var stream = MarkdownStream(); stream.append("[\(label)](\(destination))"); stream.finish()
        let configuration = MarkdownRendererConfiguration()
        let block = try #require(stream.snapshot().blocks.first)
        let prepared = try #require(configuration.prepare(block: block).inlineLayout)
        let layout = prepared.layout(containerWidth: 100, allowsOverwideFallback: true)
        let view = MarkdownCoreTextPaintedNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 200))
        view.plan = MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout)
        let recorder = AXDestinationRecorder()
        view.linkAction = MarkdownLinkAction { recorder.record($0) }
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.reconcileAccessibleLinks()
        let links = try #require(view.accessibilityChildren() as? [MarkdownAccessibleLink])
        #expect(links.count == 1)
        let link = try #require(links.first)
        #expect(link.accessibilityRole() == .link)
        #expect(link.isAccessibilityEnabled())
        #expect(link.accessibilityLabel() == label)
        #expect(!link.accessibilityFrame().isEmpty)
        #expect(!link.localFrame.isNull)
        #expect(link.accessibilityPerformPress())
        #expect(recorder.values == [destination])
        view.reconcileAccessibleLinks()
        let again = try #require(view.accessibilityChildren() as? [MarkdownAccessibleLink])
        #expect(again.first === link)
    }

    @Test
    func deniedPaintedLinksDoNotExposeEnabledActions() throws {
        var stream = MarkdownStream()
        stream.append("[Denied](javascript:alert)")
        stream.finish()
        let configuration = MarkdownRendererConfiguration()
        let block = try #require(stream.snapshot().blocks.first)
        let prepared = try #require(configuration.prepare(block: block).inlineLayout)
        let view = MarkdownCoreTextPaintedNSView(frame: .init(x: 0, y: 0, width: 200, height: 80))
        view.plan = MarkdownCoreTextPaintedLinePlan.make(
            prepared: prepared, layout: prepared.layout(containerWidth: 200, allowsOverwideFallback: true))
        view.reconcileAccessibleLinks()
        #expect((view.accessibilityChildren() as? [MarkdownAccessibleLink])?.isEmpty == true)
    }

}

private final class AXDestinationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var destinations: [String] = []
    func record(_ value: String) { lock.withLock { destinations.append(value) } }
    var values: [String] { lock.withLock { destinations } }
}
#endif
