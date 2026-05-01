import SiriusMarkdownCore
import SwiftUI

public struct InlineRunView: View {
    private var run: MarkdownInlineRun
    private var theme: MarkdownTheme
    private var linkAction: MarkdownLinkAction?
    private var linkPolicy: any MarkdownLinkPolicy
    private var imagePolicy: any MarkdownImagePolicy

    public init(
        run: MarkdownInlineRun,
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) {
        self.run = run
        self.theme = theme
        self.linkAction = linkAction
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
    }

    public var body: some View {
        switch run.kind {
        case .code:
            Text(run.text)
                .font(theme.codeFont)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(theme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .link:
            linkView
        case .image:
            imageView
        case .emphasis:
            Text(run.text)
                .italic()
        case .strong:
            Text(run.text)
                .bold()
        case .strikethrough:
            Text(run.text)
                .strikethrough()
        default:
            Text(run.text)
                .foregroundStyle(theme.textColor)
        }
    }

    @ViewBuilder
    private var linkView: some View {
        if let destination = run.destination,
           linkPolicy.evaluateLink(destination: destination) == .allow {
            Button {
                if let linkAction {
                    linkAction.open(destination)
                } else {
                    Task { @MainActor in
                        MarkdownURLOpener.open(destination)
                    }
                }
            } label: {
                Text(run.text)
                    .foregroundStyle(Color.accentColor)
                    .underline()
            }
            .buttonStyle(.plain)
        } else {
            Text(run.text)
                .foregroundStyle(theme.textColor)
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let source = run.destination,
           imagePolicy.evaluateImage(source: source, altText: run.text) == .allow {
            Text(run.text.isEmpty ? source : run.text)
                .foregroundStyle(theme.secondaryTextColor)
        } else {
            Text(run.text.isEmpty ? "[image]" : run.text)
                .foregroundStyle(theme.secondaryTextColor)
        }
    }
}
