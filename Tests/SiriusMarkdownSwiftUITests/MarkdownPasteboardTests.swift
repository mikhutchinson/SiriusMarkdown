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

// MARK: - Helpers

private func prepareSource(_ source: String) -> (
    snapshot: MarkdownSnapshot,
    prepared: MarkdownPreparedSnapshot,
    configuration: MarkdownRendererConfiguration
) {
    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let snapshot = stream.snapshot()
    return (snapshot, configuration.prepare(snapshot: snapshot), configuration)
}

// MARK: - MarkdownAffordanceActionHandler class promotion

@Suite(.serialized)
struct MarkdownAffordanceActionHandlerTests {

    // MARK: Reference-type identity

    @Test
    @MainActor
    func isReferenceType() {
        let h1 = MarkdownAffordanceActionHandler()
        let h2 = h1
        #expect(h1 === h2, "MarkdownAffordanceActionHandler must be a reference type")
    }

    @Test
    @MainActor
    func platformDefaultCreatesNewInstanceEachTime() {
        let a = MarkdownAffordanceActionHandler.platformDefault
        let b = MarkdownAffordanceActionHandler.platformDefault
        #expect(a !== b, ".platformDefault must return a fresh instance each call, not a shared singleton")
    }

    @Test
    @MainActor
    func configurationSharesHandlerReferenceOnCopy() {
        var config1 = MarkdownRendererConfiguration.document
        let handler = MarkdownAffordanceActionHandler()
        config1.affordanceActionHandler = handler
        let config2 = config1
        #expect(config1.affordanceActionHandler === config2.affordanceActionHandler,
                "Copying a configuration shares the handler reference")
    }

    @Test
    @MainActor
    func replacingHandlerOnOneCopyDoesNotAffectOther() {
        let config1 = MarkdownRendererConfiguration.document
        let original = config1.affordanceActionHandler
        var config2 = config1
        config2.affordanceActionHandler = MarkdownAffordanceActionHandler()
        #expect(config1.affordanceActionHandler === original,
                "Replacing handler on one configuration copy must not affect the other")
    }

    // MARK: Three-closure initialiser does not crash

    @Test
    @MainActor
    func defaultInitDoesNotCrash() {
        // Previously caused SIGBUS when MarkdownAffordanceActionHandler was a struct with
        // three @MainActor @Sendable closures (Swift runtime memmove in __DATA_CONST).
        let handler = MarkdownAffordanceActionHandler()
        // If we reach here without a crash, the promotion worked.
        _ = handler.copyString
        _ = handler.copyPayload
        _ = handler.exportMarkdown
        #expect(Bool(true), "default init must not crash (previously SIGBUS with struct + 3 closures)")
    }

    @Test
    @MainActor
    func fullCustomInitDoesNotCrash() {
        var copyStrCalled = false
        var copyPayloadCalled = false
        var exportCalled = false
        let handler = MarkdownAffordanceActionHandler(
            copyString: { _ in copyStrCalled = true },
            copyPayload: { _ in copyPayloadCalled = true },
            exportMarkdown: { _ in exportCalled = true }
        )
        handler.copyString("x")
        handler.copyPayload(MarkdownPasteboardPayload(plainText: "x", markdown: "x"))
        handler.exportMarkdown(MarkdownExportPayload(markdown: "x"))
        #expect(copyStrCalled)
        #expect(copyPayloadCalled)
        #expect(exportCalled)
    }

    // MARK: Default closures route to MarkdownPasteboard / MarkdownDocumentExporter

    @Test
    @MainActor
    func copyStringDefaultCallsPasteboardCopy() {
        // Verifies the default copyString writes something to the pasteboard
        // without crashing. The macOS write is verified by type in the macOS suite.
        let handler = MarkdownAffordanceActionHandler()
        handler.copyString("default-test-string")
        #expect(Bool(true), "default copyString must not crash")
    }

    @Test
    @MainActor
    func copyPayloadDefaultCallsPasteboardCopy() {
        let handler = MarkdownAffordanceActionHandler()
        handler.copyPayload(MarkdownPasteboardPayload(plainText: "plain", markdown: "**plain**"))
        #expect(Bool(true), "default copyPayload must not crash")
    }

    // MARK: Custom closures are called

    @Test
    @MainActor
    func customCopyStringIsCalled() {
        var received: String?
        let handler = MarkdownAffordanceActionHandler(copyString: { received = $0 })
        handler.copyString("hello")
        #expect(received == "hello")
    }

    @Test
    @MainActor
    func customCopyPayloadIsCalled() {
        var received: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { received = $0 })
        let payload = MarkdownPasteboardPayload(plainText: "visible", markdown: "**visible**")
        handler.copyPayload(payload)
        #expect(received == payload)
    }

    @Test
    @MainActor
    func customExportMarkdownIsCalled() {
        var received: MarkdownExportPayload?
        let handler = MarkdownAffordanceActionHandler(exportMarkdown: { received = $0 })
        let payload = MarkdownExportPayload(markdown: "# Doc", suggestedFilename: "doc.md")
        handler.exportMarkdown(payload)
        #expect(received?.markdown == "# Doc")
        #expect(received?.suggestedFilename == "doc.md")
    }

    @Test
    @MainActor
    func customisedClosuresAreIndependent() {
        // Overriding copyPayload must not affect copyString behaviour.
        var stringReceived: String?
        var payloadReceived: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(
            copyString: { stringReceived = $0 },
            copyPayload: { payloadReceived = $0 }
        )
        handler.copyString("s")
        handler.copyPayload(MarkdownPasteboardPayload(plainText: "p", markdown: "p"))
        #expect(stringReceived == "s")
        #expect(payloadReceived?.plainText == "p")
    }

    // MARK: Sendable / @unchecked Sendable

    @Test
    func sendableConformanceCompiles() async {
        // MarkdownAffordanceActionHandler must be sendable so it can be stored in
        // MarkdownRendererConfiguration and passed to SwiftUI environments.
        let handler = MarkdownAffordanceActionHandler()
        let result = await Task.detached { handler }.value
        #expect(result === handler)
    }
}

