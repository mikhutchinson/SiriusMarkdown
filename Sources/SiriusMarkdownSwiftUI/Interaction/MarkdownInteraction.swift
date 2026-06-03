import SiriusMarkdownCore
import SwiftUI

public struct MarkdownCopyPayload: Sendable, Hashable {
    public var markdown: String
    public var sourceRange: MarkdownSourceRange

    public init(markdown: String, sourceRange: MarkdownSourceRange) {
        self.markdown = markdown
        self.sourceRange = sourceRange
    }
}

public struct MarkdownLinkAction: Sendable {
    public var open: @Sendable (String) -> Void

    public init(open: @escaping @Sendable (String) -> Void) {
        self.open = open
    }
}

@MainActor
func markdownOpenURLAction(linkAction: MarkdownLinkAction?) -> OpenURLAction {
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

public struct MarkdownCopyProvider: Sendable {
    public var markdown: @Sendable (MarkdownSourceRange) -> String?
    public var documentMarkdown: (@Sendable () -> String?)?

    public init(
        markdown: @escaping @Sendable (MarkdownSourceRange) -> String?,
        documentMarkdown: (@Sendable () -> String?)? = nil
    ) {
        self.markdown = markdown
        self.documentMarkdown = documentMarkdown
    }

    public init(markdownSource: String) {
        let store = MarkdownSourceCopyStore(markdownSource)
        self.markdown = { range in
            store.markdown(in: range)
        }
        self.documentMarkdown = {
            store.markdown
        }
    }

    public var hasDocumentMarkdown: Bool {
        documentMarkdown != nil
    }

    public func markdownForDocument() -> String? {
        documentMarkdown?()
    }
}

public struct MarkdownExportPayload: Sendable, Hashable {
    public var markdown: String
    public var suggestedFilename: String

    public init(markdown: String, suggestedFilename: String = "Document.md") {
        self.markdown = markdown
        self.suggestedFilename = suggestedFilename
    }
}

public struct MarkdownAffordanceActionHandler: Sendable {
    public var copyString: @MainActor @Sendable (String) -> Void
    public var exportMarkdown: @MainActor @Sendable (MarkdownExportPayload) -> Void

    public init(
        copyString: @escaping @MainActor @Sendable (String) -> Void = { string in
            MarkdownPasteboard.copy(string)
        },
        exportMarkdown: @escaping @MainActor @Sendable (MarkdownExportPayload) -> Void = { payload in
            MarkdownDocumentExporter.export(payload)
        }
    ) {
        self.copyString = copyString
        self.exportMarkdown = exportMarkdown
    }

    public static var platformDefault: MarkdownAffordanceActionHandler {
        MarkdownAffordanceActionHandler()
    }
}

@MainActor
public final class MarkdownSelectionController: ObservableObject {
    @Published public private(set) var selectedBlockIDs: [MarkdownBlockID] = []
    @Published public private(set) var selectedSourceRanges: [MarkdownSourceRange] = []

    public var maximumSelectedBlockCount: Int
    private var blockOrder: [MarkdownBlockID] = []
    private var sourceRangeByBlockID: [MarkdownBlockID: MarkdownSourceRange] = [:]
    private var snapshotSourceLength: Int = 0

    public init(maximumSelectedBlockCount: Int = 512) {
        precondition(maximumSelectedBlockCount > 0)
        self.maximumSelectedBlockCount = maximumSelectedBlockCount
    }

    public func updateSnapshot(_ snapshot: MarkdownSnapshot) {
        blockOrder = snapshot.blocks.map(\.id)
        sourceRangeByBlockID = Dictionary(uniqueKeysWithValues: snapshot.blocks.map { ($0.id, $0.sourceRange) })
        snapshotSourceLength = snapshot.sourceLength
        let valid = Set(blockOrder)
        selectedBlockIDs.removeAll { !valid.contains($0) }
        selectedSourceRanges.removeAll {
            $0.byteRange.lowerBound < 0 ||
                $0.byteRange.upperBound > snapshot.sourceLength ||
                $0.byteRange.lowerBound > $0.byteRange.upperBound
        }
        if !selectedBlockIDs.isEmpty {
            let hadSingleContiguousRange = selectedSourceRanges.count == 1
            selectedSourceRanges = if hadSingleContiguousRange {
                combinedRange(for: selectedBlockIDs).map { [$0] } ?? []
            } else {
                orderedRanges(for: selectedBlockIDs)
            }
        }
        trimSelectionIfNeeded()
    }

    public func select(_ blockID: MarkdownBlockID, extending: Bool = false) {
        guard blockOrder.contains(blockID) else {
            return
        }

        if extending {
            if selectedBlockIDs.contains(blockID) {
                selectedBlockIDs.removeAll { $0 == blockID }
            } else {
                selectedBlockIDs.append(blockID)
            }
        } else {
            selectedBlockIDs = [blockID]
        }
        sortSelectionInDocumentOrder()
        selectedSourceRanges = orderedRanges(for: selectedBlockIDs)
        trimSelectionIfNeeded()
    }

    public func selectRange(from lowerBound: MarkdownBlockID, to upperBound: MarkdownBlockID) {
        guard let lowerIndex = blockOrder.firstIndex(of: lowerBound),
              let upperIndex = blockOrder.firstIndex(of: upperBound)
        else {
            return
        }

        let range = min(lowerIndex, upperIndex)...max(lowerIndex, upperIndex)
        selectedBlockIDs = Array(blockOrder[range])
        selectedSourceRanges = combinedRange(for: selectedBlockIDs).map { [$0] } ?? []
        trimSelectionIfNeeded()
    }

    public func selectSourceRanges(
        _ sourceRanges: [MarkdownSourceRange],
        selectedBlockIDs blockIDs: [MarkdownBlockID] = []
    ) {
        let valid = Set(blockOrder)
        selectedBlockIDs = blockIDs.filter { valid.contains($0) }
        sortSelectionInDocumentOrder()
        selectedSourceRanges = Self.orderedNonOverlappingRanges(sourceRanges)
        trimSelectionIfNeeded()
    }

    public func clearSelection() {
        selectedBlockIDs.removeAll()
        selectedSourceRanges.removeAll()
    }

    public func isSelected(_ blockID: MarkdownBlockID) -> Bool {
        selectedBlockIDs.contains(blockID)
    }

    public func selectSourceLine(
        _ line: Int,
        in snapshot: MarkdownSnapshot,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) {
        updateSnapshot(snapshot)
        guard let block = snapshot.block(containingSourceLine: line, policy: policy) else {
            return
        }

        // Block-level selection keeps byte and line ranges coherent without re-decoding source.
        select(block.id)
    }

    public func selectSourceRange(
        _ sourceRange: MarkdownSourceRange,
        in snapshot: MarkdownSnapshot,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) {
        updateSnapshot(snapshot)
        let overlappingBlockIDs = snapshot.blockIDs(overlappingSourceRange: sourceRange, policy: .exactOnly)
        if !overlappingBlockIDs.isEmpty {
            selectSourceRanges([sourceRange], selectedBlockIDs: overlappingBlockIDs)
            return
        }

        guard policy == .nearestRenderedBlock,
              let blockID = snapshot.firstBlockID(overlappingSourceRange: sourceRange, policy: policy),
              let block = snapshot.blocks.first(where: { $0.id == blockID })
        else {
            return
        }

        selectSourceRanges([block.sourceRange], selectedBlockIDs: [blockID])
    }

    public func selectSourceLine(
        _ line: Int,
        in preparedSnapshot: MarkdownPreparedSnapshot,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) {
        selectSourceLine(line, in: preparedSnapshot.snapshot, policy: policy)
    }

    public func selectSourceRange(
        _ sourceRange: MarkdownSourceRange,
        in preparedSnapshot: MarkdownPreparedSnapshot,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) {
        selectSourceRange(sourceRange, in: preparedSnapshot.snapshot, policy: policy)
    }

    public func selectedMarkdown(
        in preparedSnapshot: MarkdownPreparedSnapshot,
        copyProvider: MarkdownCopyProvider?
    ) -> String {
        guard let copyProvider else {
            return selectedPlainText(in: preparedSnapshot)
        }

        let ranges = effectiveSourceRanges(in: preparedSnapshot)
        guard !ranges.isEmpty else {
            return ""
        }

        var copied: [String] = []
        copied.reserveCapacity(ranges.count)
        for range in ranges {
            guard let markdown = copyProvider.markdown(range) else {
                return selectedPlainText(in: preparedSnapshot)
            }
            copied.append(markdown)
        }
        return copied.joined(separator: "\n")
    }

    public func selectedPlainText(in preparedSnapshot: MarkdownPreparedSnapshot) -> String {
        selectedBlocks(in: preparedSnapshot).map(Self.plainText(for:)).joined(separator: "\n")
    }

    public func copySelectedMarkdown(
        in preparedSnapshot: MarkdownPreparedSnapshot,
        copyProvider: MarkdownCopyProvider?
    ) {
        let markdown = selectedMarkdown(in: preparedSnapshot, copyProvider: copyProvider)
        guard !markdown.isEmpty else {
            return
        }

        MarkdownPasteboard.copy(markdown)
    }

    public func copySelectedPlainText(in preparedSnapshot: MarkdownPreparedSnapshot) {
        let plainText = selectedPlainText(in: preparedSnapshot)
        guard !plainText.isEmpty else {
            return
        }

        MarkdownPasteboard.copy(plainText)
    }

    private func selectedBlocks(in preparedSnapshot: MarkdownPreparedSnapshot) -> [MarkdownBlock] {
        let selected = Set(selectedBlockIDs)
        return preparedSnapshot.snapshot.blocks.filter { selected.contains($0.id) }
    }

    private func effectiveSourceRanges(in preparedSnapshot: MarkdownPreparedSnapshot) -> [MarkdownSourceRange] {
        if !selectedSourceRanges.isEmpty {
            return Self.orderedNonOverlappingRanges(selectedSourceRanges)
        }

        return Self.orderedNonOverlappingRanges(
            selectedBlocks(in: preparedSnapshot).map(\.sourceRange)
        )
    }

    private func sortSelectionInDocumentOrder() {
        let order = Dictionary(uniqueKeysWithValues: blockOrder.enumerated().map { ($0.element, $0.offset) })
        selectedBlockIDs.sort { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }
    }

    private func trimSelectionIfNeeded() {
        guard selectedBlockIDs.count > maximumSelectedBlockCount else {
            return
        }

        let hadSingleContiguousRange = selectedSourceRanges.count == 1
        selectedBlockIDs = Array(selectedBlockIDs.prefix(maximumSelectedBlockCount))
        selectedSourceRanges = if hadSingleContiguousRange {
            combinedRange(for: selectedBlockIDs).map { [$0] } ?? []
        } else {
            orderedRanges(for: selectedBlockIDs)
        }
    }

    private func orderedRanges(for blockIDs: [MarkdownBlockID]) -> [MarkdownSourceRange] {
        Self.orderedNonOverlappingRanges(blockIDs.compactMap { sourceRangeByBlockID[$0] })
    }

    private func combinedRange(for blockIDs: [MarkdownBlockID]) -> MarkdownSourceRange? {
        let ranges = blockIDs.compactMap { sourceRangeByBlockID[$0] }
        guard let lower = ranges.map(\.byteRange.lowerBound).min(),
              let upper = ranges.map(\.byteRange.upperBound).max(),
              lower < upper
        else {
            return nil
        }
        let lineLower = ranges.map(\.lineRange.lowerBound).min() ?? 1
        let lineUpper = ranges.map(\.lineRange.upperBound).max() ?? (lineLower + 1)
        return MarkdownSourceRange(byteRange: lower..<upper, lineRange: lineLower..<lineUpper)
    }

    private static func orderedNonOverlappingRanges(_ ranges: [MarkdownSourceRange]) -> [MarkdownSourceRange] {
        let sorted = ranges
            .filter { $0.byteRange.lowerBound <= $0.byteRange.upperBound }
            .sorted {
                if $0.byteRange.lowerBound == $1.byteRange.lowerBound {
                    return $0.byteRange.upperBound < $1.byteRange.upperBound
                }
                return $0.byteRange.lowerBound < $1.byteRange.lowerBound
            }

        var merged: [MarkdownSourceRange] = []
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.byteRange.lowerBound <= last.byteRange.upperBound {
                let mergedRange = MarkdownSourceRange(
                    byteRange: last.byteRange.lowerBound..<max(last.byteRange.upperBound, range.byteRange.upperBound),
                    lineRange: min(last.lineRange.lowerBound, range.lineRange.lowerBound)..<max(last.lineRange.upperBound, range.lineRange.upperBound)
                )
                merged[merged.count - 1] = mergedRange
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func plainText(for block: MarkdownBlock) -> String {
        switch block.kind {
        case .unorderedList, .orderedList, .taskList:
            return block.listItems.map(plainText(for:)).joined(separator: "\n")
        case .table:
            guard let table = block.table else {
                return block.text
            }
            let header = table.header.map(\.text).joined(separator: "\t")
            let rows = table.rows.map { row in
                row.map(\.text).joined(separator: "\t")
            }
            return ([header] + rows).filter { !$0.isEmpty }.joined(separator: "\n")
        default:
            let inlineText = block.inlines.map(\.text).joined()
            return inlineText.isEmpty ? block.text : inlineText
        }
    }

    private static func plainText(for item: MarkdownListItem) -> String {
        let marker: String
        switch item.taskState {
        case .checked:
            marker = "[x] "
        case .unchecked:
            marker = "[ ] "
        case nil:
            marker = ""
        }

        let children = item.childItems.map(plainText(for:)).joined(separator: "\n")
        return children.isEmpty ? marker + item.text : marker + item.text + "\n" + children
    }
}

private final class MarkdownSourceCopyStore: @unchecked Sendable {
    private let source: String

    init(_ source: String) {
        self.source = source
    }

    var markdown: String {
        source
    }

    func markdown(in sourceRange: MarkdownSourceRange) -> String? {
        let byteRange = sourceRange.byteRange
        guard byteRange.lowerBound >= 0,
              byteRange.lowerBound <= byteRange.upperBound,
              byteRange.upperBound <= source.utf8.count,
              let lowerUTF8 = source.utf8.index(
                  source.utf8.startIndex,
                  offsetBy: byteRange.lowerBound,
                  limitedBy: source.utf8.endIndex
              ),
              let upperUTF8 = source.utf8.index(
                  source.utf8.startIndex,
                  offsetBy: byteRange.upperBound,
                  limitedBy: source.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: source),
              let upper = String.Index(upperUTF8, within: source)
        else {
            return nil
        }

        return String(source[lower..<upper])
    }
}
