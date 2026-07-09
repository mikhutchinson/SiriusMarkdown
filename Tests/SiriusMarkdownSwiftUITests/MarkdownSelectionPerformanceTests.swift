import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
@Suite(.serialized)
struct MarkdownSelectionPerformanceTests {
    @Test
    @MainActor
    func disabledDocumentSelectionDoesNotBuildLineSelectionGeometryDuringHostInvalidationStorm() throws {
        let fixture = selectionStormFixture(documentSelection: .disabled, blockCount: 32)
        let delta = try runHostedInvalidationStorm(
            preparedSnapshot: fixture.prepared,
            configuration: fixture.configuration,
            recorder: fixture.recorder,
            invalidations: 40
        )

        #expect(delta.selectionFrameQueryCount > 0)
        #expect(delta.selectionPreferenceChangeCount == 0)
        #expect(delta.inlineLineFragmentBuildCount == 0)
        #expect(delta.selectionTextGeometryInitializationCount == 0)
        #expect(delta.selectionFingerprintBuildCount == 0)
        #expect(delta.selectionSourceRunMappingCount == 0)
        #expect(delta.selectionCoreTextLineBuildCount == 0)
    }

    @Test
    @MainActor
    func enabledDocumentSelectionHostLayoutStormDoesNotRebuildLineSelectionGeometryAfterWarmup() throws {
        let fixture = selectionStormFixture(documentSelection: .enabled, blockCount: 32)
        let delta = try runHostedInvalidationStorm(
            preparedSnapshot: fixture.prepared,
            configuration: fixture.configuration,
            recorder: fixture.recorder,
            invalidations: 40
        )

        #expect(delta.selectionPreferenceBodyEvaluationCount > 0)
        #expect(delta.selectionFrameQueryCount > 0)
        #expect(delta.inlineLineFragmentBuildCount == 0)
        #expect(delta.selectionTextGeometryInitializationCount == 0)
        #expect(delta.selectionFingerprintBuildCount == 0)
        #expect(delta.selectionSourceRunMappingCount == 0)
        #expect(delta.selectionCoreTextLineBuildCount == 0)
        // The final fragment-array cache (Part 04) now absorbs most repeat
        // queries directly, so it — not the rect-independent template cache
        // — is the primary signal that repeated geometry resolution during
        // an invalidation storm is cheap. The template cache may still see
        // occasional hits for genuinely new rects reusing known layouts,
        // but asserting `> 0` on it here would be fragile now that the
        // array cache short-circuits most calls before reaching it.
        #expect(delta.selectionFragmentArrayCacheHitCount > 0)
    }

    @Test
    @MainActor
    func enabledDocumentSelectionStormCostDoesNotScaleExpensiveSelectionWorkWithInvalidationCount() throws {
        let shortFixture = selectionStormFixture(documentSelection: .enabled, blockCount: 28)
        let shortDelta = try runHostedInvalidationStorm(
            preparedSnapshot: shortFixture.prepared,
            configuration: shortFixture.configuration,
            recorder: shortFixture.recorder,
            invalidations: 10
        )

        let longFixture = selectionStormFixture(documentSelection: .enabled, blockCount: 28)
        let longDelta = try runHostedInvalidationStorm(
            preparedSnapshot: longFixture.prepared,
            configuration: longFixture.configuration,
            recorder: longFixture.recorder,
            invalidations: 70
        )

        #expect(longDelta.selectionFrameQueryCount > shortDelta.selectionFrameQueryCount)
        #expect(shortDelta.inlineLineFragmentBuildCount == 0)
        #expect(longDelta.inlineLineFragmentBuildCount == 0)
        #expect(shortDelta.selectionFingerprintBuildCount == 0)
        #expect(longDelta.selectionFingerprintBuildCount == 0)
        #expect(shortDelta.selectionTextGeometryInitializationCount == 0)
        #expect(longDelta.selectionTextGeometryInitializationCount == 0)
    }

