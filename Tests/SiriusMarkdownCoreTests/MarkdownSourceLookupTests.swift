import Foundation
import Testing
@testable import SiriusMarkdownCore

private func finishedSnapshot(from markdown: String) -> MarkdownSnapshot {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return stream.snapshot()
}

private func sourceRange(of substring: String, in source: String) -> MarkdownSourceRange {
    guard let range = source.range(of: substring) else {
        Issue.record("Missing substring \(substring)")
        return MarkdownSourceRange(byteRange: 0..<0, lineRange: 1..<2)
    }

    let lower = source[..<range.lowerBound].utf8.count
    let upper = source[..<range.upperBound].utf8.count
    let line = source[..<range.lowerBound].filter { $0 == "\n" }.count + 1
    let lineEnd = source[..<range.upperBound].filter { $0 == "\n" }.count + 2
    return MarkdownSourceRange(byteRange: lower..<upper, lineRange: line..<lineEnd)
}

private func lineNumber(of substring: String, in source: String) -> Int {
    sourceRange(of: substring, in: source).lineRange.lowerBound
}

@Test
func sourceRangeContainsSourceLineIsOneBasedAndHalfOpen() {
    let range = MarkdownSourceRange(byteRange: 0..<10, lineRange: 2..<4)

    #expect(range.containsSourceLine(1) == false)
    #expect(range.containsSourceLine(2) == true)
    #expect(range.containsSourceLine(3) == true)
    #expect(range.containsSourceLine(4) == false)
    #expect(range.containsSourceLine(0) == false)
}

@Test
func sourceRangeOverlapsSourceLinesUsesHalfOpenSemantics() {
    let range = MarkdownSourceRange(byteRange: 0..<10, lineRange: 2..<4)

    #expect(range.overlapsSourceLines(1..<2) == false)
    #expect(range.overlapsSourceLines(3..<5) == true)
    #expect(range.overlapsSourceLines(4..<6) == false)
}

@Test
func invalidAndOutOfRangeLinesReturnNoTarget() {
    let snapshot = finishedSnapshot(from: "Only paragraph.\n")

    #expect(snapshot.blockID(containingSourceLine: 0) == nil)
    #expect(snapshot.blockID(containingSourceLine: -1) == nil)
    #expect(snapshot.block(containingSourceLine: 0, policy: .nearestRenderedBlock) == nil)

    let beyondDocument = (snapshot.blocks.last?.sourceRange.lineRange.upperBound ?? 1) + 10
    #expect(snapshot.blockID(containingSourceLine: beyondDocument) == nil)
    #expect(snapshot.blockID(containingSourceLine: beyondDocument, policy: .nearestRenderedBlock) == nil)
}

@Test
func emptySnapshotReturnsNoLookupTargets() {
    let snapshot = MarkdownSnapshot(blocks: [], sourceLength: 0, generation: 0, isFinished: true)
    let range = MarkdownSourceRange(byteRange: 0..<0, lineRange: 1..<2)

    #expect(snapshot.blockID(containingSourceLine: 1) == nil)
    #expect(snapshot.blockIDs(overlappingSourceRange: range).isEmpty)
    #expect(snapshot.firstBlockID(overlappingSourceRange: range) == nil)
}

@Test
func blankLineGapExactReturnsNilNearestReturnsFollowingBlock() throws {
    let markdown = "First paragraph.\n\nSecond paragraph.\n"
    let snapshot = finishedSnapshot(from: markdown)
    let first = try #require(snapshot.blocks.first)
    let second = try #require(snapshot.blocks.last)
    let gapLine = first.sourceRange.lineRange.upperBound

    #expect(snapshot.blockID(containingSourceLine: gapLine, policy: .exactOnly) == nil)
    #expect(snapshot.blockID(containingSourceLine: gapLine, policy: .nearestRenderedBlock) == second.id)
}

@Test
func lookupMapsMultilineParagraphHeadingListCodeAndTable() throws {
    let markdown = """
    # Title

    First line.
    Second line.

    - Item one
    - Item two

    ```swift
    let x = 1
    ```

    | A | B |
    | - | - |
    | 1 | 2 |
    """
    let snapshot = finishedSnapshot(from: markdown)

    let heading = try #require(snapshot.blocks.first { $0.kind == .heading })
    let paragraph = try #require(snapshot.blocks.first { $0.kind == .paragraph && $0.text.contains("First line.") })
    let list = try #require(snapshot.blocks.first { $0.kind == .unorderedList })
    let code = try #require(snapshot.blocks.first { $0.kind == .codeBlock })
    let table = try #require(snapshot.blocks.first { $0.kind == .table })

    #expect(snapshot.blockID(containingSourceLine: lineNumber(of: "# Title", in: markdown)) == heading.id)
    #expect(snapshot.blockID(containingSourceLine: lineNumber(of: "Second line.", in: markdown)) == paragraph.id)
    #expect(snapshot.blockID(containingSourceLine: lineNumber(of: "- Item one", in: markdown)) == list.id)
    #expect(snapshot.blockID(containingSourceLine: lineNumber(of: "let x = 1", in: markdown)) == code.id)
    #expect(snapshot.blockID(containingSourceLine: lineNumber(of: "| 1 | 2 |", in: markdown)) == table.id)
}

