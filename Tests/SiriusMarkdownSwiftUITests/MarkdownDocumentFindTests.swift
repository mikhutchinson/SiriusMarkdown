import Foundation
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite
struct MarkdownDocumentFindTests {
    private struct ImageMathRenderer: MarkdownMathRenderer {
        func renderedMath(_ source: String, isBlock: Bool) -> AttributedString { AttributedString(source) }
        func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
            .image(MarkdownPreparedMathImage(imageData: Data(), scale: 2, pointWidth: 10,
                                            pointHeight: 10, ascent: 8, descent: 2, latex: source))
        }
    }

    @Test
    func rasterizedMathDoesNotExposeItsHiddenLatexToTextFind() {
        var stream = MarkdownStream()
        stream.append("left $x^2$ right\n\n$$\nx^2\n$$\n")
        stream.finish()
        var configuration = MarkdownRendererConfiguration()
        configuration.mathRenderer = ImageMathRenderer()
        let index = MarkdownPreparedDocumentIndex(preparedSnapshot: configuration.prepare(snapshot: stream.snapshot()))
        #expect(index.matches(for: "left").count == 1)
        #expect(index.matches(for: "x^2").isEmpty)
    }

    @Test
    func searchesRenderedInlineTextAcrossFormattingAndPreservesUnicodeSource() throws {
        var stream = MarkdownStream()
        stream.append("😀 café **hello** world and e\u{301}lan.\n")
        stream.finish()
        let index = makeIndex(stream)
        let cafe = try #require(index.matches(for: "café").first)
        #expect(stream.markdown(in: cafe.sourceRange) == "café")
        let emoji = try #require(index.matches(for: "😀").first)
        #expect(stream.markdown(in: emoji.sourceRange) == "😀")
        let combined = try #require(index.matches(for: "élan", options: [.diacriticInsensitive]).first)
        #expect(stream.markdown(in: combined.sourceRange) == "e\u{301}lan")
        let styled = try #require(index.matches(for: "hello world").first)
        #expect(styled.text == "hello world")
        #expect(stream.markdown(in: styled.sourceRange).contains("hello"))
        #expect(index.matches(for: "**hello**").isEmpty)
    }

    @Test
    func caseAndDiacriticOptionsAreIndependentAndEmptyQueryHasNoMatches() {
        var stream = MarkdownStream()
        stream.append("Café cafe CAFÉ")
        stream.finish()
        let index = makeIndex(stream)
        #expect(index.matches(for: "café").count == 2)
        #expect(index.matches(for: "café", options: []).isEmpty)
        #expect(index.matches(for: "cafe", options: [.caseInsensitive, .diacriticInsensitive]).count == 3)
        #expect(index.matches(for: "").isEmpty)
    }

    @Test
    func headingsHaveDeterministicUniqueSlugsAndUnicodeFragments() throws {
        var stream = MarkdownStream()
        stream.append("# Hello *World*\n\n# Hello World\n\n# Hello World-1\n\n# Hello World\n\n## Café\n")
        stream.finish()
        let index = makeIndex(stream)
        #expect(index.headings.map(\.id) == ["hello-world", "hello-world-1", "hello-world-1-1", "hello-world-2", "café"])
        #expect(index.headings.map(\.title).first == "Hello World")
        let cafe = try #require(index.heading(forFragment: "#caf%C3%A9"))
        #expect(cafe.level == 2)
        #expect(stream.markdown(in: cafe.sourceRange).contains("Café"))
        #expect(index.heading(forFragment: "#missing") == nil)
    }

    @Test
    func nestedPreparedContentIsIndexedOnceAndHTMLSourceIsNotSearchable() throws {
        var stream = MarkdownStream()
        stream.append("""
        > Quoted needle

        - List needle
          - Nested needle

        | Header | Other |
        | --- | --- |
        | Table needle | End |

        <div><h2>Native heading</h2><p>HTML needle &amp; visible</p><script>hiddenSecret()</script></div>
        """)
        stream.finish()
        let index = makeIndex(stream)
        #expect(index.matches(for: "needle").count == 5)
        #expect(index.matches(for: "hiddenSecret").isEmpty)
        #expect(index.matches(for: "<h2>").isEmpty)
        #expect(index.matches(for: "Header Other").isEmpty)
        let entity = try #require(index.matches(for: "&").first)
        #expect(stream.markdown(in: entity.sourceRange).contains("&amp;"))
        let anchor = try #require(index.heading(forFragment: "native-heading"))
        #expect(stream.snapshot().blocks.contains { $0.id == anchor.blockID && $0.kind == .htmlBlock })
    }

    @Test
    @MainActor
    func controllerWrapsNavigationAndRetainsSelectedMatchAcrossAppend() throws {
        var stream = MarkdownStream()
        stream.append("needle first\n\nneedle second\n\n")
        let controller = MarkdownDocumentFindController(index: makeIndex(stream))
        controller.query = "needle"
        #expect(controller.matches.count == 2)
        let second = try #require(controller.next())
        #expect(controller.currentMatchIndex == 1)
        stream.append("needle third")
        controller.update(index: makeIndex(stream))
        #expect(controller.matches.count == 3)
        #expect(controller.currentMatch?.id == second.id)
        #expect(controller.next()?.id == controller.matches.last?.id)
        #expect(controller.next()?.id == controller.matches.first?.id)
        #expect(controller.previous()?.id == controller.matches.last?.id)
        controller.query = "absent"
        #expect(controller.currentMatch == nil)
        #expect(controller.next() == nil)
    }

    private func makeIndex(_ stream: MarkdownStream) -> MarkdownPreparedDocumentIndex {
        var configuration = MarkdownRendererConfiguration()
        configuration.linkMetadataResolver = nil
        return MarkdownPreparedDocumentIndex(preparedSnapshot: configuration.prepare(snapshot: stream.snapshot()))
    }
}
