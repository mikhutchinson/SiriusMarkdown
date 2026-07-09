import SwiftUI

/// Opt-in GitHub-inspired chrome bundle (Part 03; INV-BS4 — never the
/// default). Pair with `MarkdownTheme.gitHub` for correct heading / body
/// / code measurement (INV-BS8) — `MarkdownRendererConfiguration.gitHub`
/// below wires both at once.
///
/// Slots this bundle does not override — paragraph, ordered marker, list
/// item, table, table cell, math, HTML, Mermaid — fall back to their
/// `MarkdownDefault*Style` (Part 03 §3.2): paragraph and ordered markers
/// are structurally identical to GitHub's; table chrome reads
/// GitHub-flavored zebra/border/padding tokens straight from
/// `MarkdownTheme.gitHub` without needing a distinct style; math/HTML/
/// Mermaid have no GitHub-specific spec and stay on readable defaults
/// (Part 03 §3.3.2).
public struct MarkdownGitHubDocumentStyle: MarkdownDocumentStyle {
    // `nonisolated` because `MarkdownRendererConfiguration.gitHub` below
    // constructs this from a nonisolated static computed property — see
    // the identical pattern/rationale on `MarkdownDefaultCodeBlockStyle`
    // and friends in Part 01.
    nonisolated public init() {}

    public var headingStyle: MarkdownGitHubHeadingBlockStyle { .init() }
    public var blockQuoteStyle: MarkdownGitHubBlockQuoteStyle { .init() }
    public var codeBlockStyle: MarkdownGitHubCodeBlockStyle { .init() }
    public var unorderedListMarkerStyle: MarkdownGitHubUnorderedListMarkerStyle { .init() }
    public var thematicBreakStyle: MarkdownGitHubThematicBreakStyle { .init() }
}

extension MarkdownDocumentStyle where Self == MarkdownGitHubDocumentStyle {
    public static var gitHub: Self { .init() }
}

extension MarkdownRendererConfiguration {
    /// Convenience wiring `MarkdownTheme.gitHub` and
    /// `MarkdownGitHubDocumentStyle` together (Part 03 §3.4). Hosts opt in
    /// explicitly by requesting this configuration; it is never the
    /// package default (INV-BS4) — `.compactChat` / `.document` are
    /// unaffected.
    public static var gitHub: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(
            theme: .gitHub,
            inlineRenderingMode: .coreTextPaintedLines,
            documentStyle: MarkdownGitHubDocumentStyle()
        )
    }
}
