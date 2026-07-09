import SiriusMarkdownCore
import SwiftUI

/// GitHub-inspired code-block chrome: the same copy/export/collapse
/// header as the default style (`MarkdownDefaultCodeChromeHeader`), a 6pt
/// corner radius, and denser 16pt padding approximating GitHub's README
/// code blocks (Part 03 §3.3.2). `configuration.theme.codeBackground`
/// already resolves to `MarkdownGitHubColors.codeBackground` when paired
/// with `MarkdownTheme.gitHub`. Horizontal-overflow scroll containment is
/// preserved, matching the default style (INV-BS3-adjacent — GitHub is
/// not required to match defaults, but streaming/overflow safety still
/// applies to every style, INV-BS6).
public struct MarkdownGitHubCodeBlockStyle: MarkdownCodeBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let showsHeader = configuration.showsDefaultHeader
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                MarkdownDefaultCodeChromeHeader(
                    theme: configuration.theme,
                    languageLabel: configuration.languageLabel,
                    isCollapsed: configuration.isCollapsed,
                    actions: configuration.actions
                )
            }
            if configuration.isCollapsed {
                configuration.label
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal) {
                    configuration.label
                        .padding(.horizontal, 16)
                        .padding(.top, showsHeader ? 6 : 16)
                        .padding(.bottom, 16)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(configuration.theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension MarkdownCodeBlockStyle where Self == MarkdownGitHubCodeBlockStyle {
    public static var gitHub: Self { .init() }
}
