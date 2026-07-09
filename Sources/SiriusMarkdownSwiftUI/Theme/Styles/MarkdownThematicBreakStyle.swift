import SiriusMarkdownCore
import SwiftUI

/// Metadata passed to `MarkdownThematicBreakStyle`. Thematic breaks have
/// no prepared inline content, so there is no `label`.
public struct MarkdownThematicBreakStyleConfiguration {
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
}

/// Customizes the rendering of a thematic break (`---`).
@MainActor
public protocol MarkdownThematicBreakStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownThematicBreakStyleConfiguration
}

/// Default thematic-break style: a plain `Divider()`, matching pre-style
/// `MarkdownBlockView` rendering exactly (INV-BS3).
public struct MarkdownDefaultThematicBreakStyle: MarkdownThematicBreakStyle {
    public init() {}

    public func makeBody(configuration _: Configuration) -> some View {
        Divider()
    }
}

extension MarkdownThematicBreakStyle where Self == MarkdownDefaultThematicBreakStyle {
    public static var `default`: Self { .init() }
}
