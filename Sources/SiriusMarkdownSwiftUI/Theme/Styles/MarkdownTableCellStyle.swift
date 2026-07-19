import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownTableCellStyle`.
///
/// `row` is `-1` for the header row, otherwise the zero-based body row
/// index. `width` is the column's already-prepared adaptive width. Render
/// preparation maintains natural maxima and bounded streaming width revisions;
/// styles and `MarkdownBlockView` must not rescan or remeasure cell text.
public struct MarkdownTableCellStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var row: Int
    public var column: Int
    public var columnCount: Int
    public var isHeader: Bool
    public var isLastColumn: Bool
    public var alignment: MarkdownTableColumnAlignment?
    public var width: CGFloat
}

/// Customizes chrome around an already-prepared table-cell label.
///
/// `makeBody` receives prepared inline content as `configuration.label`.
/// Implementations must not run inline layout (INV-BS2). Row/zebra
/// background stays theme-owned; this protocol customizes per-cell
/// padding, alignment, dividers, and minimum height.
@MainActor
public protocol MarkdownTableCellStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownTableCellStyleConfiguration
}

/// Default table-cell style: theme-driven horizontal/vertical padding,
/// column alignment, a 38pt minimum row height, and a trailing divider
/// between columns — matching pre-style `MarkdownBlockView` cell
/// rendering exactly (INV-BS3).
public struct MarkdownDefaultTableCellStyle: MarkdownTableCellStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.theme.textColor)
            .padding(.horizontal, configuration.theme.renderTableHorizontalCellPadding)
            .padding(.vertical, configuration.theme.renderTableVerticalCellPadding)
            .frame(width: configuration.width, alignment: Self.alignment(for: configuration.alignment))
            // Accept the table row's tallest-cell proposal so trailing
            // dividers and cell chrome stay aligned for multiline rows.
            .frame(minHeight: 38, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) {
                if !configuration.isLastColumn {
                    Rectangle()
                        .fill(configuration.theme.tableBorderColor.opacity(0.72))
                        .frame(width: 1)
                }
            }
    }

    private static func alignment(for alignment: MarkdownTableColumnAlignment?) -> Alignment {
        switch alignment {
        case nil, .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
}

extension MarkdownTableCellStyle where Self == MarkdownDefaultTableCellStyle {
    public static var `default`: Self { .init() }
}
