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
    let streamRecorder = MarkdownDiagnosticsRecorder()
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        theme: .document,
        codeHighlighter: SlowCodeHighlighter(delay: 0.05)
    )
    let session = MarkdownRenderSession(
        configuration: configuration,
        streamDiagnosticsRecorder: streamRecorder,
        renderDiagnosticsRecorder: renderRecorder
    )
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
    #expect(streamRecorder.snapshot().parseCount == 0)
    #expect(renderRecorder.snapshot().codeHighlightCount == 0)
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
func renderSessionCoalescesAppendBurstBeforePreparing() async throws {
    let streamRecorder = MarkdownDiagnosticsRecorder()
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let session = MarkdownRenderSession(
        configuration: .document,
        streamDiagnosticsRecorder: streamRecorder,
        renderDiagnosticsRecorder: renderRecorder
    )
    let chunkCount = 64

    for index in 0..<chunkCount {
        session.append(
            "Paragraph \(index) has **strong text** and [a link](https://example.com/\(index)).\n\n"
        )
    }

    await session.waitUntilIdle()

    let streamCounters = streamRecorder.snapshot()
    let renderCounters = renderRecorder.snapshot()

    #expect(session.snapshot.blocks.count == chunkCount)
    #expect(streamCounters.parseCount == 1)
    #expect(streamCounters.sealedRegionParseCount == 1)
    #expect(renderCounters.renderPreparationCount == chunkCount)
    #expect(renderCounters.prepareCount == chunkCount)
}

@Test
@MainActor
func renderSessionPreparationDoesNotBlockTheMainActor() async throws {
    let highlighter = ThreadRecordingSlowCodeHighlighter(delay: 0.35)
    let configuration = MarkdownRendererConfiguration(
        theme: .document,
        codeHighlighter: highlighter
    )
    let session = MarkdownRenderSession(configuration: configuration)

    RenderSessionCallerContext.$marker.withValue(true) {
        session.append(
            """
            ```swift
            let backgroundPreparation = true
            ```
            """
        )
    }

    await session.waitUntilIdle()
    // These executor/task-local probes are deterministic under full-suite
    // saturation. A wall-clock heartbeat threshold measured the global test
    // runner's scheduling pressure and produced false regressions even when
    // preparation was correctly detached.
    #expect(highlighter.invocationCount == 1)
    #expect(highlighter.didRunOnMainThread == false)
    #expect(highlighter.didInheritCallerTaskContext == false)
}

@Test
@MainActor
func renderSessionReusesPreparedLongTranscriptBeyondCacheCapacity() async throws {
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let session = MarkdownRenderSession(
        configuration: .document,
        renderDiagnosticsRecorder: renderRecorder
    )
    let initialBlockCount = 320

    for index in 0..<initialBlockCount {
        session.append(
            "Paragraph \(index) has **strong text** and [a link](https://example.com/\(index)).\n\n"
        )
    }
    await session.waitUntilIdle()

    let afterInitial = renderRecorder.snapshot()
    session.append(
        "Paragraph \(initialBlockCount) has **fresh strong text** and [a link](https://example.com/final).\n\n"
    )
    await session.waitUntilIdle()
    let afterAppend = renderRecorder.snapshot()

    #expect(session.snapshot.blocks.count == initialBlockCount + 1)
    #expect(afterInitial.renderPreparationCount == initialBlockCount)
    #expect(afterInitial.prepareCount == initialBlockCount)
    #expect(afterAppend.renderPreparationCount == afterInitial.renderPreparationCount + 1)
    #expect(afterAppend.prepareCount == afterInitial.prepareCount + 1)
}

@Test
@MainActor
func renderSessionCoalescingPreservesHostBoundaryOrdering() async throws {
    let session = MarkdownRenderSession(configuration: .document)
    let first = "Before native insertion.\n\n"
    let second = "After native insertion.\n\n"

    session.append(first)
    session.appendHostBoundary(id: MarkdownHostBoundaryID("native-card"))
    session.append(second)
    await session.waitUntilIdle()

    #expect(session.snapshot.blocks.map(\.text) == ["Before native insertion.", "After native insertion."])
    #expect(session.preparedSnapshot.items.count == 3)

    guard case let .hostBoundary(boundary) = session.preparedSnapshot.items[1] else {
        Issue.record("Expected host boundary between coalesced append batches.")
        return
    }

    #expect(boundary.id == MarkdownHostBoundaryID("native-card"))
    #expect(boundary.sourceOffset == first.utf8.count)
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

private final class ThreadRecordingSlowCodeHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var invocationThreads: [Bool] = []
    private var inheritedCallerContexts: [Bool] = []

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var invocationCount: Int {
        lock.withLock { invocationThreads.count }
    }

    var didRunOnMainThread: Bool {
        lock.withLock { invocationThreads.contains(true) }
    }

    var didInheritCallerTaskContext: Bool {
        lock.withLock { inheritedCallerContexts.contains(true) }
    }

    func highlightedCode(_ code: String, infoString _: String?) -> AttributedString {
        lock.withLock {
            invocationThreads.append(Thread.isMainThread)
            inheritedCallerContexts.append(RenderSessionCallerContext.marker)
        }
        Thread.sleep(forTimeInterval: delay)
        return AttributedString(code)
    }
}

private enum RenderSessionCallerContext {
    @TaskLocal static var marker = false
}
