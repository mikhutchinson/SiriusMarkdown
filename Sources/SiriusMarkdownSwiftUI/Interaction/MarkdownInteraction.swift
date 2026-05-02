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

public struct MarkdownCopyProvider: Sendable {
    public var markdown: @Sendable (MarkdownSourceRange) -> String?

    public init(markdown: @escaping @Sendable (MarkdownSourceRange) -> String?) {
        self.markdown = markdown
    }

    public init(markdownSource: String) {
        let store = MarkdownSourceCopyStore(markdownSource)
        self.markdown = { range in
            store.markdown(in: range)
        }
    }
}

@MainActor
public final class MarkdownSelectionController: ObservableObject {
    @Published public private(set) var selectedBlockIDs: [MarkdownBlockID] = []

    public var maximumSelectedBlockCount: Int
    private var blockOrder: [MarkdownBlockID] = []

    public init(maximumSelectedBlockCount: Int = 512) {
        precondition(maximumSelectedBlockCount > 0)
        self.maximumSelectedBlockCount = maximumSelectedBlockCount
    }

    public func updateSnapshot(_ snapshot: MarkdownSnapshot) {
        blockOrder = snapshot.blocks.map(\.id)
        let valid = Set(blockOrder)
        selectedBlockIDs.removeAll { !valid.contains($0) }
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
        trimSelectionIfNeeded()
    }

    public func clearSelection() {
        selectedBlockIDs.removeAll()
    }

    public func isSelected(_ blockID: MarkdownBlockID) -> Bool {
        selectedBlockIDs.contains(blockID)
    }

    public func selectedMarkdown(
        in preparedSnapshot: MarkdownPreparedSnapshot,
        copyProvider: MarkdownCopyProvider?
    ) -> String {
        selectedBlocks(in: preparedSnapshot).compactMap { block in
            copyProvider?.markdown(block.sourceRange)
        }
        .joined(separator: "\n")
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

    private func sortSelectionInDocumentOrder() {
        let order = Dictionary(uniqueKeysWithValues: blockOrder.enumerated().map { ($0.element, $0.offset) })
        selectedBlockIDs.sort { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }
    }

    private func trimSelectionIfNeeded() {
        guard selectedBlockIDs.count > maximumSelectedBlockCount else {
            return
        }

        selectedBlockIDs = Array(selectedBlockIDs.prefix(maximumSelectedBlockCount))
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
