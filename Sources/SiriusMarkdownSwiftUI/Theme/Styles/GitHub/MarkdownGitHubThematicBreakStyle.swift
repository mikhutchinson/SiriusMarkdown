import SiriusMarkdownCore
import SwiftUI

/// GitHub-inspired thematic break: a GitHub-border-colored 1pt divider
/// with extra vertical spacing (Part 03 §3.3.2).
public struct MarkdownGitHubThematicBreakStyle: MarkdownThematicBreakStyle {
    public init() {}

    public func makeBody(configuration _: Configuration) -> some View {
        Rectangle()
            .fill(MarkdownGitHubColors.border)
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

extension MarkdownThematicBreakStyle where Self == MarkdownGitHubThematicBreakStyle {
    public static var gitHub: Self { .init() }
}
