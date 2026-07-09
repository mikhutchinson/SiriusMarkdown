import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownHeadingBlockStyle`.
///
/// `headingLevel` is the Markdown heading level (`1`…`6`). Heading
/// typography (font size, line height, font profile) is a `MarkdownTheme`
/// measurement concern already applied to `label` during prepare — styles
/// must not change those without also changing the matching theme, or
/// painted chrome will desync from prepared line breaks (INV-BS8).
public struct MarkdownHeadingBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var headingLevel: Int
}

/// Customizes chrome around an already-typeset heading label.
///
/// `makeBody` receives prepared inline content as `configuration.label`.
/// Implementations must not parse Markdown, run inline layout, or perform
/// CoreText prepare (INV-BS2).
@MainActor
public protocol MarkdownHeadingBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownHeadingBlockStyleConfiguration
}

/// Default heading style: passes the prepared label through unchanged.
/// This matches pre-style `MarkdownBlockView` heading rendering exactly
/// (INV-BS3) — heading typography already comes from `MarkdownTheme` via
/// the label passed in.
public struct MarkdownDefaultHeadingBlockStyle: MarkdownHeadingBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension MarkdownHeadingBlockStyle where Self == MarkdownDefaultHeadingBlockStyle {
    public static var `default`: Self { .init() }
}
