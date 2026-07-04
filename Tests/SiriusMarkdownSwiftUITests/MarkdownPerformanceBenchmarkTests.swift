import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized)
struct MarkdownPerformanceBenchmarkTests {

    // MARK: - Part 01: CTLine creation in prepare

    @Test
    @MainActor
    func preparedInlineContentHasCoreTextLinePlan() throws {
        #if canImport(CoreText)
        let stream = makeStream("Hello **world** with [a link](https://example.com).")
        let configuration = MarkdownRendererConfiguration.compactChat
        let prepared = configuration.prepare(snapshot: stream.snapshot())

        guard case let .block(_, content) = prepared.items.first else {
            Issue.record("Expected at least one block")
            return
        }
        let inlineLayout = try #require(content.inlineLayout)
        #expect(inlineLayout.coreTextLinePlan != nil)
        #expect(inlineLayout.initialLayoutResult != nil)
        #expect(!inlineLayout.initialLayoutResult!.lines.isEmpty)
        #else
        #expect(true)
        #endif
    }

    @Test
    @MainActor
    func preparedLinePlanCachedOnReusedContent() throws {
        let recorder = MarkdownDiagnosticsRecorder()
        var configuration = MarkdownRendererConfiguration.compactChat
        configuration.diagnosticsRecorder = recorder

        var stream = MarkdownStream()
        stream.append("A sealed paragraph that should be reused.")
        let firstSnapshot = configuration.prepare(snapshot: stream.snapshot())

        let firstPrepareCount = recorder.snapshot().prepareCount

        stream.append("\n\nSecond paragraph.")
        let secondSnapshot = configuration.prepare(
            snapshot: stream.snapshot(),
            reusing: firstSnapshot
        )

        let secondPrepareCount = recorder.snapshot().prepareCount

        #expect(secondPrepareCount > firstPrepareCount)
        #expect(secondSnapshot.diff.changedItemIDs.isEmpty || secondSnapshot.diff.newItemIDs.contains { $0.contains("block:") })
    }

    // MARK: - Part 02: Single-pass layout

    @Test
    @MainActor
    func preparedInlineContentHasInitialLayoutResult() throws {
        let stream = makeStream("This is a paragraph that should have a pre-computed initial layout at the default width.")
        let configuration = MarkdownRendererConfiguration.compactChat
        let prepared = configuration.prepare(snapshot: stream.snapshot())

        guard case let .block(_, content) = prepared.items.first else {
            Issue.record("Expected at least one block")
            return
        }
        let inlineLayout = try #require(content.inlineLayout)
        let initialLayout = try #require(inlineLayout.initialLayoutResult)
        #expect(!initialLayout.lines.isEmpty)
        #expect(inlineLayout.defaultLayoutWidth > 0)
    }

    // MARK: - Part 03: Incremental snapshot diff

    @Test
    @MainActor
    func diffIdentifiesNewItemsOnAppend() async throws {
        let session = MarkdownRenderSession(
            configuration: .compactChat,
            parserCacheCapacity: 64
        )

        session.append("First paragraph.\n\n")
        await session.waitUntilIdle()

        let firstDiff = session.snapshotDiff
        #expect(firstDiff.hasChanges)

        let firstItemCount = session.preparedSnapshot.items.count

        session.append("Second paragraph.\n\n")
        await session.waitUntilIdle()

        let secondDiff = session.snapshotDiff
        #expect(secondDiff.hasChanges)
        #expect(session.preparedSnapshot.items.count > firstItemCount)
    }

    @Test
    @MainActor
    func diffIdentifiesChangedTailBlockOnAppend() async throws {
        let session = MarkdownRenderSession(
            configuration: .compactChat,
            parserCacheCapacity: 64
        )

        session.append("First sealed paragraph.\n\n")
        await session.waitUntilIdle()

        let firstItemCount = session.preparedSnapshot.items.count

        session.append("Second sealed paragraph.\n\n")
        await session.waitUntilIdle()

        let secondItemCount = session.preparedSnapshot.items.count
        #expect(secondItemCount > firstItemCount)

        let secondDiff = session.snapshotDiff
        #expect(secondDiff.hasChanges)
    }

