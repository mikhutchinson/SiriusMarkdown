import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)

private let wideBlocksMarkdown = """
Wide code should remain inspectable without forcing the entire document surface to grow.

```json
{"renderer":"SiriusMarkdown","mode":"document","features":["native-swiftui","streaming-aware","prepared-inline-layout","bounded-caches","policy-hooks","host-boundaries"],"longValue":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}
```

```swift
let widthChange = "compact -> readable -> wide -> split view"
let invariant = "layout(preparedSegments, width) must not call parse(markdown)"
print(widthChange, invariant)
```
"""

@MainActor
private final class FragmentRecorder {
    var fragments: [MarkdownDocumentSelectionFragment] = []
}

@MainActor
private func makeHostingView(
    width: CGFloat,
    recorder: FragmentRecorder
) -> (hostingView: NSHostingView<AnyView>, window: NSWindow, firstBlockID: MarkdownBlockID) {
    var stream = MarkdownStream()
    stream.append(wideBlocksMarkdown)
    stream.finish()
    let snapshot = stream.snapshot()
    let firstBlockID = snapshot.blocks[0].id

    // Match `MarkdownDemoApp`'s exact configuration (Wide Blocks example)
    // rather than the `.document` default, since that is the reported
    // repro's real rendering path.
    let configuration = MarkdownRendererConfiguration(
        theme: .document,
        inlineRenderingMode: .preparedNativeLines,
        copyProvider: MarkdownCopyProvider(markdownSource: wideBlocksMarkdown)
    )
    let prepared = configuration.prepare(snapshot: snapshot)

    let view = AnyView(
        MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { fragments in
                recorder.fragments = fragments
            }
            .frame(width: width, height: 900, alignment: .topLeading)
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 900))
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    return (hostingView, window, firstBlockID)
}

@MainActor
private func tearDown(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
}

@MainActor
private func pump(_ hostingView: NSHostingView<AnyView>, iterations: Int = 8) {
    for _ in 0..<iterations {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

/// Regression guard for the reported "Wide Blocks" symptom (leading
/// paragraph missing on initial render, appearing only after a window
/// resize). At a narrow width the paragraph must wrap onto two lines;
/// `PreparedInlineTextView` pre-computes an *initial* layout at
/// `InlineRunsView.defaultLayoutWidth` (680pt, wider than this test's
/// 480pt) before any real width is known, then corrects via a
/// `GeometryReader`-fed preference once mounted. This test measures the
/// first block's selection-fragment count (one fragment per rendered
/// line) immediately after the first offscreen layout pass vs. after
/// several additional passes at the *same* width (no resize) — as of this
/// writing both counts already match in this offscreen `NSHostingView`
/// harness (no reproduction here), so this guards against a future
/// regression reintroducing the divergence rather than proving today's
/// bug report is fixed.
@Test
@MainActor
func wideBlocksNarrowWidthFirstPassUnderCountsWrappedLines() {
    let width: CGFloat = 480
    let recorder = FragmentRecorder()
    let (hostingView, window, firstBlockID) = makeHostingView(width: width, recorder: recorder)
    defer { tearDown(window) }

    hostingView.needsLayout = true
    hostingView.layoutSubtreeIfNeeded()
    let afterSinglePass = recorder.fragments.filter { $0.blockID == firstBlockID }.count

    pump(hostingView)
    let afterSettling = recorder.fragments.filter { $0.blockID == firstBlockID }.count

    print("[wideBlocksDiagnostic] firstBlockFragments afterSinglePass=\(afterSinglePass) afterSettling=\(afterSettling)")
    #expect(afterSinglePass == afterSettling)
    #expect(afterSettling > 1, "paragraph should wrap to more than one line at width \(width)")
}

#endif
