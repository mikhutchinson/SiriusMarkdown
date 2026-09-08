#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownRichTableSelectionGeometryTests {
    @Test(arguments: [true, false])
    func richTableHighlightsTrackMountedGlyphsWithSpansAndPadding(hasHeader: Bool) async throws {
        let header = hasHeader ? "<tr><th colspan=\"2\">Shared header</th></tr>" : ""
        let source = "<table>" + header + "<tr><td rowspan=\"2\">Spanning label</td><td>First row</td></tr>" +
            "<tr><td>Second row with <sup>2</sup> and <sub>n</sub></td></tr></table>"
        var stream = MarkdownStream(); stream.append(source); stream.finish()
        var configuration = MarkdownRendererConfiguration.document
        configuration.inlineRenderingMode = .coreTextPaintedLines
        configuration.nativeTextSelection = .disabled
        configuration.documentSelection = .enabled
        configuration.linkMetadataResolver = nil
        // Non-default padding ensures the assertion is not satisfied by a
        // coincidental standard-theme offset.
        configuration.theme.tableHorizontalCellPadding = 17
        configuration.theme.tableVerticalCellPadding = 11
        let block = try #require(stream.snapshot().blocks.first)
        let prepared = configuration.prepare(block: block)
        let probe = RichTableFragmentProbe()
        let root = VStack(alignment: .leading, spacing: 0) {
            MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
                .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
            Spacer(minLength: 0)
        }
        .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
        .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { probe.fragments = $0 }
        .frame(width: 600, height: 320, alignment: .topLeading)
        let host = NSHostingView(rootView: AnyView(root))
        host.frame = .init(x: 0, y: 0, width: 600, height: 320)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(.init(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
        let leaves = descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }
        for label in ["Spanning label", "First row", "Second row with"] {
            let leaf = try #require(leaves.first { $0.plan.accessibilityLabel.hasPrefix(label) })
            let fragment = try #require(probe.fragments.first { $0.textGeometry?.lineText.hasPrefix(label) == true })
            #expect(fragment.blockID == block.id)
            let highlight = try #require(fragment.highlightRects(for: [fragment.sourceRange]).first).rect
            let leafRect = leaf.convert(leaf.bounds, to: host)
            let line = try #require(leaf.plan.lines.first)
            let baselineY = leafRect.minY + line.baselineFromTop
            #expect(abs(highlight.minY - leafRect.minY) < 1,
                    "\(label): highlight \(highlight) must start at mounted text \(leafRect)")
            #expect(abs(highlight.minX - leafRect.minX) < 1)
            #expect(highlight.minY <= baselineY && highlight.maxY >= baselineY,
                    "Highlight must contain the actual CoreText baseline")
            #expect(probe.fragments.filter { $0.textGeometry?.lineText.hasPrefix(label) == true }.count == 1)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor
private final class RichTableFragmentProbe {
    var fragments: [MarkdownDocumentSelectionFragment] = []
}
#endif
