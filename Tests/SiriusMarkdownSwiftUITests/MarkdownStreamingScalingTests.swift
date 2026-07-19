#if os(macOS)
import AppKit
import SiriusMarkdownCore
import SwiftUI
import Testing
@testable import SiriusMarkdownSwiftUI

/// Streaming scaling probe: hosts `StreamingMarkdownView` in the same shape a
/// chat transcript uses (Core Text painted lines + source-backed document
/// selection) and measures per-append main-thread cost as the document grows.
/// The invariant under test: appending to a LARGE document must not cost
/// disproportionally more main-thread time than appending to a SMALL one.
@MainActor
private final class StreamingScalingHarness {
    let session: MarkdownRenderSession
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow

    init(documentSelection: MarkdownRendererConfiguration.DocumentSelection) {
        var configuration = MarkdownRendererConfiguration.compactChat
        configuration.inlineRenderingMode = .coreTextPaintedLines
        configuration.documentSelection = documentSelection
        let session = MarkdownRenderSession(configuration: configuration)
        self.session = session

        // Mirror a chat transcript: the document renders at its full natural
        // height inside an AppKit scroller, so every block materializes and
        // participates in each layout pass (no lazy viewport clipping).
        let root = StreamingScalingHost(session: session)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 480, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 800)
        self.hostingView = hostingView

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 800))
        scrollView.documentView = hostingView
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.orderBack(nil)
        self.window = window
    }

    func tearDown() {
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Appends one chunk, waits for the pipeline, then drives a full
    /// main-thread publish + layout pass and returns its duration in ms.
    func appendAndSettle(_ chunk: String) async -> Double {
        session.append(chunk)
        await session.waitUntilIdle()
        let clock = ContinuousClock()
        let start = clock.now
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1e15
    }

    /// Mirrors a transcript row host publishing a new persistent root value.
    /// Sirius does this without replacing the NSHostingView itself.
    func replaceRootAndSettle() {
        let root = StreamingScalingHost(session: session)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 480, alignment: .topLeading)
        hostingView.rootView = AnyView(root)
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}

private struct StreamingScalingHost: View {
    @ObservedObject var session: MarkdownRenderSession

    var body: some View {
        StreamingMarkdownView(
            preparedSnapshot: session.preparedSnapshot,
            configuration: session.configuration
        )
    }
}

private func scalingChunk(index: Int) -> String {
    """
    Paragraph \(index) with a sentence of streaming prose that wraps.

    - Bullet \(index).a with content
    - Bullet \(index).b with `inline code`

    """
}

