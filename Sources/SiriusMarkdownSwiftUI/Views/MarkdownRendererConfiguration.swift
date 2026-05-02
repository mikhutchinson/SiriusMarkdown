import SiriusMarkdownCore
import Foundation
import SwiftUI

public protocol MarkdownCodeHighlighter: Sendable {
    func highlightedCode(_ code: String, infoString: String?) -> AttributedString
}

public protocol MarkdownMathRenderer: Sendable {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString
}

public enum MarkdownPreparedImageSource: Sendable, Hashable {
    case placeholder(reason: String)
    case localFile(path: String)
    case data(Data, mimeType: String)
    case remote(URL)
}

public struct MarkdownPreparedImage: Sendable, Hashable {
    public var source: String
    public var altText: String?
    public var sourceRange: MarkdownSourceRange?
    public var preparedSource: MarkdownPreparedImageSource

    public init(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        preparedSource: MarkdownPreparedImageSource
    ) {
        self.source = source
        self.altText = altText
        self.sourceRange = sourceRange
        self.preparedSource = preparedSource
    }
}

public protocol MarkdownImageResolver: Sendable {
    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage
}

public struct PlainMarkdownCodeHighlighter: MarkdownCodeHighlighter, MarkdownCodeHighlighterCacheIdentifying {
    public init() {}

    public var codeHighlighterCacheIdentity: String {
        "siriusmarkdown.plain-code"
    }

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

public struct DefaultMarkdownImageResolver: MarkdownImageResolver {
    public init() {}

    public func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        let preparedSource: MarkdownPreparedImageSource
        switch policyDecision {
        case .allow:
            preparedSource = .placeholder(reason: "Image rendering requires a host image resolver.")
        case let .deny(reason):
            preparedSource = .placeholder(reason: reason)
        }

        return MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: preparedSource
        )
    }
}

public struct MarkdownRendererConfiguration: Sendable {
    public var theme: MarkdownTheme
    public var inlineRenderingMode: MarkdownInlineRenderingMode
    public var linkAction: MarkdownLinkAction?
    public var copyProvider: MarkdownCopyProvider?
    public var linkPolicy: any MarkdownLinkPolicy
    public var imagePolicy: any MarkdownImagePolicy
    public var imageResolver: any MarkdownImageResolver
    public var htmlPolicy: any MarkdownHTMLPolicy
    public var codePolicy: any MarkdownCodePolicy
    public var mathPolicy: any MarkdownMathPolicy
    public var codeHighlighter: any MarkdownCodeHighlighter
    public var mathRenderer: any MarkdownMathRenderer
    public var preparationCache: MarkdownRenderPreparationCache
    public var diagnosticsRecorder: MarkdownDiagnosticsRecorder

