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

@Suite("Streaming scaling")
struct MarkdownStreamingScalingTests {
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
