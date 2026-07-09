import SwiftUI

// MARK: - Merge-order resolution (INV-BS9)

/// Resolves one style slot using Sirius's explicit override order:
///
/// ```
/// environment per-slot override
///   ?? environment aggregate (`.markdown.documentStyle`) slot
///   ?? `configuration.documentStyle` slot
///   ?? `MarkdownDefault*Style`
/// ```
///
/// Per-slot environment modifiers always win over an aggregate document
/// style regardless of modifier application order, avoiding Textual bug
/// #45 (an aggregate applied after a per-block override silently
/// clobbering it) — see Part 02 §2.3. `internal` (not `private`) so
/// `@testable import` tests can exercise merge order directly without
/// rendering a full view (Part 02 §2.6, Part 06).
@MainActor
func resolvedMarkdownStyle<Style>(
    override: Style?,
    aggregate: (any MarkdownDocumentStyle)?,
    configuration: MarkdownRendererConfiguration,
    slot: (any MarkdownDocumentStyle) -> Style?,
    default defaultStyle: @autoclosure () -> Style
) -> Style {
    override
        ?? aggregate.flatMap(slot)
        ?? configuration.documentStyle.flatMap(slot)
        ?? defaultStyle()
}

// MARK: - Environment keys

/// Per-slot override keys default to `nil` ("unspecified"), not a
/// concrete `MarkdownDefault*Style`. `EnvironmentKey.defaultValue` runs in
/// a nonisolated context and cannot construct `@MainActor`-isolated
/// default style values; falling back to `MarkdownDefault*Style()` only
/// happens inside `resolvedMarkdownStyle`, called from `@MainActor`
/// `MarkdownBlockView` / `MarkdownListItemRow` (Part 02 §2.2 Channel B).
private struct MarkdownHeadingBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownHeadingBlockStyle)? { nil }
}

private struct MarkdownParagraphBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownParagraphBlockStyle)? { nil }
}

private struct MarkdownBlockQuoteStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownBlockQuoteStyle)? { nil }
}

private struct MarkdownCodeBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownCodeBlockStyle)? { nil }
}

private struct MarkdownTableBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownTableBlockStyle)? { nil }
}

private struct MarkdownTableCellStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownTableCellStyle)? { nil }
}

private struct MarkdownListItemStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownListItemStyle)? { nil }
}

private struct MarkdownUnorderedListMarkerStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownUnorderedListMarkerStyle)? { nil }
}

private struct MarkdownOrderedListMarkerStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownOrderedListMarkerStyle)? { nil }
}

private struct MarkdownTaskListMarkerStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownTaskListMarkerStyle)? { nil }
}

private struct MarkdownThematicBreakStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownThematicBreakStyle)? { nil }
}

private struct MarkdownMathBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownMathBlockStyle)? { nil }
}

private struct MarkdownHTMLBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownHTMLBlockStyle)? { nil }
}

private struct MarkdownMermaidBlockStyleOverrideKey: EnvironmentKey {
    static var defaultValue: (any MarkdownMermaidBlockStyle)? { nil }
}

/// Aggregate document style set by `.markdown.documentStyle(_:)`. Distinct
/// from `MarkdownRendererConfiguration.documentStyle` (Channel A) so the
/// merge order in `resolvedMarkdownStyle` can prefer environment over
/// configuration (Part 02 §2.3).
private struct MarkdownDocumentStyleAggregateKey: EnvironmentKey {
    static var defaultValue: (any MarkdownDocumentStyle)? { nil }
}

extension EnvironmentValues {
    var markdownHeadingBlockStyleOverride: (any MarkdownHeadingBlockStyle)? {
        get { self[MarkdownHeadingBlockStyleOverrideKey.self] }
        set { self[MarkdownHeadingBlockStyleOverrideKey.self] = newValue }
    }

    var markdownParagraphBlockStyleOverride: (any MarkdownParagraphBlockStyle)? {
        get { self[MarkdownParagraphBlockStyleOverrideKey.self] }
        set { self[MarkdownParagraphBlockStyleOverrideKey.self] = newValue }
    }

    var markdownBlockQuoteStyleOverride: (any MarkdownBlockQuoteStyle)? {
        get { self[MarkdownBlockQuoteStyleOverrideKey.self] }
        set { self[MarkdownBlockQuoteStyleOverrideKey.self] = newValue }
    }

    var markdownCodeBlockStyleOverride: (any MarkdownCodeBlockStyle)? {
        get { self[MarkdownCodeBlockStyleOverrideKey.self] }
        set { self[MarkdownCodeBlockStyleOverrideKey.self] = newValue }
    }

    var markdownTableBlockStyleOverride: (any MarkdownTableBlockStyle)? {
        get { self[MarkdownTableBlockStyleOverrideKey.self] }
        set { self[MarkdownTableBlockStyleOverrideKey.self] = newValue }
    }

    var markdownTableCellStyleOverride: (any MarkdownTableCellStyle)? {
        get { self[MarkdownTableCellStyleOverrideKey.self] }
        set { self[MarkdownTableCellStyleOverrideKey.self] = newValue }
    }

    var markdownListItemStyleOverride: (any MarkdownListItemStyle)? {
        get { self[MarkdownListItemStyleOverrideKey.self] }
        set { self[MarkdownListItemStyleOverrideKey.self] = newValue }
    }

    var markdownUnorderedListMarkerStyleOverride: (any MarkdownUnorderedListMarkerStyle)? {
        get { self[MarkdownUnorderedListMarkerStyleOverrideKey.self] }
        set { self[MarkdownUnorderedListMarkerStyleOverrideKey.self] = newValue }
    }

