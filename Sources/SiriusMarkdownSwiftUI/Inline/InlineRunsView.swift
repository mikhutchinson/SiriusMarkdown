import SiriusMarkdownCore
import Foundation
import SwiftUI

public enum MarkdownInlineRenderingMode: Sendable, Hashable {
    case systemText
    case preparedNativeLines
}

public struct InlineRunsView: View {
    private var attributed: AttributedString
    private var prepared: MarkdownPreparedInlineContent?
    private var theme: MarkdownTheme
    private var baseFont: Font
    private var linkAction: MarkdownLinkAction?
    private var inlineRenderingMode: MarkdownInlineRenderingMode

    public init(
        runs: [MarkdownInlineRun],
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText,
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
        self.inlineRenderingMode = inlineRenderingMode
    }

    public init(
        attributed: AttributedString,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText
    ) {
        self.attributed = attributed
        self.prepared = nil
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
    }

    public init(
        prepared: MarkdownPreparedInlineContent,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText
    ) {
        self.attributed = prepared.attributed
        self.prepared = prepared
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
    }

    @ViewBuilder
    public var body: some View {
        if let prepared {
            PreparedInlineTextView(
                prepared: prepared,
                fallbackAttributed: attributed,
                theme: theme,
                baseFont: baseFont,
                linkAction: linkAction,
                inlineRenderingMode: inlineRenderingMode
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
        let layout = lineLayout(for: prepared, containerWidth: containerWidth)
        return attributedLines(for: prepared, layout: layout)
    }

    public nonisolated static func attributedLines(
        for prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult
    ) -> [AttributedString] {
        return layout.lines.map {
            attributedSlice(prepared.attributed, text: prepared.prepared.naturalText, byteRange: $0.byteRange)
        }
    }

    public nonisolated static func lineLayout(
        for prepared: MarkdownPreparedInlineContent,
        containerWidth: Double,
        allowsOverwideFallback: Bool = true
    ) -> InlineLayoutResult {
        prepared.layout(
            containerWidth: containerWidth,
            allowsOverwideFallback: allowsOverwideFallback
        )
    }

    @available(*, deprecated, message: "Use lineLayout(for:containerWidth:) and native text rendering instead of injecting layout newlines into AttributedString.")
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

private struct PreparedInlineLayoutIdentity: Hashable {
    var sourceRange: MarkdownSourceRange?
    var naturalText: String
    var fontSize: Double
    var lineHeight: Double
}

private struct PreparedInlineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var fallbackAttributed: AttributedString
    var theme: MarkdownTheme
    var baseFont: Font
    var linkAction: MarkdownLinkAction?
    var inlineRenderingMode: MarkdownInlineRenderingMode

    @State private var containerWidth: CGFloat = 0
    @State private var layoutResult = InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
    @State private var recordedNonFiniteFallback = false
    @State private var recordedClipping = false

    private var layoutIdentity: PreparedInlineLayoutIdentity {
        PreparedInlineLayoutIdentity(
            sourceRange: prepared.prepared.sourceRange,
            naturalText: prepared.prepared.naturalText,
            fontSize: prepared.fontSize,
            lineHeight: prepared.lineHeight
        )
    }

    @ViewBuilder
    var body: some View {
        renderedText
            .environment(\.openURL, openURLAction)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(widthReader)
            .accessibilityValue(layoutResult.lines.isEmpty ? "" : "\(layoutResult.lines.count) prepared lines")
            .onAppear {
                refreshLayoutIfPossible()
            }
            .onPreferenceChange(PreparedInlineWidthPreferenceKey.self) { width in
                guard width.isFinite, width > 0 else {
                    if !recordedNonFiniteFallback {
                        recordedNonFiniteFallback = true
                        prepared.layoutCache.recordNonFiniteInlineProposalFallback()
                    }
                    return
                }

                if abs(width - containerWidth) > 0.5 {
                    containerWidth = width
                    refreshLayoutIfPossible()
                }
            }
            .onChange(of: layoutIdentity) { _ in
                layoutResult = InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
                refreshLayoutIfPossible()
            }
    }

    @ViewBuilder
    private var renderedText: some View {
        if inlineRenderingMode == .preparedNativeLines,
           containerWidth > 0,
           !layoutResult.lines.isEmpty,
           NativeInlineLineTextView.isSupported {
            NativeInlineLineTextView(
                prepared: prepared,
                layoutResult: layoutResult,
                fallbackAttributed: fallbackAttributed,
                baseFont: baseFont,
                theme: theme,
                containerWidth: containerWidth
            )
        } else {
            Text(fallbackAttributed)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PreparedInlineWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
        .allowsHitTesting(false)
    }

    private func refreshLayoutIfPossible() {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return
        }

        let layoutWidth = max(1, Double(containerWidth) - Self.nativeLineSafetyInset)
        let refreshedLayout = InlineRunsView.lineLayout(
            for: prepared,
            containerWidth: layoutWidth,
            allowsOverwideFallback: true
        )
        layoutResult = refreshedLayout
        if !recordedClipping,
           refreshedLayout.lines.contains(where: { $0.width > Double(containerWidth) + 0.5 }) {
            recordedClipping = true
            prepared.layoutCache.recordNativeLineClipping()
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

    private static let nativeLineSafetyInset: Double = 2
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