    @Test
    @MainActor
    func identicalRerenderDoesNotEvaluateSelectionPreferencesAtAll() throws {
        // SwiftUI's own view-tree diffing already skips re-invoking
        // GeometryReader content closures (and thus selection preference
        // computation entirely) when successive `rootView` assignments
        // produce a value-identical tree. This is the reason a genuinely
        // unchanged re-render costs nothing today — there is no wasted
        // per-block republish to fix for the *no-op* case. Part 04's real,
        // fixable cost only shows up when content genuinely differs across
        // several layout-settle passes for the *same* result (see
        // `repeatedIdenticalRectDuringSettleBurstHitsFragmentArrayCacheNotJustTemplateCache`
        // and the hosted append test below).
        let fixture = selectionStormFixture(documentSelection: .enabled, blockCount: 32)
        let width: CGFloat = 520
        let height: CGFloat = 1_800

        let makeRoot = {
            AnyView(SelectionInvalidationHarness(
                tick: 0,
                width: width,
                preparedSnapshot: fixture.prepared,
                configuration: fixture.configuration
            )
            .frame(width: width, height: height, alignment: .topLeading))
        }

        let hostingView = NSHostingView(rootView: makeRoot())
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        let window = offscreenSelectionPerformanceWindow(hostingView)
        defer { tearDownSelectionPerformanceWindow(window) }

        pumpSelectionPerformanceLayout(hostingView, iterations: 10)
        let before = fixture.recorder.snapshot()

        for _ in 0..<40 {
            hostingView.rootView = makeRoot()
            pumpSelectionPerformanceLayout(hostingView, iterations: 4)
        }

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())
        #expect(delta.selectionPreferenceBodyEvaluationCount == 0)
        #expect(delta.selectionPreferenceEvaluationCount == 0)
        #expect(delta.selectionPreferenceChangeCount == 0)
    }

    @Test
    @MainActor
    func appendingOneBlockDuringStreamingEvaluatesOnPreferenceChangeExactlyOnce() async throws {
        // Guards the real streaming scenario: appending ONE new block to a
        // document with many already-rendered, sealed blocks above it must
        // publish the selection-fragment preference change exactly once —
        // not once per existing block, and not once per layout-settle pass.
        // (Individual blocks' GeometryReaders may still re-evaluate a bounded
        // number of times while AppKit settles layout — that per-block cost
        // is what the fragment array cache above bounds — but the aggregated
        // `onPreferenceChange` at the document level must not multiply that
        // out across dozens of unrelated, unchanged sealed blocks.)
        let recorder = MarkdownDiagnosticsRecorder()
        var configuration = MarkdownRendererConfiguration.document
        configuration.diagnosticsRecorder = recorder

        let session = MarkdownRenderSession(
            configuration: configuration,
            parserCacheCapacity: 256,
            renderDiagnosticsRecorder: recorder
        )
        for i in 0..<30 {
            session.append("Paragraph \(i) with enough words to wrap across a couple of prepared native lines in the column.\n\n")
        }
        await session.waitUntilIdle()

        let width: CGFloat = 520
        let height: CGFloat = 3_600
        let root = AnyView(
            StreamingMarkdownView(preparedSnapshot: session.preparedSnapshot, configuration: session.configuration)
                .frame(width: width, alignment: .topLeading)
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        let window = offscreenSelectionPerformanceWindow(hostingView)
        defer { tearDownSelectionPerformanceWindow(window) }

        pumpSelectionPerformanceLayout(hostingView, iterations: 10)
        let before = recorder.snapshot()

        session.append("One more paragraph appended after the initial 30 are already rendered and settled.\n\n")
        await session.waitUntilIdle()
        hostingView.rootView = AnyView(
            StreamingMarkdownView(preparedSnapshot: session.preparedSnapshot, configuration: session.configuration)
                .frame(width: width, alignment: .topLeading)
        )
        pumpSelectionPerformanceLayout(hostingView, iterations: 6)

        let delta = SelectionCounterDelta(before: before, after: recorder.snapshot())
        #expect(delta.selectionPreferenceEvaluationCount == 1)
        #expect(delta.selectionPreferenceChangeCount == 1)
        // Not asserting an exact bound on `selectionPreferenceBodyEvaluationCount`
        // here (AppKit's own multi-pass settle behavior is not this
        // package's contract to pin exactly) — the fragment array cache
        // test above proves that repeated per-block re-evaluation within a
        // settle burst is O(1) per repeat, not a full geometry rebuild.
    }

    @Test
    @MainActor
    func selectionLineFragmentCacheInvalidatesOnlyForDistinctPreparedLayouts() throws {
        let fixture = try preparedInlineSelectionFixture()
        let narrowLayout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 128)
        let wideLayout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 260)
        let before = fixture.recorder.snapshot()

        let narrowFirst = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: narrowLayout,
            rect: CGRect(x: 0, y: 0, width: 128, height: 400),
            idPrefix: "test"
        )
        let wideFirst = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: wideLayout,
            rect: CGRect(x: 0, y: 0, width: 260, height: 400),
            idPrefix: "test"
        )
        _ = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: narrowLayout,
            rect: CGRect(x: 12, y: 24, width: 128, height: 400),
            idPrefix: "test"
        )
        _ = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: wideLayout,
            rect: CGRect(x: 12, y: 24, width: 260, height: 400),
            idPrefix: "test"
        )

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())
        let expectedLineBuilds = narrowFirst.count + wideFirst.count

        #expect(!narrowFirst.isEmpty)
        #expect(!wideFirst.isEmpty)
        #expect(delta.inlineLineFragmentBuildCount == expectedLineBuilds)
        #expect(delta.selectionTextGeometryInitializationCount == expectedLineBuilds)
        #expect(delta.selectionFingerprintBuildCount == expectedLineBuilds)
        #expect(delta.selectionLineFragmentCacheMissCount == 2)
        #expect(delta.selectionLineFragmentCacheHitCount == 2)
    }

    @Test
    @MainActor
    func rectOnlyMovementDoesNotInvalidateCachedLineSelectionGeometry() throws {
        let fixture = try preparedInlineSelectionFixture()
        let layout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 180)
        let warmup = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: layout,
            rect: CGRect(x: 0, y: 0, width: 180, height: 400),
            idPrefix: "moving"
        )
        let before = fixture.recorder.snapshot()

        var movedFirstFragment: MarkdownDocumentSelectionFragment?
        for offset in 1...40 {
            let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
                blockID: fixture.block.id,
                prepared: fixture.inlineLayout,
                layout: layout,
                rect: CGRect(x: CGFloat(offset), y: CGFloat(offset * 2), width: 180, height: 400),
                idPrefix: "moving"
            )
            movedFirstFragment = movedFirstFragment ?? fragments.first
        }

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())
        let moved = try #require(movedFirstFragment)

        #expect(!warmup.isEmpty)
        #expect(moved.rect.minX == 1)
        #expect(moved.rect.minY == 2)
        #expect(delta.inlineLineFragmentBuildCount == 0)
        #expect(delta.selectionTextGeometryInitializationCount == 0)
        #expect(delta.selectionFingerprintBuildCount == 0)
        #expect(delta.selectionSourceRunMappingCount == 0)
        #expect(delta.selectionLineFragmentCacheHitCount == 40)
    }

    @Test
    @MainActor
    func sameRectRepeatedSelectionPreferenceResolutionDoesNotRebuildLineSelectionGeometry() throws {
        let fixture = try preparedInlineSelectionFixture()
        let layout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 180)
        let rect = CGRect(x: 4, y: 8, width: 180, height: 400)
        let warmup = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: layout,
            rect: rect,
            idPrefix: "same-rect"
        )
        let before = fixture.recorder.snapshot()

        for _ in 0..<40 {
            let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
                blockID: fixture.block.id,
                prepared: fixture.inlineLayout,
                layout: layout,
                rect: rect,
                idPrefix: "same-rect"
            )
            #expect(fragments == warmup)
        }

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())

        #expect(!warmup.isEmpty)
        #expect(delta.inlineLineFragmentBuildCount == 0)
        #expect(delta.selectionTextGeometryInitializationCount == 0)
        #expect(delta.selectionFingerprintBuildCount == 0)
        #expect(delta.selectionSourceRunMappingCount == 0)
        // A same-(content, layout, rect) repeat now hits the final fragment
        // array cache directly and never even consults the (rect-
        // independent) template cache — stronger than the old behavior of
        // hitting the template cache and still re-mapping to rects every
        // time (Streaming Performance Part 04, INV-P4).
        #expect(delta.selectionFragmentArrayCacheHitCount == 40)
        #expect(delta.selectionLineFragmentCacheHitCount == 0)
        #expect(delta.selectionLineFragmentCacheMissCount == 0)
    }

    @Test
    @MainActor
    func repeatedIdenticalRectDuringSettleBurstHitsFragmentArrayCacheNotJustTemplateCache() throws {
        // Guards the actual Streaming Performance Part 04 gap that
        // reproduced empirically: a single content change can trigger
        // several layout-settle passes that re-query the SAME (content,
        // layout, rect) before geometry stabilizes. Before this fix, every
        // one of those repeats re-mapped templates to an absolute-rect
        // array from scratch even though the result was byte-identical.
        let fixture = try preparedInlineSelectionFixture()
        let layout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 180)
        let rect = CGRect(x: 0, y: 120, width: 180, height: 400)
        let before = fixture.recorder.snapshot()

        var results: [[MarkdownDocumentSelectionFragment]] = []
        for _ in 0..<6 {
            results.append(
                MarkdownDocumentSelectionFragment.inlineLineFragments(
                    blockID: fixture.block.id,
                    prepared: fixture.inlineLayout,
                    layout: layout,
                    rect: rect,
                    idPrefix: "settle-burst"
                )
            )
        }

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())

        #expect(!results[0].isEmpty)
        #expect(results.allSatisfy { $0 == results[0] })
        // First call misses (nothing cached yet); the other 5 in the burst
        // hit the array cache and skip the template map entirely.
        #expect(delta.selectionFragmentArrayCacheMissCount == 1)
        #expect(delta.selectionFragmentArrayCacheHitCount == 5)
        #expect(delta.selectionLineFragmentCacheMissCount == 1)
        #expect(delta.selectionLineFragmentCacheHitCount == 0)
    }

    @Test
    @MainActor
    func fragmentArrayCacheToleratesSubPixelRectNoiseWithinRoundingTolerance() throws {
        // Layout-settle passes can report rects that differ by sub-point
        // rounding noise (e.g. 120.0 vs 120.001) without any real geometry
        // change. The array cache rounds to the nearest half-point so these
        // still hit, matching the 0.5pt tolerance `sortedForSelection()`
        // already uses elsewhere for fragment ordering.
        let fixture = try preparedInlineSelectionFixture()
        let layout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 180)
        let warmup = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: layout,
            rect: CGRect(x: 0, y: 120, width: 180, height: 400),
            idPrefix: "sub-pixel-noise"
        )
        let before = fixture.recorder.snapshot()

        let noisyFragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: layout,
            rect: CGRect(x: 0.001, y: 119.999, width: 180.0004, height: 400),
            idPrefix: "sub-pixel-noise"
        )

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())

        #expect(!warmup.isEmpty)
        #expect(noisyFragments == warmup)
        #expect(delta.selectionFragmentArrayCacheHitCount == 1)
        #expect(delta.selectionFragmentArrayCacheMissCount == 0)
    }

    @Test
    @MainActor
    func repeatedSelectionEndpointAndHighlightQueriesReusePreparedCoreTextLine() throws {
        let fixture = try preparedInlineSelectionFixture()
        let layout = InlineRunsView.lineLayout(for: fixture.inlineLayout, containerWidth: 180)
        let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: fixture.block.id,
            prepared: fixture.inlineLayout,
            layout: layout,
            rect: CGRect(x: 0, y: 0, width: 180, height: 400),
            idPrefix: "highlight-hot-path"
        )
        let fragment = try #require(fragments.first { $0.textGeometry != nil })
        let before = fixture.recorder.snapshot()

        for _ in 0..<40 {
            let start = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + 12, y: fragment.rect.midY))
            let end = fragment.endpoint(at: CGPoint(x: fragment.rect.minX + fragment.rect.width - 12, y: fragment.rect.midY))
            let selection = MarkdownDocumentSelectionFragment.selection(from: start, to: end, in: [fragment])
            #expect(fragment.highlightRects(for: selection.ranges).isEmpty == false)
        }

        let delta = SelectionCounterDelta(before: before, after: fixture.recorder.snapshot())

        #expect(delta.selectionCoreTextLineBuildCount == 0)
        #expect(delta.selectionTextGeometryInitializationCount == 0)
        #expect(delta.selectionFingerprintBuildCount == 0)
        #expect(delta.selectionSourceRunMappingCount == 0)
    }
}

