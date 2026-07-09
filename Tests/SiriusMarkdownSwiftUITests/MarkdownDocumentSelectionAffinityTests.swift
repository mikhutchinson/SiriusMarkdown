import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

// MARK: - Helpers

private func makeFragment(
    id: String,
    byteRange: Range<Int>,
    rect: CGRect
) -> MarkdownDocumentSelectionFragment {
    MarkdownDocumentSelectionFragment(
        id: id,
        blockID: MarkdownBlockID(id),
        sourceRange: MarkdownSourceRange(byteRange: byteRange, lineRange: 1..<2),
        rect: rect
    )
}

// MARK: - Part 01: Continuous drag affinity

@Suite(.serialized)
struct MarkdownDocumentSelectionAffinityTests {

    // MARK: - Nearest-fragment fallback: vertical gutter

    @Test
    @MainActor
    func testHitFragmentInVerticalGutterResolvesNearestFragment() {
        // Fragment A: y 0–20, Fragment B: y 30–50. Pointer at y=25 (in the gutter).
        let fragmentA = makeFragment(id: "a", byteRange: 0..<10, rect: CGRect(x: 0, y: 0, width: 200, height: 20))
        let fragmentB = makeFragment(id: "b", byteRange: 10..<20, rect: CGRect(x: 0, y: 30, width: 200, height: 20))
        let fragments = [fragmentA, fragmentB]
        let pointer = CGPoint(x: 100, y: 25)

        let hit = MarkdownDocumentSelectionFragment.hitFragment(
            at: pointer,
            in: fragments,
            hitSlop: 2,
            affinityHint: nil
        )

        // Pointer is exactly 5 pts below A and 5 pts above B — equal; default (nil hint) prefers downstream (lower byte start).
        #expect(hit != nil, "Gutter pointer must not return nil")
    }

    @Test
    @MainActor
    func testHitFragmentGutterPrefersCloserFragmentWhenUnambiguous() {
        let fragmentA = makeFragment(id: "a", byteRange: 0..<10, rect: CGRect(x: 0, y: 0, width: 200, height: 20))
        let fragmentB = makeFragment(id: "b", byteRange: 10..<20, rect: CGRect(x: 0, y: 40, width: 200, height: 20))
        let fragments = [fragmentA, fragmentB]

        // Pointer at y=24 — 4 pts below A, 16 pts above B → A is closer.
        let hitNearA = MarkdownDocumentSelectionFragment.hitFragment(
            at: CGPoint(x: 100, y: 24),
            in: fragments,
            hitSlop: 2,
            affinityHint: nil
        )
        #expect(hitNearA?.id == "a", "Closer to A: should return A, got \(hitNearA?.id ?? "nil")")

        // Pointer at y=36 — 16 pts below A, 4 pts above B → B is closer.
        let hitNearB = MarkdownDocumentSelectionFragment.hitFragment(
            at: CGPoint(x: 100, y: 36),
            in: fragments,
            hitSlop: 2,
            affinityHint: nil
        )
        #expect(hitNearB?.id == "b", "Closer to B: should return B, got \(hitNearB?.id ?? "nil")")
    }

    @Test
    @MainActor
    func testHitFragmentAffinityHintUpstreamDownstream() {
        // Two fragments equidistant vertically from the pointer.
        let fragmentA = makeFragment(id: "a", byteRange: 0..<10, rect: CGRect(x: 0, y: 0, width: 200, height: 20))
        let fragmentB = makeFragment(id: "b", byteRange: 10..<20, rect: CGRect(x: 0, y: 30, width: 200, height: 20))
        let fragments = [fragmentA, fragmentB]
        let pointer = CGPoint(x: 100, y: 25) // exactly 5 below A, 5 above B

        let upstream = MarkdownDocumentSelectionFragment.hitFragment(
            at: pointer, in: fragments, hitSlop: 2, affinityHint: .upstream
        )
        let downstream = MarkdownDocumentSelectionFragment.hitFragment(
            at: pointer, in: fragments, hitSlop: 2, affinityHint: .downstream
        )

        // upstream  → pointer is moving up → prefer the fragment ABOVE (A, earlier in document).
        #expect(upstream?.id == "a", "Upstream hint should prefer A (earlier in document / above pointer). Got \(upstream?.id ?? "nil")")
        // downstream → pointer is moving down → prefer the fragment BELOW (B, later in document).
        #expect(downstream?.id == "b", "Downstream hint should prefer B (later in document / below pointer). Got \(downstream?.id ?? "nil")")
    }

