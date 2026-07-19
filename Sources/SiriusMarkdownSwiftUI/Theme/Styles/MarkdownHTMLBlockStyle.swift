import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownHTMLBlockStyle`.
///
/// `label` is already-policy-allowed HTML converted into sanitized, prepared
/// native block and inline views. The style never receives an executable DOM
/// or performs parsing; policy-denied blocks render independently (INV-BS2).
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

/// Default HTML-block style: passes the prepared native rich-content label
/// through unchanged (INV-BS3).
public struct MarkdownDefaultHTMLBlockStyle: MarkdownHTMLBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension MarkdownHTMLBlockStyle where Self == MarkdownDefaultHTMLBlockStyle {
    public static var `default`: Self { .init() }
}
