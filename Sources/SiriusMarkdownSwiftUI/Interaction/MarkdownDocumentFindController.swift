import Combine
import Foundation

/// Reusable find state. Update its index after document preparation; views only
/// observe results and reveal `currentMatch` using its block ID and source range.
@MainActor
public final class MarkdownDocumentFindController: ObservableObject {
    @Published public var isPresented = false
    @Published public var query: String = "" { didSet { refresh(preservingSelection: false) } }
    @Published public var options: MarkdownDocumentFindOptions = [.caseInsensitive] {
        didSet { refresh(preservingSelection: false) }
    }
    @Published public private(set) var matches: [MarkdownDocumentFindMatch] = []
    @Published public private(set) var currentMatchIndex: Int?
    public private(set) var index: MarkdownPreparedDocumentIndex

    public var currentMatch: MarkdownDocumentFindMatch? {
        guard let currentMatchIndex, matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    public init(index: MarkdownPreparedDocumentIndex = .empty) {
        self.index = index
    }

    /// Retains the selected occurrence when immutable source preceding it survives.
    public func update(index: MarkdownPreparedDocumentIndex) {
        self.index = index
        refresh(preservingSelection: true)
    }

    @discardableResult
    public func next() -> MarkdownDocumentFindMatch? {
        guard !matches.isEmpty else { return nil }
        currentMatchIndex = currentMatchIndex.map { ($0 + 1) % matches.count } ?? 0
        return currentMatch
    }

    @discardableResult
    public func previous() -> MarkdownDocumentFindMatch? {
        guard !matches.isEmpty else { return nil }
        currentMatchIndex = currentMatchIndex.map { $0 == 0 ? matches.count - 1 : $0 - 1 } ?? (matches.count - 1)
        return currentMatch
    }

    private func refresh(preservingSelection: Bool) {
        let selectedID = preservingSelection ? currentMatch?.id : nil
        matches = index.matches(for: query, options: options)
        currentMatchIndex = selectedID.flatMap { id in matches.firstIndex { $0.id == id } }
            ?? (matches.isEmpty ? nil : 0)
    }
}
