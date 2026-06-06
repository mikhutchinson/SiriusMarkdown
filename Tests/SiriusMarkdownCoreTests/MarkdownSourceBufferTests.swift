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
