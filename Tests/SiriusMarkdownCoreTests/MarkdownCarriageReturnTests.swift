import Testing
@testable import SiriusMarkdownCore

@Test
func carriageReturnSourceLinesAndMapsMatchCommonMarkNewlines() {
    var source = MarkdownSourceBuffer()
    source.append("one\r")
    source.append("\ntwo\rthree\nfour")

    #expect(source.lines(in: 0..<source.byteCount).map(\.text) == ["one\r", "two", "three", "four"])
    #expect(source.lineMap.newlineByteOffsets == [4, 8, 14])
    #expect(source.sourceRange(for: 9..<14).lineRange == 3..<4)
    #expect(source.lines(in: 5..<source.byteCount).map(\.text) == ["two", "three", "four"])
}

@Test
func carriageReturnParserPreservesBlockSourceAndLineRanges() {
    let markdown = "# Title\r\rSecond **bold**.\r\rThird."
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    let blocks = stream.snapshot().blocks

    #expect(blocks.map(\.kind) == [.heading, .paragraph, .paragraph])
    #expect(blocks.map { stream.markdown(in: $0.sourceRange) } == ["# Title", "Second **bold**.", "Third."])
    #expect(blocks.map(\.sourceRange.lineRange) == [1..<2, 3..<4, 5..<6])
    #expect(blocks[1].inlines.contains { $0.text == "bold" })
}

@Test
func carriageReturnStreamingMatchesWholeDocumentAcrossEverySplit() {
    let markdown = "# Title\r\n\r\n1. first\r\n\r\n2. second\r\n\r\n\r\n```swift\rlet x = 1\r```\r\rLast."
    var source = MarkdownSourceBuffer()
    source.append(markdown)
    let expected = SwiftMarkdownParser().parse(source.slice(0..<source.byteCount), lineMap: source.lineMap, idNamespace: "stream", isSealed: true)
    let bytes = Array(markdown.utf8)

    for split in 0...bytes.count {
        var stream = MarkdownStream()
        stream.append(String(decoding: bytes[..<split], as: UTF8.self))
        stream.append(String(decoding: bytes[split...], as: UTF8.self))
        stream.finish()
        let actual = stream.snapshot().blocks
        #expect(actual.map(\.kind) == expected.map(\.kind), "split \(split)")
        #expect(actual.map(\.text) == expected.map(\.text), "split \(split)")
        #expect(actual.map(\.sourceRange) == expected.map(\.sourceRange), "split \(split)")
    }
}

@Test
func carriageReturnScannerSealsCompletedParagraphWithoutFinishing() {
    var stream = MarkdownStream()
    stream.append("First.\r\rSecond")
    let blocks = stream.snapshot().blocks
    #expect(blocks.count == 2)
    #expect(blocks.first?.isSealed == true)
    #expect(blocks.last?.isSealed == false)
}

@Test
func carriageReturnInlineBreaksKeepExactSourceRanges() throws {
    for newline in ["\r", "\r\n", "\n"] {
        var stream = MarkdownStream()
        stream.append("alpha" + newline + "beta  " + newline + "gamma")
        stream.finish()
        let block = try #require(stream.snapshot().blocks.first)
        let breaks = block.inlines.filter { $0.kind == .softBreak || $0.kind == .hardBreak }
        #expect(breaks.map(\.kind) == [.softBreak, .hardBreak])
        #expect(breaks.compactMap(\.sourceRange).map { stream.markdown(in: $0) } == [newline, "  " + newline])
    }
}

@Test
func carriageReturnSingleByteStreamingDoesNotSplitLooseLists() {
    let markdown = "1. first\r\n\r\n2. second\r\n\r\n\r\nLast.\r"
    var source = MarkdownSourceBuffer()
    source.append(markdown)
    let expected = SwiftMarkdownParser().parse(source.slice(0..<source.byteCount), lineMap: source.lineMap, idNamespace: "stream", isSealed: true)
    var stream = MarkdownStream()
    for byte in markdown.utf8 {
        stream.append(String(decoding: [byte], as: UTF8.self))
        _ = stream.snapshot()
    }
    stream.finish()
    #expect(stream.snapshot().blocks.map(\.kind) == expected.map(\.kind))
    #expect(stream.snapshot().blocks.map(\.text) == expected.map(\.text))
    #expect(stream.snapshot().blocks.map(\.sourceRange) == expected.map(\.sourceRange))
}

@Test
func carriageReturnQuotedDisplayMathRemovesEveryContainerPrefix() throws {
    for newline in ["\r", "\r\n", "\n"] {
        let markdown = ["> Before:", "> \\[", "> x^2 +", "> y^2", "> \\]", "> after."].joined(separator: newline)
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let quote = try #require(stream.snapshot().blocks.first)
        let math = try #require(quote.inlines.first { $0.kind == .math })
        #expect(math.text == "x^2 +\ny^2")
    }
}
