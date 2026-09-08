import Testing
@testable import SiriusMarkdownCore

@Suite
struct MarkdownHTMLNormalizationRegressionTests {
    @Test
    func inlineHTMLPreservesMarkdownCodeSpanSpacing() throws {
        let block = try #require(parse("Before `a  b` <em>after</em>").first)
        let code = try #require(block.inlines.first { $0.presentation.contains(.code) })
        #expect(code.text == "a  b")
    }

    @Test
    func inlineHTMLPreservesRepeatedExplicitBreaks() throws {
        let block = try #require(parse("Before<br><br>after<br>").first)
        #expect(block.inlines.filter { $0.kind == .hardBreak }.count == 3)
        #expect(block.inlines.map(\.text).joined() == "Before\n\nafter\n")
    }

    @Test
    func blockHTMLPreservesRepeatedAndTrailingExplicitBreaks() throws {
        let block = try #require(parse("<p>one<br><br>two<br></p>").first?.richContent?.blocks.first)
        #expect(block.inlines.filter { $0.kind == .hardBreak }.count == 3)
        #expect(block.text == "one\n\ntwo\n")
    }

    @Test
    func blockHTMLPreservesNonbreakingAndTypographicSpaces() throws {
        let block = try #require(parse("<p>&nbsp;one&nbsp;&nbsp;two&emsp;three&nbsp;</p>").first?.richContent?.blocks.first)
        #expect(block.text == "\u{00A0}one\u{00A0}\u{00A0}two\u{2003}three\u{00A0}")
    }

    @Test
    func blockHTMLKeepsWhitespaceBetweenNestedInlineSiblings() throws {
        let block = try #require(parse("<p><span>one </span><strong>two </strong><em>three</em></p>").first?.richContent?.blocks.first)
        #expect(block.text == "one two three")
    }

    @Test
    func blockHTMLCollapsesWhitespaceAcrossInlineElementBoundaries() throws {
        let block = try #require(parse("<p>one <strong>  two  </strong>   three</p>").first?.richContent?.blocks.first)
        #expect(block.text == "one two three")
    }

    @Test
    func authoredCustomElementsCannotImpersonateMarkdownPlaceholders() throws {
        for tag in ["sirius-markdown-run", "SIRIUS-MARKDOWN-RUN", "sirius-markdown-run-internal"] {
            let block = try #require(parse("Before <\(tag) data-index=\"0\">inside</\(tag)> after").first)
            #expect(block.inlines.map(\.text).joined() == "Before inside after")
            #expect(block.inlines.allSatisfy { !$0.presentation.contains(.html) })
        }
    }

    private func parse(_ markdown: String) -> [MarkdownBlock] {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        return stream.snapshot().blocks
    }
}
