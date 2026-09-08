import Foundation
import SiriusMarkdownCore

/// Matching options for a prepared document. Matching is literal, never regex.
public struct MarkdownDocumentFindOptions: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let caseInsensitive = Self(rawValue: 1 << 0)
    public static let diacriticInsensitive = Self(rawValue: 1 << 1)
}

public struct MarkdownDocumentFindMatch: Identifiable, Sendable, Hashable {
    public let id: String
    /// The mounted top-level block containing this result.
    public let blockID: MarkdownBlockID
    public let sourceRange: MarkdownSourceRange
    public let text: String
}

public struct MarkdownHeadingAnchor: Identifiable, Sendable, Hashable {
    /// Lowercase Unicode slug, with globally unique numeric suffixes.
    public let id: String
    public let title: String
    public let level: Int
    /// The mounted top-level block; sourceRange identifies a nested heading.
    public let blockID: MarkdownBlockID
    public let sourceRange: MarkdownSourceRange
}

/// A mounted destination supplied by an HTML ID or a generated heading slug.
public struct MarkdownDocumentAnchor: Identifiable, Sendable, Hashable {
    public let id: String
    public let blockID: MarkdownBlockID
    public let sourceRange: MarkdownSourceRange
}

/// Immutable search text and heading destinations built from prepared models.
/// Construct this during preparation, not from a SwiftUI body or width change.
/// Matches cross inline styling boundaries, but never cross block/cell boundaries.
/// Transformed source (for example an HTML entity) maps to its complete original
/// source span rather than inventing a byte offset inside encoded syntax.
public struct MarkdownPreparedDocumentIndex: Sendable {
    public let headings: [MarkdownHeadingAnchor]
    public let anchors: [MarkdownDocumentAnchor]
    private let anchorsByID: [String: MarkdownDocumentAnchor]
    private let leaves: [Leaf]

    public static let empty = Self(headings: [], leaves: [])

    private init(headings: [MarkdownHeadingAnchor], leaves: [Leaf], explicitAnchors: [MarkdownDocumentAnchor] = []) {
        self.headings = headings
        self.leaves = leaves
        var anchors: [MarkdownDocumentAnchor] = []
        var byID: [String: MarkdownDocumentAnchor] = [:]
        let orderedExplicit = explicitAnchors.enumerated().sorted {
            if $0.element.sourceRange.byteRange.lowerBound == $1.element.sourceRange.byteRange.lowerBound { return $0.offset < $1.offset }
            return $0.element.sourceRange.byteRange.lowerBound < $1.element.sourceRange.byteRange.lowerBound
        }
        for candidate in orderedExplicit.map(\.element) + headings.map({ MarkdownDocumentAnchor(id: $0.id, blockID: $0.blockID, sourceRange: $0.sourceRange) }) where byID[candidate.id] == nil {
            byID[candidate.id] = candidate
            anchors.append(candidate)
        }
        self.anchors = anchors
        self.anchorsByID = byID
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot) {
        var builder = Builder()
        for block in preparedSnapshot.snapshot.blocks {
            guard let content = preparedSnapshot.preparedContentByBlockID[block.id] else { continue }
            builder.append(block: block, content: content, owner: block.id)
        }
        self.init(headings: builder.headings, leaves: builder.leaves, explicitAnchors: builder.explicitAnchors)
    }

    /// Resolves a fragment or a percent-encoded fragment, with or without '#'.
    public func heading(forFragment fragment: String) -> MarkdownHeadingAnchor? {
        let fragment = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
        let decoded = fragment.removingPercentEncoding ?? fragment
        return headings.first { $0.id == decoded }
    }

    /// Resolves sanitized explicit HTML IDs before generated heading slugs.
    /// IDs are case-sensitive; the first duplicate in source order wins.
    public func anchor(forFragment fragment: String) -> MarkdownDocumentAnchor? {
        let fragment = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
        let decoded = fragment.removingPercentEncoding ?? fragment
        return anchorsByID[decoded]
    }

