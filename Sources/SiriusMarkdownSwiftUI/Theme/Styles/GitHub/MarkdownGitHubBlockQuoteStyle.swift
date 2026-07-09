import SiriusMarkdownCore
import SwiftUI

/// GitHub-inspired block-quote chrome: a 4pt GitHub-border-colored
/// leading bar with 12pt spacing before secondary-colored content
/// (Part 03 §3.3.2).
public struct MarkdownGitHubBlockQuoteStyle: MarkdownBlockQuoteStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        MarkdownStyleLeadingContentLayout(leadingWidth: 4, spacing: 12, stretchesLeadingToContentHeight: true) {
            Rectangle()
                .fill(MarkdownGitHubColors.border)
                .frame(width: 4)
            configuration.label
                .foregroundStyle(configuration.theme.secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownBlockQuoteStyle where Self == MarkdownGitHubBlockQuoteStyle {
    public static var gitHub: Self { .init() }
}