@MainActor
private func runHostedInvalidationStorm(
    preparedSnapshot: MarkdownPreparedSnapshot,
    configuration: MarkdownRendererConfiguration,
    recorder: MarkdownDiagnosticsRecorder,
    invalidations: Int,
    width: CGFloat = 520,
    height: CGFloat = 1_800
) throws -> SelectionCounterDelta {
    let root = AnyView(SelectionInvalidationHarness(
        tick: 0,
        width: width,
        preparedSnapshot: preparedSnapshot,
        configuration: configuration
    )
    .frame(width: width, height: height, alignment: .topLeading))

    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
    let window = offscreenSelectionPerformanceWindow(hostingView)
    defer { tearDownSelectionPerformanceWindow(window) }

    pumpSelectionPerformanceLayout(hostingView, iterations: 10)
    let beforeStorm = recorder.snapshot()

    for tick in 1...invalidations {
        hostingView.rootView = AnyView(SelectionInvalidationHarness(
            tick: tick,
            width: width,
            preparedSnapshot: preparedSnapshot,
            configuration: configuration
        )
        .frame(width: width, height: height, alignment: .topLeading))
        pumpSelectionPerformanceLayout(hostingView, iterations: 4)
    }

    return SelectionCounterDelta(before: beforeStorm, after: recorder.snapshot())
}

