import Foundation
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if os(macOS)
import AppKit
import SwiftUI

@Suite(.serialized)
@MainActor
struct MarkdownLinkContextMenuTests {
    @Test
    func menuActionsRetainExactDestinationAndCopyURLRepresentation() throws {
        let recorder = MenuLinkRecorder()
        let destination = "https://example.com/a?q=one%20two#anchor"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let menu = MarkdownLinkContextMenu(
            destination: destination,
            linkAction: MarkdownLinkAction { recorder.record($0) },
            pasteboard: pasteboard
        )
        #expect(menu.items.map(\.title) == ["Open Link", "Copy Link Address"])
        menu.performActionForItem(at: 0)
        #expect(recorder.values == [destination])
        menu.performActionForItem(at: 1)
        #expect(pasteboard.string(forType: .string) == destination)
        #expect(pasteboard.string(forType: .URL) == destination)
    }

    @Test(arguments: ["[A linked label](https://example.com/one)", "An <a href=\"https://example.com/one\">HTML link</a>"])
    func mountedPaintedLinksHaveNativeMenusWithoutChangingSelection(markdown: String) throws {
        let recorder = MenuLinkRecorder()
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        var configuration = MarkdownRendererConfiguration.compactChat
        configuration.documentSelection = .enabled
        configuration.linkAction = MarkdownLinkAction { recorder.record($0) }
        let controller = MarkdownSelectionController()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        controller.selectAll(in: prepared)
        let before = controller.selectedSourceRanges
        let host = NSHostingView(rootView: StreamingMarkdownView(
            preparedSnapshot: prepared, configuration: configuration, selectionController: controller
        ).frame(width: 400, height: 80, alignment: .topLeading))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
        let window = makeWindow(host)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let view = try #require(descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }.first)
        let fragment = try #require(view.plan.linkFragments.first)
        let point = view.convert(CGPoint(x: fragment.rect.midX, y: fragment.rect.midY), to: nil)
        let menu = try #require(view.menu(for: event(.rightMouseDown, point: point, window: window)) as? MarkdownLinkContextMenu)
        #expect(controller.selectedSourceRanges == before)
        #expect(recorder.values.isEmpty)
        menu.performActionForItem(at: 0)
        #expect(recorder.values == ["https://example.com/one"])
        // A control-click or multi-click must not subsequently trigger a link.
        _ = view.menu(for: event(.leftMouseDown, point: point, window: window, modifiers: .control))
        view.mouseUp(with: event(.leftMouseUp, point: point, window: window, modifiers: .control))
        #expect(recorder.values.count == 1)
    }

    @Test
    func nativeLeafLinkMenusWorkWithDocumentSelectionWithoutStealingDrags() throws {
        let recorder = MenuLinkRecorder()
        let view = MarkdownAppKitNativeSelectableTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        view.isEditable = false
        view.isSelectable = false
        view.markdownLinkAction = MarkdownLinkAction { recorder.record($0) }
        view.textStorage?.setAttributedString(NSAttributedString(string: "Linked text", attributes: [
            .font: NSFont.systemFont(ofSize: 18), .link: "https://example.com/native"
        ]))
        let window = makeWindow(view)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let manager = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
        let local = CGPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
        let point = view.convert(local, to: nil)
        #expect(view.linkDestination(at: local) == "https://example.com/native")
        let menu = try #require(view.menu(for: event(.rightMouseDown, point: point, window: window)) as? MarkdownLinkContextMenu)
        menu.performActionForItem(at: 0)
        #expect(recorder.values == ["https://example.com/native"])
        view.mouseDown(with: event(.leftMouseDown, point: point, window: window))
        view.mouseDragged(with: event(.leftMouseDragged, point: CGPoint(x: point.x + 40, y: point.y), window: window))
        view.mouseUp(with: event(.leftMouseUp, point: point, window: window))
        #expect(recorder.values.count == 1)
        #expect(view.selectedRange().length == 0)
        #expect(view.linkDestination(at: CGPoint(x: 390, y: 60)) == nil)
    }

    private func makeWindow(_ content: NSView) -> NSWindow {
        let window = NSWindow(contentRect: content.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.contentView = content
        window.orderFront(nil)
        return window
    }

    private func event(_ type: NSEvent.EventType, point: CGPoint, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

private final class MenuLinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var destinations: [String] = []
    func record(_ value: String) { lock.withLock { destinations.append(value) } }
    var values: [String] { lock.withLock { destinations } }
}
#endif