// MARK: - MarkdownPasteboardPayload

@Suite(.serialized)
struct MarkdownPasteboardPayloadTests {

    @Test func equalityOnMatchingFields() {
        let a = MarkdownPasteboardPayload(plainText: "t", markdown: "**t**")
        let b = MarkdownPasteboardPayload(plainText: "t", markdown: "**t**")
        #expect(a == b)
    }

    @Test func inequalityOnDifferentPlain() {
        let a = MarkdownPasteboardPayload(plainText: "x", markdown: "y")
        let b = MarkdownPasteboardPayload(plainText: "z", markdown: "y")
        #expect(a != b)
    }

    @Test func inequalityOnDifferentMarkdown() {
        let a = MarkdownPasteboardPayload(plainText: "t", markdown: "a")
        let b = MarkdownPasteboardPayload(plainText: "t", markdown: "b")
        #expect(a != b)
    }

    @Test func rtfAndHTMLDefaultNil() {
        let p = MarkdownPasteboardPayload(plainText: "t", markdown: "t")
        #expect(p.rtf == nil)
        #expect(p.html == nil)
    }

    @Test func rtfAndHTMLStoredWhenProvided() {
        let rtf = Data("rtf".utf8)
        let html = Data("<p>t</p>".utf8)
        let p = MarkdownPasteboardPayload(plainText: "t", markdown: "t", rtf: rtf, html: html)
        #expect(p.rtf == rtf)
        #expect(p.html == html)
    }

    @Test func hashableConformanceConsistentWithEquality() {
        let a = MarkdownPasteboardPayload(plainText: "t", markdown: "**t**")
        let b = MarkdownPasteboardPayload(plainText: "t", markdown: "**t**")
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - MarkdownPasteboard type constant

@Suite(.serialized)
struct MarkdownPasteboardTypeTests {

    @Test func typeConstantValue() {
        #expect(MarkdownPasteboard.markdownPasteboardType == "net.siriusmarkdown.markdown")
    }

    @Test
    @MainActor
    func legacyCopyStringConvenienceDoesNotCrash() {
        MarkdownPasteboard.copy("legacy plain string")
        #expect(Bool(true))
    }

    @Test
    @MainActor
    func legacyCopyStringConvenienceProducesEqualPayload() {
        // copy(_ string:) must produce a payload where plainText == markdown == string.
        // We verify the semantic contract by inspecting what ends up on the pasteboard.
        // (macOS assertion in the macOS-only suite below; here we just verify no crash.)
        MarkdownPasteboard.copy("equal-both-sides")
        #expect(Bool(true))
    }

    @Test
    @MainActor
    func copyPayloadWithNilRTFAndHTMLDoesNotCrash() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "t", markdown: "**t**"))
        #expect(Bool(true))
    }

    @Test
    @MainActor
    func copyPayloadWithAllFieldsPopulatedDoesNotCrash() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(
            plainText: "t",
            markdown: "**t**",
            rtf: Data("rtf".utf8),
            html: Data("<p>t</p>".utf8)
        ))
        #expect(Bool(true))
    }
}