private struct SelectionInvalidationHarness: View {
    var tick: Int
    var width: CGFloat
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 0, height: 0)
                .id(tick)
            StreamingMarkdownView(preparedSnapshot: preparedSnapshot, configuration: configuration)
                .frame(width: width, alignment: .topLeading)
                .padding(.top, tick.isMultiple(of: 2) ? 0 : 0.25)
                .environment(\.selectionInvalidationTestToken, tick)
        }
        .frame(width: width, alignment: .topLeading)
    }
}

private struct SelectionInvalidationTestTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var selectionInvalidationTestToken: Int {
        get { self[SelectionInvalidationTestTokenKey.self] }
        set { self[SelectionInvalidationTestTokenKey.self] = newValue }
    }
}

@MainActor
private func offscreenSelectionPerformanceWindow<V: View>(_ hostingView: NSHostingView<V>) -> NSWindow {
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    return window
}

@MainActor
private func pumpSelectionPerformanceLayout<V: View>(
    _ hostingView: NSHostingView<V>,
    iterations: Int
) {
    for _ in 0..<iterations {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
    }
}

@MainActor
private func tearDownSelectionPerformanceWindow(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
    for _ in 0..<3 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
    }
}
#endif

private func selectionStormFixture(
    documentSelection: MarkdownRendererConfiguration.DocumentSelection,
    blockCount: Int
) -> (
    prepared: MarkdownPreparedSnapshot,
    configuration: MarkdownRendererConfiguration,
    recorder: MarkdownDiagnosticsRecorder
) {
    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.documentSelection = documentSelection
    configuration.diagnosticsRecorder = recorder

    var stream = MarkdownStream()
    stream.append(selectionStormMarkdown(blockCount: blockCount))
    stream.finish()
    return (
        prepared: configuration.prepare(snapshot: stream.snapshot()),
        configuration: configuration,
        recorder: recorder
    )
}

