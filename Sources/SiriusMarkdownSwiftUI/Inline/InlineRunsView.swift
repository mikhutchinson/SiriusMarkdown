import SiriusMarkdownCore
import Foundation
import SwiftUI

public struct InlineRunsView: View {
    private var attributed: AttributedString
    private var theme: MarkdownTheme
    private var baseFont: Font
    private var linkAction: MarkdownLinkAction?

    public init(
        runs: [MarkdownInlineRun],
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) {
        self.attributed = Self.attributedString(
            for: runs,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
    }

    public init(
        attributed: AttributedString,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil
    ) {
        self.attributed = attributed
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
    }

    public var body: some View {
        Text(attributed)
        .font(baseFont)
        .foregroundStyle(theme.textColor)
        .environment(\.openURL, OpenURLAction { url in
            if let linkAction {
                linkAction.open(url.absoluteString)
            } else {
                Task { @MainActor in
                    MarkdownURLOpener.open(url.absoluteString)
                }
            }
            return .handled
        })
    }

    public nonisolated static func plainText(
        for runs: [MarkdownInlineRun],
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) -> String {
        runs.map { run in
            switch run.kind {
            case .image:
                guard let source = run.destination else {
                    return run.text.isEmpty ? "[image]" : run.text
                }
                switch imagePolicy.evaluateImage(source: source, altText: run.text) {
                case .allow:
                    return run.text.isEmpty ? source : run.text
                case .deny:
                    return run.text.isEmpty ? "[image]" : run.text
                }
            default:
                return run.text
            }
        }.joined()
    }

    public nonisolated static func attributedString(
        for runs: [MarkdownInlineRun],
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) -> AttributedString {
        var attributed = AttributedString()

        for run in runs {
            var piece = AttributedString(visibleText(for: run, imagePolicy: imagePolicy))
            switch run.kind {
            case .emphasis:
                piece.inlinePresentationIntent = .emphasized
            case .strong:
                piece.inlinePresentationIntent = .stronglyEmphasized
            case .strikethrough:
                piece.inlinePresentationIntent = .strikethrough
            case .code, .math:
                piece.inlinePresentationIntent = .code
            case .link:
                if let destination = run.destination,
                   case .allow = linkPolicy.evaluateLink(destination: destination),
                   let url = URL(string: destination) {
                    piece.link = url
                }
            default:
                break
            }
            attributed.append(piece)
        }

        return attributed
    }

    private nonisolated static func visibleText(
        for run: MarkdownInlineRun,
        imagePolicy: any MarkdownImagePolicy
    ) -> String {
        guard run.kind == .image else {
            return run.text
        }

        guard let source = run.destination else {
            return run.text.isEmpty ? "[image]" : run.text
        }

        switch imagePolicy.evaluateImage(source: source, altText: run.text) {
        case .allow:
            return run.text.isEmpty ? source : run.text
        case .deny:
            return run.text.isEmpty ? "[image]" : run.text
        }
    }
}
