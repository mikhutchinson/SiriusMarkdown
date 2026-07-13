import SwiftUI

/// A bounded prepared-item region used by ``StreamingMarkdownView``.
///
/// Streaming documents are append-dominant: all but the final parser block are
/// normally sealed, while only the tail changes. Grouping prepared items into
/// small, stable regions gives SwiftUI a persistent layout boundary for sealed
/// history without relying on `LazyVStack`'s viewport recycler. The final
/// region contains at most ``capacity`` items, so a tail publication cannot
/// force an unbounded prepared-item measurement pass.
struct MarkdownStreamingPreparedRegion: Identifiable, Hashable {
    static let capacity = 16

    let id: String
    let revision: Int
    let renderItems: [MarkdownPreparedSnapshotRenderItem]

    var layoutToken: MarkdownStreamingRegionLayoutToken {
        MarkdownStreamingRegionLayoutToken(id: id, revision: revision)
    }

    static func make(
        renderItems: [MarkdownPreparedSnapshotRenderItem],
        layoutContextRevision: Int = 0,
        itemRevision: (MarkdownPreparedSnapshotRenderItem) -> String
    ) -> [Self] {
        guard !renderItems.isEmpty else { return [] }

        var regions: [Self] = []
        regions.reserveCapacity((renderItems.count + capacity - 1) / capacity)

        var start = 0
        while start < renderItems.count {
            let end = min(start + capacity, renderItems.count)
            let items = Array(renderItems[start..<end])
            var fingerprint = Hasher()
            fingerprint.combine(layoutContextRevision)
            fingerprint.combine(items.count)
            for item in items {
                fingerprint.combine(item.id)
                fingerprint.combine(itemRevision(item))
            }
            regions.append(
                Self(
                    id: "prepared-region:\(items[0].id)",
                    revision: fingerprint.finalize(),
                    renderItems: items
                )
            )
            start = end
        }
        return regions
    }
}

struct MarkdownStreamingRegionLayoutToken: Hashable {
    let id: String
    let revision: Int
}

private struct MarkdownStreamingRegionLayoutTokenKey: LayoutValueKey {
    static let defaultValue: MarkdownStreamingRegionLayoutToken? = nil
}

/// Natural sizes reported by mounted prepared regions. Measurements are keyed
/// by both stable region identity and content revision, so a tail publication
/// misses only the final region while sealed regions reuse their settled size.
/// Geometry reports are coalesced to keep initial mounting to one parent
/// invalidation even when a large document contains many regions.
@MainActor
final class MarkdownStreamingRegionMeasurementStore: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private var measurements: [MarkdownStreamingRegionLayoutToken: CGSize] = [:]
    private var pendingMeasurements: [MarkdownStreamingRegionLayoutToken: CGSize] = [:]
    private var flushScheduled = false

    var snapshot: [MarkdownStreamingRegionLayoutToken: CGSize] {
        measurements
    }

    func synchronize(tokens: [MarkdownStreamingRegionLayoutToken]) {
        let retained = Set(tokens)
        measurements = measurements.filter { retained.contains($0.key) }
        pendingMeasurements = pendingMeasurements.filter { retained.contains($0.key) }
    }

    func report(_ size: CGSize, for token: MarkdownStreamingRegionLayoutToken) {
        let settled = Self.quantized(size)
        guard settled.width > 0, settled.height >= 0 else { return }
        if let existing = measurements[token], Self.isApproximatelyEqual(existing, settled) {
            return
        }
        pendingMeasurements[token] = settled
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            await Task<Never, Never>.yield()
            self?.flushPendingMeasurements()
        }
    }

    private func flushPendingMeasurements() {
        flushScheduled = false
        guard !pendingMeasurements.isEmpty else { return }
        let pending = pendingMeasurements
        pendingMeasurements.removeAll(keepingCapacity: true)

        var changed = false
        for (token, size) in pending {
            if let existing = measurements[token], Self.isApproximatelyEqual(existing, size) {
                continue
            }
            measurements[token] = size
            changed = true
        }
        if changed {
            revision &+= 1
        }
    }

    private static func quantized(_ size: CGSize) -> CGSize {
        CGSize(width: quantize(size.width), height: quantize(size.height))
    }

    private static func quantize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return -1 }
        return (value * 2).rounded(.up) / 2
    }

    private static func isApproximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}

/// Non-lazy host-scrolled layout with cross-publication region measurements.
/// `sizeThatFits` calls into SwiftUI only for new/changed regions or a genuine
/// width change. Looking up and placing sealed region rectangles remains
/// linear in the much smaller region count and does not remeasure their block
/// subtrees.
private struct MarkdownStreamingRegionStackLayout: Layout {
    let spacing: CGFloat
    let measurements: [MarkdownStreamingRegionLayoutToken: CGSize]

    struct Cache {
        struct SizeKey: Hashable {
            let token: MarkdownStreamingRegionLayoutToken
            let proposalWidth: Int?
        }

