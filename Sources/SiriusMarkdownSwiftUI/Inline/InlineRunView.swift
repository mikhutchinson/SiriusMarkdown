import SiriusMarkdownCore
import SwiftUI

public struct InlineRunView: View {
    private var run: MarkdownInlineRun
    private var theme: MarkdownTheme
    private var linkAction: MarkdownLinkAction?
    private var policy: DefaultMarkdownPolicy

    public init(
        run: MarkdownInlineRun,
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        policy: DefaultMarkdownPolicy = DefaultMarkdownPolicy()
    ) {
        self.run = run
        self.theme = theme
        self.linkAction = linkAction
        self.policy = policy
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
           policy.evaluateLink(destination: destination) == .allow {
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
           policy.evaluateImage(source: source, altText: run.text) == .allow {
            Text(run.text.isEmpty ? source : run.text)
                .foregroundStyle(theme.secondaryTextColor)
        } else {
            Text(run.text.isEmpty ? "[image]" : run.text)
                .foregroundStyle(theme.secondaryTextColor)
        }
    }
}