    @Test
    @MainActor
    func testHitFragmentDirectHitStillTakesPriority() {
        let fragmentA = makeFragment(id: "a", byteRange: 0..<10, rect: CGRect(x: 0, y: 0, width: 200, height: 20))
        let fragmentB = makeFragment(id: "b", byteRange: 10..<20, rect: CGRect(x: 0, y: 100, width: 200, height: 20))
        let pointer = CGPoint(x: 100, y: 10) // inside fragmentA's rect

        let hit = MarkdownDocumentSelectionFragment.hitFragment(
            at: pointer,
            in: [fragmentA, fragmentB],
            hitSlop: 2,
            affinityHint: .downstream
        )
        #expect(hit?.id == "a", "Direct hit inside A's rect must return A regardless of affinity hint")
    }

    @Test
    @MainActor
    func testHitFragmentEmptyFragmentListReturnsNil() {
        let hit = MarkdownDocumentSelectionFragment.hitFragment(
            at: CGPoint(x: 50, y: 50),
            in: [],
            hitSlop: 4,
            affinityHint: nil
        )
        #expect(hit == nil, "Empty fragment list must return nil")
    }

    @Test
    @MainActor
    func testHitFragmentSingleFragmentInGutterRangeReturnsIt() {
        let frag = makeFragment(id: "only", byteRange: 5..<15, rect: CGRect(x: 50, y: 50, width: 100, height: 20))
        // Pointer just below the fragment's Y range — within the gutter threshold (hitSlop × 8 = 16 at slop=2).
        let hit = MarkdownDocumentSelectionFragment.hitFragment(
            at: CGPoint(x: 100, y: 76), // 76-70 = 6 pts below fragment, within threshold
            in: [frag],
            hitSlop: 2,
            affinityHint: .upstream
        )
        #expect(hit?.id == "only", "Fragment within gutter threshold must be returned by nearest-fragment fallback")
    }

    @Test
    @MainActor
    func testHitFragmentFarBeyondSingleFragmentReturnsNil() {
        let frag = makeFragment(id: "only", byteRange: 5..<15, rect: CGRect(x: 50, y: 50, width: 100, height: 20))
        // Pointer far below — beyond the gutter threshold (hitSlop × 8 = 16 at slop=2).
        let hitFar = MarkdownDocumentSelectionFragment.hitFragment(
            at: CGPoint(x: 100, y: 500), // 500-70 = 430 pts below, way beyond threshold
            in: [frag],
            hitSlop: 2,
            affinityHint: nil
        )
        #expect(hitFar == nil, "Pointer far beyond gutter threshold must return nil (no snap to distant text)")
    }

    // MARK: - Endpoint: pointer past line end stays on same fragment

    @Test
    @MainActor
    func testEndpointPastLineEndStaysOnSameFragment() {
        // Create a fragment with inline text geometry spanning bytes 0..<10 at lineWidth 100 pts.
        let source = "Hello"
        let (_, prepared, _) = prepareSelectionSnapshot(source)
        guard let block = prepared.snapshot.blocks.first,
              let content = prepared.preparedContentByBlockID[block.id]
        else {
            return
        }

        let rect = CGRect(x: 0, y: 0, width: 400, height: 30)
        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: rect
        )
        guard let fragment = fragments.first else { return }

        // Pointer way past the right edge of the fragment.
        let farRight = CGPoint(x: rect.maxX + 200, y: rect.midY)
        let endpoint = fragment.endpoint(at: farRight)