    public init(
        theme: MarkdownTheme = .compactChat,
        inlineRenderingMode: MarkdownInlineRenderingMode = .systemText,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.inlineRenderingMode = inlineRenderingMode
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.imageResolver = imageResolver
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mathRenderer = mathRenderer
        self.preparationCache = preparationCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public init(
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.init(
            theme: theme,
            inlineRenderingMode: .systemText,
            linkAction: linkAction,
            copyProvider: copyProvider,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy,
            imageResolver: imageResolver,
            htmlPolicy: htmlPolicy,
            codePolicy: codePolicy,
            mathPolicy: mathPolicy,
            codeHighlighter: codeHighlighter,
            mathRenderer: mathRenderer,
            preparationCache: preparationCache,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    public static var compactChat: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .compactChat, inlineRenderingMode: .preparedNativeLines)
    }

    public static var document: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .document, inlineRenderingMode: .preparedNativeLines)
    }

    public func prepare(block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        diagnosticsRecorder.recordRenderPreparation()

        switch block.kind {
        case .codeBlock:
            let code = Self.codeText(for: block)
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: code) {
            case .allow:
                let language = MarkdownCodeLanguage(infoString: block.infoString)
                let key = Self.codeCacheKey(
                    for: block,
                    code: code,
                    language: language,
                    palette: theme.syntaxHighlightingPalette,
                    highlighterIdentity: codeHighlighterCacheIdentity
                )
                if let cached = preparationCache.code(forKey: key) {
                    diagnosticsRecorder.recordCacheHit()
                    return MarkdownPreparedBlockContent(blockID: block.id, code: cached)
                }

                diagnosticsRecorder.recordCacheMiss()
                let highlighted: AttributedString
                if shouldRecordCodeHighlight(language: language) {
                    diagnosticsRecorder.recordCodeHighlight()
                    highlighted = MarkdownDiagnostics().signpost("CodeHighlight", category: "RenderPreparation") {
                        highlightedCode(code, infoString: block.infoString, language: language)
                    }
                } else {
                    highlighted = highlightedCode(code, infoString: block.infoString, language: language)
                }
                preparationCache.insertCode(highlighted, forKey: key)
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    code: highlighted
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .mathBlock:
            let math = Self.mathText(for: block)
            switch mathPolicy.evaluateMath(math, isBlock: true) {
            case .allow:
                let key = Self.cacheKey(for: block, namespace: "rendered-math:block")
                if let cached = preparationCache.math(forKey: key) {
                    diagnosticsRecorder.recordCacheHit()
                    return MarkdownPreparedBlockContent(blockID: block.id, math: cached)
                }

                diagnosticsRecorder.recordCacheMiss()
                diagnosticsRecorder.recordMathRender()
                let rendered = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
                    mathRenderer.renderedMath(math, isBlock: true)
                }
                preparationCache.insertMath(rendered, forKey: key)
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    math: rendered
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .htmlBlock:
            switch htmlPolicy.evaluateHTML(block.text) {
            case .allow:
                return MarkdownPreparedBlockContent(blockID: block.id, htmlAllowed: true)
            case let .deny(reason):
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    htmlAllowed: false,
                    policyDenialReason: reason
                )
            }
        case .unorderedList, .orderedList, .taskList:
            let inline = preparedInline(for: block.inlines, sourceRange: block.sourceRange, block: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: inline?.attributed,
                inlineLayout: inline,
                listItems: preparedListItems(block.listItems)
            )
        case .table:
            let inline = preparedInline(for: block.inlines, sourceRange: block.sourceRange, block: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: inline?.attributed,
                inlineLayout: inline,
                table: block.table.map(preparedTable)
            )
        default:
            let inline = preparedInline(for: block.inlines, sourceRange: block.sourceRange, block: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: inline?.attributed,
                inlineLayout: inline
            )
        }
    }

    public func prepare(snapshot: MarkdownSnapshot) -> MarkdownPreparedSnapshot {
        var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent] = [:]
        var preparedItems: [MarkdownPreparedSnapshotItem] = []

        for item in snapshot.items {
            switch item {
            case let .block(block):
                let prepared = prepare(block: block)
                preparedContentByBlockID[block.id] = prepared
                preparedItems.append(.block(block, prepared))
            case let .hostBoundary(boundary):
                preparedItems.append(.hostBoundary(boundary))
            }
        }

        return MarkdownPreparedSnapshot(
            snapshot: snapshot,
            items: preparedItems,
            preparedContentByBlockID: preparedContentByBlockID
        )
    }

    public nonisolated static func codeText(for block: MarkdownBlock) -> String {
        block.text
    }

    public nonisolated static func mathText(for block: MarkdownBlock) -> String {
        if let mathRun = block.inlines.first(where: { $0.kind == .math }) {
            return mathRun.text
        }

        var lines = block.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "$$" {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "$$" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func cacheKey(for block: MarkdownBlock, namespace: String) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: block.contentHash == 0 ? stableHash(block.text) : block.contentHash,
            namespace: namespace
        )
    }

    private nonisolated static func codeCacheKey(
        for block: MarkdownBlock,
        code: String,
        language: MarkdownCodeLanguage,
        palette: MarkdownSyntaxHighlightingPalette,
        highlighterIdentity: String
    ) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: stableHash(code),
            namespace: [
                "highlighted-code:v2",
                "language=\(language.cacheIdentity)",
                "palette=\(palette.cacheIdentity)",
                "highlighter=\(highlighterIdentity)"
            ].joined(separator: ":")
        )
    }

    private var codeHighlighterCacheIdentity: String {
        if let identifying = codeHighlighter as? any MarkdownCodeHighlighterCacheIdentifying {
            return identifying.codeHighlighterCacheIdentity
        }

        return String(reflecting: type(of: codeHighlighter))
    }

    private func shouldRecordCodeHighlight(language: MarkdownCodeLanguage) -> Bool {
        if codeHighlighter is PlainMarkdownCodeHighlighter {
            return false
        }

        if codeHighlighter is DefaultMarkdownCodeHighlighter {
            return language.shouldHighlight
        }

        return true
    }

    private func highlightedCode(
        _ code: String,
        infoString: String?,
        language: MarkdownCodeLanguage
    ) -> AttributedString {
        if codeHighlighter is PlainMarkdownCodeHighlighter {
            return DefaultMarkdownCodeHighlighter.plainCode(code)
        }

        if let defaultHighlighter = codeHighlighter as? DefaultMarkdownCodeHighlighter {
            guard language.shouldHighlight else {
                return DefaultMarkdownCodeHighlighter.plainCode(code)
            }

            return defaultHighlighter.highlightedCode(
                code,
                infoString: infoString,
                palette: theme.syntaxHighlightingPalette
            )
        }

        return codeHighlighter.highlightedCode(code, infoString: infoString)
    }

    private func preparedInline(
        for runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange,
        block: MarkdownBlock? = nil
    ) -> MarkdownPreparedInlineContent? {
        guard !runs.isEmpty else {
            return nil
        }

        let metrics = inlineMetrics(for: block)
        let key = MarkdownCacheKey(
            sourceRange: sourceRange,
            contentHash: Self.inlineHash(runs),
            namespace: "inline-prepared:\(metrics.fontSize):\(metrics.lineHeight):\(metrics.fontProfiles.cacheKey)"
        )
        if let cached = preparationCache.inline(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        diagnosticsRecorder.recordCacheMiss()
        let inlinePayload = preparedInlinePayload(for: runs)
        let images = preparedImages(for: runs)
        let prepared = PreparedInlineContent(runs: inlinePayload.runs, sourceRange: sourceRange)
        diagnosticsRecorder.recordPrepare()
        let measurer = CoreTextInlineMeasurer(profiles: metrics.fontProfiles)
        let measured = VariableWidthLineWalker(measurer: measurer).prepare(
            prepared,
            fontSize: metrics.fontSize
        )
        let layoutCache = MarkdownInlineLayoutCache(
            measurer: measurer,
            diagnosticsRecorder: diagnosticsRecorder
        )
        let inline = MarkdownPreparedInlineContent(
            attributed: inlinePayload.attributed,
            prepared: prepared,
            measured: measured,
            images: images,
            fontSize: metrics.fontSize,
            lineHeight: metrics.lineHeight,
            fontProfiles: metrics.fontProfiles,
            layoutCache: layoutCache
        )
        preparationCache.insertInline(inline, forKey: key)
        return inline
    }

    private func preparedInlinePayload(
        for runs: [MarkdownInlineRun]
    ) -> (runs: [MarkdownInlineRun], attributed: AttributedString) {
        var displayRuns: [MarkdownInlineRun] = []
        var attributed = AttributedString()

        for run in runs {
            guard run.kind == .math else {
                displayRuns.append(run)
                attributed.append(
                    InlineRunsView.attributedString(
                        for: [run],
                        linkPolicy: linkPolicy,
                        imagePolicy: imagePolicy
                    )
                )
                continue
            }

            switch mathPolicy.evaluateMath(run.text, isBlock: false) {
            case .allow:
                diagnosticsRecorder.recordMathRender()
                let rendered = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
                    mathRenderer.renderedMath(run.text, isBlock: false)
                }
                attributed.append(rendered)
                let renderedText = String(rendered.characters)
                displayRuns.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: renderedText.isEmpty ? run.text : renderedText,
                        sourceRange: run.sourceRange,
                        destination: run.destination
                    )
                )
            case .deny:
                displayRuns.append(run)
                attributed.append(
                    InlineRunsView.attributedString(
                        for: [run],
                        linkPolicy: linkPolicy,
                        imagePolicy: imagePolicy
                    )
                )
            }
        }

        return (displayRuns, attributed)
    }

    private func preparedListItems(_ items: [MarkdownListItem]) -> [MarkdownPreparedListItem] {
        items.map { item in
            let inline = preparedInline(for: item.inlines, sourceRange: item.sourceRange)
            return MarkdownPreparedListItem(
                id: "list-item:\(item.sourceRange.byteRange.lowerBound):\(item.sourceRange.byteRange.upperBound)",
                sourceRange: item.sourceRange,
                taskState: item.taskState,
                inline: inline?.attributed,
                inlineLayout: inline,
                childListKind: item.childListKind,
                childOrderedListStart: item.childOrderedListStart,
                childItems: preparedListItems(item.childItems)
            )
        }
    }

    private func preparedImages(for runs: [MarkdownInlineRun]) -> [MarkdownPreparedImage] {
        runs.compactMap { run in
            guard run.kind == .image,
                  let source = run.destination
            else {
                return nil
            }

            let decision = imagePolicy.evaluateImage(source: source, altText: run.text)
            return imageResolver.preparedImage(
                source: source,
                altText: run.text.isEmpty ? nil : run.text,
                sourceRange: run.sourceRange,
                policyDecision: decision
            )
        }
    }

    private func preparedTable(_ table: MarkdownTableBlock) -> MarkdownPreparedTableBlock {
        MarkdownPreparedTableBlock(
            columnAlignments: table.columnAlignments,
            header: table.header.map(preparedTableCell),
            rows: table.rows.enumerated().map { index, row in
                let cells = row.map(preparedTableCell)
                return MarkdownPreparedTableRow(
                    id: cells.first?.id ?? "table-row:\(index)",
                    cells: cells
                )
            }
        )
    }

    private func preparedTableCell(_ cell: MarkdownTableCell) -> MarkdownPreparedTableCell {
        let inline = preparedInline(for: cell.inlines, sourceRange: cell.sourceRange)
        return MarkdownPreparedTableCell(
            id: "table-cell:\(cell.sourceRange.byteRange.lowerBound):\(cell.sourceRange.byteRange.upperBound)",
            sourceRange: cell.sourceRange,
            inline: inline?.attributed,
            inlineLayout: inline,
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
    }

    private func inlineMetrics(
        for block: MarkdownBlock?
    ) -> (fontSize: Double, lineHeight: Double, fontProfiles: MarkdownInlineFontProfiles) {
        guard let block else {
            return (theme.paragraphFontSize, theme.paragraphLineHeight, theme.paragraphFontProfiles)
        }

        switch block.kind {
        case .heading:
            switch block.headingLevel ?? 3 {
            case 1:
                return (34, 42, theme.headingFontProfiles)
            case 2:
                return (28, 36, theme.headingFontProfiles)
            default:
                return (theme.headingFontSize, theme.headingLineHeight, theme.headingFontProfiles)
            }
        case .codeBlock, .htmlBlock, .mathBlock:
            return (theme.codeFontSize, theme.codeLineHeight, theme.codeFontProfiles)
        default:
            return (theme.paragraphFontSize, theme.paragraphLineHeight, theme.paragraphFontProfiles)
        }
    }

    private nonisolated static func inlineHash(_ runs: [MarkdownInlineRun]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for run in runs {
            hash = append(run.kind.rawValue, to: hash)
            hash = append(run.text, to: hash)
            hash = append(run.destination ?? "", to: hash)
        }
        return hash
    }

    private nonisolated static func stableHash(_ text: String) -> UInt64 {
        append(text, to: 0xcbf29ce484222325)
    }

    private nonisolated static func append(_ text: String, to initialHash: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        hash = initialHash
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

public struct MarkdownPreparedInlineContent: Sendable {
    public var attributed: AttributedString
    public var prepared: PreparedInlineContent
    public var measured: MeasuredInlineContent
    public var images: [MarkdownPreparedImage]
    public var fontSize: Double
    public var lineHeight: Double
    public var fontProfiles: MarkdownInlineFontProfiles
    public var layoutCache: MarkdownInlineLayoutCache

    public init(
        attributed: AttributedString,
        prepared: PreparedInlineContent,
        measured: MeasuredInlineContent,
        images: [MarkdownPreparedImage] = [],
        fontSize: Double,
        lineHeight: Double,
        fontProfiles: MarkdownInlineFontProfiles = .paragraphDefault,
        layoutCache: MarkdownInlineLayoutCache = MarkdownInlineLayoutCache()
    ) {
        self.attributed = attributed
        self.prepared = prepared
        self.measured = measured
        self.images = images
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontProfiles = fontProfiles
        self.layoutCache = layoutCache
    }

    public func layout(
        containerWidth: Double,
        allowsOverwideFallback: Bool = false
    ) -> InlineLayoutResult {
        layout(
            options: InlineLayoutOptions(
                containerWidth: containerWidth,
                fontSize: fontSize,
                lineHeight: lineHeight
            ),
            allowsOverwideFallback: allowsOverwideFallback
        )
    }

    public func layout(
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = false
    ) -> InlineLayoutResult {
        layoutCache.layout(
            measured,
            options: options,
            allowsOverwideFallback: allowsOverwideFallback
        )
    }
}

public final class MarkdownInlineLayoutCache: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: InlineLayoutEngine<CoreTextInlineMeasurer>

    public init(
        measurer: CoreTextInlineMeasurer = CoreTextInlineMeasurer(),
        cacheCapacity: Int = 256,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.engine = InlineLayoutEngine(
            measurer: measurer,
            cacheCapacity: cacheCapacity,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    public var diagnosticsCounters: MarkdownDiagnosticsCounters {
        lock.withLock {
            engine.diagnosticsCounters
        }
    }

    public func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = false
    ) -> InlineLayoutResult {
        lock.withLock {
            engine.layout(
                measured,
                options: options,
                allowsOverwideFallback: allowsOverwideFallback
            )
        }
    }

    public func recordNonFiniteInlineProposalFallback() {
        lock.withLock {
            engine.diagnosticsRecorder.recordNonFiniteInlineProposalFallback()
        }
    }

    public func recordNativeLineClipping() {
        lock.withLock {
            engine.diagnosticsRecorder.recordNativeLineClipping()
        }
    }
}

public final class MarkdownRenderPreparationCache: @unchecked Sendable {
    private let lock = NSLock()
    private var inlineCache: BoundedMarkdownCache<MarkdownPreparedInlineContent>
    private var codeCache: BoundedMarkdownCache<AttributedString>
    private var mathCache: BoundedMarkdownCache<AttributedString>

    public init(capacity: Int = 256) {
        self.inlineCache = BoundedMarkdownCache(capacity: capacity)
        self.codeCache = BoundedMarkdownCache(capacity: capacity)
        self.mathCache = BoundedMarkdownCache(capacity: capacity)
    }

    public func inline(forKey key: MarkdownCacheKey) -> MarkdownPreparedInlineContent? {
        lock.withLock {
            inlineCache.value(forKey: key)
        }
    }

    public func insertInline(_ inline: MarkdownPreparedInlineContent, forKey key: MarkdownCacheKey) {
        lock.withLock {
            inlineCache[key] = inline
        }
    }

    public func code(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            codeCache.value(forKey: key)
        }
    }

    public func insertCode(_ code: AttributedString, forKey key: MarkdownCacheKey) {
        lock.withLock {
            codeCache[key] = code
        }
    }

    public func math(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            mathCache.value(forKey: key)
        }
    }

    public func insertMath(_ math: AttributedString, forKey key: MarkdownCacheKey) {
        lock.withLock {
            mathCache[key] = math
        }
    }

    public func removeAll() {
        lock.withLock {
            inlineCache.removeAll()
            codeCache.removeAll()
            mathCache.removeAll()
        }
    }
}

