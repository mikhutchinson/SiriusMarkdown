import Foundation

public enum MarkdownSourceRevealPolicy: Sendable, Hashable {
    case exactOnly
    case nearestRenderedBlock
}

public extension MarkdownSourceRange {
    func containsSourceLine(_ line: Int) -> Bool {
        guard line >= 1, !lineRange.isEmpty else {
            return false
        }
        return lineRange.contains(line)
    }

    func overlapsSourceLines(_ otherLineRange: Range<Int>) -> Bool {
        guard !lineRange.isEmpty, !otherLineRange.isEmpty else {
            return false
        }
        return lineRange.lowerBound < otherLineRange.upperBound &&
            otherLineRange.lowerBound < lineRange.upperBound
    }

    func overlaps(_ other: MarkdownSourceRange) -> Bool {
        guard byteRange.lowerBound <= byteRange.upperBound,
              other.byteRange.lowerBound <= other.byteRange.upperBound
        else {
            return false
        }
        return byteRange.lowerBound < other.byteRange.upperBound &&
            other.byteRange.lowerBound < byteRange.upperBound
    }
}

public extension MarkdownSnapshot {
    func block(
        containingSourceLine line: Int,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlock? {
        guard line >= 1 else {
            return nil
        }

        if let exact = blocks.first(where: { $0.sourceRange.containsSourceLine(line) }) {
            return exact
        }

        guard policy == .nearestRenderedBlock else {
            return nil
        }

        return Self.nearestBlock(forSourceLine: line, in: blocks)
    }

    func blockID(
        containingSourceLine line: Int,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        block(containingSourceLine: line, policy: policy)?.id
    }

    func blocks(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .exactOnly
    ) -> [MarkdownBlock] {
        let overlapping = blocks.filter { $0.sourceRange.overlaps(sourceRange) }
        guard !overlapping.isEmpty || policy == .exactOnly else {
            if let nearest = Self.nearestBlock(for: sourceRange, in: self) {
                return [nearest]
            }
            return []
        }
        return overlapping
    }

    func blockIDs(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .exactOnly
    ) -> [MarkdownBlockID] {
        blocks(overlappingSourceRange: sourceRange, policy: policy).map(\.id)
    }

    func firstBlockID(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        let overlapping = blocks.filter { $0.sourceRange.overlaps(sourceRange) }
        if let first = overlapping.first {
            return first.id
        }

        guard policy == .nearestRenderedBlock else {
            return nil
        }

        return Self.nearestBlock(for: sourceRange, in: self)?.id
    }
}

private extension MarkdownSnapshot {
    static func nearestBlock(for sourceRange: MarkdownSourceRange, in snapshot: MarkdownSnapshot) -> MarkdownBlock? {
        if let line = validNearestLine(in: sourceRange),
           let block = nearestBlock(forSourceLine: line, in: snapshot.blocks)
        {
            return block
        }

        return nearestBlock(
            forByteOffset: sourceRange.byteRange.lowerBound,
            in: snapshot.blocks,
            sourceLength: snapshot.sourceLength
        )
    }

    static func validNearestLine(in sourceRange: MarkdownSourceRange) -> Int? {
        guard sourceRange.lineRange.lowerBound >= 1, !sourceRange.lineRange.isEmpty else {
            return nil
        }
        return sourceRange.lineRange.lowerBound
    }

    static func nearestBlock(forSourceLine line: Int, in blocks: [MarkdownBlock]) -> MarkdownBlock? {
        guard line >= 1, !blocks.isEmpty else {
            return nil
        }

        let documentLineUpperBound = blocks.map(\.sourceRange.lineRange.upperBound).max() ?? 1
        guard line < documentLineUpperBound else {
            return nil
        }

        if let following = blocks.first(where: { $0.sourceRange.lineRange.lowerBound > line }) {
            return following
        }

        return blocks.last(where: { $0.sourceRange.lineRange.upperBound <= line })
    }

    static func nearestBlock(forByteOffset offset: Int, in blocks: [MarkdownBlock], sourceLength: Int) -> MarkdownBlock? {
        guard !blocks.isEmpty, offset >= 0, offset < sourceLength else {
            return nil
        }

        if let exact = blocks.first(where: { $0.sourceRange.byteRange.contains(offset) }) {
            return exact
        }

        if let following = blocks.first(where: { $0.sourceRange.byteRange.lowerBound > offset }) {
            return following
        }

        return blocks.last(where: { $0.sourceRange.byteRange.upperBound <= offset })
    }
}
