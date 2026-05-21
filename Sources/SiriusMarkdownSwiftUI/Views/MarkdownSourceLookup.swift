import SiriusMarkdownCore

public extension MarkdownPreparedSnapshot {
    func blockID(
        containingSourceLine line: Int,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        snapshot.blockID(containingSourceLine: line, policy: policy)
    }

    func blockIDs(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .exactOnly
    ) -> [MarkdownBlockID] {
        snapshot.blockIDs(overlappingSourceRange: sourceRange, policy: policy)
    }

    func firstBlockID(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        snapshot.firstBlockID(overlappingSourceRange: sourceRange, policy: policy)
    }
}
