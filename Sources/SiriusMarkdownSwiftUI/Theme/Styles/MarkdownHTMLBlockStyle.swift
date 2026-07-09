import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownHTMLBlockStyle`.
///
/// `label` is the already-policy-allowed raw HTML block source rendered
/// as plain selectable text (Sirius denies or renders raw HTML inertly by
/// default; this slot only receives the allowed path — policy-denied
/// blocks render independently of style, INV-BS2).
public struct MarkdownHTMLBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes chrome around an already-policy-allowed HTML block label.
@MainActor
public protocol MarkdownHTMLBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownHTMLBlockStyleConfiguration
}

/// Default HTML-block style: passes the prepared label through unchanged.
/// `label` already renders in `theme.secondaryTextColor` — that color is
/// baked into the native selectable-text view when the label is built
/// and does not respond to an externally applied `.foregroundStyle`
/// (`MarkdownSelectableText.swift`) — matching pre-style
/// `MarkdownBlockView` HTML rendering exactly (INV-BS3).
public struct MarkdownDefaultHTMLBlockStyle: MarkdownHTMLBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension MarkdownHTMLBlockStyle where Self == MarkdownDefaultHTMLBlockStyle {
    public static var `default`: Self { .init() }
}
