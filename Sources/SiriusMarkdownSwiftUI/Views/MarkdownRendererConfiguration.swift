import SiriusMarkdownCore
import Foundation
import SwiftUI

public protocol MarkdownCodeHighlighter: Sendable {
    func highlightedCode(_ code: String, infoString: String?) -> AttributedString
}

public protocol MarkdownMathRenderer: Sendable {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString
    func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath
}

public protocol MarkdownMathRendererCacheIdentifying: Sendable {
    var mathRendererCacheIdentity: String { get }
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

public protocol MarkdownImageResolverCacheIdentifying: Sendable {
    var imageResolverCacheIdentity: String { get }
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

public struct PlainMarkdownMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying {
    public init() {}

    public var mathRendererCacheIdentity: String {
        "siriusmarkdown.plain-math"
    }

    public func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        var rendered = AttributedString(source)
        rendered.inlinePresentationIntent = .code
        return rendered
    }
}

public struct DefaultMarkdownImageResolver: MarkdownImageResolver, MarkdownImageResolverCacheIdentifying {
    public init() {}

    public var imageResolverCacheIdentity: String {
        "siriusmarkdown.default-image-resolver.v1"
    }

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
    public enum DocumentSelection: Sendable, Hashable {
        /// Install SiriusMarkdown's source-backed document selection layer.
        case enabled
        /// Disable document-level drag selection and package-owned Cmd-C copy.
        case disabled
    }

    public var theme: MarkdownTheme
    public var inlineRenderingMode: MarkdownInlineRenderingMode
    /// Native text leaf selection policy.
    ///
    /// Disabled by default while an unresolved macOS 26/Sirius hang remains
    /// traceable to SwiftUI's private `SelectionOverlay.updateNSView` path
    /// under `GraphHost.flushTransactions`. Copy affordances and
    /// `MarkdownSelectionController` remain available without mounting that
    /// overlay. Cross-block document selection is controlled separately by
    /// `documentSelection`.
    public var nativeTextSelection: MarkdownNativeTextSelection
    /// Source-backed cross-block selection owned by SiriusMarkdown.
    ///
    /// This is the default product selection path. It does not require
    /// `nativeTextSelection` and does not mount SwiftUI's container-level
    /// SwiftUI native-selection modifiers or private `SelectionOverlay`
    /// surfaces.
    public var documentSelection: DocumentSelection
    public var linkAction: MarkdownLinkAction?
    public var copyProvider: MarkdownCopyProvider?
    public var linkPolicy: any MarkdownLinkPolicy
    public var imagePolicy: any MarkdownImagePolicy
    public var imageResolver: any MarkdownImageResolver
    public var htmlPolicy: any MarkdownHTMLPolicy
    public var codePolicy: any MarkdownCodePolicy
    public var mathPolicy: any MarkdownMathPolicy
    public var codeHighlighter: any MarkdownCodeHighlighter
    public var mermaidRenderer: (any MarkdownMermaidRenderer)?
    public var mathRenderer: any MarkdownMathRenderer
    public var affordanceActionHandler: MarkdownAffordanceActionHandler
    public var preparationCache: MarkdownRenderPreparationCache
    public var diagnosticsRecorder: MarkdownDiagnosticsRecorder

    public init(
        theme: MarkdownTheme = .compactChat,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .disabled,
        documentSelection: DocumentSelection = .enabled,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.documentSelection = documentSelection
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.imageResolver = imageResolver
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mermaidRenderer = mermaidRenderer
        self.mathRenderer = mathRenderer
        self.affordanceActionHandler = affordanceActionHandler
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
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.inlineRenderingMode = .coreTextPaintedLines
        self.nativeTextSelection = .disabled
        self.documentSelection = .enabled
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.imageResolver = imageResolver
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mermaidRenderer = mermaidRenderer
        self.mathRenderer = mathRenderer
        self.affordanceActionHandler = affordanceActionHandler
        self.preparationCache = preparationCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public init(
        theme: MarkdownTheme = .compactChat,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .disabled,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.init(
            theme: theme,
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection,
            documentSelection: .enabled,
            linkAction: linkAction,
            copyProvider: copyProvider,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy,
            imageResolver: imageResolver,
            htmlPolicy: htmlPolicy,
            codePolicy: codePolicy,
            mathPolicy: mathPolicy,
            codeHighlighter: codeHighlighter,
            mermaidRenderer: mermaidRenderer,
            mathRenderer: mathRenderer,
            affordanceActionHandler: affordanceActionHandler,
            preparationCache: preparationCache,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    public static var compactChat: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .compactChat, inlineRenderingMode: .coreTextPaintedLines)
    }

    public static var document: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .document, inlineRenderingMode: .coreTextPaintedLines)
    }