        var proposalWidth: CGFloat?
        var tokens: [MarkdownStreamingRegionLayoutToken?] = []
        var sizes: [CGSize] = []
        var offsets: [CGFloat] = []
        var totalSize: CGSize = .zero
        var sizesByKey: [SizeKey: CGSize] = [:]
    }

    func makeCache(subviews _: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        let activeTokens = Set(
            subviews.compactMap { $0[MarkdownStreamingRegionLayoutTokenKey.self] }
        )
        cache.sizesByKey = cache.sizesByKey.filter { activeTokens.contains($0.key.token) }
        cache.proposalWidth = nil
        cache.tokens.removeAll(keepingCapacity: true)
        cache.sizes.removeAll(keepingCapacity: true)
        cache.offsets.removeAll(keepingCapacity: true)
        cache.totalSize = .zero
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        resolve(proposalWidth: sanitized(proposal.width), subviews: subviews, cache: &cache)
        return cache.totalSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let width = sanitized(bounds.width)
        if cache.sizes.count != subviews.count || !sameWidth(cache.proposalWidth, width) {
            resolve(proposalWidth: width, subviews: subviews, cache: &cache)
        }

        for index in subviews.indices {
            let size = cache.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + cache.offsets[index]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: size.height)
            )
        }
    }

    private func resolve(
        proposalWidth: CGFloat?,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let childProposal = ProposedViewSize(width: proposalWidth, height: nil)
        var tokens: [MarkdownStreamingRegionLayoutToken?] = []
        var sizes: [CGSize] = []
        var offsets: [CGFloat] = []
        tokens.reserveCapacity(subviews.count)
        sizes.reserveCapacity(subviews.count)
        offsets.reserveCapacity(subviews.count)

        var y: CGFloat = 0
        var maximumWidth: CGFloat = 0
        let widthKey = proposalWidth.map { Int(($0 * 2).rounded()) }
        for index in subviews.indices {
            let subview = subviews[index]
            let token = subview[MarkdownStreamingRegionLayoutTokenKey.self]
            let measured = token.flatMap { measurements[$0] }
            let size: CGSize
            if let measured, measurement(measured, matches: proposalWidth) {
                size = measured
                if let token {
                    cache.sizesByKey[Cache.SizeKey(token: token, proposalWidth: widthKey)] = measured
                }
            } else if let token,
                      let cached = cache.sizesByKey[
                          Cache.SizeKey(token: token, proposalWidth: widthKey)
                      ]
            {
                size = cached
            } else {
                size = sanitized(subview.sizeThatFits(childProposal))
                if let token {
                    cache.sizesByKey[Cache.SizeKey(token: token, proposalWidth: widthKey)] = size
                }
            }

            tokens.append(token)
            sizes.append(size)
            offsets.append(y)
            maximumWidth = max(maximumWidth, size.width)
            y += size.height
            if index < subviews.index(before: subviews.endIndex) {
                y += spacing
            }
        }

        cache.proposalWidth = proposalWidth
        cache.tokens = tokens
        cache.sizes = sizes
        cache.offsets = offsets
        cache.totalSize = CGSize(width: proposalWidth ?? maximumWidth, height: y)
    }

    private func measurement(_ size: CGSize, matches proposalWidth: CGFloat?) -> Bool {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height >= 0 else {
            return false
        }
        guard let proposalWidth else { return true }
        return abs(size.width - proposalWidth) < 0.5
    }

    private func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

    private func sanitized(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite, width > 0 else { return nil }
        return width
    }

    private func sameWidth(_ lhs: CGFloat?, _ rhs: CGFloat?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            abs(lhs - rhs) < 0.5
        default:
            false
        }
    }
}

private struct MarkdownStreamingMeasuredRegion<Content: View>: View {
    let token: MarkdownStreamingRegionLayoutToken
    let measurementStore: MarkdownStreamingRegionMeasurementStore
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                measurementStore.report(size, for: token)
            }
    }
}

extension View {
    fileprivate func markdownStreamingRegionLayoutToken(
        _ token: MarkdownStreamingRegionLayoutToken
    ) -> some View {
        layoutValue(key: MarkdownStreamingRegionLayoutTokenKey.self, value: token)
    }
}

@MainActor
func markdownStreamingRegionStack<Content: View>(
    regions: [MarkdownStreamingPreparedRegion],
    spacing: CGFloat,
    measurementStore: MarkdownStreamingRegionMeasurementStore,
    @ViewBuilder content: @escaping (MarkdownPreparedSnapshotRenderItem) -> Content
) -> some View {
    MarkdownStreamingRegionStackLayout(
        spacing: spacing,
        measurements: measurementStore.snapshot
    ) {
        ForEach(regions) { region in
            let token = region.layoutToken
            MarkdownStreamingMeasuredRegion(
                token: token,
                measurementStore: measurementStore
            ) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(region.renderItems) { item in
                        content(item)
                    }
                }
            }
            .markdownStreamingRegionLayoutToken(token)
        }
    }
}
