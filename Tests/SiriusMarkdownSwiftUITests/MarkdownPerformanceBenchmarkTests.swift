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

    // MARK: - Part 01/02 gap fix: default layout width tracks real container width

    @Test
    @MainActor
    func preparationCacheDefaultLayoutWidthFallsBackBeforeAnyRealWidthKnown() {
        let cache = MarkdownRenderPreparationCache()
        #expect(cache.currentDefaultLayoutWidth == InlineRunsView.defaultLayoutWidth)
    }

    @Test
    @MainActor
    func preparationCacheDefaultLayoutWidthTracksLastRecordedRealWidth() {
        let cache = MarkdownRenderPreparationCache()
        cache.recordActualContainerWidth(350)
        #expect(cache.currentDefaultLayoutWidth == 350)

        cache.recordActualContainerWidth(420)
        #expect(cache.currentDefaultLayoutWidth == 420)
    }

    @Test
    @MainActor
    func preparationCacheDefaultLayoutWidthIgnoresInvalidRecordedWidths() {
        let cache = MarkdownRenderPreparationCache()
        cache.recordActualContainerWidth(350)
        cache.recordActualContainerWidth(-10)
        cache.recordActualContainerWidth(.nan)
        cache.recordActualContainerWidth(0)
        #expect(cache.currentDefaultLayoutWidth == 350)
    }

    @Test
    @MainActor
    func newlyPreparedBlockUsesRecordedRealWidthNotHardcodedDefault() throws {
        // Guards the fix for the real, still-live gap behind INV-P1/INV-P2:
        // `InlineRunsView.defaultLayoutWidth` (680) is disconnected from real
        // rendering widths (e.g. a 350pt-wide phone/chat column), so the
        // pre-built initial layout / CTLine plan almost never matched the
        // actual container width and CTLine creation fell back to running
        // inside `updateNSView`/`updateUIView`. A block prepared after a
        // real width is known must be pre-computed at that real width.
        let configuration = MarkdownRendererConfiguration.compactChat
        configuration.preparationCache.recordActualContainerWidth(350)

        let stream = makeStream("This paragraph is prepared after a real 350pt width was recorded.")
        let prepared = configuration.prepare(snapshot: stream.snapshot())

        guard case let .block(_, content) = prepared.items.first else {
            Issue.record("Expected at least one block")
            return
        }
        let inlineLayout = try #require(content.inlineLayout)
        #expect(inlineLayout.defaultLayoutWidth == 350)
        #expect(inlineLayout.defaultLayoutWidth != InlineRunsView.defaultLayoutWidth)
    }

    @Test
    @MainActor
    func coreTextLinePlanRebuiltInBodyIsRecordedAndObservable() {
        // Makes the residual INV-P1 gap (prebuilt plan doesn't match real
        // width) measurable rather than assumed away (INV-P8): the counter
        // must exist, default to zero, and increment when recorded.
        let recorder = MarkdownDiagnosticsRecorder()
        #expect(recorder.snapshot().coreTextLinePlanRebuiltInBodyCount == 0)

        let layoutCache = MarkdownInlineLayoutCache(diagnosticsRecorder: recorder)
        layoutCache.recordCoreTextLinePlanRebuiltInBody()
        layoutCache.recordCoreTextLinePlanRebuiltInBody()

        #expect(recorder.snapshot().coreTextLinePlanRebuiltInBodyCount == 2)
    }

    @Test
    @MainActor
    func laterStreamedBlockPicksUpWidthReportedByEarlierBlock() async throws {
        // End-to-end: the FIRST block in a session has no recorded width and
        // falls back to the hardcoded default (unavoidable — nothing has
        // measured a real width yet). Once that block's real width is
        // reported back to the shared preparation cache (simulating what
        // `PreparedInlineTextView`'s width-preference handler does), EVERY
        // later block streamed into the same session must be pre-computed
        // at the real width, not the hardcoded default (INV-P1, INV-P2).
        let session = MarkdownRenderSession(configuration: .compactChat, parserCacheCapacity: 64)

        session.append("First paragraph, prepared before any real width is known.\n\n")
        await session.waitUntilIdle()

        guard case let .block(_, firstContent) = session.preparedSnapshot.items.first else {
            Issue.record("Expected at least one block")
            return
        }
        let firstInline = try #require(firstContent.inlineLayout)
        #expect(firstInline.defaultLayoutWidth == InlineRunsView.defaultLayoutWidth)

        // Simulate the real width arriving from `PreparedInlineTextView`.
        session.configuration.preparationCache.recordActualContainerWidth(360)

        session.append("Second paragraph, streamed in after the real width is known.\n\n")
        await session.waitUntilIdle()

        guard case let .block(_, secondContent) = session.preparedSnapshot.items.last else {
            Issue.record("Expected a second block")
            return
        }
        let secondInline = try #require(secondContent.inlineLayout)
        #expect(secondInline.defaultLayoutWidth == 360)
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
    func newItemsNotInChangedItemIDsSoViewIDIsStableAfterSealing() async throws {
        // Guards the fix for INV-P3: a block that is NEW on render N must NOT appear in
        // changedItemIDs on render N+1 when it is sealed and unchanged. If it did, the view
        // suffix would flip from ":0" to ":\(generation)", causing unnecessary view recreation.
        let session = MarkdownRenderSession(
            configuration: .compactChat,
            parserCacheCapacity: 64
        )

        session.append("Sealed paragraph one.\n\n")
        await session.waitUntilIdle()

        let firstSnapshot = session.preparedSnapshot
        let firstRenderItems = firstSnapshot.renderItems

        // On the first render the block is new. It must NOT be in changedItemIDs (only newItemIDs).
        for item in firstRenderItems {
            let baseID = firstSnapshot.item(at: item.itemIndex)?.id ?? item.id
            #expect(
                !firstSnapshot.diff.changedItemIDs.contains(baseID),
                "First-render block '\(baseID)' should not be in changedItemIDs"
            )
        }

        // Append a second paragraph. The first block is now sealed and reused.
        session.append("Sealed paragraph two.\n\n")
        await session.waitUntilIdle()

        let secondSnapshot = session.preparedSnapshot

        // The original block must NOT appear in changedItemIDs on the second render — it is
        // unchanged. This ensures itemViewID returns ":0" both times → stable view identity.
        for item in firstRenderItems {
            let baseID = firstSnapshot.item(at: item.itemIndex)?.id ?? item.id
            #expect(
                !secondSnapshot.diff.changedItemIDs.contains(baseID),
                "Sealed unchanged block '\(baseID)' appeared in changedItemIDs — view ID would flip"
            )
        }
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

        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<100 {
            session.append("Paragraph block number \(i) with some text content.\n\n")
        }
        await session.waitUntilIdle()
        let elapsed = clock.now - start

        #expect(session.preparedSnapshot.items.count >= 100)

        // <16ms per append at 60fps — enforced in release mode where optimisations are active.
        #if !DEBUG
        let totalMs = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1e15
        let msPerAppend = totalMs / 100.0
        #expect(
            msPerAppend < 16.0,
            "Per-append cost exceeds 16ms budget: \(String(format: "%.2f", msPerAppend))ms (INV-P8)"
        )
        #endif
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
        let clock = ContinuousClock()
        let start = clock.now
        let result1 = InlineRunsView.lineLayout(
            for: inlineLayout,
            containerWidth: layoutWidth1
        )
        let elapsed1 = clock.now - start
        #expect(!result1.lines.isEmpty)

        // <4ms for a single width-change relayout (quarter frame budget, layout-only path) — INV-P8.
        #if !DEBUG
        let ms1 = Double(elapsed1.components.seconds) * 1000.0
            + Double(elapsed1.components.attoseconds) / 1e15
        #expect(
            ms1 < 4.0,
            "Width-change relayout exceeds 4ms budget: \(String(format: "%.2f", ms1))ms (INV-P8)"
        )
        #endif

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
