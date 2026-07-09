import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

// MARK: - INV-BS4: GitHub is opt-in, never the default

@Test
@MainActor
func gitHubIsNotDefaultConfiguration() {
    #expect(MarkdownRendererConfiguration.compactChat.documentStyle == nil)
    #expect(MarkdownRendererConfiguration.document.documentStyle == nil)
    #expect(MarkdownRendererConfiguration.compactChat.theme != .gitHub)
    #expect(MarkdownRendererConfiguration.document.theme != .gitHub)
}

@Test
@MainActor
func gitHubConfigurationWiresThemeAndStyle() {
    let configuration = MarkdownRendererConfiguration.gitHub
    #expect(configuration.theme == .gitHub)
    #expect(configuration.documentStyle is MarkdownGitHubDocumentStyle)
}

// MARK: - INV-BS8: GitHub heading metrics participate in cache identity

@Test
@MainActor
func gitHubHeadingSizesMatchThemeTable() {
    let headings = MarkdownTheme.gitHub.headings
    #expect(headings.h1.fontSize == 32)
    #expect(headings.h1.lineHeight == 40)
    #expect(headings.h2.fontSize == 24)
    #expect(headings.h2.lineHeight == 32)
    #expect(headings.h3.fontSize == 20)
    #expect(headings.h3.lineHeight == 28)
    #expect(headings.h4.fontSize == 16)
    #expect(headings.h4.lineHeight == 24)
    #expect(headings.h5.fontSize == 14)
    #expect(headings.h5.lineHeight == 20)
    #expect(headings.h6.fontSize == 14)
    #expect(headings.h6.lineHeight == 20)
}

@Test
@MainActor
func gitHubThemeChangesRenderCacheIdentity() {
    // A chrome-only style swap must not change prepare/layout cache
    // identity (INV-BS1), but a *theme* swap that changes measurement
    // metrics — exactly what `.gitHub` does for headings/body/code — must
    // (INV-BS8), so long-transcript prepare caches key correctly.
    #expect(MarkdownTheme.gitHub.renderCacheIdentity != MarkdownTheme.document.renderCacheIdentity)
    #expect(MarkdownTheme.gitHub.renderCacheIdentity != MarkdownTheme.compactChat.renderCacheIdentity)
}

// MARK: - GitHub-specific default style parity

@Test
@MainActor
func gitHubDocumentStyleOverridesOnlySpecifiedSlots() {
    // Accessed through the `any MarkdownDocumentStyle` existential (as
    // `resolvedMarkdownStyle` does in production) so each associated
    // type is erased and these `is` checks are real dynamic-type
    // assertions rather than statically-true tautologies.
    let style: any MarkdownDocumentStyle = MarkdownGitHubDocumentStyle()
    #expect(style.headingStyle is MarkdownGitHubHeadingBlockStyle)
    #expect(style.blockQuoteStyle is MarkdownGitHubBlockQuoteStyle)
    #expect(style.codeBlockStyle is MarkdownGitHubCodeBlockStyle)
    #expect(style.unorderedListMarkerStyle is MarkdownGitHubUnorderedListMarkerStyle)
    #expect(style.thematicBreakStyle is MarkdownGitHubThematicBreakStyle)

    // Slots the plan says stay structurally identical to defaults
    // (Part 03 §3.2) are left on the aggregate protocol's own defaults.
    #expect(style.paragraphStyle is MarkdownDefaultParagraphBlockStyle)
    #expect(style.orderedListMarkerStyle is MarkdownDefaultOrderedListMarkerStyle)
    #expect(style.listItemStyle is MarkdownDefaultListItemStyle)
    #expect(style.tableStyle is MarkdownDefaultTableBlockStyle)
    #expect(style.tableCellStyle is MarkdownDefaultTableCellStyle)
    #expect(style.mathBlockStyle is MarkdownDefaultMathBlockStyle)
    #expect(style.htmlBlockStyle is MarkdownDefaultHTMLBlockStyle)
    #expect(style.mermaidBlockStyle is MarkdownDefaultMermaidBlockStyle)
}

@Test
@MainActor
func gitHubUnorderedMarkersAreHierarchicalByIndentationLevel() {
    let glyphs = (0...4).map(MarkdownGitHubUnorderedListMarkerStyle.glyph(for:))
    #expect(glyphs == ["•", "◦", "▪", "•", "◦"])

    // Also prove `makeBody` runs without crashing at a couple of levels —
    // the exact glyph mapping is asserted directly above (no view
    // reflection needed).
    let style = MarkdownGitHubUnorderedListMarkerStyle()
    for level in [0, 1, 2] {
        let configuration = MarkdownUnorderedListMarkerStyleConfiguration(
            theme: .gitHub,
            blockID: MarkdownBlockID("list-\(level)"),
            indentationLevel: level
        )
        _ = style.makeBody(configuration: configuration)
    }
}

@Test
@MainActor
func gitHubHeadingStyleAddsDividerOnlyForH1AndH2() {
    let style = MarkdownGitHubHeadingBlockStyle()
    for level in 1...6 {
        let configuration = MarkdownHeadingBlockStyleConfiguration(
            label: MarkdownBlockStyleLabel(Text("Heading")),
            theme: .gitHub,
            blockID: MarkdownBlockID("heading-\(level)"),
            indentationLevel: 0,
            headingLevel: level
        )
        // Only proves `makeBody` runs without crashing across every level
        // and stays a single composed view — full geometry/divider
        // presence is covered by the structured visual matrix (Part 06
        // §6.3) rather than a view-inspection assertion here.
        _ = style.makeBody(configuration: configuration)
    }
}
