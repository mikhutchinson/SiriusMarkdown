import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownListItemStyle`.
///
/// Marker and content are split (Textual's `ListItemStyleConfiguration`
/// shape) so a style can lay them out however it likes — `marker` is
/// already built from the relevant marker style
/// (`MarkdownUnorderedListMarkerStyle` / `MarkdownOrderedListMarkerStyle` /
/// `MarkdownTaskListMarkerStyle`); `block` is the item's own prepared
/// inline content, not including nested child lists.
public struct MarkdownListItemStyleConfiguration {
    public var marker: MarkdownBlockStyleLabel
    public var block: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes the layout of one list item's marker + content.
///
/// `makeBody` receives already-built marker and content labels. Nested
/// child lists are rendered separately by `MarkdownBlockView`, indented
/// beneath this item — implementations are not responsible for recursing
/// into children (INV-BS2).
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
        MarkdownStyleLeadingContentLayout(spacing: Self.spacing) {
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