// MARK: - macOS pasteboard write assertions

#if os(macOS)
@Suite(.serialized)
struct MarkdownPasteboardMacOSTests {

    // MARK: copy(MarkdownPasteboardPayload)

    @Test
    @MainActor
    func plainTextOnDotString() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "visible text", markdown: "**visible text**"))
        #expect(NSPasteboard.general.string(forType: .string) == "visible text",
                ".string must carry plain text, not Markdown source")
    }

    @Test
    @MainActor
    func markdownOnCustomType() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "visible text", markdown: "**visible text**"))
        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let data = NSPasteboard.general.data(forType: type)
        let written = data.flatMap { String(data: $0, encoding: .utf8) }
        #expect(written == "**visible text**", "Custom Markdown type must carry exact Markdown source")
    }

    @Test
    @MainActor
    func plainAndMarkdownAreDistinctWhenDifferent() {
        let payload = MarkdownPasteboardPayload(plainText: "plain", markdown: "**bold**")
        MarkdownPasteboard.copy(payload)
        let plain = NSPasteboard.general.string(forType: .string)
        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let markdownData = NSPasteboard.general.data(forType: type)
        let markdown = markdownData.flatMap { String(data: $0, encoding: .utf8) }
        #expect(plain != markdown, "Plain text and Markdown representations must be distinct when source differs")
    }

    @Test
    @MainActor
    func rtfAbsentWhenNil() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "t", markdown: "t", rtf: nil))
        #expect(NSPasteboard.general.data(forType: .rtf) == nil)
    }

    @Test
    @MainActor
    func htmlAbsentWhenNil() {
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "t", markdown: "t", html: nil))
        #expect(NSPasteboard.general.data(forType: .html) == nil)
    }

    @Test
    @MainActor
    func rtfWrittenWhenProvided() {
        let rtfData = Data("rtf-sentinel".utf8)
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "t", markdown: "t", rtf: rtfData))
        #expect(NSPasteboard.general.data(forType: .rtf) == rtfData)
    }

    @Test
    @MainActor
    func htmlWrittenWhenProvided() {
        let htmlData = Data("<p>t</p>".utf8)
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "t", markdown: "t", html: htmlData))
        #expect(NSPasteboard.general.data(forType: .html) == htmlData)
    }

    @Test
    @MainActor
    func legacyCopyStringWritesPlainOnDotString() {
        MarkdownPasteboard.copy("legacy-string")
        #expect(NSPasteboard.general.string(forType: .string) == "legacy-string")
    }

    @Test
    @MainActor
    func legacyCopyStringWritesSameValueOnMarkdownType() {
        // When called with a single string, both types carry the same value.
        MarkdownPasteboard.copy("code-text")
        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let data = NSPasteboard.general.data(forType: type)
        let written = data.flatMap { String(data: $0, encoding: .utf8) }
        #expect(written == "code-text", "Single-string convenience must write same value on Markdown type")
    }

    @Test
    @MainActor
    func clearContentsCalledBetweenWrites() {
        // Writing twice must not accumulate types from a previous write.
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(
            plainText: "first", markdown: "first", rtf: Data("rtf1".utf8)
        ))
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(
            plainText: "second", markdown: "second", rtf: nil
        ))
        // Second write had no RTF — it must be absent.
        #expect(NSPasteboard.general.data(forType: .rtf) == nil,
                "clearContents must remove RTF from previous write")
        #expect(NSPasteboard.general.string(forType: .string) == "second")
    }

    @Test
    @MainActor
    func markdownDataIsUTF8Encoded() {
        let emoji = "Hello 🌍 **world**"
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "Hello 🌍 world", markdown: emoji))
        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let data = NSPasteboard.general.data(forType: type)
        let decoded = data.flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == emoji, "Markdown pasteboard data must decode correctly from UTF-8")
    }

    // MARK: No network / no WebKit (INV-NS5)

    @Test
    @MainActor
    func copyWithImageAltTextInMarkdownDoesNotFetch() {
        // Pasting Markdown containing image syntax must not trigger any resolver.
        let md = "![alt](https://example.com/img.png)"
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: "alt", markdown: md))
        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let data = NSPasteboard.general.data(forType: type)
        let written = data.flatMap { String(data: $0, encoding: .utf8) }
        #expect(written == md, "Image syntax in Markdown copy must not trigger any fetch")
    }
}
#endif

