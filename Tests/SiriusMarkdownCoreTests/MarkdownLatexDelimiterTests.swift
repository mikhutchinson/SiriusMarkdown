import Testing
@testable import SiriusMarkdownCore

private func snapshot(_ markdown: String) -> MarkdownSnapshot {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return stream.snapshot()
}

@Test
func displayMathBracketsOnOwnLinesParseAsMathBlock() throws {
    let snapshot = snapshot("""
    \\[
    \\lim_{x \\to a} \\frac{f(x)}{g(x)}
    \\]
    """)

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .mathBlock)
    let mathRun = try #require(block.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "\\lim_{x \\to a} \\frac{f(x)}{g(x)}")
}

@Test
func paragraphWithDisplayMathBracketsSplitsIntoTextMathTextBlocks() throws {
    let snapshot = snapshot("""
    Then:
    \\[
    \\lim_{x \\to a} \\frac{f(x)}{g(x)} = \\lim_{x \\to a} \\frac{f'(x)}{g'(x)}
    \\]
    if the derivative limit exists.
    """)

    #expect(snapshot.blocks.map(\.kind) == [.paragraph, .mathBlock, .paragraph])
    let mathBlock = try #require(snapshot.blocks.first { $0.kind == .mathBlock })
    let mathRun = try #require(mathBlock.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "\\lim_{x \\to a} \\frac{f(x)}{g(x)} = \\lim_{x \\to a} \\frac{f'(x)}{g'(x)}")
}

@Test
func displayMathInsideBlockQuoteProducesMathRun() throws {
    let snapshot = snapshot("""
    > Then:
    > \\[
    > x^2
    > \\]
    > done.
    """)

    let quote = try #require(snapshot.blocks.first)
    #expect(quote.kind == .blockQuote)
    #expect(quote.inlines.contains { $0.kind == .math && $0.text == "x^2" })
}

@Test
func displayMathInsideBlockQuotePreservesRawTexSource() throws {
    let snapshot = snapshot("""
    > \\[
    > a_{*b*}
    > \\]
    """)

    let quote = try #require(snapshot.blocks.first)
    let mathRun = try #require(quote.inlines.first { $0.kind == .math })

    #expect(mathRun.text == "a_{*b*}")
}

@Test
func displayMathInsideListItemProducesMathRun() throws {
    let snapshot = snapshot("""
    - Then:
      \\[
      y^2
      \\]
      done.
    """)

    let list = try #require(snapshot.blocks.first)
    let item = try #require(list.listItems.first)
    #expect(list.kind == .unorderedList)
    #expect(item.inlines.contains { $0.kind == .math && $0.text == "y^2" })
}

@Test
func linkedLiteralDisplayMathDelimiterDoesNotCoalesceAcrossFollowingLines() throws {
    let snapshot = snapshot("""
    [\\[](/docs)
    x^2
    \\]
    """)

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.inlines.contains { $0.kind == .link && $0.text == "[" && $0.destination == "/docs" })
    #expect(block.inlines.allSatisfy { !$0.presentation.contains(.math) && $0.kind != .math })
}

@Test
func degradedBareDisplayBracketsWithLatexContentParseAsMathBlock() throws {
    let snapshot = snapshot("""
    [
    \\lim_{x \\to a} \\frac{f(x)}{g(x)}
    \\lim_{x \\to a} \\frac{f'(x)}{g'(x)}
    ]
    """)

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .mathBlock)
    let mathRun = try #require(block.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "\\lim_{x \\to a} \\frac{f(x)}{g(x)}\n\\lim_{x \\to a} \\frac{f'(x)}{g'(x)}")
}

@Test
func bareBracketedProseDoesNotBecomeMathBlock() throws {
    let snapshot = snapshot("""
    [
    a normal reference label
    ]
    """)

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.inlines.allSatisfy { $0.kind != .math })
}

@Test
func paragraphEmbeddedDisplayMathPreservesReferenceLinkSemantics() throws {
    let snapshot = snapshot("""
    [docs]: https://example.com/docs

    Before [docs].
    \\[
    x^2
    \\]
    After [docs].
    """)

    #expect(snapshot.blocks.map(\.kind) == [.paragraph, .mathBlock, .paragraph])
    let linkDestinations = snapshot.blocks
        .filter { $0.kind == .paragraph }
        .flatMap(\.inlines)
        .filter { $0.kind == .link }
        .compactMap(\.destination)
    #expect(linkDestinations == ["https://example.com/docs", "https://example.com/docs"])
}

