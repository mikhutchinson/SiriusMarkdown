/// An aggregate bundle of per-block style protocols (Textual's
/// `StructuredText.Style` shape, `Markdown`-prefixed).
///
/// Conform to this protocol to restyle several block kinds at once. Every
/// slot has a default (`MarkdownDefault*Style`) via a protocol extension
/// keyed on the associated type, so a conforming type only needs to
/// implement the slots it wants to change:
///
/// ```swift
/// struct ReaderStyle: MarkdownDocumentStyle {
///     var headingStyle: some MarkdownHeadingBlockStyle { UnderlineH1() }
///     // every other slot falls back to its `MarkdownDefault*Style`
/// }
/// ```
///
/// `MarkdownDocumentStyle` values are read only inside `@MainActor`
/// SwiftUI update paths and are consumed through generic (`some
/// MarkdownDocumentStyle`) call sites — never stored as the sole prepare
/// cache identity (INV-BS1) and never required to be `Sendable` /
/// `Hashable` (Part 02).
///
/// Marked `@MainActor` because every per-block slot protocol it bundles
/// (`MarkdownHeadingBlockStyle`, `MarkdownCodeBlockStyle`, etc.) is itself
/// `@MainActor`; matching that isolation here lets the default-style
/// extensions below construct `MarkdownDefault*Style()` values directly.
@MainActor
public protocol MarkdownDocumentStyle {
    associatedtype HeadingStyle: MarkdownHeadingBlockStyle = MarkdownDefaultHeadingBlockStyle
    associatedtype ParagraphStyle: MarkdownParagraphBlockStyle = MarkdownDefaultParagraphBlockStyle
    associatedtype BlockQuoteStyle: MarkdownBlockQuoteStyle = MarkdownDefaultBlockQuoteStyle
    associatedtype CodeBlockStyle: MarkdownCodeBlockStyle = MarkdownDefaultCodeBlockStyle
    associatedtype TableStyle: MarkdownTableBlockStyle = MarkdownDefaultTableBlockStyle
    associatedtype TableCellStyle: MarkdownTableCellStyle = MarkdownDefaultTableCellStyle
    associatedtype ListItemStyle: MarkdownListItemStyle = MarkdownDefaultListItemStyle
    associatedtype UnorderedListMarkerStyle: MarkdownUnorderedListMarkerStyle = MarkdownDefaultUnorderedListMarkerStyle
    associatedtype OrderedListMarkerStyle: MarkdownOrderedListMarkerStyle = MarkdownDefaultOrderedListMarkerStyle
    associatedtype TaskListMarkerStyle: MarkdownTaskListMarkerStyle = MarkdownDefaultTaskListMarkerStyle
    associatedtype ThematicBreakStyle: MarkdownThematicBreakStyle = MarkdownDefaultThematicBreakStyle
    associatedtype MathBlockStyle: MarkdownMathBlockStyle = MarkdownDefaultMathBlockStyle
    associatedtype HTMLBlockStyle: MarkdownHTMLBlockStyle = MarkdownDefaultHTMLBlockStyle
    associatedtype MermaidBlockStyle: MarkdownMermaidBlockStyle = MarkdownDefaultMermaidBlockStyle

    var headingStyle: HeadingStyle { get }
    var paragraphStyle: ParagraphStyle { get }
    var blockQuoteStyle: BlockQuoteStyle { get }
    var codeBlockStyle: CodeBlockStyle { get }
    var tableStyle: TableStyle { get }
    var tableCellStyle: TableCellStyle { get }
    var listItemStyle: ListItemStyle { get }
    var unorderedListMarkerStyle: UnorderedListMarkerStyle { get }
    var orderedListMarkerStyle: OrderedListMarkerStyle { get }
    var taskListMarkerStyle: TaskListMarkerStyle { get }
    var thematicBreakStyle: ThematicBreakStyle { get }
    var mathBlockStyle: MathBlockStyle { get }
    var htmlBlockStyle: HTMLBlockStyle { get }
    var mermaidBlockStyle: MermaidBlockStyle { get }
}

extension MarkdownDocumentStyle where HeadingStyle == MarkdownDefaultHeadingBlockStyle {
    public var headingStyle: HeadingStyle { MarkdownDefaultHeadingBlockStyle() }
}

