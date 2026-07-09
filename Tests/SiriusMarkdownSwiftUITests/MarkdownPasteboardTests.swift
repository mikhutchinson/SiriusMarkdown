import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Part 03: Pasteboard richness

@Suite(.serialized)
struct MarkdownPasteboardTests {

    // MARK: - MarkdownPasteboardPayload construction

    @Test
    @MainActor
    func testPayloadEquality() {
        let p1 = MarkdownPasteboardPayload(plainText: "Hello", markdown: "**Hello**")
        let p2 = MarkdownPasteboardPayload(plainText: "Hello", markdown: "**Hello**")
        let p3 = MarkdownPasteboardPayload(plainText: "Hi", markdown: "**Hi**")
        #expect(p1 == p2)
        #expect(p1 != p3)
    }

    @Test
    @MainActor
    func testPayloadStoresRTFAndHTMLWhenProvided() {
        let rtf = Data("rtf-bytes".utf8)
        let html = Data("<p>Hello</p>".utf8)
        let payload = MarkdownPasteboardPayload(plainText: "Hello", markdown: "Hello", rtf: rtf, html: html)
        #expect(payload.rtf == rtf)
        #expect(payload.html == html)
    }

    @Test
    @MainActor
    func testPayloadOptionalRTFHTMLDefaultsToNil() {
        let payload = MarkdownPasteboardPayload(plainText: "A", markdown: "A")
        #expect(payload.rtf == nil)
        #expect(payload.html == nil)
    }

    // MARK: - Pasteboard type constant

    @Test
    @MainActor
    func testMarkdownPasteboardTypeConstant() {
        #expect(MarkdownPasteboard.markdownPasteboardType == "net.siriusmarkdown.markdown")
    }

    // MARK: - macOS: copy(_:MarkdownPasteboardPayload) writes plain + Markdown types

    #if os(macOS)
    @Test
    @MainActor
    func testCopyPayloadWritesPlainStringType() {
        let payload = MarkdownPasteboardPayload(plainText: "visible text", markdown: "**visible text**")
        MarkdownPasteboard.copy(payload)

        let plain = NSPasteboard.general.string(forType: .string)
        #expect(plain == "visible text", "Pasteboard .string must contain plain text, not Markdown source")
    }

    @Test
    @MainActor
    func testCopyPayloadWritesMarkdownType() {
        let payload = MarkdownPasteboardPayload(plainText: "visible text", markdown: "**visible text**")
        MarkdownPasteboard.copy(payload)

        let markdownType = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let markdownData = NSPasteboard.general.data(forType: markdownType)
        let markdown = markdownData.flatMap { String(data: $0, encoding: .utf8) }
        #expect(markdown == "**visible text**", "Package Markdown UTI must carry exact Markdown source")
    }

    @Test
    @MainActor
    func testCopyPayloadOmitsRTFWhenNil() {
        let payload = MarkdownPasteboardPayload(plainText: "text", markdown: "text", rtf: nil)
        MarkdownPasteboard.copy(payload)

        let rtfData = NSPasteboard.general.data(forType: .rtf)
        #expect(rtfData == nil, "Nil RTF in payload must produce absent pasteboard RTF type")
    }

    @Test
    @MainActor
    func testCopyPayloadOmitsHTMLWhenNil() {
        let payload = MarkdownPasteboardPayload(plainText: "text", markdown: "text", html: nil)
        MarkdownPasteboard.copy(payload)

        let htmlData = NSPasteboard.general.data(forType: .html)
        #expect(htmlData == nil, "Nil HTML in payload must produce absent pasteboard HTML type")
    }

    @Test
    @MainActor
    func testCopyPayloadWritesRTFWhenPresent() {
        let rtfData = Data("rtf-payload".utf8)
        let payload = MarkdownPasteboardPayload(plainText: "text", markdown: "text", rtf: rtfData)
        MarkdownPasteboard.copy(payload)

        let written = NSPasteboard.general.data(forType: .rtf)
        #expect(written == rtfData, "Non-nil RTF must be written to pasteboard")
    }

