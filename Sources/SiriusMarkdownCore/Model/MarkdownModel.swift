import Foundation

public struct MarkdownBlockID: Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct MarkdownHostBoundaryID: Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct MarkdownHostBoundary: Identifiable, Sendable, Hashable {
    public var id: MarkdownHostBoundaryID
    public var sourceOffset: Int

    public init(id: MarkdownHostBoundaryID, sourceOffset: Int) {
        self.id = id
        self.sourceOffset = sourceOffset
    }
}

public struct MarkdownSourceRange: Sendable, Hashable {
    public var byteRange: Range<Int>
    public var lineRange: Range<Int>

    public init(byteRange: Range<Int>, lineRange: Range<Int>) {
        self.byteRange = byteRange
        self.lineRange = lineRange
    }
}

public enum MarkdownBlockKind: String, Sendable, Hashable, Codable {
    case paragraph
    case heading
    case unorderedList
    case orderedList
    case taskList
    case blockQuote
    case codeBlock
    case table
    case thematicBreak
    case mathBlock
    case htmlBlock
    case blank
}

public enum MarkdownInlineKind: String, Sendable, Hashable, Codable {
    case text
    case emphasis
    case strong
    case strikethrough
    case code
    case link
    case image
    case softBreak
    case hardBreak
    case math
}

public struct MarkdownInlinePresentation: OptionSet, Sendable, Hashable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let emphasis = MarkdownInlinePresentation(rawValue: 1 << 0)
    public static let strong = MarkdownInlinePresentation(rawValue: 1 << 1)
    public static let strikethrough = MarkdownInlinePresentation(rawValue: 1 << 2)
    public static let code = MarkdownInlinePresentation(rawValue: 1 << 3)
    public static let math = MarkdownInlinePresentation(rawValue: 1 << 4)
    public static let image = MarkdownInlinePresentation(rawValue: 1 << 5)
    public static let html = MarkdownInlinePresentation(rawValue: 1 << 6)
    public static let subscriptText = MarkdownInlinePresentation(rawValue: 1 << 7)
    public static let superscriptText = MarkdownInlinePresentation(rawValue: 1 << 8)
    public static let linkDecoration = MarkdownInlinePresentation(rawValue: 1 << 9)

    public static func defaultPresentation(for kind: MarkdownInlineKind) -> MarkdownInlinePresentation {
        switch kind {
        case .emphasis:
            return .emphasis
        case .strong:
            return .strong
        case .strikethrough:
            return .strikethrough
        case .code:
            return .code
        case .math:
            return .math
        case .image:
            return .image
        default:
            return []
        }
    }
}

public enum MarkdownTaskState: String, Sendable, Hashable, Codable {
    case checked
    case unchecked
}

public enum MarkdownTableColumnAlignment: String, Sendable, Hashable, Codable {
    case left
    case center
    case right
}

public struct MarkdownInlineRun: Sendable, Hashable {
    public var kind: MarkdownInlineKind
    public var text: String
    public var sourceRange: MarkdownSourceRange?
    public var destination: String?
    public var imageSource: String?
    public var presentation: MarkdownInlinePresentation
    /// Reserved box metrics for an allowed image/attachment run (Inline
    /// Attachments Part 01). When non-nil, prepare has already replaced
    /// `text` with a single atomic placeholder character and layout must
    /// use `pointWidth`/`pointHeight`/`ascent`/`descent` instead of
    /// measuring `text`. Denied images never set this field — they keep
    /// today's alt/`[image: reason]` text-atomic path.
    public var attachmentMetrics: MarkdownInlineAttachmentMetrics?

    public init(
        kind: MarkdownInlineKind,
        text: String,
        sourceRange: MarkdownSourceRange? = nil,
        destination: String? = nil,
        imageSource: String? = nil,
        presentation: MarkdownInlinePresentation? = nil,
        attachmentMetrics: MarkdownInlineAttachmentMetrics? = nil
    ) {
        self.kind = kind
        self.text = text
        self.sourceRange = sourceRange
        self.destination = destination
        self.imageSource = imageSource
        self.presentation = presentation ?? MarkdownInlinePresentation.defaultPresentation(for: kind)
        self.attachmentMetrics = attachmentMetrics
    }
}

