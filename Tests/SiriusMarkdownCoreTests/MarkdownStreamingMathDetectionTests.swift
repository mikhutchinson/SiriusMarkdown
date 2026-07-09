import Testing
@testable import SiriusMarkdownCore

// MARK: - Partial $$ blocks

@Test
func streamingPartialDollarDollarDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n")

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingClosedDollarDollarSealsCorrectly() throws {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n$$\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    #expect(block.kind == .mathBlock)
}

@Test
func streamingPartialDollarDollarThenCloseSeals() throws {
    var stream = MarkdownStream()
    stream.append("$$\n\\sum_{i=0}^n x_i\n")
    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })

    stream.append("$$\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    #expect(block.kind == .mathBlock)
}

// MARK: - Partial \[...\] blocks

@Test
func streamingPartialBracketDisplayMathDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("\\[\n\\lim_{x \\to a} \\frac{f(x)}{g(x)}\n")

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingClosedBracketDisplayMathSealsCorrectly() throws {
    var stream = MarkdownStream()
    stream.append("\\[\n\\frac{a}{b}\n\\]\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    #expect(block.kind == .mathBlock)
}

// MARK: - Partial \begin{...} environments

@Test
func streamingPartialBeginEnvironmentDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("\\begin{equation}\nx = y\n")

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingClosedBeginEnvironmentSealsCorrectly() throws {
    var stream = MarkdownStream()
    stream.append("\\begin{equation}\nx = y\n\\end{equation}\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.contains { $0.kind == .mathBlock })
}

@Test
func streamingPartialBeginEnvironmentThenCloseSeals() {
    var stream = MarkdownStream()
    stream.append("\\begin{equation}\nx = y\n")
    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })

    stream.append("\\end{equation}\n")
    stream.finish()
    #expect(stream.snapshot().blocks.contains { $0.kind == .mathBlock })
}

@Test
func streamingPartialArrayEnvironmentDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("\\begin{array}{cc}\na & b \\\\\nc & d\n")

    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingClosedArrayEnvironmentSealsCorrectly() {
    var stream = MarkdownStream()
    stream.append("\\begin{array}{cc}\na & b \\\\\nc & d\n\\end{array}\n")
    stream.finish()

    #expect(stream.snapshot().blocks.contains { $0.kind == .mathBlock })
}

@Test
func streamingSelfClosingBeginEnvironmentOnOneLineDoesNotBlockSealing() {
    var stream = MarkdownStream()
    stream.append("\\begin{equation} x = y \\end{equation}\n\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.contains { $0.kind == .mathBlock })
}

// MARK: - Math inside block quotes

@Test
func streamingMathInsideBlockQuoteDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("> $$\n> \\frac{a}{b}\n")

    // The scanner must keep the region mutable while $$ is open (INV-M5).
    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingBracketDisplayMathInsideBlockQuoteDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("> \\[\n> \\frac{a}{b}\n")

    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })
}

// MARK: - Math inside list items

@Test
func streamingMathInsideListItemDoesNotSealEarly() {
    var stream = MarkdownStream()
    stream.append("- $$\n  \\frac{a}{b}\n")

    // The scanner must keep the region mutable while $$ is open (INV-M5).
    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })
}

// MARK: - Math adjacent to code fences

@Test
func streamingMathAdjacentToCodeFenceDoesNotConfuseTracker() {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n$$\n\n")
    stream.append("```swift\nlet x = 1\n```\n\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.contains { $0.kind == .mathBlock })
    #expect(snapshot.blocks.contains { $0.kind == .codeBlock })
}

@Test
func streamingCodeFenceAdjacentToMathDoesNotConfuseTracker() {
    var stream = MarkdownStream()
    stream.append("```swift\nlet x = 1\n```\n\n")
    stream.append("$$\n\\frac{a}{b}\n$$\n\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.contains { $0.kind == .codeBlock })
    #expect(snapshot.blocks.contains { $0.kind == .mathBlock })
}

// MARK: - Multi-line equations

@Test
func streamingMultiLineEquationDoesNotSealUntilClosingDelimiter() {
    var stream = MarkdownStream()
    stream.append("$$\n\\begin{aligned}\nx &= y + 1 \\\\\ny &= z - 1\n")

    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })

    stream.append("\\end{aligned}\n$$\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.contains { $0.kind == .mathBlock })
}

// MARK: - Boundary scanner direct tests

@Test
func scannerDoesNotSealOpenBeginEnvironment() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\begin{equation}\nx = y\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsClosedBeginEnvironment() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\begin{equation}\nx = y\n\\end{equation}\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotSealOpenBeginEnvironmentInBlockQuote() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("> \\begin{equation}\n> x = y\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsClosedBeginEnvironmentInBlockQuote() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("> \\begin{equation}\n> x = y\n> \\end{equation}\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotSealOpenBeginEnvironmentInListItem() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("- \\begin{equation}\n  x = y\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsSelfClosingBeginEnvironmentOnOneLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\begin{equation} x = y \\end{equation}\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotSealOpenBeginCasesEnvironment() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\begin{cases}\nx + y = 5 \\\\\n2x - y = 1\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsClosedBeginCasesEnvironment() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\begin{cases}\nx + y = 5 \\\\\n2x - y = 1\n\\end{cases}\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

// MARK: - Partial \(...\) inline math (INV-M5)

@Test
func streamingPartialInlineParenMathDoesNotInventMathBlock() {
    // Inline `\(...\)` is not a block fence. An open `\(` in the mutable tail
    // must not produce a math *block*; the scanner must not invent display-math
    // seal behavior for inline delimiters (INV-M3 / INV-M5).
    var stream = MarkdownStream()
    stream.append("Prose with \\(x^2 + y^2\n")

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingClosedInlineParenMathParsesAsInlineNotBlock() throws {
    var stream = MarkdownStream()
    stream.append("Prose with \\(x^2 + y^2\\) continues.\n\n")
    stream.finish()

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
    let block = try #require(snapshot.blocks.first)
    #expect(block.inlines.contains { $0.kind == .math })
}

@Test
func scannerDoesNotTreatOpenInlineParenAsMathFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Hello \\(x\n\n")

    let scanner = MarkdownBoundaryScanner()
    // A blank line after open inline `\(` is still a normal paragraph seal
    // opportunity — unlike open `$$` / `\[` / `\begin{...}` fences.
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}
