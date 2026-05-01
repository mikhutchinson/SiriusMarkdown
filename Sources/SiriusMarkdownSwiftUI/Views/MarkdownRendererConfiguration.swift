import SiriusMarkdownCore
import SwiftUI

public protocol MarkdownCodeHighlighter: Sendable {
    func highlightedCode(_ code: String, infoString: String?) -> AttributedString
}

public protocol MarkdownMathRenderer: Sendable {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString
}

public struct PlainMarkdownCodeHighlighter: MarkdownCodeHighlighter {
    public init() {}

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

public struct MarkdownRendererConfiguration: Sendable {
    public var theme: MarkdownTheme
    public var linkAction: MarkdownLinkAction?
    public var copyProvider: MarkdownCopyProvider?
    public var linkPolicy: any MarkdownLinkPolicy
    public var imagePolicy: any MarkdownImagePolicy
    public var htmlPolicy: any MarkdownHTMLPolicy
    public var codePolicy: any MarkdownCodePolicy
    public var mathPolicy: any MarkdownMathPolicy
    public var codeHighlighter: any MarkdownCodeHighlighter
    public var mathRenderer: any MarkdownMathRenderer
    public var preparationCache: MarkdownRenderPreparationCache
    public var diagnosticsRecorder: MarkdownDiagnosticsRecorder

    public init(
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = PlainMarkdownCodeHighlighter(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.imagePolicy = imagePolicy
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mathRenderer = mathRenderer
        self.preparationCache = preparationCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public static let compactChat = MarkdownRendererConfiguration(theme: .compactChat)
    public static let document = MarkdownRendererConfiguration(theme: .document)

    public func prepare(block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        diagnosticsRecorder.recordRenderPreparation()

        switch block.kind {
        case .codeBlock:
            let code = Self.codeText(for: block)
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: code) {
            case .allow:
                let key = Self.cacheKey(for: block, namespace: "highlighted-code:\(block.infoString ?? "")")
                if let cached = preparationCache.code(forKey: key) {
                    return MarkdownPreparedBlockContent(blockID: block.id, code: cached)
                }

                diagnosticsRecorder.recordCodeHighlight()
                let highlighted = MarkdownDiagnostics().signpost("CodeHighlight", category: "RenderPreparation") {
                    codeHighlighter.highlightedCode(code, infoString: block.infoString)
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
                    return MarkdownPreparedBlockContent(blockID: block.id, math: cached)
                }

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
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: preparedInline(for: block.inlines, sourceRange: block.sourceRange),
                listItems: preparedListItems(block.listItems)
            )
        case .table:
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: preparedInline(for: block.inlines, sourceRange: block.sourceRange),
                table: block.table.map(preparedTable)
            )
        default:
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: preparedInline(for: block.inlines, sourceRange: block.sourceRange)
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

    private func preparedInline(
        for runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange
    ) -> AttributedString? {
        guard !runs.isEmpty else {
            return nil
        }

        let key = MarkdownCacheKey(
            sourceRange: sourceRange,
            contentHash: Self.inlineHash(runs),
            namespace: "inline-attributed"
        )
        if let cached = preparationCache.inline(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        diagnosticsRecorder.recordCacheMiss()
        let attributed = InlineRunsView.attributedString(
            for: runs,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
        preparationCache.insertInline(attributed, forKey: key)
        return attributed
    }

    private func preparedListItems(_ items: [MarkdownListItem]) -> [MarkdownPreparedListItem] {
        items.map { item in
            MarkdownPreparedListItem(
                sourceRange: item.sourceRange,
                taskState: item.taskState,
                inline: preparedInline(for: item.inlines, sourceRange: item.sourceRange),
                childItems: preparedListItems(item.childItems)
            )
        }
    }

    private func preparedTable(_ table: MarkdownTableBlock) -> MarkdownPreparedTableBlock {
        MarkdownPreparedTableBlock(
            columnAlignments: table.columnAlignments,
            header: table.header.map(preparedTableCell),
            rows: table.rows.map { row in
                row.map(preparedTableCell)
            }
        )
    }

    private func preparedTableCell(_ cell: MarkdownTableCell) -> MarkdownPreparedTableCell {
        MarkdownPreparedTableCell(
            sourceRange: cell.sourceRange,
            inline: preparedInline(for: cell.inlines, sourceRange: cell.sourceRange),
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
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

public final class MarkdownRenderPreparationCache: @unchecked Sendable {
    private let lock = NSLock()
    private var inlineCache: BoundedMarkdownCache<AttributedString>
    private var codeCache: BoundedMarkdownCache<AttributedString>
    private var mathCache: BoundedMarkdownCache<AttributedString>

    public init(capacity: Int = 256) {
        self.inlineCache = BoundedMarkdownCache(capacity: capacity)
        self.codeCache = BoundedMarkdownCache(capacity: capacity)
        self.mathCache = BoundedMarkdownCache(capacity: capacity)
    }

    public func inline(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            inlineCache[key]
        }
    }

    public func insertInline(_ inline: AttributedString, forKey key: MarkdownCacheKey) {
        lock.withLock {
            inlineCache[key] = inline
        }
    }

    public func code(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            codeCache[key]
        }
    }

    public func insertCode(_ code: AttributedString, forKey key: MarkdownCacheKey) {
        lock.withLock {
            codeCache[key] = code
        }
    }

    public func math(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            mathCache[key]
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
    public var listItems: [MarkdownPreparedListItem]
    public var table: MarkdownPreparedTableBlock?
    public var code: AttributedString?
    public var math: AttributedString?
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        blockID: MarkdownBlockID,
        inline: AttributedString? = nil,
        listItems: [MarkdownPreparedListItem] = [],
        table: MarkdownPreparedTableBlock? = nil,
        code: AttributedString? = nil,
        math: AttributedString? = nil,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.blockID = blockID
        self.inline = inline
        self.listItems = listItems
        self.table = table
        self.code = code
        self.math = math
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
    }
}

public struct MarkdownPreparedListItem: Sendable {
    public var sourceRange: MarkdownSourceRange
    public var taskState: MarkdownTaskState?
    public var inline: AttributedString?
    public var childItems: [MarkdownPreparedListItem]

    public init(
        sourceRange: MarkdownSourceRange,
        taskState: MarkdownTaskState? = nil,
        inline: AttributedString? = nil,
        childItems: [MarkdownPreparedListItem] = []
    ) {
        self.sourceRange = sourceRange
        self.taskState = taskState
        self.inline = inline
        self.childItems = childItems
    }
}

public struct MarkdownPreparedTableCell: Sendable {
    public var sourceRange: MarkdownSourceRange
    public var inline: AttributedString?
    public var colspan: UInt
    public var rowspan: UInt

    public init(
        sourceRange: MarkdownSourceRange,
        inline: AttributedString? = nil,
        colspan: UInt = 1,
        rowspan: UInt = 1
    ) {
        self.sourceRange = sourceRange
        self.inline = inline
        self.colspan = colspan
        self.rowspan = rowspan
    }
}

public struct MarkdownPreparedTableBlock: Sendable {
    public var columnAlignments: [MarkdownTableColumnAlignment?]
    public var header: [MarkdownPreparedTableCell]
    public var rows: [[MarkdownPreparedTableCell]]

    public init(
        columnAlignments: [MarkdownTableColumnAlignment?],
        header: [MarkdownPreparedTableCell],
        rows: [[MarkdownPreparedTableCell]]
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
