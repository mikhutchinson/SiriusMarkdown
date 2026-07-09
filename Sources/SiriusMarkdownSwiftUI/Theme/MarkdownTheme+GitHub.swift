import SwiftUI

/// GitHub-inspired theme metrics (Part 03 §3.3.1).
///
/// Heading font sizes / line heights / weight live here (not in
/// `MarkdownGitHubHeadingBlockStyle`) because `MarkdownTheme` is the
/// prepare/layout cache identity core (INV-BS1) — CoreText measures
/// headings using these metrics, so painted chrome and prepared line
/// breaks stay in sync (INV-BS8). Approximates Textual's GitHub font
/// scales (`[2, 1.5, 1.25, 1, 0.875, 0.85]`) against a 16pt body using
/// absolute points; not a Dynamic Type / Font-Relative Layout scale
/// (Part 03 §3.7).
public extension MarkdownTheme {
    static var gitHub: MarkdownTheme {
        var theme = MarkdownTheme(
            paragraphFontSize: 16,
            paragraphLineHeight: 24,
            codeFontSize: 14,
            codeLineHeight: 20,
            headings: MarkdownHeadingStyles(
                h1: MarkdownTextStyle(
                    font: .system(size: 32, weight: .semibold),
                    fontSize: 32,
                    lineHeight: 40,
                    fontProfiles: .headingDefault
                ),
                h2: MarkdownTextStyle(
                    font: .system(size: 24, weight: .semibold),
                    fontSize: 24,
                    lineHeight: 32,
                    fontProfiles: .headingDefault
                ),
                h3: MarkdownTextStyle(
                    font: .system(size: 20, weight: .semibold),
                    fontSize: 20,
                    lineHeight: 28,
                    fontProfiles: .headingDefault
                ),
                h4: MarkdownTextStyle(
                    font: .system(size: 16, weight: .semibold),
                    fontSize: 16,
                    lineHeight: 24,
                    fontProfiles: .headingDefault
                ),
                h5: MarkdownTextStyle(
                    font: .system(size: 14, weight: .semibold),
                    fontSize: 14,
                    lineHeight: 20,
                    fontProfiles: .headingDefault
                ),
                h6: MarkdownTextStyle(
                    font: .system(size: 14, weight: .semibold),
                    fontSize: 14,
                    lineHeight: 20,
                    fontProfiles: .headingDefault
                )
            )
        )
        theme.blockSpacing = 12
        theme.quoteAccent = MarkdownGitHubColors.border
        theme.codeBackground = MarkdownGitHubColors.codeBackground
        theme.tableBackground = .clear
        theme.tableHeaderBackground = MarkdownGitHubColors.tableHeaderBackground
        theme.tableAlternateRowBackground = MarkdownGitHubColors.tableAlternateRowBackground
        theme.tableBorderColor = MarkdownGitHubColors.border
        theme.tableAccentColor = MarkdownGitHubColors.outerBorder
        theme.tableCornerRadius = 6
        theme.tableHorizontalCellPadding = 13
        theme.tableVerticalCellPadding = 6
        return theme
    }
}
