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
    private var nativeTextSelection: MarkdownNativeTextSelection

    public init(
        runs: [MarkdownInlineRun],
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText,
        nativeTextSelection: MarkdownNativeTextSelection = .disabled,
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
        self.nativeTextSelection = nativeTextSelection
    }

    public init(
        attributed: AttributedString,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText,
        nativeTextSelection: MarkdownNativeTextSelection = .disabled
    ) {
        self.attributed = attributed
        self.prepared = nil
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
    }

    public init(
        prepared: MarkdownPreparedInlineContent,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText,
        nativeTextSelection: MarkdownNativeTextSelection = .disabled
    ) {
        self.attributed = prepared.attributed
        self.prepared = prepared
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
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
                inlineRenderingMode: inlineRenderingMode,
                nativeTextSelection: nativeTextSelection
            )
        } else {
            MarkdownSelectableText(
                attributed: attributed,
                font: baseFont,
                fontSize: theme.paragraphFontSize,
                lineHeight: theme.paragraphLineHeight,
                fontProfile: theme.paragraphFontProfiles.body,
                textColor: theme.textColor,
                linkAction: linkAction,
                nativeTextSelection: nativeTextSelection
            )
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
            if let intent = inlinePresentationIntent(for: run.presentation, kind: run.kind) {
                piece.inlinePresentationIntent = intent
            }

            if run.kind == .link {
                if let destination = run.destination,
                   case .allow = linkPolicy.evaluateLink(destination: destination),
                   let url = URL(string: destination) {
                    piece.link = url
                }
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
        attributedLines(for: prepared, attributed: prepared.attributed, layout: layout)
    }

    nonisolated static func nativeLineAttributedString(
        for prepared: MarkdownPreparedInlineContent,
        attributed: AttributedString,
        layout: InlineLayoutResult
    ) -> AttributedString {
        let lines = attributedLines(for: prepared, attributed: attributed, layout: layout)
        guard !lines.isEmpty else {
            return AttributedString("")
        }

        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(defaultFontAttributedString("\n", prepared: prepared))
            }
            result.append(line.characters.isEmpty ? defaultFontAttributedString(" ", prepared: prepared) : line)
        }
        return result
    }

    nonisolated static func attributedLines(
        for prepared: MarkdownPreparedInlineContent,
        attributed: AttributedString,
        layout: InlineLayoutResult
    ) -> [AttributedString] {
        layout.lines.map {
            attributedSlice(attributed, text: prepared.prepared.naturalText, byteRange: $0.byteRange)
        }
    }

    nonisolated static func renderingAttributedString(for prepared: MarkdownPreparedInlineContent) -> AttributedString {
        var rendered = prepared.attributed
        var cursor = 0
        let text = prepared.prepared.naturalText

        for run in prepared.prepared.runs {
            let upper = cursor + run.text.utf8.count
            applyFont(
                to: &rendered,
                text: text,
                byteRange: cursor..<upper,
                kind: run.kind,
                presentation: run.presentation,
                prepared: prepared
            )
            cursor = upper
        }

        return rendered
    }

    nonisolated static func nativeLineLayoutWidth(
        for prepared: MarkdownPreparedInlineContent,
        containerWidth: Double
    ) -> Double {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return 1
        }
        return max(1, containerWidth - nativeLinePaintGuard(for: prepared))
    }

    nonisolated static func nativeLinePaintGuard(for prepared: MarkdownPreparedInlineContent) -> Double {
        max(3, min(8, ceil(prepared.fontSize * 0.22)))
    }

    nonisolated static func nativeLineSpacing(for prepared: MarkdownPreparedInlineContent) -> CGFloat {
        max(0, CGFloat(prepared.lineHeight - prepared.fontSize) * 0.25)
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

    private nonisolated static func applyFont(
        to attributed: inout AttributedString,
        text: String,
        byteRange: Range<Int>,
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation,
        prepared: MarkdownPreparedInlineContent
    ) {
        guard !byteRange.isEmpty,
              let stringRange = stringRange(forUTF8Range: byteRange, in: text)
        else {
            return
        }

        let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: stringRange.upperBound)
        let characters = attributed.characters
        guard lowerOffset <= upperOffset,
              upperOffset <= characters.count
        else {
            return
        }

        let lower = characters.index(characters.startIndex, offsetBy: lowerOffset)
        let upper = characters.index(characters.startIndex, offsetBy: upperOffset)
        attributed[lower..<upper].font = swiftUIFont(
            for: prepared.fontProfiles.profile(for: presentation, kind: kind),
            kind: kind,
            presentation: presentation,
            size: prepared.fontSize
        )
    }

    private nonisolated static func defaultFontAttributedString(
        _ string: String,
        prepared: MarkdownPreparedInlineContent
    ) -> AttributedString {
        var attributed = AttributedString(string)
        attributed.font = swiftUIFont(
            for: prepared.fontProfiles.profile(for: .text),
            kind: .text,
            presentation: [],
            size: prepared.fontSize
        )
        return attributed
    }

    private nonisolated static func swiftUIFont(
        for profile: MarkdownFontProfile,
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation,
        size: Double
    ) -> Font {
        var font: Font
        switch profile {
        case let .system(weight, design):
            font = .system(size: CGFloat(size), weight: swiftUIWeight(weight), design: swiftUIDesign(design))
        case let .monospacedSystem(weight):
            font = .system(size: CGFloat(size), weight: swiftUIWeight(weight), design: .monospaced)
        case let .named(name, weight):
            font = .custom(name, size: CGFloat(size)).weight(swiftUIWeight(weight))
        }

        if presentation.contains(.emphasis) || kind == .emphasis {
            font = font.italic()
        }
        return font
    }

    private nonisolated static func inlinePresentationIntent(
        for presentation: MarkdownInlinePresentation,
        kind: MarkdownInlineKind
    ) -> InlinePresentationIntent? {
        var intent: InlinePresentationIntent = []
        if presentation.contains(.emphasis) || kind == .emphasis {
            intent.insert(.emphasized)
        }
        if presentation.contains(.strong) || kind == .strong {
            intent.insert(.stronglyEmphasized)
        }
        if presentation.contains(.strikethrough) || kind == .strikethrough {
            intent.insert(.strikethrough)
        }
        if presentation.contains(.code) || presentation.contains(.math) || kind == .code || kind == .math {
            intent.insert(.code)
        }
        return intent.isEmpty ? nil : intent
    }

    private nonisolated static func swiftUIWeight(_ weight: MarkdownFontWeight) -> Font.Weight {
        switch weight {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }

    private nonisolated static func swiftUIDesign(_ design: MarkdownFontDesign) -> Font.Design {
        switch design {
        case .default:
            return .default
        case .serif:
            return .serif
        case .rounded:
            return .rounded
        case .monospaced:
            return .monospaced
        }
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
    var nativeTextSelection: MarkdownNativeTextSelection

    @Environment(\.markdownDocumentSelectionContext) private var documentSelectionContext

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
        renderSurface
            .environment(\.openURL, openURLAction)
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
    private var renderSurface: some View {
        if canRenderNativeLines {
            Color.clear
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: nativeLineSurfaceHeight, alignment: .topLeading)
                .background(widthReader)
                .overlay(alignment: .topLeading) {
                    NativeInlineLineTextView(
                        prepared: prepared,
                        layoutResult: layoutResult,
                        fallbackAttributed: fallbackAttributed,
                        baseFont: baseFont,
                        theme: theme,
                        containerWidth: containerWidth,
                        nativeTextSelection: nativeTextSelection
                    )
                }
                .background(nativeLineSelectionFragmentsPreference)
        } else {
            MarkdownSelectableText(
                attributed: fallbackAttributed,
                font: baseFont,
                fontSize: prepared.fontSize,
                lineHeight: prepared.lineHeight,
                fontProfile: prepared.fontProfiles.body,
                textColor: theme.textColor,
                linkAction: linkAction,
                nativeTextSelection: nativeTextSelection
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .background(widthReader)
                .background(fallbackSelectionFragmentPreference)
        }
    }

    private var canRenderNativeLines: Bool {
        inlineRenderingMode == .preparedNativeLines &&
            containerWidth > 0 &&
            !layoutResult.lines.isEmpty &&
            NativeInlineLineTextView.isSupported
    }

    private var nativeLineSurfaceHeight: CGFloat {
        let lineCount = layoutResult.lines.count
        guard lineCount > 0 else {
            return CGFloat(prepared.lineHeight)
        }

        let lineHeight = CGFloat(prepared.lineHeight)
        let spacing = InlineRunsView.nativeLineSpacing(for: prepared)
        return CGFloat(lineCount) * lineHeight + CGFloat(max(0, lineCount - 1)) * spacing
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

    private var nativeLineSelectionFragmentsPreference: some View {
        GeometryReader { proxy in
            let rect = selectionPreferenceRect(from: proxy)
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: nativeLineSelectionFragments(
                    rect: rect
                )
            )
        }
        .allowsHitTesting(false)
    }

    private var fallbackSelectionFragmentPreference: some View {
        GeometryReader { proxy in
            let rect = selectionPreferenceRect(from: proxy)
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: fallbackSelectionFragments(
                    rect: rect
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func selectionPreferenceRect(from proxy: GeometryProxy) -> CGRect {
        prepared.layoutCache.recordSelectionPreferenceBodyEvaluation()
        prepared.layoutCache.recordSelectionFrameQuery()
        return proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
    }

    private func nativeLineSelectionFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext else {
            return []
        }
        return MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: documentSelectionContext.blockID,
            prepared: prepared,
            layout: layoutResult,
            rect: rect,
            idPrefix: "text-leaf"
        )
    }

    private func fallbackSelectionFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext,
              let sourceRange = prepared.prepared.sourceRange,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0
        else {
            return []
        }
        return [
            MarkdownDocumentSelectionFragment.fallbackTextFragment(
                blockID: documentSelectionContext.blockID,
                sourceRange: sourceRange,
                rect: rect,
                idPrefix: "text-leaf-fallback"
            )
        ]
    }

    private func refreshLayoutIfPossible() {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return
        }

        let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
            for: prepared,
            containerWidth: Double(containerWidth)
        )
        let refreshedLayout = InlineRunsView.lineLayout(
            for: prepared,
            containerWidth: layoutWidth,
            allowsOverwideFallback: true
        )
        layoutResult = refreshedLayout
        if !recordedClipping,
           refreshedLayout.lines.contains(where: { $0.width > layoutWidth + 0.5 }) {
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
