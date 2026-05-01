import SiriusMarkdownCore
import SwiftUI

public struct InlineRunView: View {
    private var attributed: AttributedString
    private var theme: MarkdownTheme
    private var linkAction: MarkdownLinkAction?

    public init(
        run: MarkdownInlineRun,
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) {
        self.attributed = InlineRunsView.attributedString(
            for: [run],
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
        self.theme = theme
        self.linkAction = linkAction
    }

    public var body: some View {
        InlineRunsView(
            attributed: attributed,
            theme: theme,
            linkAction: linkAction
        )
    }
}