    public func matches(
        for query: String,
        options: MarkdownDocumentFindOptions = [.caseInsensitive]
    ) -> [MarkdownDocumentFindMatch] {
        guard !query.isEmpty else { return [] }
        var comparison: String.CompareOptions = []
        if options.contains(.caseInsensitive) { comparison.insert(.caseInsensitive) }
        if options.contains(.diacriticInsensitive) { comparison.insert(.diacriticInsensitive) }
        var results: [MarkdownDocumentFindMatch] = []
        for leaf in leaves {
            var cursor = leaf.text.startIndex
            while cursor < leaf.text.endIndex,
                  let range = leaf.text.range(
                    of: query, options: comparison, range: cursor..<leaf.text.endIndex,
                    locale: Locale(identifier: "en_US_POSIX")
                  ) {
                guard range.lowerBound < range.upperBound else { break }
                let lower = leaf.text.utf8.distance(from: leaf.text.utf8.startIndex, to: range.lowerBound)
                let upper = leaf.text.utf8.distance(from: leaf.text.utf8.startIndex, to: range.upperBound)
                if let source = leaf.sourceRange(for: lower..<upper) {
                    results.append(MarkdownDocumentFindMatch(
                        id: "\(leaf.id):\(lower):\(upper)",
                        blockID: leaf.blockID, sourceRange: source,
                        text: String(leaf.text[range])
                    ))
                }
                cursor = range.upperBound
            }
        }
        return results
    }

    private struct Segment: Sendable {
        let visible: Range<Int>
        let source: MarkdownSourceRange
        let exact: Bool
    }

    private struct Leaf: Sendable {
        let id: String
        let blockID: MarkdownBlockID
        let text: String
        let segments: [Segment]