public struct MarkdownListItem: Sendable, Hashable {
    public var sourceRange: MarkdownSourceRange
    public var taskState: MarkdownTaskState?
    public var text: String
    public var inlines: [MarkdownInlineRun]
    public var childListKind: MarkdownBlockKind?
    public var childOrderedListStart: UInt?
    public var childItems: [MarkdownListItem]

    public init(
        sourceRange: MarkdownSourceRange,
        taskState: MarkdownTaskState? = nil,
        text: String,
        inlines: [MarkdownInlineRun] = [],
        childListKind: MarkdownBlockKind? = nil,
        childOrderedListStart: UInt? = nil,
        childItems: [MarkdownListItem] = []
    ) {
        self.sourceRange = sourceRange
        self.taskState = taskState
        self.text = text
        self.inlines = inlines
        self.childListKind = childListKind
        self.childOrderedListStart = childOrderedListStart
        self.childItems = childItems
    }
}

public struct MarkdownTableCell: Sendable, Hashable {
    public var sourceRange: MarkdownSourceRange
    public var text: String
    public var inlines: [MarkdownInlineRun]
    /// Deterministic hash of the source slice that produced this cell.
    ///
    /// Table cell identity is anchored at its stable source start while this
    /// value tracks append-only content growth. Render preparation can
    /// therefore distinguish an unchanged historical cell from the one
    /// mutable streaming cell without hashing its runs again.
    public var contentHash: UInt64
    public var colspan: UInt
    public var rowspan: UInt

    public init(
        sourceRange: MarkdownSourceRange,
        text: String,
        inlines: [MarkdownInlineRun] = [],
        contentHash: UInt64 = 0,
        colspan: UInt = 1,
        rowspan: UInt = 1
    ) {
        self.sourceRange = sourceRange
        self.text = text
        self.inlines = inlines
        self.contentHash = contentHash
        self.colspan = colspan
        self.rowspan = rowspan
    }
}

public struct MarkdownTableBlock: Sendable, Hashable {
    public var columnAlignments: [MarkdownTableColumnAlignment?]
    public var header: [MarkdownTableCell] {
        didSet { refreshSpanSummary() }
    }
    public var rows: [[MarkdownTableCell]] {
        didSet { refreshSpanSummary() }
    }
    /// True when any semantic cell spans more than one logical row or column.
    /// Parsers compute this once so ordinary streaming GFM tables can retain
    /// their allocation-free preparation fast path.
    public private(set) var hasSpans: Bool

    public init(
        columnAlignments: [MarkdownTableColumnAlignment?],
        header: [MarkdownTableCell],
        rows: [[MarkdownTableCell]]
    ) {
        self.columnAlignments = columnAlignments
        self.header = header
        self.rows = rows
        self.hasSpans = Self.containsSpans(header: header, rows: rows)
    }

    private static func containsSpans(
        header: [MarkdownTableCell],
        rows: [[MarkdownTableCell]]
    ) -> Bool {
        header.contains { $0.colspan > 1 || $0.rowspan > 1 } ||
            rows.contains { row in
                row.contains { $0.colspan > 1 || $0.rowspan > 1 }
            }
    }

    private mutating func refreshSpanSummary() {
        hasSpans = Self.containsSpans(header: header, rows: rows)
    }
}

public struct MarkdownBlock: Identifiable, Sendable, Hashable {
    public var id: MarkdownBlockID
    public var kind: MarkdownBlockKind
    public var sourceRange: MarkdownSourceRange
    public var text: String
    public var inlines: [MarkdownInlineRun]
    public var listItems: [MarkdownListItem]
    public var table: MarkdownTableBlock?
    public var contentHash: UInt64
    public var orderedListStart: UInt?
    public var headingLevel: Int?
    public var infoString: String?
    public var isSealed: Bool
    /// Sanitized native semantic content converted from an authorized HTML
    /// block. The outer `.htmlBlock` retains the exact Markdown source range
    /// and stable identity; child blocks reuse the normal renderer pipeline.
    public var richContent: MarkdownRichContent?

