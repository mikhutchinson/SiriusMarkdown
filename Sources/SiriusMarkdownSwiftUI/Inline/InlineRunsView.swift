import SiriusMarkdownCore
import Foundation
import SwiftUI

public enum MarkdownInlineRenderingMode: Sendable, Hashable {
    case systemText
    case preparedNativeLines
    case coreTextPaintedLines
}

extension MarkdownInlineRenderingMode {
    var usesPreparedLineSurface: Bool {
        switch self {
        case .systemText:
            return false
        case .preparedNativeLines, .coreTextPaintedLines:
            return true
        }
    }
}

public struct InlineRunsView: View {
    public nonisolated static let defaultLayoutWidth: Double = 680

    private var attributed: AttributedString
    private var prepared: MarkdownPreparedInlineContent?
    private var theme: MarkdownTheme
    private var baseFont: Font
    private var fallbackMetrics: MarkdownInlineFallbackMetrics
    private var linkAction: MarkdownLinkAction?
    private var inlineRenderingMode: MarkdownInlineRenderingMode
    private var nativeTextSelection: MarkdownNativeTextSelection
    /// Exact content width already resolved by an enclosing prepared layout,
    /// currently the default table-cell pipeline. When present, the inline
    /// leaf must not mount a GeometryReader/preference feedback loop.
    private var fixedPreparedContainerWidth: Double?

