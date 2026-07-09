import SwiftUI

/// A type-erased, already-prepared piece of block content passed to a
/// style protocol's `makeBody(configuration:)`.
///
/// `MarkdownBlockView` builds this label from `MarkdownPreparedBlockContent`
/// (prepared inline layout, highlighted code, prepared math, table grids,
/// list markers, …) before invoking a style. Styles decorate an already
/// built label; they never parse Markdown, run inline layout, highlight
/// code, or validate math (INV-BS2, `AGENTS.md`).
public struct MarkdownBlockStyleLabel: View {
    private let content: AnyView

    public init(_ content: some View) {
        self.content = AnyView(content)
    }

    public var body: some View {
        content
    }
}