public struct MarkdownPreparedSnapshot: Sendable {
    public var snapshot: MarkdownSnapshot
    public var items: [MarkdownPreparedSnapshotItem]
    public var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]

    public init(
        snapshot: MarkdownSnapshot,
        items: [MarkdownPreparedSnapshotItem],
        preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]
    ) {
        self.snapshot = snapshot
        self.items = items
        self.preparedContentByBlockID = preparedContentByBlockID
    }

    public subscript(blockID: MarkdownBlockID) -> MarkdownPreparedBlockContent? {
        preparedContentByBlockID[blockID]
    }
}

public enum MarkdownPreparedSnapshotItem: Identifiable, Sendable {
    case block(MarkdownBlock, MarkdownPreparedBlockContent)
    case hostBoundary(MarkdownHostBoundary)

    public var id: String {
        switch self {
        case let .block(block, _):
            return "block:\(block.id.rawValue)"
        case let .hostBoundary(boundary):
            return "host:\(boundary.id.rawValue)"
        }
    }
}

public struct MarkdownPreparedBlockContent: Sendable {
    public var blockID: MarkdownBlockID
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var listItems: [MarkdownPreparedListItem]
    public var table: MarkdownPreparedTableBlock?
    public var code: AttributedString?
    public var math: AttributedString?
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        blockID: MarkdownBlockID,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        listItems: [MarkdownPreparedListItem] = [],
        table: MarkdownPreparedTableBlock? = nil,
        code: AttributedString? = nil,
        math: AttributedString? = nil,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.blockID = blockID
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.listItems = listItems
        self.table = table
        self.code = code
        self.math = math
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
    }
}

