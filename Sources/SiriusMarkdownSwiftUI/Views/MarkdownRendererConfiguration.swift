import SiriusMarkdownCore
import SwiftUI

public protocol MarkdownCodeHighlighter: Sendable {
    func highlightedCode(_ code: String, infoString: String?) -> AttributedString
}

public protocol MarkdownMathRenderer: Sendable {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString
}

public struct PlainMarkdownCodeHighlighter: MarkdownCodeHighlighter {
    public init() {}

    public func highlightedCode(_ code: String, infoString _: String?) -> AttributedString {
        var highlighted = AttributedString(code)
        highlighted.inlinePresentationIntent = .code
        return highlighted
    }
}

public struct PlainMarkdownMathRenderer: MarkdownMathRenderer {
    public init() {}

    public func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        var rendered = AttributedString(source)
        rendered.inlinePresentationIntent = .code
        return rendered
    }
}

public struct MarkdownRendererConfiguration: Sendable {
    public var theme: MarkdownTheme
    public var linkAction: MarkdownLinkAction?
    public var linkPolicy: any MarkdownLinkPolicy
    public var imagePolicy: any MarkdownImagePolicy
    public var htmlPolicy: any MarkdownHTMLPolicy
    public var codePolicy: any MarkdownCodePolicy
    public var mathPolicy: any MarkdownMathPolicy
    public var codeHighlighter: any MarkdownCodeHighlighter
    public var mathRenderer: any MarkdownMathRenderer

    public init(
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = PlainMarkdownCodeHighlighter(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer()
    ) {
        self.theme = theme
        self.linkAction = linkAction
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mathRenderer = mathRenderer
    }

    public static let compactChat = MarkdownRendererConfiguration(theme: .compactChat)
    public static let document = MarkdownRendererConfiguration(theme: .document)
}

public struct MarkdownBlockRenderPlan: Sendable, Equatable {
    public var kind: MarkdownBlockKind
    public var listItemCount: Int
    public var tableColumnCount: Int
    public var tableBodyRowCount: Int
    public var codeAllowed: Bool?
    public var mathAllowed: Bool?
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        kind: MarkdownBlockKind,
        listItemCount: Int = 0,
        tableColumnCount: Int = 0,
        tableBodyRowCount: Int = 0,
        codeAllowed: Bool? = nil,
        mathAllowed: Bool? = nil,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.kind = kind
        self.listItemCount = listItemCount
        self.tableColumnCount = tableColumnCount
        self.tableBodyRowCount = tableBodyRowCount
        self.codeAllowed = codeAllowed
        self.mathAllowed = mathAllowed
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
    }
}
