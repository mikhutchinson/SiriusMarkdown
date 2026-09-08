import Foundation
import SiriusMarkdownCore
import Testing
@testable import SiriusMarkdownSwiftUI
#if os(macOS)
import AppKit
#endif

@Suite(.serialized)
@MainActor
struct MarkdownRichCopyTests {
    @Test
    func documentCopyProducesSemanticHTMLAndPreservesMarkdownAndPlainText() throws {
        let source = "# Heading\n\nHello **bold** and *italic* with [Example](https://example.com/?a=1&b=2).\n\n3. Three\n4. Four\n\n> Quote\n\n| Name | Value |\n| --- | --- |\n| A | B |\n"
        let (prepared, selection) = prepare(source)
        let originalPlainText = selection.selectedPlainText(in: prepared)
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: MarkdownCopyProvider(markdownSource: source))
        let html = try #require(payload.html.flatMap { String(data: $0, encoding: .utf8) })
        #expect(payload.markdown == source)
        #expect(payload.plainText == originalPlainText)
        #expect(html.contains("<h1>Heading</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
        #expect(html.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        #expect(html.contains("<ol start=\"3\">"))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<td>B</td>"))
    }

    @Test
    func partialSelectionDoesNotCopyUnselectedRunContent() throws {
        let source = "Before **strong words** after"
        let (prepared, selection) = prepare(source)
        let range = try #require(source.range(of: "strong"))
        let lower = source[..<range.lowerBound].utf8.count
        selection.selectSourceRanges([MarkdownSourceRange(byteRange: lower..<(lower + "strong".utf8.count), lineRange: 1..<2)])
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: MarkdownCopyProvider(markdownSource: source))
        let html = try #require(payload.html.flatMap { String(data: $0, encoding: .utf8) })
        #expect(payload.markdown == "strong")
        #expect(payload.plainText == "strong")
        #expect(html.contains("<strong>strong</strong>"))
        #expect(!html.contains("Before"))
        #expect(!html.contains("words"))
        #expect(!html.contains("after"))
    }

    @Test
    func copiedHTMLIsEscapedAndUsesPreparedLinkPolicy() throws {
        let source = "[denied](https://example.com/) and [active](javascript:alert(1)) `</code><script>bad</script>`"
        let configuration = MarkdownRendererConfiguration(linkPolicy: DenyCopiedLinks(), linkMetadataResolver: nil)
        let (prepared, selection) = prepare(source, configuration: configuration)
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: MarkdownCopyProvider(markdownSource: source))
        let html = try #require(payload.html.flatMap { String(data: $0, encoding: .utf8) })
        #expect(!html.contains("<a "))
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;bad&lt;/script&gt;"))
        #expect(payload.markdown == source)
    }

    @Test
    func sanitizedRichHTMLCopiesNativeSemanticsWithoutSourceTagsOrFetches() throws {
        let source = "<div><p>Hello <strong>world</strong></p><script>secret()</script><img src=\"https://example.com/remote.png\" alt=\"Picture\"></div>"
        let (prepared, selection) = prepare(source)
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: MarkdownCopyProvider(markdownSource: source))
        let html = try #require(payload.html.flatMap { String(data: $0, encoding: .utf8) })
        #expect(payload.plainText.contains("Hello world"))
        #expect(!payload.plainText.contains("<div>"))
        #expect(!payload.plainText.contains("secret()"))
        #expect(html.contains("<strong>world</strong>"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img"))
        #expect(!html.contains("remote.png"))
    }

    @Test
    func portableClipboardItemIncludesEverySuppliedRepresentation() {
        let payload = MarkdownPasteboardPayload(plainText: "plain", markdown: "**plain**", rtf: Data("rtf".utf8), html: Data("<b>plain</b>".utf8))
        let item = MarkdownPasteboard.portableItem(for: payload)
        #expect(item["public.utf8-plain-text"] as? String == payload.plainText)
        #expect(item[MarkdownPasteboard.markdownPasteboardType] as? String == payload.markdown)
        #expect(item["public.rtf"] as? Data == payload.rtf)
        #expect(item["public.html"] as? Data == payload.html)
    }

    @Test
    func emptySelectionDoesNotGenerateRichPayloads() {
        let (prepared, selection) = prepare("text")
        selection.clearSelection()
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: nil)
        #expect(payload.plainText.isEmpty)
        #expect(payload.markdown.isEmpty)
        #expect(payload.html == nil)
        #expect(payload.rtf == nil)
    }

    #if os(macOS)
    @Test
    func nativeRTFRoundTripRetainsBoldItalicAndLinkAttributes() throws {
        let (prepared, selection) = prepare("**Bold** *Italic* [Link](https://example.com)")
        let payload = selection.selectedPasteboardPayload(in: prepared, copyProvider: nil)
        let rtf = try #require(payload.rtf)
        let restored = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let bold = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        let italicIndex = (restored.string as NSString).range(of: "Italic").location
        let italic = try #require(restored.attribute(.font, at: italicIndex, effectiveRange: nil) as? NSFont)
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic))
        let linkIndex = (restored.string as NSString).range(of: "Link").location
        let link = restored.attribute(.link, at: linkIndex, effectiveRange: nil)
        #expect((link as? URL)?.absoluteString == "https://example.com" || link as? String == "https://example.com")
    }
    #endif

    private func prepare(_ source: String, configuration: MarkdownRendererConfiguration = MarkdownRendererConfiguration(linkMetadataResolver: nil)) -> (MarkdownPreparedSnapshot, MarkdownSelectionController) {
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let selection = MarkdownSelectionController()
        selection.selectAll(in: prepared)
        return (prepared, selection)
    }
}

private struct DenyCopiedLinks: MarkdownLinkPolicy {
    func evaluateLink(destination: String) -> MarkdownPolicyDecision { .deny(reason: "Test deny") }
}
