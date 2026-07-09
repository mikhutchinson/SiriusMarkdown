import SwiftUI

/// GitHub-inspired color tokens shared by `MarkdownTheme.gitHub` and the
/// `MarkdownGitHub*Style` chrome (Part 03 §3.3.1).
///
/// These are built from SwiftUI's semantic system colors (`.primary`,
/// `.secondary`, `.blue`) with opacity tuning — the same approach every
/// other `MarkdownTheme` preset already uses — rather than fixed sRGB
/// values or asset-catalog colors, so they adapt to light/dark and any
/// platform accent-color customization automatically without requiring a
/// bundled asset catalog (Part 03 §3.3.1 "do not depend on asset
/// catalogs"). This approximates GitHub's palette; it is not a pixel
/// match for github.com's CSS (Part 03 §3.3.3).
enum MarkdownGitHubColors {
    /// GitHub's ubiquitous hairline border/divider color (table borders,
    /// block-quote bar, thematic breaks, H1/H2 heading underline).
    static let border = Color.primary.opacity(0.14)

    /// Slightly stronger border used for the table's outer edge.
    static let outerBorder = Color.primary.opacity(0.2)

    /// Code block / inline code background ("canvas.subtle" analog).
    static let codeBackground = Color.primary.opacity(0.055)

    /// Table header row background.
    static let tableHeaderBackground = Color.primary.opacity(0.05)

    /// Table zebra-striped row background.
    static let tableAlternateRowBackground = Color.primary.opacity(0.03)

    /// GitHub's link/accent blue. Uses the system semantic blue rather
    /// than a fixed hex so it still adapts across light/dark and
    /// increased-contrast accessibility settings.
    static let accent = Color.blue
}
