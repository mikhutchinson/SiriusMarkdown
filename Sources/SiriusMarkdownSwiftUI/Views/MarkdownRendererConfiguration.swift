import SiriusMarkdownCore

public struct MarkdownRendererConfiguration: Sendable {
    public var theme: MarkdownTheme
    public var linkAction: MarkdownLinkAction?
    public var policy: DefaultMarkdownPolicy

    public init(
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        policy: DefaultMarkdownPolicy = DefaultMarkdownPolicy()
    ) {
        self.theme = theme
        self.linkAction = linkAction
        self.policy = policy
    }

    public static let compactChat = MarkdownRendererConfiguration(theme: .compactChat)
    public static let document = MarkdownRendererConfiguration(theme: .document)
}