        func sourceRange(for visible: Range<Int>) -> MarkdownSourceRange? {
            var ranges: [MarkdownSourceRange] = []
            var lower = 0
            var upper = segments.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if segments[middle].visible.upperBound <= visible.lowerBound { lower = middle + 1 }
                else { upper = middle }
            }
            var index = lower
            while index < segments.count, segments[index].visible.lowerBound < visible.upperBound {
                let segment = segments[index]
                index += 1
                let overlap = max(visible.lowerBound, segment.visible.lowerBound)..<min(visible.upperBound, segment.visible.upperBound)
                if segment.exact {
                    let base = segment.source.byteRange.lowerBound - segment.visible.lowerBound
                    ranges.append(MarkdownSourceRange(
                        byteRange: (base + overlap.lowerBound)..<(base + overlap.upperBound),
                        lineRange: segment.source.lineRange
                    ))
                } else {
                    ranges.append(segment.source)
                }
            }
            guard let first = ranges.first else { return nil }
            return MarkdownSourceRange(
                byteRange: (ranges.map { $0.byteRange.lowerBound }.min() ?? first.byteRange.lowerBound)..<(ranges.map { $0.byteRange.upperBound }.max() ?? first.byteRange.upperBound),
                lineRange: (ranges.map { $0.lineRange.lowerBound }.min() ?? first.lineRange.lowerBound)..<(ranges.map { $0.lineRange.upperBound }.max() ?? first.lineRange.upperBound)
            )
        }
    }

    private struct Builder {
        var leaves: [Leaf] = []
        var headings: [MarkdownHeadingAnchor] = []
        var usedSlugs: Set<String> = []
        var explicitAnchors: [MarkdownDocumentAnchor] = []

        mutating func appendAnchors(_ anchors: [MarkdownHTMLAnchor], owner: MarkdownBlockID) {
            explicitAnchors.append(contentsOf: anchors.map { MarkdownDocumentAnchor(id: $0.identifier, blockID: owner, sourceRange: $0.sourceRange) })
        }

        mutating func appendInlineAnchors(_ runs: [MarkdownInlineRun], owner: MarkdownBlockID) {
            for run in runs { appendAnchors(run.htmlAnchors, owner: owner) }
        }

        mutating func appendListAnchors(_ items: [MarkdownListItem], owner: MarkdownBlockID) {
            for item in items {
                appendInlineAnchors(item.inlines, owner: owner)
                appendListAnchors(item.childItems, owner: owner)
            }
        }

        mutating func append(block: MarkdownBlock, content: MarkdownPreparedBlockContent, owner: MarkdownBlockID) {
            guard content.policyDenialReason == nil else { return }
            appendInlineAnchors(block.inlines, owner: owner)
            appendListAnchors(block.listItems, owner: owner)
            if let table = block.table {
                for row in [table.header] + table.rows {
                    for cell in row { appendInlineAnchors(cell.inlines, owner: owner) }
                }
            }
            if content.richContent != nil { appendAnchors(block.richContent?.htmlAnchors ?? [], owner: owner) }
            if case .image? = content.mathRender { return }
            if let rich = content.richContent {
                for child in rich.blocks { append(block: child.block, content: child.preparedContent, owner: owner) }
                return
            }
            if !content.childBlocks.isEmpty {
                for child in content.childBlocks { append(block: child.block, content: child.preparedContent, owner: owner) }
                return
            }
            if !content.listItems.isEmpty {
                for item in content.listItems { append(item: item, owner: owner) }
                return
            }
            if let table = content.table {
                for cell in table.header { append(cell: cell, owner: owner) }
                for row in table.rows { for cell in row.cells { append(cell: cell, owner: owner) } }
                return
            }
            let previousCount = leaves.count
            append(
                inline: content.inlineLayout ?? content.selectionInlineLayout,
                fallback: content.inline ?? content.code ?? content.math,
                source: block.sourceRange, id: block.id.rawValue, owner: owner
            )
            if block.kind == .heading, leaves.count > previousCount, let leaf = leaves.last {
                let title = leaf.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = Self.slug(title)
                var slug = base
                var suffix = 1
                while usedSlugs.contains(slug) {
                    slug = "\(base)-\(suffix)"
                    suffix += 1
                }
                usedSlugs.insert(slug)
                headings.append(MarkdownHeadingAnchor(
                    id: slug, title: title, level: block.headingLevel ?? 1,
                    blockID: owner, sourceRange: block.sourceRange
                ))
            }
        }

        mutating func append(item: MarkdownPreparedListItem, owner: MarkdownBlockID) {
            if item.childBlocks.isEmpty {
                append(inline: item.inlineLayout ?? item.selectionInlineLayout, fallback: item.inline,
                       source: item.sourceRange, id: "list:\(item.sourceRange.byteRange.lowerBound)", owner: owner)
                for child in item.childItems { append(item: child, owner: owner) }
            } else {
                for child in item.childBlocks { append(block: child.block, content: child.preparedContent, owner: owner) }
            }
        }

        mutating func append(cell: MarkdownPreparedTableCell, owner: MarkdownBlockID) {
            append(inline: cell.inlineLayout ?? cell.selectionInlineLayout, fallback: cell.inline,
                   source: cell.sourceRange, id: cell.id, owner: owner)
        }

        mutating func append(inline: MarkdownPreparedInlineContent?, fallback: AttributedString?, source: MarkdownSourceRange, id: String, owner: MarkdownBlockID) {
            var text = ""
            var segments: [Segment] = []
            var visibleByteCount = 0
            if let inline {
                let rasterizedMath = Set((inline.mathTextPieces ?? []).compactMap { piece -> String? in
                    if case let .math(image) = piece { return image.latex }
                    return nil
                })
                for run in inline.prepared.runs {
                    guard !run.presentation.contains(.linkDecoration), !run.text.isEmpty else { continue }
                    // An attachment's replacement character is visual chrome,
                    // not searchable prose. Keep it as a boundary between words.
                    let isRaster = run.attachmentMetrics != nil ||
                        ((run.kind == .math || run.presentation.contains(.math)) && rasterizedMath.contains(run.text))
                    let visibleText = isRaster ? "\u{FFFC}" : run.text
                    let lower = visibleByteCount
                    text += visibleText
                    visibleByteCount += visibleText.utf8.count
                    let mappedSource = run.sourceRange ?? source
                    guard !mappedSource.byteRange.isEmpty, !isRaster else { continue }
                    segments.append(Segment(
                        visible: lower..<visibleByteCount, source: mappedSource,
                        exact: mappedSource.byteRange.count == visibleText.utf8.count
                    ))
                }
            } else if let fallback {
                text = String(fallback.characters)
                segments = [Segment(visible: 0..<text.utf8.count, source: source, exact: false)]
            }
            guard !text.isEmpty else { return }
            leaves.append(Leaf(id: "\(owner.rawValue):\(id)", blockID: owner, text: text, segments: segments))
        }

        static func slug(_ title: String) -> String {
            var slug = ""
            for scalar in title.lowercased().unicodeScalars {
                if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    slug.append("-")
                } else if CharacterSet.alphanumerics.contains(scalar) ||
                            CharacterSet.nonBaseCharacters.contains(scalar) || scalar == "-" || scalar == "_" {
                    slug.unicodeScalars.append(scalar)
                }
            }
            return slug.isEmpty ? "section" : slug
        }
    }
}