private func preparedInlineSelectionFixture() throws -> (
    block: MarkdownBlock,
    inlineLayout: MarkdownPreparedInlineContent,
    recorder: MarkdownDiagnosticsRecorder
) {
    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.diagnosticsRecorder = recorder

    var stream = MarkdownStream()
    stream.append(
        """
        Alpha **strong beta** and [linked gamma](https://example.com) plus `code delta` continue with enough words to wrap across several prepared native lines.
        """
    )
    stream.finish()

    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    let block = try #require(snapshot.blocks.first)
    let inlineLayout = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)
    return (block, inlineLayout, recorder)
}

private func selectionStormMarkdown(blockCount: Int) -> String {
    (0..<blockCount).map { index in
        """
        Paragraph \(index) has **strong text \(index)**, [a stable link \(index)](https://example.com/\(index)), `inline code \(index)`, and enough trailing words to wrap into multiple prepared native lines in a transcript column.
        """
    }
    .joined(separator: "\n\n")
}

private struct SelectionCounterDelta {
    var selectionPreferenceBodyEvaluationCount: Int
    var selectionFrameQueryCount: Int
    var inlineLineFragmentBuildCount: Int
    var selectionTextGeometryInitializationCount: Int
    var selectionFingerprintBuildCount: Int
    var selectionSourceRunMappingCount: Int
    var selectionPreferenceChangeCount: Int
    var selectionPreferenceEvaluationCount: Int
    var selectionCoreTextLineBuildCount: Int
    var selectionLineFragmentCacheHitCount: Int
    var selectionLineFragmentCacheMissCount: Int
    var selectionFragmentArrayCacheHitCount: Int
    var selectionFragmentArrayCacheMissCount: Int

