import Foundation
import Testing
@testable import SiriusMarkdownCore

@Suite
struct MarkdownHTMLAnchorTests {
    @Test
    func supportedBlockHTMLIDsAreRetainedWithoutActiveOrInvalidIDs() throws {
        let source = "<div id=\"section\"><h2 id=\"Title\">Heading</h2><p id=\"caf&#233;\">Text</p><script id=\"active\">bad()</script><input id=\"form\"><span id=\"bad id\">bad</span></div>"
        let rich = try #require(parse(source).first?.richContent)
        #expect(rich.htmlAnchors.map(\.identifier) == ["section", "Title", "café"])
        for anchor in rich.htmlAnchors {
            let raw = String(decoding: Array(source.utf8)[anchor.sourceRange.byteRange], as: UTF8.self)
            #expect(raw.contains("id="))
        }
        #expect(!rich.blocks.map(\.text).joined().contains("bad()"))
    }

    @Test
    func inlineAndEmptyIDsKeepTheirSourceRangesWithoutVisibleText() throws {
        let source = "Before <span id=\"first\">one</span> <a id=\"empty\"></a> <span id=\"second\">two</span> after"
        let block = try #require(parse(source).first)
        let anchors = block.inlines.flatMap(\.htmlAnchors)
        #expect(anchors.map(\.identifier) == ["first", "empty", "second"])
        #expect(block.inlines.map(\.text).joined() == "Before one  two after")
        for anchor in anchors {
            let raw = String(decoding: Array(source.utf8)[anchor.sourceRange.byteRange], as: UTF8.self)
            #expect(raw.contains("id=\"\(anchor.identifier)\""))
        }
    }

    @Test
    func streamedAnchorMetadataMatchesStaticModelWithAbsoluteOffsets() throws {
        let source = "Prelude.\n\n<div id=\"container\"><p id=\"inside\">Text</p></div>\n\nAfter <a id=\"tail\"></a> text."
        let expected = parse(source)
        for chunkSize in [1, 2, 5, 17] {
            var stream = MarkdownStream()
            var cursor = source.startIndex
            while cursor < source.endIndex {
                let end = source.index(cursor, offsetBy: chunkSize, limitedBy: source.endIndex) ?? source.endIndex
                stream.append(String(source[cursor..<end]))
                cursor = end
            }
            stream.finish()
            #expect(stream.snapshot().blocks == expected)
        }
    }

    @Test
    func anchorMetadataChangesIdentityWithoutChangingLayoutFingerprint() {
        let range = MarkdownSourceRange(byteRange: 0..<10, lineRange: 1..<2)
        let first = PreparedInlineContent(runs: [MarkdownInlineRun(kind: .text, text: "", sourceRange: range, htmlAnchors: [MarkdownHTMLAnchor(identifier: "first", sourceRange: range)])])
        let second = PreparedInlineContent(runs: [MarkdownInlineRun(kind: .text, text: "", sourceRange: range, htmlAnchors: [MarkdownHTMLAnchor(identifier: "other", sourceRange: range)])])
        #expect(first.cacheFingerprint != second.cacheFingerprint)
        #expect(first.layoutCacheFingerprint == second.layoutCacheFingerprint)
    }

    private func parse(_ source: String) -> [MarkdownBlock] {
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        return stream.snapshot().blocks
    }
}
