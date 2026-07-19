import SwiftUI

enum MarkdownStyleLeadingContentVerticalAlignment: Equatable {
    case top
    case firstTextBaseline
}

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
    var verticalAlignment: MarkdownStyleLeadingContentVerticalAlignment = .top

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
        let contentDimensions = subviews[1].dimensions(
            // Text and prepared inline surfaces are intrinsically tall. Passing
            // the enclosing proposal's height here makes flexible wrappers
            // vertically center their child and publishes a displaced baseline.
            in: ProposedViewSize(width: contentWidth, height: nil)
        )
        let leadingDimensions = subviews[0].dimensions(
            in: ProposedViewSize(
                width: resolvedLeadingWidth,
                height: stretchesLeadingToContentHeight ? contentDimensions.height : nil
            )
        )
        let offsets = verticalOffsets(
            leadingDimensions: leadingDimensions,
            contentDimensions: contentDimensions
        )
        let height = max(
            offsets.leading + leadingDimensions.height,
            offsets.content + contentDimensions.height
        )
        let width = availableWidth ?? resolvedLeadingWidth + spacing + contentDimensions.width
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
        let contentDimensions = subviews[1].dimensions(
            in: ProposedViewSize(width: contentWidth, height: nil)
        )
        let leadingHeight = stretchesLeadingToContentHeight ? contentDimensions.height : nil
        let leadingDimensions = subviews[0].dimensions(
            in: ProposedViewSize(width: resolvedLeadingWidth, height: leadingHeight)
        )
        let offsets = verticalOffsets(
            leadingDimensions: leadingDimensions,
            contentDimensions: contentDimensions
        )
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + offsets.leading),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: resolvedLeadingWidth, height: leadingHeight)
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.minX + resolvedLeadingWidth + spacing,
                y: bounds.minY + offsets.content
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: contentWidth, height: contentDimensions.height)
        )
    }

    private func verticalOffsets(
        leadingDimensions: ViewDimensions,
        contentDimensions: ViewDimensions
    ) -> (leading: CGFloat, content: CGFloat) {
        guard verticalAlignment == .firstTextBaseline,
              !stretchesLeadingToContentHeight
        else {
            return (0, 0)
        }

        return Self.firstTextBaselineOffsets(
            leadingBaseline: leadingDimensions[.firstTextBaseline],
            contentBaseline: contentDimensions[.firstTextBaseline]
        )
    }

    static func firstTextBaselineOffsets(
        leadingBaseline: CGFloat,
        contentBaseline: CGFloat
    ) -> (leading: CGFloat, content: CGFloat) {
        let sharedBaseline = max(leadingBaseline, contentBaseline)
        return (
            max(0, sharedBaseline - leadingBaseline),
            max(0, sharedBaseline - contentBaseline)
        )
    }

    private func finiteWidth(from proposal: ProposedViewSize) -> CGFloat? {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return nil
        }
        return width
    }
}
