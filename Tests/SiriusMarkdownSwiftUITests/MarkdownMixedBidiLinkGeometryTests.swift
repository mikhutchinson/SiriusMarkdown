#if os(macOS)
import AppKit
import CoreText
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownMixedBidiLinkGeometryTests {
    private func fixture() throws -> (MarkdownCoreTextPaintedLinePlan, Int) {
        let label = "abc אבג"
        var stream = MarkdownStream()
        // The unlinked Hebrew suffix is painted between the label's Latin
        // and Hebrew parts, although it follows the link in logical order.
        stream.append("[\(label)](https://example.com/bidi)דהו")
        stream.finish()
        let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil, linkDecoration: .disabled)
        let block = try #require(stream.snapshot().blocks.first)
        let prepared = try #require(configuration.prepare(block: block).inlineLayout)
        let layout = prepared.layout(containerWidth: 500, allowsOverwideFallback: true)
        return (MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout), label.utf16.count)
    }

    @Test func disjointBidiLinkHitsOnlyItsShapedGlyphs() throws {
        let (plan, linkEnd) = try fixture()
        let line = try #require(plan.lines.first)
        #expect(plan.lines.count == 1)
        let fragments = line.linkFragments.sorted { $0.rect.minX < $1.rect.minX }
        #expect(fragments.count == 2)
        #expect(Set(fragments.map(\.id)).count == fragments.count)
        var linkedGlyphs = 0
        var unlinkedGlyphs = 0
        for run in CTLineGetGlyphRuns(line.ctLine) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            for index in indices.indices where abs(advances[index].width) > 0.1 {
                let point = CGPoint(x: positions[index].x + advances[index].width / 2, y: plan.lineHeight / 2)
                var tracker = MarkdownCoreTextPaintedLinkClickTracker()
                let clickable = tracker.begin(at: point, fragments: fragments, hitSlop: 0)
                if indices[index] < linkEnd {
                    linkedGlyphs += 1
                    #expect(clickable)
                    #expect(tracker.finish(at: point, fragments: fragments, hitSlop: 0) == "https://example.com/bidi")
                } else {
                    unlinkedGlyphs += 1
                    #expect(!clickable)
                }
            }
        }
        #expect(linkedGlyphs > 0)
        #expect(unlinkedGlyphs > 0)
    }

    @Test func disjointBidiLinkKeepsOneAccessibleElementWithUnionFrame() throws {
        let (plan, _) = try fixture()
        #expect(plan.linkFragments.count == 2)
        let view = MarkdownCoreTextPaintedNSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        view.plan = plan
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.reconcileAccessibleLinks()
        let children = try #require(view.accessibilityChildren() as? [MarkdownAccessibleLink])
        #expect(children.count == 1)
        let child = try #require(children.first)
        #expect(child.accessibilityLabel() == "abc אבג")
        let union = plan.linkFragments.reduce(CGRect.null) { $0.union($1.rect) }
        #expect(child.localFrame == union)
        #expect(!child.accessibilityFrame().isEmpty)
    }
}
#endif
