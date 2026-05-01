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