    public func prepare(block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        diagnosticsRecorder.recordRenderPreparation()

        switch block.kind {
        case .codeBlock:
            let code = Self.codeText(for: block)
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: code) {
            case .allow:
                let language = MarkdownCodeLanguage(infoString: block.infoString)
                if language.isMermaid,
                   let mermaid = preparedMermaid(code, block: block)
                {
                    return MarkdownPreparedBlockContent(
                        blockID: block.id,
                        mermaid: mermaid
                    )
                }
                let selectionInline = preparedCodeSelectionInline(for: block)
                let key = Self.codeCacheKey(
                    for: block,
                    code: code,
                    language: language,
                    palette: theme.syntaxHighlightingPalette,
                    highlighterIdentity: codeHighlighterCacheIdentity
                )
                if let key,
                   let cached = preparationCache.code(forKey: key) {
                    diagnosticsRecorder.recordCacheHit()
                    return MarkdownPreparedBlockContent(
                        blockID: block.id,
                        selectionInlineLayout: selectionInline,
                        code: cached
                    )
                }

                if key != nil {
                    diagnosticsRecorder.recordCacheMiss()
                }
                let highlighted: AttributedString
                if shouldRecordCodeHighlight(language: language) {
                    diagnosticsRecorder.recordCodeHighlight()
                    highlighted = MarkdownDiagnostics().signpost("CodeHighlight", category: "RenderPreparation") {
                        highlightedCode(code, infoString: block.infoString, language: language)
                    }
                } else {
                    highlighted = highlightedCode(code, infoString: block.infoString, language: language)
                }
                if let key {
                    preparationCache.insertCode(highlighted, forKey: key)
                }
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    selectionInlineLayout: selectionInline,
                    code: highlighted
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .mathBlock:
            let math = Self.mathText(for: block)
            switch mathPolicy.evaluateMath(math, isBlock: true) {
            case .allow:
                let fontSize = mathBlockFontSize
                if let key = blockMathCacheKey(for: block, fontSize: fontSize) {
                    if let cached = preparationCache.math(forKey: key) {
                        diagnosticsRecorder.recordCacheHit()
                        return mathBlockContent(for: block, math: cached)
                    }

                    diagnosticsRecorder.recordCacheMiss()
                    diagnosticsRecorder.recordMathRender()
                    let rendered = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
                        mathRenderer.preparedMath(math, isBlock: true, fontSize: fontSize)
                    }
                    preparationCache.insertMath(rendered, forKey: key)
                    return mathBlockContent(for: block, math: rendered)
                }

                diagnosticsRecorder.recordMathRender()
                let rendered = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
                    mathRenderer.preparedMath(math, isBlock: true, fontSize: fontSize)
                }
                return mathBlockContent(for: block, math: rendered)
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .htmlBlock:
            switch htmlPolicy.evaluateHTML(block.text) {
            case .allow:
                let selectionInline = htmlSelectionText(for: block).flatMap { text in
                    preparedVisibleTextSelectionInline(
                        text: text,
                        sourceRange: block.sourceRange,
                        block: block
                    )
                }
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    selectionInlineLayout: selectionInline,
                    htmlAllowed: true
                )
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
        prepare(snapshot: snapshot, reusing: nil)
    }

    func prepare(
        snapshot: MarkdownSnapshot,
        reusing previousSnapshot: MarkdownPreparedSnapshot?
    ) -> MarkdownPreparedSnapshot {
        var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent] = [:]
        var preparedItems: [MarkdownPreparedSnapshotItem] = []
        preparedContentByBlockID.reserveCapacity(snapshot.blocks.count)
        preparedItems.reserveCapacity(snapshot.items.count)

        let previousItems = previousSnapshot?.items ?? []
        var fallbackReuse: MarkdownPreparedSnapshotReuse?

