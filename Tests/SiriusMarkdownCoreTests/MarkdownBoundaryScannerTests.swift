import Testing
@testable import SiriusMarkdownCore

@Test
func scannerDoesNotSealOpenCodeFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```swift\nlet x = 1\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsAfterClosedFenceAndBlankLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```swift\nlet x = 1\n```\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotSealOpenMathFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\nx^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}