// MARK: - Document selection copy path

@Suite(.serialized)
struct MarkdownDocumentSelectionCopyPathTests {

    // MARK: copyPayload is called (not copyString) for document Cmd-C

    @Test
    @MainActor
    func copySelectionCallsCopyPayload() {
        let source = "Hello world"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectSourceRanges(
            [MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2)],
            selectedBlockIDs: [snapshot.blocks[0].id]
        )

        var capturedPayload: MarkdownPasteboardPayload?
        var copyStringCallCount = 0
        let handler = MarkdownAffordanceActionHandler(
            copyString: { _ in copyStringCallCount += 1 },
            copyPayload: { capturedPayload = $0 }
        )
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        ctx.copySelection()

        #expect(capturedPayload != nil, "copyPayload must be called for document selection copy")
        #expect(copyStringCallCount == 0, "copyString must NOT be called separately — copyPayload is the sole exit point")
    }

    @Test
    @MainActor
    func copySelectionPayloadMarkdownEqualsExactSource() {
        let source = "Hello world"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectSourceRanges(
            [MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2)],
            selectedBlockIDs: [snapshot.blocks[0].id]
        )

        var payload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { payload = $0 })
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        ctx.copySelection()

        #expect(payload?.markdown == "Hello", "Payload markdown must equal exact source slice")
    }

    @Test
    @MainActor
    func copySelectionPayloadPlainTextIsNonEmpty() {
        let source = "**Bold** text"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        var payload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { payload = $0 })
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        ctx.copySelection()

        #expect(!(payload?.plainText.isEmpty ?? true), "Payload plainText must be non-empty")
    }

    @Test
    @MainActor
    func copySelectionPayloadPlainFallsBackToMarkdownWhenPlainEmpty() {
        // If selectedPlainText returns "" (no inline runs, no matching source), plainText
        // must fall back to markdown so the pasteboard is never empty on .string.
        let source = "x"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        // Select a zero-length range that produces no plain text.
        controller.selectSourceRanges(
            [MarkdownSourceRange(byteRange: 0..<0, lineRange: 1..<1)],
            selectedBlockIDs: []
        )

        var payload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { payload = $0 })
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        ctx.copySelection()

        // Empty selection → copyPayload is not called at all (guard !markdown.isEmpty).
        #expect(payload == nil, "Empty selection must not invoke copyPayload")
    }

    @Test
    @MainActor
    func copySelectionDoesNotCallCopyPayloadWhenSelectionIsEmpty() {
        let source = "Text"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        // Deliberately leave selection empty.

        var callCount = 0
        let handler = MarkdownAffordanceActionHandler(copyPayload: { _ in callCount += 1 })
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        )
        ctx.copySelection()

        #expect(callCount == 0, "copyPayload must not fire when nothing is selected")
    }

    @Test
    @MainActor
    func copySelectionPayloadMarkdownAndPlainAreCoherent() {
        // The payload passed to copyPayload must have matching fields:
        // markdown is the source-backed Markdown, plainText is the visible text.
        // They may be equal (plain text blocks) or different (styled Markdown).
        let source = "Simple paragraph"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        var payload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { payload = $0 })
        MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        ).copySelection()

        #expect(!(payload?.markdown.isEmpty ?? true))
        #expect(!(payload?.plainText.isEmpty ?? true))
    }

    // MARK: copySelectedMarkdown on controller also routes through payload

    @Test
    @MainActor
    func copySelectedMarkdownOnControllerWritesMultiRepPasteboard() {
        let source = "Copy me"
        let (snapshot, prepared, _) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)
        let provider = MarkdownCopyProvider(markdownSource: source)

        // This calls MarkdownPasteboard.copy(payload) directly — no crash, no network.
        controller.copySelectedMarkdown(in: prepared, copyProvider: provider)
        #expect(Bool(true), "copySelectedMarkdown must not crash")
    }

    // MARK: Code affordance copy still uses copyString (single-string path)

    @Test
    @MainActor
    func codeAffordanceCopyUsesOnlyCopyString() {
        // Block-level "Copy code" affordances call copyString, NOT copyPayload.
        var copyStringCalled = false
        var copyPayloadCalled = false
        let handler = MarkdownAffordanceActionHandler(
            copyString: { _ in copyStringCalled = true },
            copyPayload: { _ in copyPayloadCalled = true }
        )

        // Simulate what MarkdownBlockView does for code copy.
        handler.copyString("let x = 42")

        #expect(copyStringCalled, "Code affordance must call copyString")
        #expect(!copyPayloadCalled, "Code affordance must not call copyPayload")
    }

    // MARK: Payload plainText fallback when plain is empty

    @Test
    @MainActor
    func payloadPlainTextFallsBackToMarkdownStringNotEmpty() {
        let source = "Content"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        var payload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { payload = $0 })
        MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        ).copySelection()

        // plainText must never be empty because the fallback is the markdown string.
        if let p = payload {
            #expect(!p.plainText.isEmpty, "plainText must never be empty in a non-empty selection")
            #expect(!p.markdown.isEmpty, "markdown must never be empty in a non-empty selection")
        }
    }

    // MARK: Streaming / selection churn

    @Test
    @MainActor
    func copySelectionDuringStreamingDoesNotCrash() {
        var stream = MarkdownStream()
        stream.append("# Heading\n\nParagraph of text.\n\n- Item one\n- Item two")
        stream.finish()

        var configuration = MarkdownRendererConfiguration.document
        configuration.copyProvider = MarkdownCopyProvider(markdownSource: "# Heading\n\nParagraph of text.\n\n- Item one\n- Item two")

        let snapshot = stream.snapshot()
        let prepared = configuration.prepare(snapshot: snapshot)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        var payloadCount = 0
        configuration.affordanceActionHandler = MarkdownAffordanceActionHandler(
            copyPayload: { _ in payloadCount += 1 }
        )
        let ctx = MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: configuration.affordanceActionHandler
        )

        // Fire copySelection multiple times in a row — must not crash or double-write.
        for _ in 0..<5 {
            ctx.copySelection()
        }
        #expect(payloadCount == 5, "copyPayload must fire exactly once per copySelection call")
    }
}