    public init(
        runs: [MarkdownInlineRun],
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .platformDefault,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        fontProfile: MarkdownFontProfile? = nil
    ) {
        self.attributed = Self.attributedString(
            for: runs,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
        self.prepared = nil
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.fallbackMetrics = MarkdownInlineFallbackMetrics(
            fontSize: fontSize ?? theme.paragraphFontSize,
            lineHeight: lineHeight ?? theme.paragraphLineHeight,
            fontProfile: fontProfile ?? theme.paragraphFontProfiles.body
        )
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.fixedPreparedContainerWidth = nil
    }

    public init(
        attributed: AttributedString,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .platformDefault,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        fontProfile: MarkdownFontProfile? = nil
    ) {
        self.attributed = attributed
        self.prepared = nil
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.fallbackMetrics = MarkdownInlineFallbackMetrics(
            fontSize: fontSize ?? theme.paragraphFontSize,
            lineHeight: lineHeight ?? theme.paragraphLineHeight,
            fontProfile: fontProfile ?? theme.paragraphFontProfiles.body
        )
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.fixedPreparedContainerWidth = nil
    }

    public init(
        prepared: MarkdownPreparedInlineContent,
        theme: MarkdownTheme = .compactChat,
        baseFont: Font? = nil,
        linkAction: MarkdownLinkAction? = nil,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .platformDefault
    ) {
        self.attributed = prepared.attributed
        self.prepared = prepared
        self.theme = theme
        self.baseFont = baseFont ?? theme.paragraphFont
        self.fallbackMetrics = MarkdownInlineFallbackMetrics(
            fontSize: prepared.fontSize,
            lineHeight: prepared.lineHeight,
            fontProfile: prepared.fontProfiles.body
        )
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.fixedPreparedContainerWidth = nil
    }

    func preparedContainerWidth(_ width: Double?) -> Self {
        var copy = self
        copy.fixedPreparedContainerWidth = width
        return copy
    }

    var fallbackTextMetrics: MarkdownInlineFallbackMetrics {
        fallbackMetrics
    }

    @ViewBuilder
    public var body: some View {
        if let prepared {
            #if os(macOS)
            if nativeTextSelection == .enabled {
                preparedInlineTextView(prepared)
            } else if let mathPieces = prepared.mathTextPieces, !mathPieces.isEmpty {
                inlineMathTextView(pieces: mathPieces, prepared: prepared)
            } else {
                preparedInlineTextView(prepared)
            }
            #else
            if let mathPieces = prepared.mathTextPieces, !mathPieces.isEmpty {
                inlineMathTextView(pieces: mathPieces, prepared: prepared)
            } else {
                preparedInlineTextView(prepared)
            }
            #endif
        } else {
            MarkdownSelectableText(
                attributed: attributed,
                font: baseFont,
                fontSize: fallbackMetrics.fontSize,
                lineHeight: fallbackMetrics.lineHeight,
                fontProfile: fallbackMetrics.fontProfile,
                textColor: theme.textColor,
                linkAction: linkAction,
                nativeTextSelection: nativeTextSelection
            )
        }
    }

    private func inlineMathTextView(
        pieces: [MarkdownInlineMathPiece],
        prepared: MarkdownPreparedInlineContent
    ) -> some View {
        InlineMathTextView(
            pieces: pieces,
            prepared: prepared,
            font: baseFont,
            color: theme.textColor,
            fontSize: prepared.fontSize,
            linkAction: linkAction
        )
    }

    private func preparedInlineTextView(_ prepared: MarkdownPreparedInlineContent) -> some View {
        PreparedInlineTextView(
            prepared: prepared,
            fallbackAttributed: attributed,
            theme: theme,
            baseFont: baseFont,
            linkAction: linkAction,
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection,
            fixedPreparedContainerWidth: fixedPreparedContainerWidth
        )
    }

    /*
     Image-backed inline math normally uses `InlineMathTextView` so SwiftUI can
     compose its prepared glyph bitmap into `Text`. On macOS native-selection
     mode, `PreparedInlineTextView` instead feeds those same prepared pieces to
     the bounded AppKit text leaf as TextKit attachments. This keeps the math
     visual and makes the entire paragraph selectable without mounting
     SwiftUI's private `SelectionOverlay`.
     */

    public nonisolated static func plainText(
        for runs: [MarkdownInlineRun],
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy()
    ) -> String {
        runs.map { run in
            if run.isImagePresentation {
                guard let source = run.resolvedImageSource else {
                    return run.text.isEmpty ? "[image]" : run.text
                }
                switch imagePolicy.evaluateImage(source: source, altText: run.text) {
                case .allow:
                    return run.text.isEmpty ? source : run.text
                case .deny:
                    return run.text.isEmpty ? "[image]" : run.text
                }
            }
            return run.text
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

            if run.isLinkPresentation {
                if let destination = run.destination,
                   let url = markdownLinkURL(for: destination, policy: linkPolicy) {
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
        guard run.isImagePresentation else {
            return run.text
        }

        guard let source = run.resolvedImageSource else {
            return run.text.isEmpty ? "[image]" : run.text
        }

        switch imagePolicy.evaluateImage(source: source, altText: run.text) {
        case .allow:
            return run.text.isEmpty ? source : run.text
        case .deny:
            return run.text.isEmpty ? "[image]" : run.text
        }
    }

    nonisolated static func attributedSlice(
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

    nonisolated static func textSlice(
        text: String,
        byteRange: Range<Int>
    ) -> String {
        guard let stringRange = stringRange(forUTF8Range: byteRange, in: text) else {
            return ""
        }
        return String(text[stringRange])
    }

    nonisolated static func stringRange(
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
        let scriptScale = presentation.contains(.subscriptText) || presentation.contains(.superscriptText) ? 0.76 : 1
        attributed[lower..<upper].font = swiftUIFont(
            for: prepared.fontProfiles.profile(for: presentation, kind: kind),
            kind: kind,
            presentation: presentation,
            size: prepared.fontSize * scriptScale
        )
        if presentation.contains(.superscriptText) {
            attributed[lower..<upper].baselineOffset = prepared.fontSize * 0.34
        } else if presentation.contains(.subscriptText) {
            attributed[lower..<upper].baselineOffset = -(prepared.fontSize * 0.18)
        }
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

extension MarkdownPreparedInlineContent {
    /// Visible semantic text for accessibility. Atomic link decorations are
    /// deliberately omitted: the destination label already names the link,
    /// and assistive technology should not announce a globe or "website icon"
    /// as authored document content.
    var semanticAccessibilityText: String {
        prepared.runs.lazy
            .filter { !$0.presentation.contains(.linkDecoration) }
            .map(\.text)
            .joined()
    }
}

struct MarkdownInlineFallbackMetrics: Sendable, Hashable {
    var fontSize: Double
    var lineHeight: Double
    var fontProfile: MarkdownFontProfile

    init(fontSize: Double, lineHeight: Double, fontProfile: MarkdownFontProfile) {
        self.init(
            fontSize: fontSize,
            lineHeight: lineHeight,
            fontProfile: fontProfile,
            fallbackFontSize: 14,
            fallbackLineHeight: 14
        )
    }

    init(
        fontSize: Double,
        lineHeight: Double,
        fontProfile: MarkdownFontProfile,
        fallbackFontSize: Double,
        fallbackLineHeight: Double
    ) {
        let safeFontSize = Self.sanitizedPositive(fontSize, fallback: fallbackFontSize)
        self.fontSize = safeFontSize
        self.lineHeight = MarkdownInlineLineHeight.resolved(
            requested: Self.sanitizedPositive(
                lineHeight,
                fallback: max(fallbackLineHeight, safeFontSize)
            ),
            fontSize: safeFontSize,
            profiles: MarkdownInlineFontProfiles(uniform: fontProfile)
        )
        self.fontProfile = fontProfile
    }

    private static func sanitizedPositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}

nonisolated func markdownLinkURL(for destination: String, policy: any MarkdownLinkPolicy) -> URL? {
    guard case .allow = policy.evaluateLink(destination: destination) else {
        return nil
    }

    let urlDestination: String
    if let normalizer = policy as? any MarkdownLinkDestinationNormalizing {
        guard let normalized = normalizer.normalizedLinkDestination(for: destination) else {
            return nil
        }
        urlDestination = normalized
    } else {
        urlDestination = destination
    }

    return URL(string: urlDestination)
}

private extension MarkdownInlineRun {
    var isLinkPresentation: Bool {
        kind == .link ||
            ((kind == .softBreak || kind == .hardBreak) && destination != nil)
    }

    var isImagePresentation: Bool {
        kind == .image || presentation.contains(.image)
    }

    var resolvedImageSource: String? {
        imageSource ?? (kind == .image ? destination : nil)
    }
}

struct PreparedInlineLayoutIdentity: Hashable {
    var cacheFingerprint: MarkdownContentFingerprint
    var fixedPreparedContainerWidth: Double?
}

/// Bounded descendant-layout state propagated to a mounted streaming region.
///
/// A real container-width change reaches `PreparedInlineTextView` through a
/// deferred preference update. Until that update runs, an ancestor can
/// provisionally measure the new width with the old line layout. This compact
/// aggregate changes only after the prepared leaf has installed its current
/// width-specific `layoutResult`, giving the region host a precise signal to
/// discard that provisional measurement without replacing view identity.
struct MarkdownPreparedInlineLayoutSettlement: Equatable {
    static let empty = Self(leafCount: 0, low: 0, high: 0)

    var leafCount: Int
    var low: UInt64
    var high: UInt64

    static func leaf(
        identity: PreparedInlineLayoutIdentity,
        containerWidth: CGFloat,
        layoutResult: InlineLayoutResult
    ) -> Self {
        var fingerprint = MarkdownContentFingerprint(
            domain: "prepared-inline-layout-settlement"
        )
        fingerprint.combine(identity.cacheFingerprint)
        if let fixedPreparedContainerWidth = identity.fixedPreparedContainerWidth {
            fingerprint.combine(true)
            fingerprint.combine(fixedPreparedContainerWidth)
        } else {
            fingerprint.combine(false)
        }
        fingerprint.combine(Double(containerWidth))
        fingerprint.combine(layoutResult.cacheFingerprint)
        return Self(
            leafCount: 1,
            low: fingerprint.low,
            high: fingerprint.high
        )
    }

    mutating func combine(_ next: Self) {
        leafCount &+= next.leafCount
        // Streaming regions are bounded by prepared render items. Commutative
        // two-lane aggregation avoids retaining one preference value per
        // descendant while remaining sensitive to duplicate leaves.
        low &+= next.low
        high &+= next.high
    }
}

struct MarkdownPreparedInlineLayoutSettlementPreferenceKey: PreferenceKey {
    static let defaultValue = MarkdownPreparedInlineLayoutSettlement.empty

    static func reduce(
        value: inout MarkdownPreparedInlineLayoutSettlement,
        nextValue: () -> MarkdownPreparedInlineLayoutSettlement
    ) {
        value.combine(nextValue())
    }
}

private struct MarkdownStreamingRegionMeasurementEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var markdownStreamingRegionMeasurementEnabled: Bool {
        get { self[MarkdownStreamingRegionMeasurementEnabledKey.self] }
        set { self[MarkdownStreamingRegionMeasurementEnabledKey.self] = newValue }
    }
}

private struct PreparedInlineTextView: View {
    var prepared: MarkdownPreparedInlineContent
    var fallbackAttributed: AttributedString
    var theme: MarkdownTheme
    var baseFont: Font
    var linkAction: MarkdownLinkAction?
    var inlineRenderingMode: MarkdownInlineRenderingMode
    var nativeTextSelection: MarkdownNativeTextSelection
    var fixedPreparedContainerWidth: Double?

    @Environment(\.markdownDocumentSelectionContext) private var documentSelectionContext
    @Environment(\.markdownSelectionController) private var selectionController
    @Environment(\.markdownStreamingRegionMeasurementEnabled)
    private var streamingRegionMeasurementEnabled

    @State private var containerWidth: CGFloat = 0
    @State private var layoutResult: InlineLayoutResult
    @State private var recordedNonFiniteFallback = false
    @State private var recordedClipping = false

    init(
        prepared: MarkdownPreparedInlineContent,
        fallbackAttributed: AttributedString,
        theme: MarkdownTheme,
        baseFont: Font,
        linkAction: MarkdownLinkAction?,
        inlineRenderingMode: MarkdownInlineRenderingMode,
        nativeTextSelection: MarkdownNativeTextSelection,
        fixedPreparedContainerWidth: Double?
    ) {
        self.prepared = prepared
        self.fallbackAttributed = fallbackAttributed
        self.theme = theme
        self.baseFont = baseFont
        self.linkAction = linkAction
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.fixedPreparedContainerWidth = fixedPreparedContainerWidth
        let initial = prepared.initialLayoutResult ?? InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
        _layoutResult = State(initialValue: initial)
        if let initial = prepared.initialLayoutResult, !initial.lines.isEmpty {
            _containerWidth = State(initialValue: CGFloat(
                fixedPreparedContainerWidth ?? prepared.defaultLayoutWidth
            ))
        }
    }

    private var layoutIdentity: PreparedInlineLayoutIdentity {
        PreparedInlineLayoutIdentity(
            cacheFingerprint: prepared.cacheFingerprint,
            fixedPreparedContainerWidth: fixedPreparedContainerWidth
        )
    }

    @ViewBuilder
    var body: some View {
        if fixedPreparedContainerWidth != nil,
           nativeTextSelection != .enabled,
           canRenderNativeLines
        {
            fixedPreparedNativeLineSurface
                // A content or prepared-width revision replaces the leaf.
                .id(layoutIdentity)
        } else if fixedPreparedContainerWidth != nil {
            decoratedRenderSurface
                // A content or prepared-width revision replaces the stateful
                // leaf. Retained rows keep an identical identity and never
                // mount per-cell width feedback machinery.
                .id(layoutIdentity)
        } else {
            dynamicallySizedRenderSurface
        }
    }

    private var fixedPreparedNativeLineSurface: some View {
        let firstBaselineFromTop = prepared.firstTextBaselineFromTop(
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection
        )
        let width = CGFloat(fixedPreparedContainerWidth ?? prepared.defaultLayoutWidth)
        return NativeInlineLineTextView(
            prepared: prepared,
            layoutResult: layoutResult,
            fallbackAttributed: fallbackAttributed,
            baseFont: baseFont,
            theme: theme,
            containerWidth: width,
            linkAction: linkAction,
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection,
            dragSelectionHandler: makeDragSelectionHandler()
        )
        .alignmentGuide(.firstTextBaseline) { _ in firstBaselineFromTop }
        .environment(\.openURL, markdownOpenURLAction(linkAction: linkAction))
        .accessibilityValue(layoutResult.lines.isEmpty ? "" : "\(layoutResult.lines.count) prepared lines")
    }

    private var decoratedRenderSurface: some View {
        let firstBaselineFromTop = prepared.firstTextBaselineFromTop(
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection
        )
        return renderSurface
            // Neither prepared leaf is a SwiftUI `Text`. Publish the baseline
            // used by its actual engine so parent list layouts never guess.
            .alignmentGuide(.firstTextBaseline) { _ in
                firstBaselineFromTop
            }
            .environment(\.openURL, markdownOpenURLAction(linkAction: linkAction))
            .accessibilityValue(layoutResult.lines.isEmpty ? "" : "\(layoutResult.lines.count) prepared lines")
    }

    private var dynamicallySizedRenderSurface: some View {
        decoratedRenderSurface
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

                // Report the real on-screen width back to the session's
                // shared preparation cache so later-prepared blocks (e.g.
                // new blocks appearing during streaming) pre-compute their
                // initial layout / CTLine plan at a width that actually
                // matches the rendering context, instead of a fixed
                // constant most layouts never hit (INV-P1, INV-P2).
                prepared.preparationCache?.recordActualContainerWidth(Double(width))

                if abs(width - containerWidth) > 0.5 {
                    containerWidth = width
                    refreshLayoutIfPossible()
                }
            }
            .markdownOnChange(of: layoutIdentity) { _ in
                layoutResult = prepared.initialLayoutResult ?? InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
                if let initial = prepared.initialLayoutResult, !initial.lines.isEmpty {
                    containerWidth = CGFloat(prepared.defaultLayoutWidth)
                }
                refreshLayoutIfPossible()
            }
            .preference(
                key: MarkdownPreparedInlineLayoutSettlementPreferenceKey.self,
                value: streamingRegionMeasurementEnabled
                    ? MarkdownPreparedInlineLayoutSettlement.leaf(
                        identity: layoutIdentity,
                        containerWidth: containerWidth,
                        layoutResult: layoutResult
                    )
                    : .empty
            )
    }

    @ViewBuilder
    private var renderSurface: some View {
        if nativeTextSelection == .enabled {
            MarkdownNativeSelectableWidthLayout {
                MarkdownSelectableText(
                    attributed: InlineRunsView.renderingAttributedString(for: prepared),
                    font: baseFont,
                    fontSize: prepared.fontSize,
                    lineHeight: prepared.lineHeight,
                    fontProfile: prepared.fontProfiles.body,
                    textColor: theme.textColor,
                    linkAction: linkAction,
                    nativeTextSelection: .enabled,
                    lineSpacing: InlineRunsView.nativeLineSpacing(for: prepared),
                    wraps: true,
                    preparedInlineContent: prepared,
                    mathTextPieces: prepared.mathTextPieces
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(widthReaderIfNeeded)
        } else if canRenderNativeLines {
            Color.clear
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: nativeLineSurfaceHeight, alignment: .topLeading)
                .background(widthReaderIfNeeded)
                .overlay(alignment: .topLeading) {
                    NativeInlineLineTextView(
                        prepared: prepared,
                        layoutResult: layoutResult,
                        fallbackAttributed: fallbackAttributed,
                        baseFont: baseFont,
                        theme: theme,
                        containerWidth: containerWidth,
                        linkAction: linkAction,
                        inlineRenderingMode: inlineRenderingMode,
                        nativeTextSelection: nativeTextSelection,
                        dragSelectionHandler: makeDragSelectionHandler()
                    )
                }
                .background(nativeLineSelectionFragmentsPreferenceIfNeeded)
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
                .background(widthReaderIfNeeded)
                .background(fallbackSelectionFragmentPreferenceIfNeeded)
        }
    }

    private var canRenderNativeLines: Bool {
        inlineRenderingMode.usesPreparedLineSurface &&
            !layoutResult.lines.isEmpty
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

    @ViewBuilder
    private var widthReaderIfNeeded: some View {
        if fixedPreparedContainerWidth == nil {
            widthReader
        }
    }

    private var nativeLineSelectionFragmentsPreference: some View {
        GeometryReader { proxy in
            let rect = selectionPreferenceRect(from: proxy)
            let fragments = nativeLineSelectionFragments(rect: rect)
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: fragments
            )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var nativeLineSelectionFragmentsPreferenceIfNeeded: some View {
        if fixedPreparedContainerWidth == nil {
            nativeLineSelectionFragmentsPreference
        }
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

    @ViewBuilder
    private var fallbackSelectionFragmentPreferenceIfNeeded: some View {
        if fixedPreparedContainerWidth == nil {
            fallbackSelectionFragmentPreference
        }
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

    @MainActor
    private func makeDragSelectionHandler() -> ((CGPoint, CGPoint) -> Void)? {
        guard let selectionController, let documentSelectionContext else {
            return nil
        }
        let blockID = documentSelectionContext.blockID
        let prepared = prepared
        let layoutResult = layoutResult
        return { startPoint, endPoint in
            let fragments = MarkdownDocumentSelectionFragment.inlineLineFragments(
                blockID: blockID,
                prepared: prepared,
                layout: layoutResult,
                rect: CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                idPrefix: "text-leaf"
            )
            guard !fragments.isEmpty else { return }
            let startFragment = MarkdownDocumentSelectionFragment.hitFragment(
                at: startPoint, in: fragments, hitSlop: 4
            )
            let endFragment = MarkdownDocumentSelectionFragment.hitFragment(
                at: endPoint, in: fragments, hitSlop: 4
            )
            guard let startFragment, let endFragment else { return }
            let selection = MarkdownDocumentSelectionFragment.selection(
                from: startFragment, to: endFragment, in: fragments
            )
            selectionController.selectSourceRanges(
                selection.ranges,
                selectedBlockIDs: selection.blockIDs
            )
        }
    }

}

private struct MarkdownNativeSelectableWidthLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else {
            return .zero
        }
        let finiteWidth = proposal.width.flatMap { width in
            width.isFinite && width > 0 ? width : nil
        }
        let measured = subview.sizeThatFits(
            ProposedViewSize(width: finiteWidth, height: nil)
        )
        return CGSize(width: finiteWidth ?? measured.width, height: measured.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard let subview = subviews.first else {
            return
        }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
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