public struct MarkdownPreparedListItem: Identifiable, Sendable {
    public var id: String
    public var sourceRange: MarkdownSourceRange
    public var taskState: MarkdownTaskState?
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var childListKind: MarkdownBlockKind?
    public var childOrderedListStart: UInt?
    public var childItems: [MarkdownPreparedListItem]

    public init(
        id: String,
        sourceRange: MarkdownSourceRange,
        taskState: MarkdownTaskState? = nil,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        childListKind: MarkdownBlockKind? = nil,
        childOrderedListStart: UInt? = nil,
        childItems: [MarkdownPreparedListItem] = []
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.taskState = taskState
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.childListKind = childListKind
        self.childOrderedListStart = childOrderedListStart
        self.childItems = childItems
    }
}

public struct MarkdownPreparedTableCell: Identifiable, Sendable {
    public var id: String
    public var sourceRange: MarkdownSourceRange
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var colspan: UInt
    public var rowspan: UInt

    public init(
        id: String,
        sourceRange: MarkdownSourceRange,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        colspan: UInt = 1,
        rowspan: UInt = 1
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.colspan = colspan
        self.rowspan = rowspan
    }
}

public struct MarkdownPreparedTableRow: Identifiable, Sendable {
    public var id: String
    public var cells: [MarkdownPreparedTableCell]

    public init(id: String, cells: [MarkdownPreparedTableCell]) {
        self.id = id
        self.cells = cells
    }
}

public struct MarkdownPreparedTableBlock: Sendable {
    public var columnAlignments: [MarkdownTableColumnAlignment?]
    public var header: [MarkdownPreparedTableCell]
    public var rows: [MarkdownPreparedTableRow]

    public init(
        columnAlignments: [MarkdownTableColumnAlignment?],
        header: [MarkdownPreparedTableCell],
        rows: [MarkdownPreparedTableRow]
    ) {
        self.columnAlignments = columnAlignments
        self.header = header
        self.rows = rows
    }
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