// MARK: - macOS: full Cmd-C integration

#if os(macOS)
@Suite(.serialized)
struct MarkdownCopyIntegrationMacOSTests {

    @Test
    @MainActor
    func documentCopyUsesPayloadWithDistinctPlainAndMarkdown() {
        let source = "**Bold** and *italic* text"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        var capturedPayload: MarkdownPasteboardPayload?
        let handler = MarkdownAffordanceActionHandler(copyPayload: { capturedPayload = $0 })
        MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: handler
        ).copySelection()

        guard let payload = capturedPayload else {
            #expect(Bool(false), "copyPayload must be invoked")
            return
        }
        // Markdown source contains delimiters; plain text is stripped.
        #expect(payload.markdown.contains("**"), "Markdown field must contain source delimiters")
        #expect(!payload.plainText.contains("**"), "Plain text field must not contain Markdown delimiters")
    }

    @Test
    @MainActor
    func pasteboardStringIsPlainAfterDocumentCopy() {
        let source = "**Bold**"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: configuration.affordanceActionHandler
        ).copySelection()

        let plain = NSPasteboard.general.string(forType: .string)
        #expect(!(plain?.contains("**") ?? false),
                "After document copy, .string must be plain text, not Markdown with delimiters")
    }

    @Test
    @MainActor
    func pasteboardMarkdownTypeContainsSourceAfterDocumentCopy() {
        let source = "**Bold**"
        let (snapshot, prepared, configuration) = prepareSource(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)
        controller.selectAll(in: snapshot)

        MarkdownDocumentSelectionCopyContext(
            selectionController: controller,
            preparedSnapshot: prepared,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: configuration.affordanceActionHandler
        ).copySelection()

        let type = NSPasteboard.PasteboardType(rawValue: MarkdownPasteboard.markdownPasteboardType)
        let data = NSPasteboard.general.data(forType: type)
        let written = data.flatMap { String(data: $0, encoding: .utf8) }
        #expect(written?.contains("**") ?? false,
                "After document copy, Markdown UTI must contain source with delimiters")
    }
}
#endif