extension MarkdownDocumentStyle where ParagraphStyle == MarkdownDefaultParagraphBlockStyle {
    public var paragraphStyle: ParagraphStyle { MarkdownDefaultParagraphBlockStyle() }
}

extension MarkdownDocumentStyle where BlockQuoteStyle == MarkdownDefaultBlockQuoteStyle {
    public var blockQuoteStyle: BlockQuoteStyle { MarkdownDefaultBlockQuoteStyle() }
}

extension MarkdownDocumentStyle where CodeBlockStyle == MarkdownDefaultCodeBlockStyle {
    public var codeBlockStyle: CodeBlockStyle { MarkdownDefaultCodeBlockStyle() }
}

extension MarkdownDocumentStyle where TableStyle == MarkdownDefaultTableBlockStyle {
    public var tableStyle: TableStyle { MarkdownDefaultTableBlockStyle() }
}

extension MarkdownDocumentStyle where TableCellStyle == MarkdownDefaultTableCellStyle {
    public var tableCellStyle: TableCellStyle { MarkdownDefaultTableCellStyle() }
}

extension MarkdownDocumentStyle where ListItemStyle == MarkdownDefaultListItemStyle {
    public var listItemStyle: ListItemStyle { MarkdownDefaultListItemStyle() }
}

extension MarkdownDocumentStyle where UnorderedListMarkerStyle == MarkdownDefaultUnorderedListMarkerStyle {
    public var unorderedListMarkerStyle: UnorderedListMarkerStyle { MarkdownDefaultUnorderedListMarkerStyle() }
}

extension MarkdownDocumentStyle where OrderedListMarkerStyle == MarkdownDefaultOrderedListMarkerStyle {
    public var orderedListMarkerStyle: OrderedListMarkerStyle { MarkdownDefaultOrderedListMarkerStyle() }
}

extension MarkdownDocumentStyle where TaskListMarkerStyle == MarkdownDefaultTaskListMarkerStyle {
    public var taskListMarkerStyle: TaskListMarkerStyle { MarkdownDefaultTaskListMarkerStyle() }
}

extension MarkdownDocumentStyle where ThematicBreakStyle == MarkdownDefaultThematicBreakStyle {
    public var thematicBreakStyle: ThematicBreakStyle { MarkdownDefaultThematicBreakStyle() }
}

extension MarkdownDocumentStyle where MathBlockStyle == MarkdownDefaultMathBlockStyle {
    public var mathBlockStyle: MathBlockStyle { MarkdownDefaultMathBlockStyle() }
}

extension MarkdownDocumentStyle where HTMLBlockStyle == MarkdownDefaultHTMLBlockStyle {
    public var htmlBlockStyle: HTMLBlockStyle { MarkdownDefaultHTMLBlockStyle() }
}

extension MarkdownDocumentStyle where MermaidBlockStyle == MarkdownDefaultMermaidBlockStyle {
    public var mermaidBlockStyle: MermaidBlockStyle { MarkdownDefaultMermaidBlockStyle() }
}

/// The all-defaults document style. Reproduces pre-style
/// `MarkdownBlockView` chrome exactly (INV-BS3).
public struct MarkdownDefaultDocumentStyle: MarkdownDocumentStyle {
    public init() {}
}

extension MarkdownDocumentStyle where Self == MarkdownDefaultDocumentStyle {
    public static var `default`: Self { .init() }
}

/// Sendable storage box for an `any MarkdownDocumentStyle` existential.
///
/// `MarkdownDocumentStyle` is `@MainActor` (Part 01), but
/// `MarkdownRendererConfiguration` is `Sendable` (INV-BS1 §2.2 Channel A).
/// `any MarkdownDocumentStyle` is not itself `Sendable` — this box lets
/// configuration carry the existential without requiring conforming
/// style types to declare `Sendable`. `@unchecked` is safe because the
/// wrapped value is only ever *read* (copied out) here; every call that
/// actually invokes a `makeBody` on the wrapped style happens through
/// `@MainActor` call sites in `MarkdownBlockView`, matching the
/// documented "read only inside `@MainActor` SwiftUI update paths"
/// contract on `MarkdownDocumentStyle` above.
struct MarkdownDocumentStyleBox: @unchecked Sendable {
    let style: any MarkdownDocumentStyle

    init(_ style: any MarkdownDocumentStyle) {
        self.style = style
    }
}
