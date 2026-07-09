import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownMermaidBlockStyle`.
///
/// `label` is the already-prepared Mermaid diagram view (or a collapsed
/// placeholder) built from `MarkdownPreparedMermaidDiagram` — styles never
/// render Mermaid source themselves. Sirius adds this slot because it has
/// no Textual equivalent; the diagram renderer stays pluggable through
/// `MarkdownRendererConfiguration.mermaidRenderer`.
public struct MarkdownMermaidBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var languageLabel: String?
    public var isCollapsed: Bool
    public var actions: MarkdownCodeBlockActions

    /// Whether default chrome would show a header row for this
    /// configuration, given `theme.codeBlockAffordances` and which
    /// actions are actually available. Custom styles may ignore this.
    public var showsDefaultHeader: Bool {
        MarkdownDefaultCodeChromeHeader.showsHeader(
            theme: theme,
            languageLabel: languageLabel,
            actions: actions
        )
    }
}

/// Customizes chrome around an already-prepared Mermaid diagram label.
///
/// `makeBody` receives a prepared diagram view as `configuration.label`.
/// Implementations must not render Mermaid source or reimplement
/// pasteboard/export behavior — use `configuration.actions` (INV-BS2).
@MainActor
public protocol MarkdownMermaidBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownMermaidBlockStyleConfiguration
}

/// Default Mermaid-block style: the same language-label + copy/export/
/// collapse header used by code blocks, `theme.codeBackground` fill, and
/// a 6pt corner radius — matching pre-style `MarkdownBlockView` Mermaid
/// rendering exactly (INV-BS3).
public struct MarkdownDefaultMermaidBlockStyle: MarkdownMermaidBlockStyle {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                configuration.label
                    .padding(.horizontal, 10)
                    .padding(.top, showsHeader ? 4 : 10)
                    .padding(.bottom, 10)
            }
        }
        .background(configuration.theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension MarkdownMermaidBlockStyle where Self == MarkdownDefaultMermaidBlockStyle {
    public static var `default`: Self { .init() }
}
