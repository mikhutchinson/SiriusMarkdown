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
        #expect(delta.selectionLineFragmentCacheHitCount > 0)
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
        #expect(delta.selectionLineFragmentCacheHitCount == 40)
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
    var selectionCoreTextLineBuildCount: Int
    var selectionLineFragmentCacheHitCount: Int
    var selectionLineFragmentCacheMissCount: Int

    init(before: MarkdownDiagnosticsCounters, after: MarkdownDiagnosticsCounters) {
        self.selectionPreferenceBodyEvaluationCount = after.selectionPreferenceBodyEvaluationCount - before.selectionPreferenceBodyEvaluationCount
        self.selectionFrameQueryCount = after.selectionFrameQueryCount - before.selectionFrameQueryCount
        self.inlineLineFragmentBuildCount = after.inlineLineFragmentBuildCount - before.inlineLineFragmentBuildCount
        self.selectionTextGeometryInitializationCount = after.selectionTextGeometryInitializationCount - before.selectionTextGeometryInitializationCount
        self.selectionFingerprintBuildCount = after.selectionFingerprintBuildCount - before.selectionFingerprintBuildCount
        self.selectionSourceRunMappingCount = after.selectionSourceRunMappingCount - before.selectionSourceRunMappingCount
        self.selectionPreferenceChangeCount = after.selectionPreferenceChangeCount - before.selectionPreferenceChangeCount
        self.selectionCoreTextLineBuildCount = after.selectionCoreTextLineBuildCount - before.selectionCoreTextLineBuildCount
        self.selectionLineFragmentCacheHitCount = after.selectionLineFragmentCacheHitCount - before.selectionLineFragmentCacheHitCount
        self.selectionLineFragmentCacheMissCount = after.selectionLineFragmentCacheMissCount - before.selectionLineFragmentCacheMissCount
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
