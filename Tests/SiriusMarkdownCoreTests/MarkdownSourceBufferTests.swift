import Testing
@testable import SiriusMarkdownCore

@Test
func sourceBufferAppendsSlicesAndMapsLines() {
    var buffer = MarkdownSourceBuffer()
    let first = buffer.append("one\n")
    let second = buffer.append("two\nthree")

    #expect(first.byteRange == 0..<4)
    #expect(second.byteRange == 4..<13)
    #expect(buffer.slice(4..<7).text == "two")
    #expect(buffer.lineMap.lineNumber(containingByteOffset: 0) == 1)
    #expect(buffer.lineMap.lineNumber(containingByteOffset: 4) == 2)
    #expect(buffer.lineMap.lineNumber(containingByteOffset: 8) == 3)
}

@Test
func sourceBufferReturnsFullTextAcrossChunks() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("# Heading\n")
    buffer.append("\nBody")

    #expect(buffer.fullText() == "# Heading\n\nBody")
}

@Test
func sourceBufferEmptyAppendDoesNotAddAChunkOrChangeOffsets() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("alpha")
    let empty = buffer.append("")
    buffer.append("beta")

    #expect(empty.byteRange == 5..<5)
    #expect(buffer.byteCount == 9)
    #expect(buffer.fullText() == "alphabeta")
    #expect(buffer.slice(0..<buffer.byteCount).text == "alphabeta")
    #expect(buffer.lines(in: 0..<buffer.byteCount).map(\.text) == ["alphabeta"])
}

@Test
func sourceBufferDecodesMultiChunkUnicodeSliceAsSingleUTF8Stream() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("alpha ")
    buffer.append("日本語 ")
    buffer.append("emoji 😀 ")
    buffer.append("rtl שלום")

    let full = buffer.slice(0..<buffer.byteCount)
    let middleLower = "alpha ".utf8.count
    let middleUpper = middleLower + "日本語 emoji 😀".utf8.count

    #expect(full.text == "alpha 日本語 emoji 😀 rtl שלום")
    #expect(buffer.slice(middleLower..<middleUpper).text == "日本語 emoji 😀")
}

@Test
func sourceBufferDecodesLinesAcrossChunkBoundariesWithoutLineCopies() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("first ")
    buffer.append("line\nsecond ")
    buffer.append("日本語")
    buffer.append("\nthird 😀")

    let lines = buffer.lines(in: 0..<buffer.byteCount)

    #expect(lines.map(\.text) == ["first line", "second 日本語", "third 😀"])
    #expect(lines.map(\.includesTerminatingNewline) == [true, true, false])
    #expect(lines.map(\.byteRange) == [
        0..<"first line".utf8.count,
        "first line\n".utf8.count..<"first line\nsecond 日本語".utf8.count,
        "first line\nsecond 日本語\n".utf8.count..<"first line\nsecond 日本語\nthird 😀".utf8.count
    ])
}

@Test
func sourceBufferClampsOutOfBoundsByteRanges() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("alpha\nbeta")

    #expect(buffer.slice((-4)..<99).byteRange == 0..<10)
    #expect(buffer.slice((-4)..<99).text == "alpha\nbeta")
    #expect(buffer.slice(99..<120).byteRange == 10..<10)
    #expect(buffer.slice(99..<120).text == "")
    #expect(buffer.lines(in: (-4)..<99).map(\.text) == ["alpha", "beta"])
    #expect(buffer.lines(in: 99..<120).isEmpty)
    #expect(buffer.containsByte(10, in: (-4)..<99))
    #expect(!buffer.containsByte(10, in: 99..<120))
    #expect(buffer.sourceRange(for: (-4)..<99).byteRange == 0..<10)
    #expect(buffer.sourceRange(for: (-4)..<99).lineRange == 1..<3)
    #expect(buffer.sourceRange(for: 99..<120).byteRange == 10..<10)
}