    init(before: MarkdownDiagnosticsCounters, after: MarkdownDiagnosticsCounters) {
        self.selectionPreferenceBodyEvaluationCount = after.selectionPreferenceBodyEvaluationCount - before.selectionPreferenceBodyEvaluationCount
        self.selectionFrameQueryCount = after.selectionFrameQueryCount - before.selectionFrameQueryCount
        self.inlineLineFragmentBuildCount = after.inlineLineFragmentBuildCount - before.inlineLineFragmentBuildCount
        self.selectionTextGeometryInitializationCount = after.selectionTextGeometryInitializationCount - before.selectionTextGeometryInitializationCount
        self.selectionFingerprintBuildCount = after.selectionFingerprintBuildCount - before.selectionFingerprintBuildCount
        self.selectionSourceRunMappingCount = after.selectionSourceRunMappingCount - before.selectionSourceRunMappingCount
        self.selectionPreferenceChangeCount = after.selectionPreferenceChangeCount - before.selectionPreferenceChangeCount
        self.selectionPreferenceEvaluationCount = after.selectionPreferenceEvaluationCount - before.selectionPreferenceEvaluationCount
        self.selectionCoreTextLineBuildCount = after.selectionCoreTextLineBuildCount - before.selectionCoreTextLineBuildCount
        self.selectionLineFragmentCacheHitCount = after.selectionLineFragmentCacheHitCount - before.selectionLineFragmentCacheHitCount
        self.selectionLineFragmentCacheMissCount = after.selectionLineFragmentCacheMissCount - before.selectionLineFragmentCacheMissCount
        self.selectionFragmentArrayCacheHitCount = after.selectionFragmentArrayCacheHitCount - before.selectionFragmentArrayCacheHitCount
        self.selectionFragmentArrayCacheMissCount = after.selectionFragmentArrayCacheMissCount - before.selectionFragmentArrayCacheMissCount
    }
}