    var markdownOrderedListMarkerStyleOverride: (any MarkdownOrderedListMarkerStyle)? {
        get { self[MarkdownOrderedListMarkerStyleOverrideKey.self] }
        set { self[MarkdownOrderedListMarkerStyleOverrideKey.self] = newValue }
    }

    var markdownTaskListMarkerStyleOverride: (any MarkdownTaskListMarkerStyle)? {
        get { self[MarkdownTaskListMarkerStyleOverrideKey.self] }
        set { self[MarkdownTaskListMarkerStyleOverrideKey.self] = newValue }
    }

    var markdownThematicBreakStyleOverride: (any MarkdownThematicBreakStyle)? {
        get { self[MarkdownThematicBreakStyleOverrideKey.self] }
        set { self[MarkdownThematicBreakStyleOverrideKey.self] = newValue }
    }

    var markdownMathBlockStyleOverride: (any MarkdownMathBlockStyle)? {
        get { self[MarkdownMathBlockStyleOverrideKey.self] }
        set { self[MarkdownMathBlockStyleOverrideKey.self] = newValue }
    }

    var markdownHTMLBlockStyleOverride: (any MarkdownHTMLBlockStyle)? {
        get { self[MarkdownHTMLBlockStyleOverrideKey.self] }
        set { self[MarkdownHTMLBlockStyleOverrideKey.self] = newValue }
    }

    var markdownMermaidBlockStyleOverride: (any MarkdownMermaidBlockStyle)? {
        get { self[MarkdownMermaidBlockStyleOverrideKey.self] }
        set { self[MarkdownMermaidBlockStyleOverrideKey.self] = newValue }
    }

    var markdownDocumentStyleAggregate: (any MarkdownDocumentStyle)? {
        get { self[MarkdownDocumentStyleAggregateKey.self] }
        set { self[MarkdownDocumentStyleAggregateKey.self] = newValue }
    }
}

// MARK: - `.markdown` namespace (Part 02 §2.2 Channel B)

/// Per-slot and aggregate block-style modifiers, mirroring Textual's
/// `View+Textual.swift` namespace shape. Per-block modifiers always win
/// over `.markdown.documentStyle(_:)` regardless of application order
/// (INV-BS9) — see `resolvedMarkdownStyle`.
public struct MarkdownNamespace<Base: View> {
    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    public func headingStyle(_ style: some MarkdownHeadingBlockStyle) -> some View {
        base.environment(\.markdownHeadingBlockStyleOverride, style)
    }

    public func paragraphStyle(_ style: some MarkdownParagraphBlockStyle) -> some View {
        base.environment(\.markdownParagraphBlockStyleOverride, style)
    }

    public func blockQuoteStyle(_ style: some MarkdownBlockQuoteStyle) -> some View {
        base.environment(\.markdownBlockQuoteStyleOverride, style)
    }

    public func codeBlockStyle(_ style: some MarkdownCodeBlockStyle) -> some View {
        base.environment(\.markdownCodeBlockStyleOverride, style)
    }

    public func tableStyle(_ style: some MarkdownTableBlockStyle) -> some View {
        base.environment(\.markdownTableBlockStyleOverride, style)
    }

    public func tableCellStyle(_ style: some MarkdownTableCellStyle) -> some View {
        base.environment(\.markdownTableCellStyleOverride, style)
    }

    public func listItemStyle(_ style: some MarkdownListItemStyle) -> some View {
        base.environment(\.markdownListItemStyleOverride, style)
    }

    public func unorderedListMarkerStyle(_ style: some MarkdownUnorderedListMarkerStyle) -> some View {
        base.environment(\.markdownUnorderedListMarkerStyleOverride, style)
    }

    public func orderedListMarkerStyle(_ style: some MarkdownOrderedListMarkerStyle) -> some View {
        base.environment(\.markdownOrderedListMarkerStyleOverride, style)
    }

    public func taskListMarkerStyle(_ style: some MarkdownTaskListMarkerStyle) -> some View {
        base.environment(\.markdownTaskListMarkerStyleOverride, style)
    }

    public func thematicBreakStyle(_ style: some MarkdownThematicBreakStyle) -> some View {
        base.environment(\.markdownThematicBreakStyleOverride, style)
    }

    public func mathBlockStyle(_ style: some MarkdownMathBlockStyle) -> some View {
        base.environment(\.markdownMathBlockStyleOverride, style)
    }

    public func htmlBlockStyle(_ style: some MarkdownHTMLBlockStyle) -> some View {
        base.environment(\.markdownHTMLBlockStyleOverride, style)
    }

    public func mermaidBlockStyle(_ style: some MarkdownMermaidBlockStyle) -> some View {
        base.environment(\.markdownMermaidBlockStyleOverride, style)
    }

    /// Sets every block style slot from an aggregate document style.
    ///
    /// Slots set by a per-block modifier (`.markdown.headingStyle(...)`,
    /// etc.) still win over this aggregate regardless of whether this
    /// modifier is applied before or after them (INV-BS9) — the two live
    /// in separate environment keys, resolved in `resolvedMarkdownStyle`.
    public func documentStyle(_ style: some MarkdownDocumentStyle) -> some View {
        base.environment(\.markdownDocumentStyleAggregate, style)
    }
}

extension View {
    /// Entry point for Sirius's per-block style modifiers, e.g.
    /// `someView.markdown.headingStyle(UnderlineH1())`.
    public var markdown: MarkdownNamespace<Self> {
        MarkdownNamespace(self)
    }
}
