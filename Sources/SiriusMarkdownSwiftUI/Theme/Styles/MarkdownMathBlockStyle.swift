import SiriusMarkdownCore
import SwiftUI

/// Metadata and prepared content passed to `MarkdownMathBlockStyle`.
///
/// `label` is already-typeset math content — either a rasterized formula
/// image (`isImage == true`, centered/scrollable presentation already
/// applied by the label) or a monospaced text fallback (`isImage ==
/// false`). Sirius adds this slot because it has no Textual equivalent;
/// typesetting stays pluggable through `MarkdownRendererConfiguration.mathRenderer`.
public struct MarkdownMathBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var isImage: Bool
}

/// Customizes chrome around already-typeset math content.
///
/// `makeBody` receives prepared math content as `configuration.label`.
/// Implementations must not validate or typeset LaTeX (INV-BS2).
@MainActor
public protocol MarkdownMathBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownMathBlockStyleConfiguration
}

/// Default math-block style: text fallbacks get 8pt padding,
/// `theme.codeBackground`, and a 6pt corner radius; rasterized formula
/// images keep their own centered/scrollable presentation without extra
/// chrome — matching pre-style `MarkdownBlockView` math rendering exactly
/// (INV-BS3).
public struct MarkdownDefaultMathBlockStyle: MarkdownMathBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if configuration.isImage {
            configuration.label
        } else {
            configuration.label
                .padding(8)
                .background(configuration.theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

extension MarkdownMathBlockStyle where Self == MarkdownDefaultMathBlockStyle {
    public static var `default`: Self { .init() }
}