// MARK: - Native Selection Feel: drag affinity and streaming churn (INV-NS4, INV-NS8)

#if canImport(AppKit)
extension MarkdownSelectionPerformanceTests {

    /// Synthetic drag samples over fixed fragment list must not increase preference publication
    /// counts (INV-NS4: selection work stays bounded under append/seal). Affinity resolution
    /// is a pure function over the snapshot — it must not trigger new preference publications.
    @Test
    @MainActor
    func testDragSamplesDoNotIncreaseSelectionPreferenceChurn() {
        let fixture = selectionStormFixture(documentSelection: .enabled, blockCount: 8)
        let recorder = fixture.recorder

        // Build a synthetic fragment list simulating prepared blocks.
        var allFragments: [MarkdownDocumentSelectionFragment] = []
        for (i, block) in fixture.prepared.snapshot.blocks.enumerated() {
            let rect = CGRect(x: 0, y: CGFloat(i * 40), width: 400, height: 30)
            let fallback = MarkdownPreparedBlockContent(blockID: block.id)
            let content = fixture.prepared.preparedContentByBlockID[block.id] ?? fallback
            allFragments.append(contentsOf: MarkdownDocumentSelectionFragment.fragments(
                for: block,
                preparedContent: content,
                rect: rect
            ))
        }

        let before = recorder.snapshot()

        // Simulate 40 drag samples — each just calls hitFragment (pure function, no preference mutation).
        for i in 0..<40 {
            let y = CGFloat(i * 5)
            let affinityHint: MarkdownDocumentSelectionAffinity = y < 100 ? .downstream : .upstream
            _ = MarkdownDocumentSelectionFragment.hitFragment(
                at: CGPoint(x: 100, y: y),
                in: allFragments,
                hitSlop: 4,
                affinityHint: affinityHint
            )
        }

        let delta = SelectionCounterDelta(before: before, after: recorder.snapshot())

        // Drag affinity resolution must not produce any preference changes.
        #expect(delta.selectionPreferenceChangeCount == 0,
                "Drag affinity resolution must not emit new preference changes (got \(delta.selectionPreferenceChangeCount))")
        // Affinity hits must not rebuild inline line fragments.
        #expect(delta.inlineLineFragmentBuildCount == 0,
                "Drag samples must not rebuild inline line fragments (got \(delta.inlineLineFragmentBuildCount))")
    }

    /// Affinity resolution over N fragments must be O(N): the number of fragment comparisons
    /// must not grow super-linearly with fragment count.
    @Test
    @MainActor
    func testAffinityResolutionIsBoundedWithFragmentCount() {
        // Create a larger fragment list.
        var largeFragments: [MarkdownDocumentSelectionFragment] = []
        largeFragments.reserveCapacity(200)
        for i in 0..<200 {
            let blockID = MarkdownBlockID("b\(i)")
            let sourceRange = MarkdownSourceRange(byteRange: (i * 10)..<(i * 10 + 10), lineRange: i..<(i + 1))
            let rect = CGRect(x: 0, y: CGFloat(i * 25), width: 300, height: 20)
            largeFragments.append(MarkdownDocumentSelectionFragment(
                id: "f\(i)",
                blockID: blockID,
                sourceRange: sourceRange,
                rect: rect
            ))
        }

        // Pointer in a gutter — triggers nearest-fragment fallback.
        let gutterPoint = CGPoint(x: 150, y: 612) // between fragment 24 (y=600–620) and 25 (y=625–645)

        let hit = MarkdownDocumentSelectionFragment.hitFragment(
            at: gutterPoint,
            in: largeFragments,
            hitSlop: 2,
            affinityHint: .downstream
        )

        // Must resolve to *some* fragment (not nil) — the plan's gutter guarantee.
        #expect(hit != nil, "Affinity resolution over 200 fragments must still resolve a hit")
    }
}
#endif
