import SiriusMarkdownCore
import SwiftUI

/// GitHub-inspired heading chrome: semibold weight, an H1/H2 divider
/// underlay, and a tertiary (secondary-text) H6 foreground (Part 03
/// §3.3.2). Heading font size, line height, and weight are set by
/// `MarkdownTheme.gitHub.headings` and already applied to
/// `configuration.label` during prepare — this style only adds chrome
/// around the already-measured label (INV-BS8); it must be paired with
/// `MarkdownTheme.gitHub` (or an equivalent theme) for correct heading
/// metrics, not applied alone (Part 04 §4.4).
public struct MarkdownGitHubHeadingBlockStyle: MarkdownHeadingBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
                .fontWeight(.semibold)
                .foregroundStyle(
                    configuration.headingLevel == 6
                        ? configuration.theme.secondaryTextColor
                        : configuration.theme.textColor
                )
            if configuration.headingLevel == 1 || configuration.headingLevel == 2 {
                Rectangle()
                    .fill(MarkdownGitHubColors.border)
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownHeadingBlockStyle where Self == MarkdownGitHubHeadingBlockStyle {
    public static var gitHub: Self { .init() }
}