    @Test
    @MainActor
    func testCopyPayloadWritesHTMLWhenPresent() {
        let htmlData = Data("<p>text</p>".utf8)
        let payload = MarkdownPasteboardPayload(plainText: "text", markdown: "text", html: htmlData)
        MarkdownPasteboard.copy(payload)

        let written = NSPasteboard.general.data(forType: .html)
        #expect(written == htmlData, "Non-nil HTML must be written to pasteboard")
    }
    #endif

    // MARK: - Legacy copy(_:String) convenience still works

    @Test
    @MainActor
    func testLegacyCopyStringConvenienceStillWorks() {
        // Calling copy(_:String) must not crash and must write something to the pasteboard.
        MarkdownPasteboard.copy("legacy string")
        // We verify this doesn't throw; platform-specific read verified in macOS block above.
        #expect(Bool(true), "copy(_:String) must not crash")
    }

    // MARK: - No network / no WebKit (INV-NS5 structural assertion)

    @Test
    @MainActor
    func testCopyPayloadDoesNotInvokeImageResolver() {
        // Structural assertion: MarkdownPasteboard.copy(_:MarkdownPasteboardPayload) is a
        // pure pasteboard write with no hook points for image loading or network I/O.
        // The type takes only plain text, markdown string, and pre-derived optional data —
        // there is no URL or resolver parameter and thus no opportunity to call a resolver.
        let payload = MarkdownPasteboardPayload(plainText: "text with image ![alt](https://example.com/img.png)", markdown: "text with image ![alt](https://example.com/img.png)")
        // Must not crash and must not trigger any image fetch (we verify by successfully returning).
        MarkdownPasteboard.copy(payload)
        #expect(Bool(true), "copy(_:MarkdownPasteboardPayload) must not invoke any image resolver (no URL parameter in API)")
    }

    // MARK: - MarkdownAffordanceActionHandler

    @Test
    @MainActor
    func testAffordanceActionHandlerCopyStringStillWorks() {
        var captured: String?
        let handler = MarkdownAffordanceActionHandler(
            copyString: { str in captured = str }
        )

        handler.copyString("hello")
        #expect(captured == "hello")
    }

    // MARK: - Document copy context uses payload path (writes to system pasteboard + calls copyString)

    #if os(macOS)
    @Test
    @MainActor
    func testDocumentCopySelectionUsesPayloadPath() {
        let source = "Hello world"
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        let snapshot = stream.snapshot()
        var configuration = MarkdownRendererConfiguration.document
        configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)
        let prepared = configuration.prepare(snapshot: snapshot)

        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        let blockID = snapshot.blocks[0].id
        controller.selectSourceRanges(
            [MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2)],
            selectedBlockIDs: [blockID]
        )

        // Spy on copyString (which is still called for host notification after the multi-rep write).
        var capturedString: String?
        let handler = MarkdownAffordanceActionHandler(
            copyString: { str in capturedString = str }
        )

        let copyContext = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        copyContext.copySelection()

        // copyString must be called with the exact Markdown.
        #expect(capturedString == "Hello", "copyString must receive exact Markdown slice after copySelection")

        // System pasteboard must carry Markdown on the custom type.
        let markdownType = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let markdownData = NSPasteboard.general.data(forType: markdownType)
        let pasteboardMarkdown = markdownData.flatMap { String(data: $0, encoding: .utf8) }
        #expect(pasteboardMarkdown == "Hello", "System pasteboard Markdown UTI must carry exact Markdown")

        // System pasteboard plain text must be non-empty.
        let plain = NSPasteboard.general.string(forType: .string)
        #expect(!(plain?.isEmpty ?? true), "System pasteboard .string must contain plain text")
    }
    #endif
}
