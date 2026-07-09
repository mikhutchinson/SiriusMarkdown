import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownTableBlockStyle`.
///
/// `label` is the already-built table grid (header row plus body rows),
/// with every cell already run through `MarkdownTableCellStyle`. This
/// style wraps the grid with an outer container only; row/zebra
/// backgrounds stay theme-owned (`tableHeaderBackground`,
/// `tableAlternateRowBackground`) so a GitHub-style zebra table does not
/// require a custom style, only a matching theme (INV-BS8).
public struct MarkdownTableBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes chrome around an already-built table grid.
///
/// `makeBody` receives the prepared table grid as `configuration.label`.
/// Implementations must not build rows/cells from raw table data
/// (INV-BS2).
@MainActor
public protocol MarkdownTableBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownTableBlockStyleConfiguration
}

/// Default table style: horizontal-overflow scroll container,
/// `theme.tableBackground` fill, rounded corners, and a
/// `theme.tableBorderColor` outline — matching pre-style
/// `MarkdownBlockView` table rendering exactly (INV-BS3).
public struct MarkdownDefaultTableBlockStyle: MarkdownTableBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ScrollView(.horizontal) {
            configuration.label
                .background(configuration.theme.tableBackground)
                .clipShape(RoundedRectangle(cornerRadius: configuration.theme.renderTableCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: configuration.theme.renderTableCornerRadius)
                        .stroke(configuration.theme.tableBorderColor)
                }
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownTableBlockStyle where Self == MarkdownDefaultTableBlockStyle {
    public static var `default`: Self { .init() }
}
