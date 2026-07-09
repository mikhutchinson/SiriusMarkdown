import SiriusMarkdownCore
import SwiftUI

// MARK: - Unordered

/// Metadata passed to `MarkdownUnorderedListMarkerStyle`. Unordered
/// markers have no prepared inline content, so there is no `label`.
public struct MarkdownUnorderedListMarkerStyleConfiguration {
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes the bullet glyph for an unordered list item.
@MainActor
public protocol MarkdownUnorderedListMarkerStyle {
    associatedtype Body: View
    /// Optional marker column width used when indenting nested child lists.
    /// Return `nil` for marker views whose intrinsic width should not
    /// influence descendant indentation.
    var markerWidth: CGFloat? { get }
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownUnorderedListMarkerStyleConfiguration
}

extension MarkdownUnorderedListMarkerStyle {
    public var markerWidth: CGFloat? { nil }
}

/// Default unordered marker: a 28pt-wide, trailing-aligned `"•"` in
/// `theme.codeFont` / `theme.secondaryTextColor` — matching pre-style
/// `MarkdownBlockView` list rendering exactly (INV-BS3).
public struct MarkdownDefaultUnorderedListMarkerStyle: MarkdownUnorderedListMarkerStyle {
    /// `internal` (not `private`) so `@testable import` can lock this
    /// geometry constant directly (Part 06 §6.2.1 `defaultListMarkerWidths`).
    static let width: CGFloat = 28

    public init() {}

    public var markerWidth: CGFloat? { Self.width }

    public func makeBody(configuration: Configuration) -> some View {
        Text("•")
            .font(configuration.theme.codeFont)
            .foregroundStyle(configuration.theme.secondaryTextColor)
            .frame(width: Self.width, alignment: .trailing)
    }
}

extension MarkdownUnorderedListMarkerStyle where Self == MarkdownDefaultUnorderedListMarkerStyle {
    public static var `default`: Self { .init() }
}

// MARK: - Ordered

/// Metadata passed to `MarkdownOrderedListMarkerStyle`. `ordinal` is the
/// item's resolved list number (`orderedListStart` plus its zero-based
/// position).
public struct MarkdownOrderedListMarkerStyleConfiguration {
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var ordinal: Int
}

/// Customizes the numeral for an ordered list item.
@MainActor
public protocol MarkdownOrderedListMarkerStyle {
    associatedtype Body: View
    /// Optional marker column width used when indenting nested child lists.
    /// Return `nil` for marker views whose intrinsic width should not
    /// influence descendant indentation.
    var markerWidth: CGFloat? { get }
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownOrderedListMarkerStyleConfiguration
}

extension MarkdownOrderedListMarkerStyle {
    public var markerWidth: CGFloat? { nil }
}

/// Default ordered marker: a 34pt-wide, trailing-aligned `"N."` in
/// `theme.codeFont` / `theme.secondaryTextColor` — matching pre-style
/// `MarkdownBlockView` list rendering exactly (INV-BS3).
public struct MarkdownDefaultOrderedListMarkerStyle: MarkdownOrderedListMarkerStyle {
    /// `internal` (not `private`) so `@testable import` can lock this
    /// geometry constant directly (Part 06 §6.2.1 `defaultListMarkerWidths`).
    static let width: CGFloat = 34

    public init() {}

    public var markerWidth: CGFloat? { Self.width }

    public func makeBody(configuration: Configuration) -> some View {
        Text("\(configuration.ordinal).")
            .font(configuration.theme.codeFont)
            .foregroundStyle(configuration.theme.secondaryTextColor)
            .frame(width: Self.width, alignment: .trailing)
    }
}

extension MarkdownOrderedListMarkerStyle where Self == MarkdownDefaultOrderedListMarkerStyle {
    public static var `default`: Self { .init() }
}

// MARK: - Task

/// Metadata passed to `MarkdownTaskListMarkerStyle`.
public struct MarkdownTaskListMarkerStyleConfiguration {
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var isChecked: Bool
}

/// Customizes the checkbox glyph for a GFM task-list item.
@MainActor
public protocol MarkdownTaskListMarkerStyle {
    associatedtype Body: View
    /// Optional marker column width used when indenting nested child lists.
    /// Return `nil` for marker views whose intrinsic width should not
    /// influence descendant indentation.
    var markerWidth: CGFloat? { get }
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownTaskListMarkerStyleConfiguration
}

extension MarkdownTaskListMarkerStyle {
    public var markerWidth: CGFloat? { nil }
}

/// Default task marker: a 28pt-wide SF Symbol checkbox — checked items
/// use `Color.accentColor`, unchecked use `theme.secondaryTextColor` —
/// matching pre-style `MarkdownBlockView` task-list rendering exactly
/// (INV-BS3).
public struct MarkdownDefaultTaskListMarkerStyle: MarkdownTaskListMarkerStyle {
    static let width: CGFloat = 28

    public init() {}

    public var markerWidth: CGFloat? { Self.width }

    public func makeBody(configuration: Configuration) -> some View {
        let metrics = MarkdownInlineFallbackMetrics(
            fontSize: configuration.theme.paragraphFontSize,
            lineHeight: configuration.theme.paragraphLineHeight,
            fontProfile: configuration.theme.paragraphFontProfiles.body,
            fallbackFontSize: 16,
            fallbackLineHeight: 22
        )
        let markerFontSize = CGFloat(min(max(metrics.fontSize - 2, 12), 14))

        Image(systemName: configuration.isChecked ? "checkmark.square.fill" : "square")
            .font(.system(size: markerFontSize, weight: .semibold))
            .foregroundStyle(configuration.isChecked ? Color.accentColor : configuration.theme.secondaryTextColor)
            .frame(height: metrics.lineHeight, alignment: .trailing)
            .frame(width: Self.width, alignment: .trailing)
    }
}

extension MarkdownTaskListMarkerStyle where Self == MarkdownDefaultTaskListMarkerStyle {
    public static var `default`: Self { .init() }
}
