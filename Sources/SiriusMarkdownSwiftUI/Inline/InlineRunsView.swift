import SiriusMarkdownCore
import Foundation
import SwiftUI

public struct InlineRunsView: View {
    private var attributed: AttributedString
    private var prepared: MarkdownPreparedInlineContent?
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
        self.prepared = nil
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
        self.prepared = nil
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
    }

    public init(
        prepared: MarkdownPreparedInlineContent,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil
    ) {
        self.attributed = prepared.attributed
        self.prepared = prepared
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
    }

    @ViewBuilder
    public var body: some View {
        if let prepared {
            PreparedInlineTextView(
                prepared: prepared,
                fallbackAttributed: attributed,
                theme: theme,
                baseFont: baseFont,
                linkAction: linkAction
            )
        } else {
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

    public nonisolated static func attributedLines(
        for prepared: MarkdownPreparedInlineContent,
        containerWidth: Double
    ) -> [AttributedString] {
        let layout = VariableWidthLineWalker().layout(
            prepared.measured,
            options: InlineLayoutOptions(
                containerWidth: containerWidth,
                fontSize: prepared.fontSize,
                lineHeight: prepared.lineHeight
            ),
            allowsOverwideFallback: false
        )

        return layout.lines.map {
            attributedSlice(prepared.attributed, text: prepared.prepared.naturalText, byteRange: $0.byteRange)
        }
    }

    public nonisolated static func lineBrokenAttributedString(
        for prepared: MarkdownPreparedInlineContent,
        containerWidth: Double
    ) -> AttributedString {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return prepared.attributed
        }

        let lines = attributedLines(for: prepared, containerWidth: containerWidth)
        guard !lines.isEmpty else {
            return prepared.attributed
        }

        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(line)
        }
        return result
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

    private nonisolated static func attributedSlice(
        _ attributed: AttributedString,
        text: String,
        byteRange: Range<Int>
    ) -> AttributedString {
        guard let stringRange = stringRange(forUTF8Range: byteRange, in: text) else {
            return AttributedString("")
        }

        let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: stringRange.upperBound)
        let characters = attributed.characters
        guard lowerOffset <= upperOffset,
              upperOffset <= characters.count
        else {
            return AttributedString(String(text[stringRange]))
        }

        let lower = characters.index(characters.startIndex, offsetBy: lowerOffset)
        let upper = characters.index(characters.startIndex, offsetBy: upperOffset)
        return AttributedString(attributed[lower..<upper])
    }

    private nonisolated static func stringRange(
        forUTF8Range byteRange: Range<Int>,
        in text: String
    ) -> Range<String.Index>? {
        guard byteRange.lowerBound >= 0,
              byteRange.upperBound <= text.utf8.count,
              let lowerUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.lowerBound,
                limitedBy: text.utf8.endIndex
              ),
              let upperUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.upperBound,
                limitedBy: text.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: text),
              let upper = String.Index(upperUTF8, within: text)
        else {
            return nil
        }

        return lower..<upper
    }
}

private struct PreparedInlineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var fallbackAttributed: AttributedString
    var theme: MarkdownTheme
    var baseFont: Font
    var linkAction: MarkdownLinkAction?

    @State private var containerWidth: CGFloat = 0

    var body: some View {
        Text(
            containerWidth > 0
                ? InlineRunsView.lineBrokenAttributedString(
                    for: prepared,
                    containerWidth: Double(containerWidth)
                )
                : fallbackAttributed
        )
        .font(baseFont)
        .foregroundStyle(theme.textColor)
        .environment(\.openURL, openURLAction)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PreparedInlineWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(PreparedInlineWidthPreferenceKey.self) { width in
            if width > 0, abs(width - containerWidth) > 0.5 {
                containerWidth = width
            }
        }
    }

    private var openURLAction: OpenURLAction {
        OpenURLAction { url in
            if let linkAction {
                linkAction.open(url.absoluteString)
            } else {
                Task { @MainActor in
                    MarkdownURLOpener.open(url.absoluteString)
                }
            }
            return .handled
        }
    }
}

private struct PreparedInlineWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
