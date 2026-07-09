import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownParagraphBlockStyle`.
public struct MarkdownParagraphBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes chrome around an already-prepared paragraph label.
///
/// `makeBody` receives prepared inline content as `configuration.label`.
/// Implementations must not parse Markdown or run inline layout (INV-BS2).
@MainActor
public protocol MarkdownParagraphBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownParagraphBlockStyleConfiguration
}

/// Default paragraph style: passes the prepared label through unchanged,
/// matching pre-style `MarkdownBlockView` paragraph rendering (INV-BS3).
public struct MarkdownDefaultParagraphBlockStyle: MarkdownParagraphBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension MarkdownParagraphBlockStyle where Self == MarkdownDefaultParagraphBlockStyle {
    public static var `default`: Self { .init() }
}
