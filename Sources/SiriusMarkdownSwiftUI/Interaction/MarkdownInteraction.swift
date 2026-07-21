import SiriusMarkdownCore
import SwiftUI

// MARK: - Selection context types (Part 02)

/// Identifies a scrollable block region that can own an exclusive selection context.
public struct MarkdownScrollableSelectionRegionID: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case codeBlock
        case table
    }

    public var blockID: MarkdownBlockID
    public var role: Role

    public init(blockID: MarkdownBlockID, role: Role) {
        self.blockID = blockID
        self.role = role
    }
}

/// The currently active selection owner. Activating one context clears the other.
public enum MarkdownSelectionContextKind: Sendable, Hashable {
    case document
    case scrollableRegion(MarkdownScrollableSelectionRegionID)
}

// MARK: -

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
    let renderIdentity: UUID

    public init(open: @escaping @Sendable (String) -> Void) {
        self.open = open
        self.renderIdentity = UUID()
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

/// Intercepts affordance copy/export actions from the document and block layers.
///
/// `MarkdownAffordanceActionHandler` is a reference type so that:
/// - The three `@MainActor @Sendable` closure fields do not trigger Swift runtime
///   memmove failures when evaluated as default arguments in struct initialisers.
/// - Hosts can share a single configured handler across multiple views without
///   copy overhead, while still replacing a configuration's handler via reassignment.
///
/// All stored closures are constants (set at initialisation time). To change
/// behaviour, create and assign a new handler instance.
public final class MarkdownAffordanceActionHandler: @unchecked Sendable {
    /// Called for single-string copy actions: code block affordance copy, Markdown
    /// source copy from affordances, and other sites that have one string with no
    /// plain/Markdown distinction. The default implementation calls
    /// `MarkdownPasteboard.copy(_ string:)`, which writes a payload whose
    /// `plainText` and `markdown` fields are equal.
    public let copyString: @MainActor @Sendable (String) -> Void

    /// Called for document selection Cmd-C and programmatic
    /// `copySelectedMarkdown`. The payload carries separate `plainText` and
    /// `markdown` fields so the host can decide what to surface (e.g. show the
    /// Markdown in a toast while the system pasteboard receives plain text).
    /// The default implementation calls `MarkdownPasteboard.copy(_ payload:)`.
    public let copyPayload: @MainActor @Sendable (MarkdownPasteboardPayload) -> Void

    /// Called when the user exports Markdown to a file. The default opens a
    /// save panel on macOS and falls back to `MarkdownPasteboard.copy` elsewhere.
    public let exportMarkdown: @MainActor @Sendable (MarkdownExportPayload) -> Void

    public init(
        copyString: @escaping @MainActor @Sendable (String) -> Void = { string in
            MarkdownPasteboard.copy(string)
        },
        copyPayload: @escaping @MainActor @Sendable (MarkdownPasteboardPayload) -> Void = { payload in
            MarkdownPasteboard.copy(payload)
        },
        exportMarkdown: @escaping @MainActor @Sendable (MarkdownExportPayload) -> Void = { payload in
            MarkdownDocumentExporter.export(payload)
        }
    ) {
        self.copyString = copyString
        self.copyPayload = copyPayload
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
    /// The currently active selection context. Default is `.document`.
    ///
    /// Calling `activateContext(_:)` with a different context clears all existing
    /// selected ranges and block IDs before switching. This matches Textual's
    /// documented rule: activating a scrollable region clears document selection
    /// and vice versa.
    @Published public private(set) var activeContext: MarkdownSelectionContextKind = .document

    public var maximumSelectedBlockCount: Int {
        didSet {
            maximumSelectedBlockCount = max(1, maximumSelectedBlockCount)
            trimSelectionIfNeeded()
        }
    }
    private var blockOrder: [MarkdownBlockID] = []
    private var sourceRangeByBlockID: [MarkdownBlockID: MarkdownSourceRange] = [:]
    private var snapshotSourceLength: Int = 0
    private var selectionIntent: SelectionIntent = .none

    private enum SelectionIntent {
        case none
        case blocks
        case contiguousBlocks
        case sourceRanges
        case fullDocument
    }

    public init(maximumSelectedBlockCount: Int = 512) {
        self.maximumSelectedBlockCount = max(1, maximumSelectedBlockCount)
    }

    public func updateSnapshot(_ snapshot: MarkdownSnapshot) {
        let selectionIndex = Self.selectionIndex(for: snapshot.blocks)
        blockOrder = selectionIndex.blockOrder
        sourceRangeByBlockID = selectionIndex.sourceRangeByBlockID
        snapshotSourceLength = snapshot.sourceLength
        let valid = Set(blockOrder)
        selectedBlockIDs.removeAll { !valid.contains($0) }
        selectedSourceRanges.removeAll {
            $0.byteRange.lowerBound < 0 ||
                $0.byteRange.upperBound > snapshot.sourceLength ||
                $0.byteRange.lowerBound > $0.byteRange.upperBound
        }

        switch selectionIntent {
        case .none:
            break
        case .blocks:
            guard !selectedBlockIDs.isEmpty else {
                clearSelection()
                return
            }
            selectedSourceRanges = orderedRanges(for: selectedBlockIDs)
        case .contiguousBlocks:
            guard !selectedBlockIDs.isEmpty else {
                clearSelection()
                return
            }
            selectedSourceRanges = combinedRange(for: selectedBlockIDs).map { [$0] } ?? []
        case .sourceRanges:
            selectedSourceRanges = Self.orderedNonOverlappingRanges(selectedSourceRanges)
            selectedBlockIDs = selectedBlockIDsOverlapping(selectedSourceRanges, in: selectedBlockIDs)
            if selectedSourceRanges.isEmpty, selectedBlockIDs.isEmpty {
                selectionIntent = .none
            }
        case .fullDocument:
            guard snapshot.sourceLength > 0 else {
                clearSelection()
                return
            }
            selectedBlockIDs = blockOrder
            selectedSourceRanges = [fullDocumentSourceRange()]
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
        selectionIntent = selectedBlockIDs.isEmpty ? .none : .blocks
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
        selectionIntent = selectedBlockIDs.isEmpty ? .none : .contiguousBlocks
        trimSelectionIfNeeded()
    }

    public func selectSourceRanges(
        _ sourceRanges: [MarkdownSourceRange],
        selectedBlockIDs blockIDs: [MarkdownBlockID] = []
    ) {
        let valid = Set(blockOrder)
        selectedSourceRanges = Self.orderedNonOverlappingRanges(sourceRanges)
        selectedBlockIDs = selectedBlockIDsOverlapping(
            selectedSourceRanges,
            in: blockIDs.filter { valid.contains($0) }
        )
        sortSelectionInDocumentOrder()
        selectionIntent = selectedSourceRanges.isEmpty && selectedBlockIDs.isEmpty ? .none : .sourceRanges
        trimSelectionIfNeeded()
    }

    public func selectAll(in snapshot: MarkdownSnapshot) {
        updateSnapshot(snapshot)
        guard snapshot.sourceLength > 0 else {
            clearSelection()
            return
        }

        selectedBlockIDs = blockOrder
        selectedSourceRanges = [fullDocumentSourceRange()]
        selectionIntent = .fullDocument
    }

    public func selectAll(in preparedSnapshot: MarkdownPreparedSnapshot) {
        selectAll(in: preparedSnapshot.snapshot)
    }

    public func clearSelection() {
        selectedBlockIDs.removeAll()
        selectedSourceRanges.removeAll()
        selectionIntent = .none
    }

    /// Activates the given selection context, clearing all selected ranges if the context changes.
    ///
    /// If `context` equals `activeContext`, this is a no-op (avoids spurious published changes).
    /// Use `.document` for the main document drag path and `.scrollableRegion` for code/table
    /// horizontal scrollers.
    public func activateContext(_ context: MarkdownSelectionContextKind) {
        guard context != activeContext else { return }
        clearSelection()
        activeContext = context
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
        if !selectedSourceRanges.isEmpty {
            return Self.plainText(
                for: Self.orderedNonOverlappingRanges(selectedSourceRanges),
                in: preparedSnapshot.snapshot
            )
        }
        if selectionIntent == .sourceRanges {
            return ""
        }

        return selectedBlocks(in: preparedSnapshot).map(Self.plainText(for:)).joined(separator: "\n")
    }

    public func copySelectedMarkdown(
        in preparedSnapshot: MarkdownPreparedSnapshot,
        copyProvider: MarkdownCopyProvider?
    ) {
        let markdown = selectedMarkdown(in: preparedSnapshot, copyProvider: copyProvider)
        guard !markdown.isEmpty else {
            return
        }
        let plainText = selectedPlainText(in: preparedSnapshot)
        let payload = MarkdownPasteboardPayload(
            plainText: plainText.isEmpty ? markdown : plainText,
            markdown: markdown
        )
        MarkdownPasteboard.copy(payload)
    }

    public func copySelectedPlainText(in preparedSnapshot: MarkdownPreparedSnapshot) {
        let plainText = selectedPlainText(in: preparedSnapshot)
        guard !plainText.isEmpty else {
            return
        }
        MarkdownPasteboard.copy(MarkdownPasteboardPayload(plainText: plainText, markdown: plainText))
    }

    private func selectedBlocks(in preparedSnapshot: MarkdownPreparedSnapshot) -> [MarkdownBlock] {
        let selected = Set(selectedBlockIDs)
        return preparedSnapshot.snapshot.blocks.filter { selected.contains($0.id) }
    }

    private func effectiveSourceRanges(in preparedSnapshot: MarkdownPreparedSnapshot) -> [MarkdownSourceRange] {
        if !selectedSourceRanges.isEmpty {
            return Self.orderedNonOverlappingRanges(selectedSourceRanges)
        }
        if selectionIntent == .sourceRanges {
            return []
        }

        return Self.orderedNonOverlappingRanges(
            selectedBlocks(in: preparedSnapshot).map(\.sourceRange)
        )
    }

    private func sortSelectionInDocumentOrder() {
        var order: [MarkdownBlockID: Int] = [:]
        for (index, blockID) in blockOrder.enumerated() where order[blockID] == nil {
            order[blockID] = index
        }
        selectedBlockIDs.sort { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }
    }

    private func trimSelectionIfNeeded() {
        guard selectedBlockIDs.count > maximumSelectedBlockCount else {
            return
        }

        let fullDocumentRange = fullDocumentSourceRange()
        let isFullDocumentSelection = selectedSourceRanges.count == 1 &&
            selectedSourceRanges.first?.byteRange == fullDocumentRange.byteRange
        guard !isFullDocumentSelection else {
            return
        }
        let existingSourceRanges = selectedSourceRanges
        selectedBlockIDs = Array(selectedBlockIDs.prefix(maximumSelectedBlockCount))
        selectedSourceRanges = switch selectionIntent {
        case .sourceRanges:
            clippedSourceRanges(existingSourceRanges, to: selectedBlockIDs)
        case .contiguousBlocks:
            combinedRange(for: selectedBlockIDs).map { [$0] } ?? []
        default:
            orderedRanges(for: selectedBlockIDs)
        }
        if selectionIntent == .sourceRanges {
            selectedBlockIDs = selectedBlockIDsOverlapping(selectedSourceRanges, in: selectedBlockIDs)
            if selectedSourceRanges.isEmpty, selectedBlockIDs.isEmpty {
                selectionIntent = .none
            }
        }
    }

    private func fullDocumentSourceRange() -> MarkdownSourceRange {
        let lineLower = sourceRangeByBlockID.values.map(\.lineRange.lowerBound).min() ?? 1
        let lineUpper = sourceRangeByBlockID.values.map(\.lineRange.upperBound).max() ?? lineLower
        return MarkdownSourceRange(
            byteRange: 0..<snapshotSourceLength,
            lineRange: lineLower..<max(lineUpper, lineLower + 1)
        )
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

    private func clippedSourceRanges(
        _ ranges: [MarkdownSourceRange],
        to blockIDs: [MarkdownBlockID]
    ) -> [MarkdownSourceRange] {
        let blockRanges = blockIDs.compactMap { sourceRangeByBlockID[$0] }
        guard !ranges.isEmpty, !blockRanges.isEmpty else {
            return []
        }

        var clipped: [MarkdownSourceRange] = []
        for range in Self.orderedNonOverlappingRanges(ranges) {
            for blockRange in blockRanges {
                let lower = max(range.byteRange.lowerBound, blockRange.byteRange.lowerBound)
                let upper = min(range.byteRange.upperBound, blockRange.byteRange.upperBound)
                guard lower < upper else {
                    continue
                }
                clipped.append(
                    MarkdownSourceRange(
                        byteRange: lower..<upper,
                        lineRange: Self.clippedLineRange(for: range, to: blockRange)
                    )
                )
            }
        }
        return Self.orderedNonOverlappingRanges(clipped)
    }

    private func selectedBlockIDsOverlapping(
        _ ranges: [MarkdownSourceRange],
        in candidateBlockIDs: [MarkdownBlockID]
    ) -> [MarkdownBlockID] {
        guard !ranges.isEmpty, !candidateBlockIDs.isEmpty else {
            return []
        }

        return candidateBlockIDs.filter { blockID in
            guard let blockRange = sourceRangeByBlockID[blockID] else {
                return false
            }
            return ranges.contains { blockRange.overlaps($0) }
        }
    }

    private static func clippedLineRange(
        for range: MarkdownSourceRange,
        to blockRange: MarkdownSourceRange
    ) -> Range<Int> {
        let lower = max(range.lineRange.lowerBound, blockRange.lineRange.lowerBound)
        let upper = min(range.lineRange.upperBound, blockRange.lineRange.upperBound)
        if lower < upper {
            return lower..<upper
        }
        if !range.lineRange.isEmpty {
            return range.lineRange
        }
        if !blockRange.lineRange.isEmpty {
            return blockRange.lineRange
        }
        return 1..<2
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

    private static func selectionIndex(
        for blocks: [MarkdownBlock]
    ) -> (blockOrder: [MarkdownBlockID], sourceRangeByBlockID: [MarkdownBlockID: MarkdownSourceRange]) {
        var blockOrder: [MarkdownBlockID] = []
        var sourceRangeByBlockID: [MarkdownBlockID: MarkdownSourceRange] = [:]

        for block in blocks {
            if let existing = sourceRangeByBlockID[block.id] {
                sourceRangeByBlockID[block.id] = mergedSourceRange(existing, block.sourceRange)
            } else {
                blockOrder.append(block.id)
                sourceRangeByBlockID[block.id] = block.sourceRange
            }
        }

        return (blockOrder, sourceRangeByBlockID)
    }

    private static func mergedSourceRange(
        _ lhs: MarkdownSourceRange,
        _ rhs: MarkdownSourceRange
    ) -> MarkdownSourceRange {
        MarkdownSourceRange(
            byteRange: min(lhs.byteRange.lowerBound, rhs.byteRange.lowerBound)..<max(lhs.byteRange.upperBound, rhs.byteRange.upperBound),
            lineRange: min(lhs.lineRange.lowerBound, rhs.lineRange.lowerBound)..<max(lhs.lineRange.upperBound, rhs.lineRange.upperBound)
        )
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

    private static func plainText(
        for ranges: [MarkdownSourceRange],
        in snapshot: MarkdownSnapshot
    ) -> String {
        ranges.map { range in
            snapshot.blocks.compactMap { block in
                plainText(in: range.byteRange, for: block)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func plainText(
        in selectedRange: Range<Int>,
        for block: MarkdownBlock
    ) -> String? {
        guard selectedRange.overlaps(block.sourceRange.byteRange) else {
            return nil
        }
        if selectedRange.contains(block.sourceRange.byteRange) {
            return plainText(for: block)
        }

        switch block.kind {
        case .unorderedList, .orderedList, .taskList:
            return joinedPlainText(block.listItems.compactMap { plainText(in: selectedRange, for: $0) })
        case .table:
            guard let table = block.table else {
                return plainText(
                    in: selectedRange,
                    runs: block.inlines,
                    fallbackText: block.text,
                    fallbackSourceRange: block.sourceRange.byteRange
                )
            }
            return plainText(in: selectedRange, for: table)
        default:
            return plainText(
                in: selectedRange,
                runs: block.inlines,
                fallbackText: block.text,
                fallbackSourceRange: block.sourceRange.byteRange
            )
        }
    }

    private static func plainText(
        in selectedRange: Range<Int>,
        for item: MarkdownListItem
    ) -> String? {
        guard selectedRange.overlaps(item.sourceRange.byteRange) else {
            return nil
        }
        if selectedRange.contains(item.sourceRange.byteRange) {
            return plainText(for: item)
        }

        let ownText = plainText(
            in: selectedRange,
            runs: item.inlines,
            fallbackText: item.text,
            fallbackSourceRange: item.sourceRange.byteRange
        )
        let childText = item.childItems.compactMap { plainText(in: selectedRange, for: $0) }
        return joinedPlainText(([ownText] + childText).compactMap { $0 })
    }

    private static func plainText(
        in selectedRange: Range<Int>,
        for table: MarkdownTableBlock
    ) -> String? {
        let rows = ([table.header] + table.rows).compactMap { row -> String? in
            let cells = row.compactMap { cell -> String? in
                guard selectedRange.overlaps(cell.sourceRange.byteRange) else {
                    return nil
                }
                if selectedRange.contains(cell.sourceRange.byteRange) {
                    return cell.text
                }
                return plainText(
                    in: selectedRange,
                    runs: cell.inlines,
                    fallbackText: cell.text,
                    fallbackSourceRange: cell.sourceRange.byteRange
                )
            }
            guard !cells.isEmpty else {
                return nil
            }
            return cells.joined(separator: "\t")
        }
        return joinedPlainText(rows)
    }

    private static func plainText(
        in selectedRange: Range<Int>,
        runs: [MarkdownInlineRun],
        fallbackText: String,
        fallbackSourceRange: Range<Int>
    ) -> String? {
        let text = runs.map { plainText(in: selectedRange, for: $0) }.joined()
        if !text.isEmpty {
            return text
        }

        guard runs.isEmpty else {
            return nil
        }
        guard !fallbackText.isEmpty else {
            return nil
        }
        if selectedRange.contains(fallbackSourceRange) {
            return fallbackText
        }

        let overlap = max(selectedRange.lowerBound, fallbackSourceRange.lowerBound)..<min(selectedRange.upperBound, fallbackSourceRange.upperBound)
        guard !overlap.isEmpty else {
            return nil
        }
        if fallbackSourceRange.count == fallbackText.utf8.count {
            let visibleRange = (overlap.lowerBound - fallbackSourceRange.lowerBound)..<(overlap.upperBound - fallbackSourceRange.lowerBound)
            return substring(fallbackText, utf8Range: visibleRange)
        }

        let visibleLower = visibleByteOffset(
            forSourceByteOffset: overlap.lowerBound,
            sourceRange: fallbackSourceRange,
            visibleByteCount: fallbackText.utf8.count
        )
        let visibleUpper = visibleByteOffset(
            forSourceByteOffset: overlap.upperBound,
            sourceRange: fallbackSourceRange,
            visibleByteCount: fallbackText.utf8.count
        )
        let sliced = substring(fallbackText, utf8Range: min(visibleLower, visibleUpper)..<max(visibleLower, visibleUpper))
        return sliced.isEmpty ? nil : sliced
    }

    private static func plainText(
        in selectedRange: Range<Int>,
        for run: MarkdownInlineRun
    ) -> String {
        guard let sourceRange = run.sourceRange?.byteRange,
              selectedRange.overlaps(sourceRange)
        else {
            return ""
        }
        if selectedRange.contains(sourceRange) {
            return run.text
        }

        let overlap = max(selectedRange.lowerBound, sourceRange.lowerBound)..<min(selectedRange.upperBound, sourceRange.upperBound)
        guard !overlap.isEmpty else {
            return ""
        }
        if sourceRange.count == run.text.utf8.count {
            let visibleRange = (overlap.lowerBound - sourceRange.lowerBound)..<(overlap.upperBound - sourceRange.lowerBound)
            return substring(run.text, utf8Range: visibleRange)
        }

        let visibleLower = visibleByteOffset(
            forSourceByteOffset: overlap.lowerBound,
            sourceRange: sourceRange,
            visibleByteCount: run.text.utf8.count
        )
        let visibleUpper = visibleByteOffset(
            forSourceByteOffset: overlap.upperBound,
            sourceRange: sourceRange,
            visibleByteCount: run.text.utf8.count
        )
        return substring(run.text, utf8Range: min(visibleLower, visibleUpper)..<max(visibleLower, visibleUpper))
    }

    private static func visibleByteOffset(
        forSourceByteOffset sourceByteOffset: Int,
        sourceRange: Range<Int>,
        visibleByteCount: Int
    ) -> Int {
        guard sourceRange.count > 0, visibleByteCount > 0 else {
            return 0
        }
        let clamped = min(max(sourceByteOffset, sourceRange.lowerBound), sourceRange.upperBound)
        let progress = Double(clamped - sourceRange.lowerBound) / Double(sourceRange.count)
        return min(visibleByteCount, max(0, Int((Double(visibleByteCount) * progress).rounded())))
    }

    private static func substring(_ text: String, utf8Range: Range<Int>) -> String {
        let lowerOffset = min(max(utf8Range.lowerBound, 0), text.utf8.count)
        let upperOffset = min(max(utf8Range.upperBound, lowerOffset), text.utf8.count)
        guard lowerOffset < upperOffset,
              let lowerUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: lowerOffset,
                limitedBy: text.utf8.endIndex
              ),
              let upperUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: upperOffset,
                limitedBy: text.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: text),
              let upper = String.Index(upperUTF8, within: text)
        else {
            return ""
        }
        return String(text[lower..<upper])
    }

    private static func joinedPlainText(_ parts: [String]) -> String? {
        let text = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.isEmpty ? nil : text
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

private extension Range where Bound == Int {
    func contains(_ other: Range<Int>) -> Bool {
        lowerBound <= other.lowerBound && other.upperBound <= upperBound
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
