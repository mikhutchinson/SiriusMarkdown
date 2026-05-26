import Foundation
import Combine
import SwiftUI
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

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

@Test
@MainActor
func preparedSnapshotForwardsSourceLookupWithoutPreparingAgain() async throws {
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let session = MarkdownRenderSession(
        configuration: MarkdownRendererConfiguration(
            theme: .document,
            diagnosticsRecorder: renderRecorder
        )
    )
    session.append("# Title\n\nBody paragraph.\n")
    session.finish()
    await session.waitUntilIdle()

    let prepareCountBefore = renderRecorder.snapshot().prepareCount
    let line = session.preparedSnapshot.snapshot.blocks.first?.sourceRange.lineRange.lowerBound ?? 1

    #expect(session.preparedSnapshot.blockID(containingSourceLine: line) == session.snapshot.blockID(containingSourceLine: line))

    let span = try #require(session.snapshot.blocks.first?.sourceRange)
    #expect(session.preparedSnapshot.firstBlockID(overlappingSourceRange: span) == session.snapshot.firstBlockID(overlappingSourceRange: span))
    #expect(renderRecorder.snapshot().prepareCount == prepareCountBefore)
}

@Test
@MainActor
func renderSessionLookupUpdatesAfterAppendAndReset() async throws {
    let session = MarkdownRenderSession(configuration: .document)
    session.append("# First\n\n")
    await session.waitUntilIdle()
    let firstHeadingID = try #require(session.blockID(containingSourceLine: 1))

    session.append("Second section.\n")
    session.finish()
    await session.waitUntilIdle()
    let secondParagraphLine = try #require(
        session.snapshot.blocks.first { $0.kind == .paragraph }?.sourceRange.lineRange.lowerBound
    )
    let secondID = try #require(session.blockID(containingSourceLine: secondParagraphLine))
    #expect(secondID != firstHeadingID)

    session.reset()
    session.append("# Replacement\n")
    session.finish()
    await session.waitUntilIdle()
    let replacementHeading = try #require(session.snapshot.blocks.first)
    #expect(replacementHeading.text.contains("Replacement"))
    #expect(session.blockID(containingSourceLine: secondParagraphLine) == nil)
}

@Test
@MainActor
func renderSessionResetSuppressesStaleQueuedAppendPublication() async {
    let configuration = MarkdownRendererConfiguration(
        theme: .document,
        codeHighlighter: SlowCodeHighlighter(delay: 0.05)
    )
    let session = MarkdownRenderSession(configuration: configuration)
    var resetIssued = false
    var postResetSourceLengths: [Int] = []
    let cancellable = session.$snapshot.dropFirst().sink { snapshot in
        if resetIssued {
            postResetSourceLengths.append(snapshot.sourceLength)
        }
    }

    session.append(
        """
        ```swift
        let stale = true
        ```
        """
    )
    resetIssued = true
    session.reset()
    await session.waitUntilIdle()
    cancellable.cancel()

    #expect(postResetSourceLengths == [0])
    #expect(session.snapshot.sourceLength == 0)
    #expect(session.preparedSnapshot.snapshot.sourceLength == 0)
}

@Test
@MainActor
func renderSessionTailAppendKeepsRevealTargetStable() async throws {
    let session = MarkdownRenderSession(configuration: .document)
    session.append("# Title\n\nStreaming")
    await session.waitUntilIdle()
    let before = try #require(session.blockID(containingSourceLine: 1))

    session.append(" tail")
    await session.waitUntilIdle()
    let during = try #require(session.blockID(containingSourceLine: 1))
    #expect(before == during)
}

@Test
@MainActor
func selectionControllerSelectSourceLineHighlightsResolvedBlock() async throws {
    let source = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let controller = MarkdownSelectionController()
    let heading = try #require(session.snapshot.blocks.first { $0.kind == .heading })
    let headingLine = heading.sourceRange.lineRange.lowerBound

    controller.selectSourceLine(headingLine, in: session.preparedSnapshot)
    #expect(controller.selectedBlockIDs == [heading.id])
    #expect(controller.selectedSourceRanges == [heading.sourceRange])
}

@Test
@MainActor
func selectionControllerSelectSourceRangeUsesOverlappingBlocks() async throws {
    let source = "# One\n\nTwo\n\nThree\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let controller = MarkdownSelectionController()
    let blocks = session.snapshot.blocks
    let span = MarkdownSourceRange(
        byteRange: blocks[0].sourceRange.byteRange.lowerBound..<blocks[2].sourceRange.byteRange.upperBound,
        lineRange: blocks[0].sourceRange.lineRange.lowerBound..<blocks[2].sourceRange.lineRange.upperBound
    )

    controller.selectSourceRange(span, in: session.snapshot)
    #expect(controller.selectedBlockIDs == blocks.map(\.id))
    #expect(controller.selectedSourceRanges.count == 1)
}

@Test
@MainActor
func selectionControllerSelectSourceRangeUsesNearestFallbackInGap() async throws {
    let source = "First.\n\nSecond.\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let first = try #require(session.snapshot.blocks.first)
    let second = try #require(session.snapshot.blocks.last)
    let gapLine = first.sourceRange.lineRange.upperBound
    let gapRange = MarkdownSourceRange(byteRange: 0..<0, lineRange: gapLine..<(gapLine + 1))

    let controller = MarkdownSelectionController()
    controller.selectSourceRange(gapRange, in: session.preparedSnapshot)
    #expect(controller.selectedBlockIDs == [second.id])
    #expect(controller.selectedSourceRanges == [second.sourceRange])
}

@Test
@MainActor
func selectionControllerSelectSourceLineUsesNearestFallbackInGap() async throws {
    let source = "First.\n\nSecond.\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let first = try #require(session.snapshot.blocks.first)
    let second = try #require(session.snapshot.blocks.last)
    let gapLine = first.sourceRange.lineRange.upperBound

    let controller = MarkdownSelectionController()
    controller.selectSourceLine(gapLine, in: session.snapshot)
    #expect(controller.selectedBlockIDs == [second.id])
    #expect(controller.selectedSourceRanges == [second.sourceRange])
}

private final class SlowCodeHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func highlightedCode(_ code: String, infoString _: String?) -> AttributedString {
        Thread.sleep(forTimeInterval: delay)
        return AttributedString(code)
    }
}
