import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownBlockQuoteStyle`.
public struct MarkdownBlockQuoteStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes chrome around an already-prepared block-quote label.
///
/// `makeBody` receives prepared inline content as `configuration.label`
/// (without a foreground color applied). Implementations must not parse
/// Markdown or run inline layout (INV-BS2).
@MainActor
public protocol MarkdownBlockQuoteStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownBlockQuoteStyleConfiguration
}

/// Default block-quote style: a 3pt `theme.quoteAccent` leading bar with
/// 8pt spacing before secondary-colored content, matching pre-style
/// `MarkdownBlockView` block-quote geometry exactly (INV-BS3).
public struct MarkdownDefaultBlockQuoteStyle: MarkdownBlockQuoteStyle {
    /// `internal` (not `private`) so `@testable import` can lock these
    /// geometry constants directly (Part 06 §6.2.1
    /// `defaultBlockQuoteChromeMatchesLegacyGeometry`) without reflecting
    /// into the returned view's layout.
    static let leadingWidth: CGFloat = 3
    static let spacing: CGFloat = 8

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        MarkdownStyleLeadingContentLayout(
            leadingWidth: Self.leadingWidth,
            spacing: Self.spacing,
            stretchesLeadingToContentHeight: true
        ) {
            Rectangle()
                .fill(configuration.theme.quoteAccent)
                .frame(width: Self.leadingWidth)
            configuration.label
                .foregroundStyle(configuration.theme.secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MarkdownBlockQuoteStyle where Self == MarkdownDefaultBlockQuoteStyle {
    public static var `default`: Self { .init() }
}