@Suite("Streaming scaling", .serialized)
struct MarkdownStreamingScalingTests {
    @Test
    func preparedRegionsStayBoundedAndOnlyTailRegionRevisionChanges() throws {
        let count = MarkdownStreamingPreparedRegion.capacity * 3 + 5
        let renderItems = (0..<count).map {
            MarkdownPreparedSnapshotRenderItem(id: "item-\($0)", itemIndex: $0)
        }
        let initial = MarkdownStreamingPreparedRegion.make(renderItems: renderItems) {
            $0.id + ":0"
        }

        #expect(initial.count == 4)
        #expect(initial.dropLast().allSatisfy {
            $0.renderItems.count == MarkdownStreamingPreparedRegion.capacity
        })
        #expect(initial.last?.renderItems.count == 5)

        let tailID = try #require(renderItems.last?.id)
        let changed = MarkdownStreamingPreparedRegion.make(renderItems: renderItems) { item in
            item.id == tailID ? item.id + ":1" : item.id + ":0"
        }

        #expect(changed.map(\.id) == initial.map(\.id))
        #expect(changed.dropLast().map(\.layoutToken) == initial.dropLast().map(\.layoutToken))
        #expect(changed.last?.layoutToken != initial.last?.layoutToken)
        #expect(changed.allSatisfy {
            $0.renderItems.count <= MarkdownStreamingPreparedRegion.capacity
        })
    }

    @Test
    @MainActor
    func perAppendMainThreadCostStaysBoundedAsDocumentGrows() async throws {
        let harness = StreamingScalingHarness(documentSelection: .enabled)
        defer { harness.tearDown() }

        // Warm up + grow to a small document.
        var smallSamples: [Double] = []
        for index in 0..<10 {
            let ms = await harness.appendAndSettle(scalingChunk(index: index))
            if index >= 5 { smallSamples.append(ms) }
        }

        // Grow to a large document (~150 blocks).
        for index in 10..<50 {
            _ = await harness.appendAndSettle(scalingChunk(index: index))
        }

        var largeSamples: [Double] = []
        for index in 50..<60 {
            let ms = await harness.appendAndSettle(scalingChunk(index: index))
            largeSamples.append(ms)
        }

        let smallMedian = median(smallSamples)
        let largeMedian = median(largeSamples)
        print(
            "[streaming-scaling] documentSelection=on small=\(fmt(smallSamples)) " +
            "large=\(fmt(largeSamples)) medians=\(String(format: "%.2f", smallMedian))ms" +
            " -> \(String(format: "%.2f", largeMedian))ms"
        )

        // Scaling gate: a 6x-larger document may not cost more than ~4x per
        // publish+layout pass. Deliberately loose for CI noise; the pre-fix
        // pathological paths regress by 10-100x, not 4x.
        let scalingMessage = "Per-append main-thread cost grew superlinearly: " +
            "\(String(format: "%.2f", smallMedian))ms -> " +
            "\(String(format: "%.2f", largeMedian))ms"
        #expect(
            largeMedian <= max(4.0 * smallMedian, smallMedian + 12.0),
            Comment(rawValue: scalingMessage)
        )
    }

    @Test
    @MainActor
    func selectionLayerDoesNotDominatePerAppendCost() async throws {
        let enabledHarness = StreamingScalingHarness(documentSelection: .enabled)
        var enabledSamples: [Double] = []
        for index in 0..<40 {
            let ms = await enabledHarness.appendAndSettle(scalingChunk(index: index))
            if index >= 30 { enabledSamples.append(ms) }
        }
        enabledHarness.tearDown()

        let disabledHarness = StreamingScalingHarness(documentSelection: .disabled)
        var disabledSamples: [Double] = []
        for index in 0..<40 {
            let ms = await disabledHarness.appendAndSettle(scalingChunk(index: index))
            if index >= 30 { disabledSamples.append(ms) }
        }
        disabledHarness.tearDown()

        let enabledMedian = median(enabledSamples)
        let disabledMedian = median(disabledSamples)
        print(
            "[streaming-scaling] selection on=\(String(format: "%.2f", enabledMedian))ms " +
            "off=\(String(format: "%.2f", disabledMedian))ms"
        )

        // The document-selection layer must be a modest additive cost, not a
        // multiplier, during live streaming.
        let selectionMessage = "Document-selection layer dominates streaming cost: " +
            "on=\(String(format: "%.2f", enabledMedian))ms " +
            "off=\(String(format: "%.2f", disabledMedian))ms"
        #expect(
            enabledMedian <= max(2.5 * disabledMedian, disabledMedian + 8.0),
            Comment(rawValue: selectionMessage)
        )
    }

    /// Reproduces the host shape that crashed Sirius during a large live
    /// response: a naturally-sized StreamingMarkdownView inside an AppKit
    /// scroll document, with prepared snapshots publishing while the window
    /// actively runs layout/display cycles. The former LazyVStack item-phase
    /// recycler eventually requested another constraints update from inside
    /// NSHostingView.layout; AppKit converted that recursive display-cycle
    /// guard into EXC_BREAKPOINT. This test is intentionally a real NSWindow
    /// render loop, not a view-construction assertion.
    @Test
    @MainActor
    func rapidPreparedPublicationsStayConstraintSafeInAppKitHost() async throws {
        let harness = StreamingScalingHarness(documentSelection: .enabled)
        defer { harness.tearDown() }

        var samples: [Double] = []
        for index in 0..<90 {
            let ms = await harness.appendAndSettle(rapidScalingChunk(index: index))
            harness.window.contentView?.needsLayout = true
            harness.window.contentView?.layoutSubtreeIfNeeded()
            harness.window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(2))
            if index >= 80 {
                samples.append(ms)
            }
        }

        let tailMedian = median(samples)
        print(
            "[streaming-constraint-safety] final-document-bytes=\(harness.session.preparedSnapshot.snapshot.sourceLength) " +
            "tail-layout-median=\(String(format: "%.2f", tailMedian))ms"
        )
        #expect(tailMedian < 16.0)
    }

    /// Guards the persistent-row-host boundary used by Sirius. A streaming
    /// surface must tolerate root-value replacement while AppKit owns the
    /// hosting view and is actively driving layout. In particular, layout
    /// cache identity is derived from explicit renderer inputs; environment
    /// changes settle through mounted-region geometry instead of a dynamic
    /// environment projection at this root boundary.
    @Test
    @MainActor
    func persistentHostingRootReplacementStaysEnvironmentSafe() async throws {
        let harness = StreamingScalingHarness(documentSelection: .enabled)
        defer { harness.tearDown() }

        for index in 0..<30 {
            _ = await harness.appendAndSettle(scalingChunk(index: index))
        }

        for index in 30..<45 {
            harness.session.append(scalingChunk(index: index))
            await harness.session.waitUntilIdle()
            harness.replaceRootAndSettle()
            try? await Task.sleep(for: .milliseconds(2))
        }

        #expect(harness.hostingView.frame.width == 480)
        #expect(harness.session.preparedSnapshot.snapshot.sourceLength > 0)
    }

    @Test
    @MainActor
    func live120RowTableRemeasuresOnlyChangedRowsAndStaysFrameBounded() async throws {
        let harness = StreamingScalingHarness(documentSelection: .enabled)
        defer { harness.tearDown() }

        _ = await harness.appendAndSettle(streamingTablePrefix)
        var earlySamples: [Double] = []
        var lateSamples: [Double] = []
        for rowIndex in 0..<120 {
            let chunks = streamingTableRowChunks(index: rowIndex)
            for chunk in chunks {
                let elapsed = await harness.appendAndSettle(chunk)
                if rowIndex < 10 {
                    earlySamples.append(elapsed)
                }
                if rowIndex >= 110 {
                    lateSamples.append(elapsed)
                }
            }
        }

        harness.session.finish()
        await harness.session.waitUntilIdle()
        harness.hostingView.needsLayout = true
        harness.hostingView.layoutSubtreeIfNeeded()
        harness.hostingView.displayIfNeeded()

        let earlyMedian = median(earlySamples)
        let lateMedian = median(lateSamples)
        let counters = harness.session.renderCounters
        let table = try #require(
            harness.session.preparedSnapshot.snapshot.blocks
                .first(where: { $0.kind == .table })?.table
        )
        print(
            "[streaming-table-host] rows=\(table.rows.count) " +
            "early=\(String(format: "%.2f", earlyMedian))ms " +
            "late=\(String(format: "%.2f", lateMedian))ms " +
            "rowMeasures=\(counters.tableRowLayoutMeasurementCount) " +
            "rowCacheHits=\(counters.tableRowLayoutCacheHitCount) " +
            "cellPrepare=\(counters.tableCellPreparationCount) " +
            "cellCompare=\(counters.tableCellIncrementalComparisonCount)"
        )

        #expect(table.rows.count == 120)
        #expect(counters.tableRowLayoutCacheHitCount > counters.tableRowLayoutMeasurementCount)
        #expect(counters.tableRowLayoutMeasurementCount < 1_200)
        #expect(counters.tableCellIncrementalComparisonCount < 4_000)
        #expect(lateMedian <= max(4 * earlyMedian, earlyMedian + 12))
        #expect(lateMedian < 16)
    }
}

private func rapidScalingChunk(index: Int) -> String {
    (0..<8).map { paragraph in
        """
        ## Section \(index).\(paragraph)

        Streaming paragraph \(index).\(paragraph) contains **strong text**, `inline code`, a [safe link](https://example.com), and enough prose to wrap across several prepared Core Text lines in a transcript-width host.

        - Item A for \(index).\(paragraph)
        - Item B for \(index).\(paragraph)

        """
    }.joined()
}

private let streamingTablePrefix = """
| Item | Decimal | Sentence | Link | Detail | Tail |
| :--- | ---: | :---: | --- | --- | --- |

"""

private func streamingTableRowChunks(index: Int) -> [String] {
    let row = "| Item \(index) varied text | \(index).25 | Sentence \(index), punctuation. " +
        "| [reference \(index)](https://example.com/items/\(index)) " +
        "| detail \(index) | tail \(index) |\n"
    let marker = "https://example"
    guard let range = row.range(of: marker) else { return [row] }
    let split = row.index(range.lowerBound, offsetBy: marker.count)
    return [String(row[..<split]), String(row[split...])]
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

private func fmt(_ values: [Double]) -> String {
    "[" + values.map { String(format: "%.1f", $0) }.joined(separator: ", ") + "]"
}
#endif