@Test
func rangeLookupReturnsOrderedBlockIDsAcrossMultipleBlocks() throws {
    let markdown = "# One\n\nTwo\n\nThree\n"
    let snapshot = finishedSnapshot(from: markdown)
    let blocks = snapshot.blocks
    #expect(blocks.count == 3)

    let span = MarkdownSourceRange(
        byteRange: blocks[0].sourceRange.byteRange.lowerBound..<blocks[2].sourceRange.byteRange.upperBound,
        lineRange: blocks[0].sourceRange.lineRange.lowerBound..<blocks[2].sourceRange.lineRange.upperBound
    )

    #expect(snapshot.blockIDs(overlappingSourceRange: span) == blocks.map(\.id))
    #expect(snapshot.firstBlockID(overlappingSourceRange: span) == blocks[0].id)
}

@Test
func firstBlockIDUsesNearestFallbackWhenRangeStartsInGap() throws {
    let markdown = "First.\n\nSecond.\n"
    let snapshot = finishedSnapshot(from: markdown)
    let first = try #require(snapshot.blocks.first)
    let second = try #require(snapshot.blocks.last)
    let gapLine = first.sourceRange.lineRange.upperBound
    let gapRange = MarkdownSourceRange(byteRange: 0..<0, lineRange: gapLine..<(gapLine + 1))

    #expect(snapshot.firstBlockID(overlappingSourceRange: gapRange, policy: .exactOnly) == nil)
    #expect(snapshot.firstBlockID(overlappingSourceRange: gapRange, policy: .nearestRenderedBlock) == second.id)
}

@Test
func firstBlockIDFallsBackToNearestBlockByByteOffsetWhenLineRangeIsEmpty() throws {
    let markdown = "First.\n\nSecond.\n"
    let snapshot = finishedSnapshot(from: markdown)
    let first = try #require(snapshot.blocks.first)
    let second = try #require(snapshot.blocks.last)
    let gapByteOffset = first.sourceRange.byteRange.upperBound
    let gapRange = MarkdownSourceRange(byteRange: gapByteOffset..<gapByteOffset, lineRange: 0..<0)

    #expect(snapshot.firstBlockID(overlappingSourceRange: gapRange, policy: .exactOnly) == nil)
    #expect(snapshot.firstBlockID(overlappingSourceRange: gapRange, policy: .nearestRenderedBlock) == second.id)
}

@Test
func activeTailAppendKeepsRevealTargetStable() throws {
    var stream = MarkdownStream()
    stream.append("# Title\n\n")
    let before = try #require(stream.snapshot().blockID(containingSourceLine: 1))

    stream.append("Still streaming")
    let during = try #require(stream.snapshot().blockID(containingSourceLine: 1))

    stream.finish()
    let after = try #require(stream.snapshot().blockID(containingSourceLine: 1))

    #expect(before == during)
    #expect(before == after)
}

@Test
func finishKeepsRevealTargetIDStableAfterTailSeals() throws {
    var stream = MarkdownStream()
    stream.append("Active paragraph")
    let tailID = try #require(stream.snapshot().blocks.first?.id)

    stream.finish()
    let sealedSnapshot = stream.snapshot()
    let sealedID = try #require(sealedSnapshot.blockID(containingSourceLine: 1))

    #expect(tailID == sealedID)
    #expect(sealedSnapshot.blocks.first?.isSealed == true)
}

@Test
func crlfInputMapsSourceLinesToExpectedBlocks() throws {
    let markdown = [
        "# Title",
        "",
        "Paragraph one.",
        "",
        "```swift",
        "let x = 1",
        "```",
    ].joined(separator: "\r\n")

    var streamed = MarkdownStream()
    for chunk in markdown.split(separator: "\r\n", omittingEmptySubsequences: false).map({ String($0) + "\r\n" }) {
        streamed.append(chunk)
    }
    streamed.finish()

    let snapshot = streamed.snapshot()
    let heading = try #require(snapshot.blocks.first { $0.kind == .heading })
    let paragraph = try #require(snapshot.blocks.first { $0.kind == .paragraph })
    let code = try #require(snapshot.blocks.first { $0.kind == .codeBlock })

    #expect(snapshot.blockID(containingSourceLine: heading.sourceRange.lineRange.lowerBound) == heading.id)
    #expect(snapshot.blockID(containingSourceLine: paragraph.sourceRange.lineRange.lowerBound) == paragraph.id)
    #expect(snapshot.blockID(containingSourceLine: code.sourceRange.lineRange.lowerBound) == code.id)
}

@Test
func trailingOutOfDocumentLineReturnsNoRevealTarget() throws {
    let markdown = "First.\n\nSecond.\n"
    let snapshot = finishedSnapshot(from: markdown)
    let second = try #require(snapshot.blocks.last)
    let trailingGapLine = second.sourceRange.lineRange.upperBound

    #expect(snapshot.blockID(containingSourceLine: trailingGapLine, policy: .exactOnly) == nil)
    #expect(snapshot.blockID(containingSourceLine: trailingGapLine, policy: .nearestRenderedBlock) == nil)

    let lastContentLine = second.sourceRange.lineRange.lowerBound
    #expect(snapshot.blockID(containingSourceLine: lastContentLine) == second.id)
}
