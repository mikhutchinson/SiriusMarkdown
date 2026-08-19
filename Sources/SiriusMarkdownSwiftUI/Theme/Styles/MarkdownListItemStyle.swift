import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownListItemStyle`.
///
/// Marker and content are split (Textual's `ListItemStyleConfiguration`
/// shape) so a style can lay them out however it likes — `marker` is
/// already built from the relevant marker style
/// (`MarkdownUnorderedListMarkerStyle` / `MarkdownOrderedListMarkerStyle` /
/// `MarkdownTaskListMarkerStyle`); `block` is the item's prepared inline
/// content or recursively prepared native child-block stack.
public struct MarkdownListItemStyleConfiguration {
    public var marker: MarkdownBlockStyleLabel
    public var block: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes the layout of one list item's marker + content.
///
/// `makeBody` receives already-built marker and content labels. Parsed native
/// child blocks, including child lists, are already recursively rendered in
/// the content label. Legacy manually constructed `childItems` remain a
/// separately rendered compatibility path. Implementations are not
/// responsible for recursing into either representation (INV-BS2).
@MainActor
public protocol MarkdownListItemStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownListItemStyleConfiguration
}

/// Default list-item style: marker leading, content flowing into the
/// remaining width with 8pt spacing — matching pre-style
/// `MarkdownBlockView` list-item rendering exactly (INV-BS3). Marker
/// width comes from the active marker style's own `.frame(width:)`
/// (`MarkdownStyleLeadingContentLayout` measures it automatically).
public struct MarkdownDefaultListItemStyle: MarkdownListItemStyle {
    static let spacing: CGFloat = 8

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        MarkdownStyleLeadingContentLayout(
            spacing: Self.spacing,
            verticalAlignment: .firstTextBaseline
        ) {
            configuration.marker
            configuration.block
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownListItemStyle where Self == MarkdownDefaultListItemStyle {
    public static var `default`: Self { .init() }
}
