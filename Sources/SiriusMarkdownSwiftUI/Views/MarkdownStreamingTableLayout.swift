import SiriusMarkdownCore
import SwiftUI

/// Stable row or bounded row-group identity plus the revisions that can change
/// its measured size. Historical groups keep the same token while only the
/// mutable suffix grows; a bounded column-width bucket change intentionally
/// invalidates every group because the grid geometry genuinely changed.
struct MarkdownStreamingTableRowLayoutToken: Hashable {
    let id: String
    let contentFingerprint: MarkdownContentFingerprint
    let columnWidthFingerprint: MarkdownContentFingerprint
    let columnWidthRevision: UInt64
    let layoutContextIdentity: String
    let inlineRenderingMode: MarkdownInlineRenderingMode
    let nativeTextSelection: MarkdownNativeTextSelection
    let preparedLayoutHeight: Double?
}

/// Everything that can change the default table row's constructed SwiftUI
/// subtree. Layout identity remains separate so link-action replacement does
/// not discard a still-valid natural-size measurement.
struct MarkdownStreamingTableRowRenderToken: Hashable {
    let layoutToken: MarkdownStreamingTableRowLayoutToken
    let columnAlignments: [MarkdownTableColumnAlignment?]
    let linkActionIdentity: UUID?
}

/// Defers construction of a default table row until SwiftUI determines that
/// its explicit render token changed. A growing table republishes its block on
/// every tail append; without this boundary SwiftUI reevaluates every retained
/// row and all of its inline leaf values even though their prepared models are
/// immutable.
struct MarkdownStreamingTableRowRenderBoundary<Content: View>: View, Equatable {
    let token: MarkdownStreamingTableRowRenderToken
    let diagnosticsRecorder: MarkdownDiagnosticsRecorder
    private let content: () -> Content

    init(
        token: MarkdownStreamingTableRowRenderToken,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.token = token
        self.diagnosticsRecorder = diagnosticsRecorder
        self.content = content
    }

    nonisolated static func == (
        lhs: MarkdownStreamingTableRowRenderBoundary<Content>,
        rhs: MarkdownStreamingTableRowRenderBoundary<Content>
    ) -> Bool {
        let reused = lhs.token == rhs.token
        lhs.diagnosticsRecorder.recordTableRowBodyComparison(reused: reused)
        return reused
    }

    var body: some View {
        evaluatedContent
    }

    private var evaluatedContent: Content {
        diagnosticsRecorder.recordTableRowBodyEvaluation()
        return content()
    }
}

private struct MarkdownStreamingTableRowLayoutTokenKey: LayoutValueKey {
    static let defaultValue: MarkdownStreamingTableRowLayoutToken? = nil
}

/// Non-lazy table row stack with cross-publication natural-size reuse.
///
/// A regular `VStack` may ask every accumulated row to remeasure whenever the
/// active table tail publishes. This layout keeps natural sizes keyed by the
/// stable row token and proposal width, so only a new/changed tail row (or a
/// real column-width revision) enters the row subtree's `sizeThatFits` path.
struct MarkdownStreamingTableRowStackLayout: Layout {
    let diagnosticsRecorder: MarkdownDiagnosticsRecorder
    let measurementCache: MarkdownRenderPreparationCache?

    struct Cache {
        var sizes: [CGSize] = []
        var offsets: [CGFloat] = []
        var totalSize: CGSize = .zero
        var sizesByToken: [MarkdownStreamingTableRowLayoutToken: CGSize] = [:]
    }

    func makeCache(subviews _: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        guard measurementCache != nil else {
            // A custom cell style has no required cache identity. Its padding,
            // minimum height, or other geometry may change while row/content
            // tokens stay stable, so never carry natural sizes across view
            // updates for that path.
            cache.sizesByToken.removeAll(keepingCapacity: true)
            cache.sizes.removeAll(keepingCapacity: true)
            cache.offsets.removeAll(keepingCapacity: true)
            cache.totalSize = .zero
            return
        }
        let activeTokens = Set(
            subviews.compactMap { $0[MarkdownStreamingTableRowLayoutTokenKey.self] }
        )
        cache.sizesByToken = cache.sizesByToken.filter { activeTokens.contains($0.key) }
        cache.sizes.removeAll(keepingCapacity: true)
        cache.offsets.removeAll(keepingCapacity: true)
        cache.totalSize = .zero
    }

    func sizeThatFits(
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        resolve(subviews: subviews, cache: &cache)
        return cache.totalSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        if cache.sizes.count != subviews.count {
            resolve(subviews: subviews, cache: &cache)
        }

        for index in subviews.indices {
            let size = cache.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + cache.offsets[index]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func resolve(
        subviews: Subviews,
        cache: inout Cache
    ) {
        // Every cell has an explicit prepared column width, so a row's
        // natural size is independent of the outer horizontal proposal.
        // Keying by the proposal caused scroll-view fitting passes to create
        // many redundant cache entries for the same fixed-width row.
        let childProposal = ProposedViewSize.unspecified
        var sizes: [CGSize] = []
        var offsets: [CGFloat] = []
        sizes.reserveCapacity(subviews.count)
        offsets.reserveCapacity(subviews.count)

        var y: CGFloat = 0
        var maximumWidth: CGFloat = 0
        for index in subviews.indices {
            let subview = subviews[index]
            let token = subview[MarkdownStreamingTableRowLayoutTokenKey.self]
            var size: CGSize
            if let measurementCache,
               let token,
               let cached = cache.sizesByToken[token] ?? measurementCache.tableRowSize(for: token)
            {
                size = cached
                cache.sizesByToken[token] = cached
                diagnosticsRecorder.recordTableRowLayoutCacheHit()
            } else {
                size = sanitized(subview.sizeThatFits(childProposal))
                diagnosticsRecorder.recordTableRowLayoutMeasurement()
                if let preparedHeight = token?.preparedLayoutHeight,
                   preparedHeight.isFinite,
                   preparedHeight > 0
                {
                    size.height = max(size.height, CGFloat(preparedHeight))
                }
                if let measurementCache, let token {
                    cache.sizesByToken[token] = size
                    measurementCache.storeTableRowSize(size, for: token)
                }
            }
            sizes.append(size)
            offsets.append(y)
            y += size.height
            maximumWidth = max(maximumWidth, size.width)
        }

        cache.sizes = sizes
        cache.offsets = offsets
        cache.totalSize = CGSize(width: maximumWidth, height: y)
    }

    private func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

}

extension View {
    func markdownStreamingTableRowLayoutToken(
        _ token: MarkdownStreamingTableRowLayoutToken
    ) -> some View {
        layoutValue(key: MarkdownStreamingTableRowLayoutTokenKey.self, value: token)
    }
}
