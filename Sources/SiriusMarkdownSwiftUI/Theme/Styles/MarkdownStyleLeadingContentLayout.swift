import SwiftUI

/// Shared two-column layout used by default block-quote and list-item
/// styles: a leading view (accent bar, list marker) followed by flexible
/// content that receives the remaining width. When `leadingWidth` is `nil`
/// the leading subview's own intrinsic width (e.g. a marker's `.frame(width:)`)
/// is measured and reused, so marker width stays owned by marker styles
/// instead of being duplicated here.
///
/// Kept internal — hosts customize chrome through style protocols
/// (`MarkdownBlockQuoteStyle`, `MarkdownListItemStyle`, marker styles),
/// not by depending on this layout type directly.
struct MarkdownStyleLeadingContentLayout: Layout {
    var leadingWidth: CGFloat?
    var spacing: CGFloat
    var stretchesLeadingToContentHeight: Bool = false

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard subviews.count >= 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }

        let resolvedLeadingWidth = leadingWidth ?? subviews[0].sizeThatFits(.unspecified).width
        let availableWidth = finiteWidth(from: proposal)
        let contentWidth = availableWidth.map { max(0, $0 - resolvedLeadingWidth - spacing) }
        let leadingSize = subviews[0].sizeThatFits(
            ProposedViewSize(width: resolvedLeadingWidth, height: proposal.height)
        )
        let contentSize = subviews[1].sizeThatFits(
            ProposedViewSize(width: contentWidth, height: proposal.height)
        )
        let height = max(leadingSize.height, contentSize.height)
        let width = availableWidth ?? resolvedLeadingWidth + spacing + contentSize.width
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard subviews.count >= 2 else {
            subviews.first?.place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
            )
            return
        }

        let resolvedLeadingWidth = leadingWidth ?? subviews[0].sizeThatFits(.unspecified).width
        let contentWidth = max(0, bounds.width - resolvedLeadingWidth - spacing)
        let leadingHeight = stretchesLeadingToContentHeight ? bounds.height : nil
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: resolvedLeadingWidth, height: leadingHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + resolvedLeadingWidth + spacing, y: bounds.minY),
            proposal: ProposedViewSize(width: contentWidth, height: bounds.height)
        )
    }

    private func finiteWidth(from proposal: ProposedViewSize) -> CGFloat? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }
        return width
    }
}