    public init(
        id: MarkdownBlockID,
        kind: MarkdownBlockKind,
        sourceRange: MarkdownSourceRange,
        text: String,
        inlines: [MarkdownInlineRun] = [],
        listItems: [MarkdownListItem] = [],
        table: MarkdownTableBlock? = nil,
        contentHash: UInt64 = 0,
        orderedListStart: UInt? = nil,
        headingLevel: Int? = nil,
        infoString: String? = nil,
        isSealed: Bool,
        richContent: MarkdownRichContent? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceRange = sourceRange
        self.text = text
        self.inlines = inlines
        self.listItems = listItems
        self.table = table
        self.contentHash = contentHash
        self.orderedListStart = orderedListStart
        self.headingLevel = headingLevel
        self.infoString = infoString
        self.isSealed = isSealed
        self.richContent = richContent
    }

    public init(
        id: MarkdownBlockID,
        kind: MarkdownBlockKind,
        sourceRange: MarkdownSourceRange,
        text: String,
        inlines: [MarkdownInlineRun] = [],
        headingLevel: Int? = nil,
        infoString: String? = nil,
        isSealed: Bool,
        richContent: MarkdownRichContent? = nil
    ) {
        self.init(
            id: id,
            kind: kind,
            sourceRange: sourceRange,
            text: text,
            inlines: inlines,
            listItems: [],
            table: nil,
            contentHash: 0,
            orderedListStart: nil,
            headingLevel: headingLevel,
            infoString: infoString,
            isSealed: isSealed,
            richContent: richContent
        )
    }
}

public struct MarkdownRichContentDiagnostics: Sendable, Hashable {
    public var parsedNodeCount: Int
    public var droppedNodeCount: Int
    public var unwrappedNodeCount: Int
    public var sourceMappingFallbackCount: Int

    public init(
        parsedNodeCount: Int = 0,
        droppedNodeCount: Int = 0,
        unwrappedNodeCount: Int = 0,
        sourceMappingFallbackCount: Int = 0
    ) {
        self.parsedNodeCount = parsedNodeCount
        self.droppedNodeCount = droppedNodeCount
        self.unwrappedNodeCount = unwrappedNodeCount
        self.sourceMappingFallbackCount = sourceMappingFallbackCount
    }
}

/// Sanitized HTML represented entirely through the package's normal native
/// Markdown block/run models. SwiftSoup nodes never cross this value boundary.
public struct MarkdownRichContent: Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var diagnostics: MarkdownRichContentDiagnostics

    public init(
        blocks: [MarkdownBlock],
        diagnostics: MarkdownRichContentDiagnostics = MarkdownRichContentDiagnostics()
    ) {
        self.blocks = blocks
        self.diagnostics = diagnostics
    }
}

public enum MarkdownSnapshotItem: Identifiable, Sendable, Hashable {
    case block(MarkdownBlock)
    case hostBoundary(MarkdownHostBoundary)

    public var id: String {
        switch self {
        case let .block(block):
            return "block:\(block.id.rawValue)"
        case let .hostBoundary(boundary):
            return "host:\(boundary.id.rawValue)"
        }
    }
}

public struct MarkdownSnapshot: Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var items: [MarkdownSnapshotItem]
    public var sourceLength: Int
    public var generation: Int
    public var isFinished: Bool

    public init(
        blocks: [MarkdownBlock],
        items: [MarkdownSnapshotItem]? = nil,
        sourceLength: Int,
        generation: Int,
        isFinished: Bool
    ) {
        self.blocks = blocks
        self.items = items ?? blocks.map { .block($0) }
        self.sourceLength = sourceLength
        self.generation = generation
        self.isFinished = isFinished
    }
}
