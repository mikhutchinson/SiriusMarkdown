import SiriusMarkdownCore
import SwiftUI

public struct InlineRunsView: View {
    private var runs: [MarkdownInlineRun]
    private var theme: MarkdownTheme
    private var baseFont: Font
    private var linkAction: MarkdownLinkAction?
    private var policy: DefaultMarkdownPolicy

    public init(
        runs: [MarkdownInlineRun],
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        policy: DefaultMarkdownPolicy = DefaultMarkdownPolicy()
    ) {
        self.runs = runs
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
        self.policy = policy
    }

    public var body: some View {
        InlineFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                InlineRunView(
                    run: run,
                    theme: theme,
                    linkAction: linkAction,
                    policy: policy
                )
            }
        }
        .font(baseFont)
        .foregroundStyle(theme.textColor)
    }
}

private struct InlineFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(in: bounds.width, subviews: subviews)
        for item in arrangement.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func arrange(
        in maxWidth: CGFloat,
        subviews: Subviews
    ) -> (items: [LayoutItem], size: CGSize) {
        var items: [LayoutItem] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0
        let effectiveMaxWidth = maxWidth.isFinite ? maxWidth : CGFloat.greatestFiniteMagnitude

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > effectiveMaxWidth {
                measuredWidth = max(measuredWidth, cursor.x - horizontalSpacing)
                cursor.x = 0
                cursor.y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            items.append(LayoutItem(index: index, origin: cursor, size: size))
            cursor.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        measuredWidth = max(measuredWidth, cursor.x > 0 ? cursor.x - horizontalSpacing : 0)
        return (
            items,
            CGSize(
                width: maxWidth.isFinite ? min(measuredWidth, maxWidth) : measuredWidth,
                height: cursor.y + lineHeight
            )
        )
    }

    private struct LayoutItem {
        var index: Int
        var origin: CGPoint
        var size: CGSize
    }
}