        for (index, item) in snapshot.items.enumerated() {
            if index < previousItems.count,
               let reused = Self.reusedPreparedItem(for: item, previousItem: previousItems[index]) {
                switch reused {
                case let .block(block, prepared):
                    preparedContentByBlockID[block.id] = prepared
                case .hostBoundary:
                    break
                }
                preparedItems.append(reused)
                continue
            }

            switch item {
            case let .block(block):
                if fallbackReuse == nil, previousSnapshot != nil {
                    fallbackReuse = MarkdownPreparedSnapshotReuse(
                        previousItems: previousItems.dropFirst(index)
                    )
                }
                let prepared = fallbackReuse?.content(for: block) ?? prepare(block: block)
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

    private static func reusedPreparedItem(
        for item: MarkdownSnapshotItem,
        previousItem: MarkdownPreparedSnapshotItem
    ) -> MarkdownPreparedSnapshotItem? {
        switch (item, previousItem) {
        case let (.block(block), .block(previousBlock, previousContent))
            where block == previousBlock:
            return .block(block, previousContent)
        case let (.hostBoundary(boundary), .hostBoundary(previousBoundary))
            where boundary == previousBoundary:
            return .hostBoundary(boundary)
        default:
            return nil
        }
    }

    func unpreparedSnapshot(for snapshot: MarkdownSnapshot) -> MarkdownPreparedSnapshot {
        var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent] = [:]
        var preparedItems: [MarkdownPreparedSnapshotItem] = []

        for item in snapshot.items {
            switch item {
            case let .block(block):
                let content = unpreparedContent(for: block)
                preparedContentByBlockID[block.id] = content
                preparedItems.append(.block(block, content))
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

    func unpreparedContent(for block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        switch block.kind {
        case .codeBlock:
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: Self.codeText(for: block)) {
            case .allow:
                break
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .mathBlock:
            switch mathPolicy.evaluateMath(Self.mathText(for: block), isBlock: true) {
            case .allow:
                break
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
        default:
            break
        }

        return MarkdownPreparedBlockContent(
            blockID: block.id,
            listItems: block.listItems.map { unpreparedListItem($0, parentID: block.id.rawValue) },
            table: unpreparedTable(block.table, parentID: block.id.rawValue)
        )
    }

    private func unpreparedListItem(
        _ item: MarkdownListItem,
        parentID: String
    ) -> MarkdownPreparedListItem {
        let id = "unprepared-list:\(parentID):\(item.sourceRange.byteRange.lowerBound)-\(item.sourceRange.byteRange.upperBound)"
        return MarkdownPreparedListItem(
            id: id,
            sourceRange: item.sourceRange,
            taskState: item.taskState,
            inline: unpreparedInline(item.inlines) ?? AttributedString(item.text),
            childListKind: item.childListKind,
            childOrderedListStart: item.childOrderedListStart,
            childItems: item.childItems.map { unpreparedListItem($0, parentID: id) }
        )
    }

    private func unpreparedTable(
        _ table: MarkdownTableBlock?,
        parentID: String
    ) -> MarkdownPreparedTableBlock? {
        guard let table else {
            return nil
        }

        return MarkdownPreparedTableBlock(
            columnAlignments: table.columnAlignments,
            header: table.header.enumerated().map { index, cell in
                unpreparedTableCell(cell, parentID: parentID, rowID: "header", column: index)
            },
            rows: table.rows.enumerated().map { rowIndex, row in
                let rowID = "row-\(rowIndex)"
                return MarkdownPreparedTableRow(
                    id: "unprepared-table:\(parentID):\(rowID)",
                    cells: row.enumerated().map { column, cell in
                        unpreparedTableCell(cell, parentID: parentID, rowID: rowID, column: column)
                    }
                )
            }
        )
    }

    private func unpreparedTableCell(
        _ cell: MarkdownTableCell,
        parentID: String,
        rowID: String,
        column: Int
    ) -> MarkdownPreparedTableCell {
        MarkdownPreparedTableCell(
            id: "unprepared-table:\(parentID):\(rowID):\(column)",
            sourceRange: cell.sourceRange,
            inline: unpreparedInline(cell.inlines) ?? AttributedString(cell.text),
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
    }

    private func unpreparedInline(_ runs: [MarkdownInlineRun]) -> AttributedString? {
        guard !runs.isEmpty else {
            return nil
        }

        return InlineRunsView.attributedString(
            for: runs,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
    }

    public nonisolated static func codeText(for block: MarkdownBlock) -> String {
        block.text
    }

    public nonisolated static func mathText(for block: MarkdownBlock) -> String {
        if let mathRun = block.inlines.first(where: { $0.kind == .math }) {
            return mathRun.text
        }

        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\begin{"), trimmed.contains("\\end{") {
            return trimmed
        }

        for (open, close) in [("$$", "$$"), ("\\[", "\\]")] {
            guard trimmed.hasPrefix(open),
                  trimmed.hasSuffix(close),
                  trimmed.count >= open.count + close.count
            else {
                continue
            }

            let start = trimmed.index(trimmed.startIndex, offsetBy: open.count)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -close.count)
            if start <= end {
                return String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    private nonisolated static func cacheKey(for block: MarkdownBlock, namespace: String) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: block.contentHash == 0 ? stableHash(block.text) : block.contentHash,
            namespace: namespace
        )
    }

    private func blockMathCacheKey(for block: MarkdownBlock, fontSize: Double) -> MarkdownCacheKey? {
        guard let mathPolicyIdentity,
              let mathRendererIdentity
        else {
            return nil
        }

        return Self.cacheKey(
            for: block,
            namespace: [
                "rendered-math:block:v3",
                "policy=\(mathPolicyIdentity)",
                "renderer=\(mathRendererIdentity)",
                "fontSize=\(fontSize)"
            ].joined(separator: ":")
        )
    }

    var mathBlockFontSize: Double {
        (theme.paragraphFontSize * 1.3).rounded()
    }

    private func mathBlockContent(
        for block: MarkdownBlock,
        math: MarkdownPreparedMath
    ) -> MarkdownPreparedBlockContent {
        switch math {
        case let .text(attributed):
            let visibleText = String(attributed.characters)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                selectionInlineLayout: preparedVisibleTextSelectionInline(
                    text: visibleText,
                    sourceRange: mathSelectionSourceRange(for: block),
                    block: block
                ),
                math: attributed,
                mathRender: .text(attributed)
            )
        case let .image(image):
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                math: AttributedString(image.latex),
                mathRender: .image(image)
            )
        }
    }

    private func preparedVisibleTextSelectionInline(
        text: String,
        sourceRange: MarkdownSourceRange,
        block: MarkdownBlock
    ) -> MarkdownPreparedInlineContent? {
        guard !text.isEmpty else {
            return nil
        }

        return preparedInline(
            for: [
                MarkdownInlineRun(
                    kind: .text,
                    text: text,
                    sourceRange: sourceRange
                )
            ],
            sourceRange: sourceRange,
            block: block
        )
    }

    private func htmlSelectionText(for block: MarkdownBlock) -> String? {
        let sourceByteCount = block.sourceRange.byteRange.count
        guard sourceByteCount > 0 else {
            return nil
        }
        if block.text.utf8.count == sourceByteCount {
            return block.text
        }

        var text = block.text
        while text.utf8.count > sourceByteCount,
              text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }
        guard text.utf8.count == sourceByteCount else {
            return nil
        }
        return text
    }

    private func mathSelectionSourceRange(for block: MarkdownBlock) -> MarkdownSourceRange {
        block.inlines.first { $0.kind == .math }?.sourceRange ?? block.sourceRange
    }

    private nonisolated static func codeCacheKey(
        for block: MarkdownBlock,
        code: String,
        language: MarkdownCodeLanguage,
        palette: MarkdownSyntaxHighlightingPalette,
        highlighterIdentity: String?
    ) -> MarkdownCacheKey? {
        guard let highlighterIdentity else {
            return nil
        }

        return MarkdownCacheKey(
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

    private nonisolated static func mermaidCacheKey(
        for block: MarkdownBlock,
        code: String,
        rendererIdentity: String?,
        themeIdentity: String
    ) -> MarkdownCacheKey? {
        guard let rendererIdentity else {
            return nil
        }

        return MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: stableHash(code),
            namespace: [
                "rendered-mermaid:v1",
                "renderer=\(rendererIdentity)",
                "theme=\(themeIdentity)"
            ].joined(separator: ":")
        )
    }

    private var codeHighlighterCacheIdentity: String? {
        if let identifying = codeHighlighter as? any MarkdownCodeHighlighterCacheIdentifying {
            return identifying.codeHighlighterCacheIdentity
        }

        return nil
    }

    private var mermaidRendererCacheIdentity: String? {
        guard let mermaidRenderer else {
            return nil
        }

        if let identifying = mermaidRenderer as? any MarkdownMermaidRendererCacheIdentifying {
            return identifying.mermaidRendererCacheIdentity
        }

        return nil
    }

    private var mermaidThemeCacheIdentity: String {
        return String(theme.hashValue)
    }

    private var linkPolicyIdentity: String? {
        (linkPolicy as? any MarkdownLinkPolicyCacheIdentifying)?.linkPolicyCacheIdentity
    }

    private var imagePolicyIdentity: String? {
        (imagePolicy as? any MarkdownImagePolicyCacheIdentifying)?.imagePolicyCacheIdentity
    }

    private var imageResolverIdentity: String? {
        (imageResolver as? any MarkdownImageResolverCacheIdentifying)?.imageResolverCacheIdentity
    }

    private var mathPolicyIdentity: String? {
        (mathPolicy as? any MarkdownMathPolicyCacheIdentifying)?.mathPolicyCacheIdentity
    }

    private var mathRendererIdentity: String? {
        (mathRenderer as? any MarkdownMathRendererCacheIdentifying)?.mathRendererCacheIdentity
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

    private func preparedMermaid(
        _ code: String,
        block: MarkdownBlock
    ) -> MarkdownPreparedMermaidDiagram? {
        guard let mermaidRenderer else {
            return nil
        }

        let key = Self.mermaidCacheKey(
            for: block,
            code: code,
            rendererIdentity: mermaidRendererCacheIdentity,
            themeIdentity: mermaidThemeCacheIdentity
        )
        if let key,
           let cached = preparationCache.mermaid(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        if key != nil {
            diagnosticsRecorder.recordCacheMiss()
        }
        diagnosticsRecorder.recordMermaidRender()
        let rendered = MarkdownDiagnostics().signpost("MermaidRender", category: "RenderPreparation") {
            mermaidRenderer.renderedMermaid(code, sourceRange: block.sourceRange, theme: theme)
        }
        guard let rendered else {
            diagnosticsRecorder.recordMermaidFallback()
            return nil
        }

        if let key {
            preparationCache.insertMermaid(rendered, forKey: key)
        }
        return rendered
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
        let imageDecisions = preparedImageDecisions(for: runs)
        let mathDecisions = preparedMathDecisions(for: runs)
        let cacheKey = inlineCacheNamespace(
            for: runs,
            metrics: metrics,
            imageDecisions: imageDecisions,
            mathDecisions: mathDecisions
        ).map { namespace in
            MarkdownCacheKey(
                sourceRange: sourceRange,
                contentHash: Self.inlineHash(runs),
                namespace: namespace
            )
        }
        if let cacheKey,
           let cached = preparationCache.inline(forKey: cacheKey) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        if cacheKey != nil {
            diagnosticsRecorder.recordCacheMiss()
        }
        let images = preparedImages(from: imageDecisions)
        let inlinePayload = preparedInlinePayload(
            for: runs,
            images: images,
            mathDecisions: mathDecisions,
            fontSize: metrics.fontSize
        )
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
            layoutCache: layoutCache,
            mathTextPieces: inlinePayload.mathPieces
        )
        if let cacheKey {
            preparationCache.insertInline(inline, forKey: cacheKey)
        }
        return inline
    }

    private func preparedCodeSelectionInline(for block: MarkdownBlock) -> MarkdownPreparedInlineContent? {
        guard block.kind == .codeBlock,
              !block.inlines.isEmpty
        else {
            return nil
        }

        let sourceRange = block.inlines.first?.sourceRange ?? block.sourceRange
        let selectionRuns = block.inlines.map { run in
            MarkdownInlineRun(
                kind: .text,
                text: run.text,
                sourceRange: run.sourceRange,
                destination: run.destination,
                imageSource: run.imageSource
            )
        }
        return preparedInline(for: selectionRuns, sourceRange: sourceRange, block: block)
    }

    private func inlineCacheNamespace(
        for runs: [MarkdownInlineRun],
        metrics: (fontSize: Double, lineHeight: Double, fontProfiles: MarkdownInlineFontProfiles),
        imageDecisions: [MarkdownPreparedImageDecision],
        mathDecisions: [MarkdownPreparedMathDecision]
    ) -> String? {
        var components = [
            "inline-prepared:v2",
            "fontSize=\(metrics.fontSize)",
            "lineHeight=\(metrics.lineHeight)",
            "fontProfiles=\(metrics.fontProfiles.cacheKey)"
        ]

        if runs.contains(where: { $0.isLinkPresentation }) {
            guard let linkPolicyIdentity else {
                return nil
            }
            components.append("linkPolicy=\(linkPolicyIdentity)")
        }

        if !imageDecisions.isEmpty {
            guard let imagePolicyIdentity else {
                return nil
            }
            components.append("imagePolicy=\(imagePolicyIdentity)")
            if imageDecisions.contains(where: { decision in
                if case .allow = decision.policyDecision {
                    return true
                }
                return false
            }) {
                guard let imageResolverIdentity else {
                    return nil
                }
                components.append("imageResolver=\(imageResolverIdentity)")
            }
        }

        if runs.contains(where: { $0.isMathPresentation }) {
            guard let mathPolicyIdentity else {
                return nil
            }
            components.append("mathPolicy=\(mathPolicyIdentity)")
            if mathDecisions.contains(where: { decision in
                if case .allow = decision.policyDecision {
                    return true
                }
                return false
            }) {
                guard let mathRendererIdentity else {
                    return nil
                }
                components.append("mathRenderer=\(mathRendererIdentity)")
            }
        }

        return components.joined(separator: ":")
    }

    private func preparedImageDecisions(for runs: [MarkdownInlineRun]) -> [MarkdownPreparedImageDecision] {
        runs.compactMap { run in
            guard run.isImagePresentation,
                  let source = run.resolvedImageSource
            else {
                return nil
            }

            return MarkdownPreparedImageDecision(
                run: run,
                source: source,
                policyDecision: imagePolicy.evaluateImage(source: source, altText: run.text)
            )
        }
    }

    private func preparedMathDecisions(for runs: [MarkdownInlineRun]) -> [MarkdownPreparedMathDecision] {
        runs.compactMap { run in
            guard run.isMathPresentation else {
                return nil
            }

            return MarkdownPreparedMathDecision(
                run: run,
                policyDecision: mathPolicy.evaluateMath(run.text, isBlock: false)
            )
        }
    }

    private func preparedInlinePayload(
        for runs: [MarkdownInlineRun],
        images: [MarkdownPreparedImage],
        mathDecisions: [MarkdownPreparedMathDecision],
        fontSize: Double
    ) -> (runs: [MarkdownInlineRun], attributed: AttributedString, mathPieces: [MarkdownInlineMathPiece]?) {
        var displayRuns: [MarkdownInlineRun] = []
        var attributed = AttributedString()
        var pieces: [MarkdownInlineMathPiece] = []
        var pendingText = AttributedString()
        var producedMathImage = false
        var mathDecisionIndex = 0

        func flushPendingText() {
            guard !pendingText.characters.isEmpty else {
                return
            }
            pieces.append(.text(pendingText))
            pendingText = AttributedString()
        }

        for run in runs {
            if run.isImagePresentation {
                let displayRun = preparedImageDisplayRun(for: run, images: images)
                displayRuns.append(displayRun)
                let piece = InlineRunsView.attributedString(
                    for: [displayRun],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
                continue
            }

            guard run.isMathPresentation else {
                displayRuns.append(run)
                let piece = InlineRunsView.attributedString(
                    for: [run],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
                continue
            }

            let mathDecision = mathDecisions[mathDecisionIndex]
            mathDecisionIndex += 1

            switch mathDecision.policyDecision {
            case .allow:
                diagnosticsRecorder.recordMathRender()
                let preparedMath = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
                    mathRenderer.preparedMath(run.text, isBlock: false, fontSize: fontSize)
                }

                switch preparedMath {
                case let .image(image):
                    producedMathImage = true
                    flushPendingText()
                    pieces.append(.math(image))
                    let fallback = mathAttributedString(
                        AttributedString(image.latex),
                        preservingLinkFrom: run
                    )
                    attributed.append(fallback)
                    let fallbackText = String(fallback.characters)
                    displayRuns.append(
                        MarkdownInlineRun(
                            kind: run.kind,
                            text: fallbackText.isEmpty ? run.text : fallbackText,
                            sourceRange: run.sourceRange,
                            destination: run.destination,
                            imageSource: run.imageSource,
                            presentation: run.presentation
                        )
                    )
                case let .text(renderedMath):
                    let rendered = mathAttributedString(renderedMath, preservingLinkFrom: run)
                    attributed.append(rendered)
                    pendingText.append(rendered)
                    let renderedText = String(rendered.characters)
                    displayRuns.append(
                        MarkdownInlineRun(
                            kind: run.kind,
                            text: renderedText.isEmpty ? run.text : renderedText,
                            sourceRange: run.sourceRange,
                            destination: run.destination,
                            imageSource: run.imageSource,
                            presentation: run.presentation
                        )
                    )
                }
            case .deny:
                displayRuns.append(run)
                let piece = InlineRunsView.attributedString(
                    for: [run],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
            }
        }

        flushPendingText()
        return (displayRuns, attributed, producedMathImage ? pieces : nil)
    }

    private func mathAttributedString(
        _ rendered: AttributedString,
        preservingLinkFrom run: MarkdownInlineRun
    ) -> AttributedString {
        guard run.kind == .link,
              let destination = run.destination,
              let url = markdownLinkURL(for: destination, policy: linkPolicy)
        else {
            return rendered
        }

        var copy = rendered
        copy.link = url
        return copy
    }

    private func preparedImageDisplayRun(
        for run: MarkdownInlineRun,
        images: [MarkdownPreparedImage]
    ) -> MarkdownInlineRun {
        guard let image = images.first(where: { preparedImage in
            preparedImage.source == run.resolvedImageSource &&
                preparedImage.sourceRange == run.sourceRange
        }) else {
            return run
        }

        var copy = run
        copy.text = imageDisplayText(for: image)
        copy.imageSource = nil
        if copy.kind == .image {
            copy.destination = nil
        }
        return copy
    }

    private func imageDisplayText(for image: MarkdownPreparedImage) -> String {
        if let altText = image.altText, !altText.isEmpty {
            return altText
        }

        switch image.preparedSource {
        case let .placeholder(reason):
            return "[image: \(reason)]"
        case let .localFile(path):
            return path
        case .data:
            return "[image]"
        case let .remote(url):
            return url.absoluteString
        }
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

    private func preparedImages(from decisions: [MarkdownPreparedImageDecision]) -> [MarkdownPreparedImage] {
        decisions.map { imageDecision in
            switch imageDecision.policyDecision {
            case .allow:
                return imageResolver.preparedImage(
                    source: imageDecision.source,
                    altText: imageDecision.run.text.isEmpty ? nil : imageDecision.run.text,
                    sourceRange: imageDecision.run.sourceRange,
                    policyDecision: imageDecision.policyDecision
                )
            case let .deny(reason):
                return MarkdownPreparedImage(
                    source: imageDecision.source,
                    altText: imageDecision.run.text.isEmpty ? nil : imageDecision.run.text,
                    sourceRange: imageDecision.run.sourceRange,
                    preparedSource: .placeholder(reason: reason)
                )
            }
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
            let style = theme.headingStyle(for: block.headingLevel)
            return (style.fontSize, style.lineHeight, style.fontProfiles)
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
            hash = append(String(run.presentation.rawValue), to: hash)
            hash = append(run.text, to: hash)
            hash = append(run.destination ?? "", to: hash)
            hash = append(run.imageSource ?? "", to: hash)
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

private struct MarkdownPreparedImageDecision {
    var run: MarkdownInlineRun
    var source: String
    var policyDecision: MarkdownPolicyDecision
}

private struct MarkdownPreparedMathDecision {
    var run: MarkdownInlineRun
    var policyDecision: MarkdownPolicyDecision
}

private struct MarkdownPreparedSnapshotReuse {
    private var contentsByBlockID: [MarkdownBlockID: [(block: MarkdownBlock, content: MarkdownPreparedBlockContent)]]

    init(previousItems: ArraySlice<MarkdownPreparedSnapshotItem>) {
        var contentsByBlockID: [MarkdownBlockID: [(block: MarkdownBlock, content: MarkdownPreparedBlockContent)]] = [:]
        for item in previousItems {
            guard case let .block(block, content) = item else {
                continue
            }
            contentsByBlockID[block.id, default: []].append((block, content))
        }
        self.contentsByBlockID = contentsByBlockID
    }

    mutating func content(for block: MarkdownBlock) -> MarkdownPreparedBlockContent? {
        guard var candidates = contentsByBlockID[block.id],
              let index = candidates.firstIndex(where: { $0.block == block })
        else {
            return nil
        }

        let match = candidates.remove(at: index)
        if candidates.isEmpty {
            contentsByBlockID.removeValue(forKey: block.id)
        } else {
            contentsByBlockID[block.id] = candidates
        }
        return match.content
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
    /// When non-nil, this inline content contains typeset math and should be
    /// rendered with native `Text` composition instead of prepared CoreText lines.
    public var mathTextPieces: [MarkdownInlineMathPiece]?

    public init(
        attributed: AttributedString,
        prepared: PreparedInlineContent,
        measured: MeasuredInlineContent,
        images: [MarkdownPreparedImage] = [],
        fontSize: Double,
        lineHeight: Double,
        fontProfiles: MarkdownInlineFontProfiles = .paragraphDefault,
        layoutCache: MarkdownInlineLayoutCache = MarkdownInlineLayoutCache(),
        mathTextPieces: [MarkdownInlineMathPiece]? = nil
    ) {
        self.attributed = attributed
        self.prepared = prepared
        self.measured = measured
        self.images = images
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontProfiles = fontProfiles
        self.layoutCache = layoutCache
        self.mathTextPieces = mathTextPieces
    }

    public func layout(
        containerWidth: Double,
        allowsOverwideFallback: Bool = true
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
        allowsOverwideFallback: Bool = true
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
    private var selectionLineFragmentCache: BoundedMarkdownCache<[MarkdownDocumentSelectionLineFragmentTemplate]>

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
        self.selectionLineFragmentCache = BoundedMarkdownCache(capacity: cacheCapacity)
    }

    public var diagnosticsCounters: MarkdownDiagnosticsCounters {
        lock.withLock {
            engine.diagnosticsCounters
        }
    }

    public func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = true
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

    func recordSelectionPreferenceBodyEvaluation() {
        lock.withLock {
            engine.diagnosticsRecorder.recordSelectionPreferenceBodyEvaluation()
        }
    }

    func recordSelectionFrameQuery() {
        lock.withLock {
            engine.diagnosticsRecorder.recordSelectionFrameQuery()
        }
    }

    func selectionLineFragmentTemplates(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        idPrefix: String
    ) -> [MarkdownDocumentSelectionLineFragmentTemplate] {
        let key = selectionLineFragmentCacheKey(
            blockID: blockID,
            prepared: prepared,
            layout: layout,
            idPrefix: idPrefix
        )
        return lock.withLock {
            if let cached = selectionLineFragmentCache.value(forKey: key) {
                engine.diagnosticsRecorder.recordSelectionLineFragmentCacheHit()
                return cached
            }

            engine.diagnosticsRecorder.recordSelectionLineFragmentCacheMiss()
            let templates = MarkdownDocumentSelectionFragment.makeInlineLineFragmentTemplates(
                blockID: blockID,
                prepared: prepared,
                layout: layout,
                idPrefix: idPrefix,
                diagnosticsRecorder: engine.diagnosticsRecorder
            )
            if !templates.isEmpty {
                selectionLineFragmentCache[key] = templates
            }
            return templates
        }
    }

    private func selectionLineFragmentCacheKey(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        idPrefix: String
    ) -> MarkdownCacheKey {
        var hasher = Hasher()
        hasher.combine(blockID)
        hasher.combine(idPrefix)
        hasher.combine(prepared.prepared.sourceRange)
        hasher.combine(prepared.prepared.naturalText)
        hasher.combine(prepared.prepared.runs)
        hasher.combine(prepared.fontSize)
        hasher.combine(prepared.lineHeight)
        hasher.combine(prepared.fontProfiles)
        hasher.combine(layout.lines)
        hasher.combine(layout.naturalWidth)
        hasher.combine(layout.height)
        let fingerprint = UInt64(bitPattern: Int64(hasher.finalize()))
        let sourceRange = prepared.prepared.sourceRange ?? MarkdownSourceRange(
            byteRange: 0..<prepared.prepared.naturalText.utf8.count,
            lineRange: 0..<0
        )
        return MarkdownCacheKey(
            sourceRange: sourceRange,
            contentHash: fingerprint,
            namespace: "selection-line-fragments"
        )
    }
}

public final class MarkdownRenderPreparationCache: @unchecked Sendable {
    private let lock = NSLock()
    private var inlineCache: BoundedMarkdownCache<MarkdownPreparedInlineContent>
    private var codeCache: BoundedMarkdownCache<AttributedString>
    private var mermaidCache: BoundedMarkdownCache<MarkdownPreparedMermaidDiagram>
    private var mathCache: BoundedMarkdownCache<MarkdownPreparedMath>

    public init(capacity: Int = 256) {
        self.inlineCache = BoundedMarkdownCache(capacity: capacity)
        self.codeCache = BoundedMarkdownCache(capacity: capacity)
        self.mermaidCache = BoundedMarkdownCache(capacity: capacity)
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

    public func mermaid(forKey key: MarkdownCacheKey) -> MarkdownPreparedMermaidDiagram? {
        lock.withLock {
            mermaidCache.value(forKey: key)
        }
    }

    public func insertMermaid(_ mermaid: MarkdownPreparedMermaidDiagram, forKey key: MarkdownCacheKey) {
        lock.withLock {
            mermaidCache[key] = mermaid
        }
    }

    public func math(forKey key: MarkdownCacheKey) -> MarkdownPreparedMath? {
        lock.withLock {
            mathCache.value(forKey: key)
        }
    }

    public func insertMath(_ math: MarkdownPreparedMath, forKey key: MarkdownCacheKey) {
        lock.withLock {
            mathCache[key] = math
        }
    }

    public func removeAll() {
        lock.withLock {
            inlineCache.removeAll()
            codeCache.removeAll()
            mermaidCache.removeAll()
            mathCache.removeAll()
        }
    }
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

    var isMathPresentation: Bool {
        kind == .math || presentation.contains(.math)
    }
}

public struct MarkdownPreparedSnapshot: Sendable {
    public var snapshot: MarkdownSnapshot
    public var items: [MarkdownPreparedSnapshotItem]
    public var renderItems: [MarkdownPreparedSnapshotRenderItem]
    public var itemIDs: [String]
    public var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]

    public init(
        snapshot: MarkdownSnapshot,
        items: [MarkdownPreparedSnapshotItem],
        renderItems: [MarkdownPreparedSnapshotRenderItem]? = nil,
        preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]
    ) {
        self.snapshot = snapshot
        self.items = items
        let resolvedRenderItems = renderItems ?? items.enumerated().map { index, item in
            MarkdownPreparedSnapshotRenderItem(id: item.id, itemIndex: index)
        }
        self.renderItems = resolvedRenderItems
        self.itemIDs = resolvedRenderItems.map(\.id)
        self.preparedContentByBlockID = preparedContentByBlockID
    }

    public subscript(blockID: MarkdownBlockID) -> MarkdownPreparedBlockContent? {
        preparedContentByBlockID[blockID]
    }

    public func item(at index: Int) -> MarkdownPreparedSnapshotItem? {
        guard items.indices.contains(index) else {
            return nil
        }
        return items[index]
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

public struct MarkdownPreparedSnapshotRenderItem: Identifiable, Sendable, Hashable {
    public var id: String
    public var itemIndex: Int

    public init(id: String, itemIndex: Int) {
        self.id = id
        self.itemIndex = itemIndex
    }
}

public struct MarkdownPreparedBlockContent: Sendable {
    public var blockID: MarkdownBlockID
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var selectionInlineLayout: MarkdownPreparedInlineContent?
    public var listItems: [MarkdownPreparedListItem]
    public var table: MarkdownPreparedTableBlock?
    public var mermaid: MarkdownPreparedMermaidDiagram?
    public var code: AttributedString?
    public var math: AttributedString?
    public var mathRender: MarkdownPreparedMath?
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        blockID: MarkdownBlockID,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        selectionInlineLayout: MarkdownPreparedInlineContent? = nil,
        listItems: [MarkdownPreparedListItem] = [],
        table: MarkdownPreparedTableBlock? = nil,
        mermaid: MarkdownPreparedMermaidDiagram? = nil,
        code: AttributedString? = nil,
        math: AttributedString? = nil,
        mathRender: MarkdownPreparedMath? = nil,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.blockID = blockID
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.selectionInlineLayout = selectionInlineLayout
        self.listItems = listItems
        self.table = table
        self.mermaid = mermaid
        self.code = code
        self.math = math
        self.mathRender = mathRender
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
    public var mermaidRendered: Bool
    public var mermaidControlsVisible: Bool
    public var mermaidZoomControlsVisible: Bool
    public var mermaidFitButtonVisible: Bool
    public var mermaidResetButtonVisible: Bool
    public var mermaidHasGeometry: Bool
    public var codeLanguageLabel: String?
    public var codeCopyButtonVisible: Bool
    public var codeExportButtonVisible: Bool
    public var codeCollapseButtonVisible: Bool
    public var codeInitiallyCollapsed: Bool
    public var mathAllowed: Bool?
    public var mathRendered: Bool
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        kind: MarkdownBlockKind,
        listItemCount: Int = 0,
        tableColumnCount: Int = 0,
        tableBodyRowCount: Int = 0,
        codeAllowed: Bool? = nil,
        mermaidRendered: Bool = false,
        mermaidControlsVisible: Bool = false,
        mermaidZoomControlsVisible: Bool = false,
        mermaidFitButtonVisible: Bool = false,
        mermaidResetButtonVisible: Bool = false,
        mermaidHasGeometry: Bool = false,
        codeLanguageLabel: String? = nil,
        codeCopyButtonVisible: Bool = false,
        codeExportButtonVisible: Bool = false,
        codeCollapseButtonVisible: Bool = false,
        codeInitiallyCollapsed: Bool = false,
        mathAllowed: Bool? = nil,
        mathRendered: Bool = false,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.kind = kind
        self.listItemCount = listItemCount
        self.tableColumnCount = tableColumnCount
        self.tableBodyRowCount = tableBodyRowCount
        self.codeAllowed = codeAllowed
        self.mermaidRendered = mermaidRendered
        self.mermaidControlsVisible = mermaidControlsVisible
        self.mermaidZoomControlsVisible = mermaidZoomControlsVisible
        self.mermaidFitButtonVisible = mermaidFitButtonVisible
        self.mermaidResetButtonVisible = mermaidResetButtonVisible
        self.mermaidHasGeometry = mermaidHasGeometry
        self.codeLanguageLabel = codeLanguageLabel
        self.codeCopyButtonVisible = codeCopyButtonVisible
        self.codeExportButtonVisible = codeExportButtonVisible
        self.codeCollapseButtonVisible = codeCollapseButtonVisible
        self.codeInitiallyCollapsed = codeInitiallyCollapsed
        self.mathAllowed = mathAllowed
        self.mathRendered = mathRendered
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
    }
}
