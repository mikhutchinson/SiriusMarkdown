#if os(macOS)
import AppKit
import Foundation
import SiriusMarkdownCore
import SwiftUI
import Testing
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized)
struct MarkdownAlternateLinkSurfaceTests {
    @Test @MainActor
    func alternateRenderingModesMountLinkMenusAndForwardHostActions() throws {
        for mode in [MarkdownInlineRenderingMode.systemText, .preparedNativeLines] {
            try assertNativeLinkSurface(mode: mode, includesMath: false)
        }
    }

    @Test
    func explicitLineSourceMapAccountsForUnicodeWhitespaceAndEmptyLines() {
        let prepared = PreparedInlineContent(runs: [
            MarkdownInlineRun(kind: .text, text: "😀 first "),
            MarkdownInlineRun(kind: .text, text: "🔗"),
            MarkdownInlineRun(kind: .text, text: " Label")
        ])
        let layout = InlineLayoutResult(lines: [
            InlineLineRange(byteRange: 0..<10, width: 100),
            InlineLineRange(byteRange: 10..<10, width: 0),
            InlineLineRange(byteRange: 11..<21, width: 100)
        ], naturalWidth: 100, height: 60)
        let ranges = MarkdownNativeLineSourceMap.runRanges(prepared: prepared, layout: layout)
        #expect(ranges[0] == nil)
        #expect(ranges[1] == NSRange(location: 11, length: 2))
        #expect(ranges[2] == NSRange(location: 13, length: 6))
    }

    @Test @MainActor
    func multilineDecoratedNativeLinesKeepTextAndAttachmentPlacement() throws {
        try assertNativeLinkSurface(mode: .preparedNativeLines, includesMath: false, multiline: true)
    }

    @Test @MainActor
    func mathParagraphsKeepLinkMenusInEveryRenderingMode() throws {
        for mode in [MarkdownInlineRenderingMode.systemText, .preparedNativeLines, .coreTextPaintedLines] {
            try assertNativeLinkSurface(mode: mode, includesMath: true)
        }
    }

    @MainActor
    private func assertNativeLinkSurface(mode: MarkdownInlineRenderingMode, includesMath: Bool, multiline: Bool = false) throws {
        let destination = "https://example.com/route"
        var stream = MarkdownStream()
        let prefix = multiline ? String(repeating: "Multilingual 😀 wrapping text ", count: 4) : "Before "
        stream.append(prefix + (includesMath ? "$x$ [Example](\(destination))" : "[Example](\(destination))"))
        stream.finish()
        let block = try #require(stream.snapshot().blocks.first)
        let recorder = ActionRecorder()
        let configuration = MarkdownRendererConfiguration(
            inlineRenderingMode: mode,
            nativeTextSelection: .disabled,
            linkAction: MarkdownLinkAction { recorder.record($0) },
            linkMetadataResolver: SurfaceIconResolver(),
            mathRenderer: LinkSurfaceMathRenderer()
        )
        var prepared = try #require(configuration.prepare(block: block).inlineLayout)
        prepared.initialLayoutResult = prepared.layout(containerWidth: 360, allowsOverwideFallback: true)
        let view = InlineRunsView(
            prepared: prepared,
            linkAction: configuration.linkAction,
            inlineRenderingMode: mode,
            nativeTextSelection: .disabled
        ).preparedContainerWidth(360)
        let host = NSHostingView(rootView: view.frame(width: 360, height: 120, alignment: .topLeading))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let textView = try #require(findTextView(host))
        #expect(!textView.isSelectable, "Document selection must retain ownership of drags")
        let storage = try #require(textView.textStorage)
        let manager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        manager.ensureLayout(for: container)
        let label = (storage.string as NSString).range(of: "Example")
        #expect(label.location != NSNotFound)
        #expect(!textView.preparedAttachments.isEmpty)
        for attachment in textView.preparedAttachments {
            #expect(storage.attribute(.attachment, at: attachment.characterRange.location, effectiveRange: nil) != nil)
            #expect((storage.string as NSString).substring(with: attachment.characterRange) == "\u{FFFC}")
        }
        if multiline {
            #expect(storage.string.contains("\n"))
            let visible = storage.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            #expect(visible.contains("Example"))
            #expect(visible.filter { $0 == "😀" }.count == 4)
        }
        guard label.location != NSNotFound else { return }
        let glyphRange = manager.glyphRange(forCharacterRange: NSRange(location: label.location, length: 1), actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphRange, in: container)
        let point = CGPoint(x: bounds.midX + textView.textContainerOrigin.x, y: bounds.midY + textView.textContainerOrigin.y)
        #expect(textView.linkDestination(at: point) == destination)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: textView.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(textView.menu(for: event))
        #expect(menu.items.map(\.title) == ["Open Link", "Copy Link Address"])
        menu.performActionForItem(at: 0)
        #expect(recorder.destinations == [destination])
        if includesMath {
            var attachments = 0
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if value != nil { attachments += 1 }
            }
            #expect(attachments > 0)
        }
    }

    @MainActor
    private func findTextView(_ view: NSView) -> MarkdownAppKitNativeSelectableTextView? {
        if let textView = view as? MarkdownAppKitNativeSelectableTextView { return textView }
        return view.subviews.lazy.compactMap { findTextView($0) }.first
    }
}

private final class ActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func record(_ destination: String) { lock.withLock { values.append(destination) } }
    var destinations: [String] { lock.withLock { values } }
}

private struct SurfaceIconResolver: MarkdownLinkMetadataResolver {
    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        .metadata(MarkdownLinkMetadata(destination: destination, decoration: .favicon(MarkdownLinkIcon(
            sourceURL: destination.appendingPathComponent("favicon.png"),
            data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!,
            mimeType: "image/png", pixelWidth: 1, pixelHeight: 1
        ))))
    }
    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        cachedResolution(for: destination) ?? .unavailable
    }
}

private struct LinkSurfaceMathRenderer: MarkdownMathRenderer {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString { AttributedString(source) }
    func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
        .image(MarkdownPreparedMathImage(
            imageData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!,
            scale: 1, pointWidth: 18, pointHeight: 12, ascent: 9, descent: 3, latex: source
        ))
    }
}
#endif
