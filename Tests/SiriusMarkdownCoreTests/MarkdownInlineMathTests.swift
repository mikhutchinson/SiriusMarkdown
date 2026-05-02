import Testing
import SiriusMarkdownCore

@Test
func inlineMathIsDetectedWithoutRewritingCodeSpans() throws {
    var stream = MarkdownStream()
    stream.append("Inline $x^2$ survives, but `price $5` stays code.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "x^2" })
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "price $5" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}

@Test
func escapedDollarDoesNotStartInlineMath() throws {
    var stream = MarkdownStream()
    stream.append("Cost is \\$5 and math is $a_1$.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)

    #expect(block.inlines.contains { $0.kind == .math && $0.text == "a_1" })
    #expect(block.inlines.filter { $0.kind == .math }.count == 1)
}
