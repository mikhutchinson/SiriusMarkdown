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
func scannerTreatsCRLFBlankLinesLikeLF() {
    let scanner = MarkdownBoundaryScanner()

    var paragraph = MarkdownSourceBuffer()
    paragraph.append("alpha\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: paragraph, after: 0) == paragraph.byteCount)

    var looseList = MarkdownSourceBuffer()
    looseList.append("1. item\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == nil)
    looseList.append("\r\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == looseList.byteCount)
}

@Test
func scannerTreatsCRLFFencesMathAndHTMLLikeLF() {
    let scanner = MarkdownBoundaryScanner()

    var code = MarkdownSourceBuffer()
    code.append("```swift\r\nlet x = 1\r\n```\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: code, after: 0) == code.byteCount)

    var math = MarkdownSourceBuffer()
    math.append("$$\r\nx^2\r\n$$\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: math, after: 0) == math.byteCount)

    var html = MarkdownSourceBuffer()
    html.append("<div>\r\nraw\r\n</div>\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: html, after: 0) == html.byteCount)
}

@Test
func scannerDoesNotSealOpenMathFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\nx^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerPreservesOpenFenceAcrossIncrementalScansUntilCloseLine() {
    let scanner = MarkdownBoundaryScanner()

    var buffer = MarkdownSourceBuffer()
    buffer.append("```\npartial\n")

    var state = MarkdownBoundaryScanState()
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("\n````\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerTreatsInsufficientClosingBackticksAsInsideFenceStill() {
    var buffer = MarkdownSourceBuffer()
    buffer.append(String(repeating: "`", count: 5))
    buffer.append("\nhi\n")
    buffer.append(String(repeating: "`", count: 4))
    buffer.append("\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotCloseTildeFenceWithBacktickCloser() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("~~~\nbody\n")
    buffer.append(String(repeating: "`", count: 4))
    buffer.append("\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealMathFenceUntilClosingLineEqualsDollarFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\n$x $y$\nstill")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsSmallMathFenceWhenCloserIsOwnLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\n$$\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerKeepsCommentOpenAcrossInnerBlankLines() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("<!-- intro\n\nbody\nstill open\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsAfterScriptBlockCloserEvenWithIndentedContent() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("<script>\n  console.log(1);\n</script>\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDeferSealAfterSingleBlankFollowingOrderedListMarker() {
    let scanner = MarkdownBoundaryScanner()

    var state = MarkdownBoundaryScanState()
    var buffer2 = MarkdownSourceBuffer()
    buffer2.append("1. outer\n\n")
    var result = scanner.scan(in: buffer2, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer2.append("\n")
    result = scanner.scan(in: buffer2, state: &state)
    #expect(result.safeUpperBound == buffer2.byteCount)
}

@Test
func scannerUpdatesSealCandidateAcrossMultipleParagraphSeparatorsInOneScan() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("alpha\n\nbeta\n\n")

    let scanner = MarkdownBoundaryScanner()
    let seal = scanner.safeSealUpperBound(in: buffer, after: 0)
    #expect(seal == buffer.byteCount)
}

@Test
func scannerDoesNotRescanIncompleteLongLineBeforeNewline() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()

    for _ in 0..<1_000 {
        buffer.append("a")
        let result = scanner.scan(in: buffer, state: &state)
        #expect(result.safeUpperBound == nil)
        #expect(result.scannedByteCount == 0)
        #expect(result.scannedLineCount == 0)
    }

    buffer.append("\n\n")
    let result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
    #expect(result.scannedLineCount == 2)
    #expect(result.scannedByteCount == buffer.byteCount)
}