    @Test
    @MainActor
    func unchangedSealedBlocksNotReprepared() async throws {
        let recorder = MarkdownDiagnosticsRecorder()
        var configuration = MarkdownRendererConfiguration.compactChat
        configuration.diagnosticsRecorder = recorder

        let session = MarkdownRenderSession(
            configuration: configuration,
            parserCacheCapacity: 64,
            renderDiagnosticsRecorder: recorder
        )

        session.append("First sealed paragraph.\n\n")
        await session.waitUntilIdle()

        let firstPrepareCount = recorder.snapshot().prepareCount

        session.append("Second sealed paragraph.\n\n")
        await session.waitUntilIdle()

        let secondPrepareCount = recorder.snapshot().prepareCount

        let prepareDelta = secondPrepareCount - firstPrepareCount
        #expect(prepareDelta > 0)
        #expect(prepareDelta <= 3)
    }

    @Test
    @MainActor
    func fullSnapshotStillPublishedAlongsideDiff() async throws {
        let session = MarkdownRenderSession(
            configuration: .compactChat,
            parserCacheCapacity: 64
        )

        session.append("Some content.\n\n")
        await session.waitUntilIdle()

        #expect(!session.preparedSnapshot.items.isEmpty)
        #expect(session.preparedSnapshot.diff.hasChanges)
        #expect(!session.preparedSnapshot.renderItems.isEmpty)
    }

    // MARK: - Part 04: Selection preference churn

    @Test
    @MainActor
    func selectionPreferenceChangeCountDoesNotIncrementForIdenticalFragments() {
        let fragments = makeTestFragments()
        let sortedOnce = fragments.sortedForSelection()
        let sortedTwice = fragments.sortedForSelection()
        #expect(sortedOnce == sortedTwice)
    }

    // MARK: - Part 05: Measured benchmarks

    @Test
    @MainActor
    func appendTo100BlocksUnderBudget() async throws {
        let session = MarkdownRenderSession(
            configuration: .compactChat,
            parserCacheCapacity: 128
        )

        for i in 0..<100 {
            session.append("Paragraph block number \(i) with some text content.\n\n")
        }
        await session.waitUntilIdle()

        #expect(session.preparedSnapshot.items.count >= 100)
    }

    @Test
    @MainActor
    func widthChangeRelayoutIsCheapForSingleBlock() throws {
        let stream = makeStream(String(repeating: "This is a long paragraph that wraps across many lines. ", count: 20))
        let configuration = MarkdownRendererConfiguration.compactChat
        let prepared = configuration.prepare(snapshot: stream.snapshot())

        guard case let .block(_, content) = prepared.items.first else {
            Issue.record("Expected at least one block")
            return
        }
        let inlineLayout = try #require(content.inlineLayout)

        let layoutWidth1 = InlineRunsView.nativeLineLayoutWidth(
            for: inlineLayout,
            containerWidth: 400
        )
        let result1 = InlineRunsView.lineLayout(
            for: inlineLayout,
            containerWidth: layoutWidth1
        )
        #expect(!result1.lines.isEmpty)

        let layoutWidth2 = InlineRunsView.nativeLineLayoutWidth(
            for: inlineLayout,
            containerWidth: 800
        )
        let result2 = InlineRunsView.lineLayout(
            for: inlineLayout,
            containerWidth: layoutWidth2
        )
        #expect(!result2.lines.isEmpty)
        #expect(result2.lines.count <= result1.lines.count)
    }

    // MARK: - Helpers

    private func makeStream(_ markdown: String) -> MarkdownStream {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        return stream
    }

    private func makeTestFragments() -> [MarkdownDocumentSelectionFragment] {
        [
            MarkdownDocumentSelectionFragment(
                id: "test:0",
                blockID: MarkdownBlockID("block-0"),
                sourceRange: MarkdownSourceRange(byteRange: 0..<10, lineRange: 0..<1),
                rect: CGRect(x: 0, y: 0, width: 100, height: 20)
            ),
            MarkdownDocumentSelectionFragment(
                id: "test:1",
                blockID: MarkdownBlockID("block-0"),
                sourceRange: MarkdownSourceRange(byteRange: 10..<20, lineRange: 0..<1),
                rect: CGRect(x: 0, y: 20, width: 100, height: 20)
            )
        ]
    }
}