        // Endpoint must be within the fragment's own source range (not a neighboring block's).
        let range = fragment.sourceRange.byteRange
        #expect(
            range.contains(endpoint.sourceByteOffset) || endpoint.sourceByteOffset == range.upperBound,
            "X past line end must clamp to this fragment's source range, got \(endpoint.sourceByteOffset) not in \(range)"
        )
    }

    // MARK: - verticalGapDistance helper

    @Test
    @MainActor
    func testVerticalGapDistanceInsideRect() {
        let frag = makeFragment(id: "x", byteRange: 0..<10, rect: CGRect(x: 0, y: 10, width: 100, height: 20))
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 15)) == 0)
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 10)) == 0)
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 30)) == 0)
    }

    @Test
    @MainActor
    func testVerticalGapDistanceAboveRect() {
        let frag = makeFragment(id: "x", byteRange: 0..<10, rect: CGRect(x: 0, y: 10, width: 100, height: 20))
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 5)) == 5.0)
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 0)) == 10.0)
    }

    @Test
    @MainActor
    func testVerticalGapDistanceBelowRect() {
        let frag = makeFragment(id: "x", byteRange: 0..<10, rect: CGRect(x: 0, y: 10, width: 100, height: 20))
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 35)) == 5.0)
        #expect(frag.verticalGapDistance(to: CGPoint(x: 50, y: 50)) == 20.0)
    }

    // MARK: - No unbounded per-glyph overlays (INV-NS2 architecture assertion)

    @Test
    @MainActor
    func testHighlightRectsAreFragmentBounded() {
        // Hit-testing must produce at most one fragment per query, not per-character.
        let fragments = (0..<5).map { i in
            makeFragment(
                id: "f\(i)",
                byteRange: (i * 10)..<(i * 10 + 10),
                rect: CGRect(x: 0, y: CGFloat(i * 25), width: 200, height: 20)
            )
        }
        let range = MarkdownSourceRange(byteRange: 0..<50, lineRange: 1..<6)
        var totalHighlightRects = 0
        for fragment in fragments {
            totalHighlightRects += fragment.highlightRects(for: [range]).count
        }
        // Each fragment overlapping the range emits at most 1 rect (no per-glyph explosion).
        #expect(totalHighlightRects <= fragments.count, "Highlight rects must not exceed fragment count (no per-glyph overlays)")
    }

    // MARK: - Cross-block selection through mixed block types (INV-NS1)

    @Test
    @MainActor
    func testSelectRangeAcrossTwoFragmentsProducesContiguousSourceRange() {
        // Two non-overlapping fragments (different blocks).
        let fragA = makeFragment(id: "a", byteRange: 0..<10, rect: CGRect(x: 0, y: 0, width: 200, height: 20))
        let fragB = makeFragment(id: "b", byteRange: 15..<25, rect: CGRect(x: 0, y: 30, width: 200, height: 20))
        let fragments = [fragA, fragB]

        let lower = MarkdownDocumentSelectionEndpoint(
            blockID: fragA.blockID,
            sourceByteOffset: 2,
            line: 1
        )
        let upper = MarkdownDocumentSelectionEndpoint(
            blockID: fragB.blockID,
            sourceByteOffset: 20,
            line: 2
        )

        let result = MarkdownDocumentSelectionFragment.selection(from: lower, to: upper, in: fragments)
        #expect(result.ranges.count == 1, "Cross-fragment selection must produce one contiguous range")
        let range = result.ranges[0]
        #expect(range.byteRange.lowerBound == 2)
        #expect(range.byteRange.upperBound == 20)
        #expect(result.blockIDs.count > 0, "Must identify selected blocks")
    }
}

// MARK: - Test helper

private func prepareSelectionSnapshot(
    _ source: String
) -> (snapshot: MarkdownSnapshot, prepared: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    return (snapshot, prepared, configuration)
}