@Test
func displayMathBracketsInlineOnOneLineParsesAsMathBlock() throws {
    let snapshot = snapshot("\\[x^2 + y^2 = z^2\\]")

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .mathBlock)
    let mathRun = try #require(block.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "x^2 + y^2 = z^2")
}

@Test
func latexEnvironmentParsesAsMathBlockPreservingDelimiters() throws {
    let snapshot = snapshot("\\begin{equation} x^2 + y^2 = z^2 \\end{equation}")

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .mathBlock)
    let mathRun = try #require(block.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "\\begin{equation} x^2 + y^2 = z^2 \\end{equation}")
}

@Test
func dollarDisplayMathStillParsesAsMathBlock() throws {
    let snapshot = snapshot("""
    $$
    a^2 + b^2 = c^2
    $$
    """)

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .mathBlock)
    let mathRun = try #require(block.inlines.first { $0.kind == .math })
    #expect(mathRun.text == "a^2 + b^2 = c^2")
}

@Test
func latexParenInlineMathIsDetected() throws {
    let snapshot = snapshot("Limit is \\(\\frac{0}{0}\\) here.")

    let block = try #require(snapshot.blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }
    #expect(mathRuns.count == 1)
    #expect(mathRuns.first?.text == "\\frac{0}{0}")
    #expect(block.inlines.contains { $0.kind == .text && $0.text.contains("Limit is") })
    #expect(block.inlines.contains { $0.kind == .text && $0.text.contains("here.") })
}

@Test
func latexParenAndDollarInlineMathCoexist() throws {
    let snapshot = snapshot("First \\(a+b\\) then $c-d$ done.")

    let block = try #require(snapshot.blocks.first)
    let mathRuns = block.inlines.filter { $0.kind == .math }
    #expect(mathRuns.map(\.text) == ["a+b", "c-d"])
}

@Test
func escapedBracketsInProseDoNotBecomeMathBlock() throws {
    let snapshot = snapshot("A literal array index like a\\[i\\] should stay prose.")

    let block = try #require(snapshot.blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.inlines.allSatisfy { $0.kind != .math })
}

private let latexStreamingCorpus = """
# L'Hopital

Given a limit \\(\\frac{f(x)}{g(x)}\\) we proceed.

\\[
\\lim_{x \\to a} \\frac{f(x)}{g(x)} = \\lim_{x \\to a} \\frac{f'(x)}{g'(x)}
\\]

Classic dollar math:

$$
\\frac{\\sin x}{x}
$$

Environment form:

\\begin{cases} x + y = 5 \\\\ 2x - y = 1 \\end{cases}

Done.
"""

private func assertLatexStreamingEquivalence(chunkSize: Int) {
    var streamed = MarkdownStream()
    var chunk = ""
    for character in latexStreamingCorpus {
        chunk.append(character)
        if chunk.count == chunkSize {
            streamed.append(chunk)
            chunk.removeAll(keepingCapacity: true)
        }
    }
    if !chunk.isEmpty {
        streamed.append(chunk)
    }
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(latexStreamingCorpus)
    oneShot.finish()

    let streamedSnapshot = streamed.snapshot()
    let oneShotSnapshot = oneShot.snapshot()

    #expect(streamedSnapshot.blocks.map(\.kind) == oneShotSnapshot.blocks.map(\.kind))
    #expect(streamedSnapshot.blocks.map(\.text) == oneShotSnapshot.blocks.map(\.text))
    #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    #expect(oneShotSnapshot.blocks.filter { $0.kind == .mathBlock }.count == 3)
}

@Test func latexStreamingEquivalenceChunk001() { assertLatexStreamingEquivalence(chunkSize: 1) }
@Test func latexStreamingEquivalenceChunk002() { assertLatexStreamingEquivalence(chunkSize: 2) }
@Test func latexStreamingEquivalenceChunk003() { assertLatexStreamingEquivalence(chunkSize: 3) }
@Test func latexStreamingEquivalenceChunk005() { assertLatexStreamingEquivalence(chunkSize: 5) }
@Test func latexStreamingEquivalenceChunk007() { assertLatexStreamingEquivalence(chunkSize: 7) }
@Test func latexStreamingEquivalenceChunk011() { assertLatexStreamingEquivalence(chunkSize: 11) }
@Test func latexStreamingEquivalenceChunk013() { assertLatexStreamingEquivalence(chunkSize: 13) }
@Test func latexStreamingEquivalenceChunk017() { assertLatexStreamingEquivalence(chunkSize: 17) }
@Test func latexStreamingEquivalenceChunk023() { assertLatexStreamingEquivalence(chunkSize: 23) }
