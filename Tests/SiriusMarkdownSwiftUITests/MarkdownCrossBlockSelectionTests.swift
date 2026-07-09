import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

// MARK: - Test helpers

private func sourceRange(of substring: String, in source: String) -> MarkdownSourceRange {
    guard let range = source.range(of: substring) else {
        fatalError("Substring not found: \(substring)")
    }
    let lower = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound.samePosition(in: source.utf8)!)
    let upper = source.utf8.distance(from: source.utf8.startIndex, to: range.upperBound.samePosition(in: source.utf8)!)
    let line = source.distance(from: source.startIndex, to: source.lineRange(for: range).lowerBound) + 1
    let lineEnd = source.distance(from: source.startIndex, to: source.lineRange(for: range).upperBound) + 1
    return MarkdownSourceRange(byteRange: lower..<upper, lineRange: line..<lineEnd)
}

private func prepareSnapshot(
    _ source: String,
    configuration: MarkdownRendererConfiguration = .document
) -> (snapshot: MarkdownSnapshot, prepared: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
    var configuration = configuration
    if configuration.copyProvider == nil {
        configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)
    }
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    return (snapshot, prepared, configuration)
}

private let testRect = CGRect(x: 0, y: 0, width: 400, height: 200)

private struct RectOrigin: Hashable {
    let x: CGFloat
    let y: CGFloat
    init(_ rect: CGRect) { x = rect.minX; y = rect.minY }
}

// MARK: - Part 01: Table cell selection tests

@Suite(.serialized)
struct MarkdownTableCellSelectionTests {
    @Test
    @MainActor
    func tableCellWithInlineLayoutPublishesTextGeometryFragments() throws {
        let source = """
        | Header A | Header B |
        |----------|----------|
        | Cell A1  | Cell B1  |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: tableBlock,
            preparedContent: tableContent,
            rect: testRect
        )

        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func emitsTextLeafSelectionFragmentsChecksSelectionInlineLayoutForTables() throws {
        let source = """
        | Header | Value |
        |--------|-------|
        | Key    | Data  |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])

        #expect(tableContent.emitsTextLeafSelectionFragments)
    }

    @Test
    @MainActor
    func tableCellFragmentsHaveDistinctRects() throws {
        let source = """
        | Alpha | Beta |
        |-------|------|
        | 1     | 2    |
        | 3     | 4    |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: tableBlock,
            preparedContent: tableContent,
            rect: testRect
        )

        #expect(fragments.count >= 6)
        let rects = fragments.map { $0.rect }
        let uniqueOrigins = Set(rects.map { RectOrigin($0) })
        #expect(uniqueOrigins.count > 1)
    }

    @Test
    @MainActor
    func tableCellFragmentsCoverAllCells() throws {
        let source = """
        | H1 | H2 |
        |----|----|
        | A  | B  |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])
        let table = try #require(tableContent.table)

        let allCells = table.header + table.rows.flatMap(\.cells)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: tableBlock,
            preparedContent: tableContent,
            rect: testRect
        )

        for cellRange in allCells.map({ $0.sourceRange.byteRange }) {
            let hasOverlap = fragments.contains {
                $0.sourceRange.byteRange.overlaps(cellRange)
            }
            #expect(hasOverlap, "No fragment overlaps cell source range \(cellRange)")
        }
    }

    @Test
    @MainActor
    func tableCellWithoutInlineLayoutHasSelectionInlineLayoutPrepared() throws {
        let source = """
        | Header | Value |
        |--------|-------|
        | Key    | Data  |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])
        let table = try #require(tableContent.table)

        let allCells = table.header + table.rows.flatMap(\.cells)
        let cellsWithLayout = allCells.filter { $0.inlineLayout != nil || $0.selectionInlineLayout != nil }
        #expect(!cellsWithLayout.isEmpty)
    }
}

// MARK: - Part 02: List item selection tests

@Suite(.serialized)
struct MarkdownListItemSelectionTests {
    @Test
    @MainActor
    func listItemWithInlineLayoutPublishesTextGeometryFragments() throws {
        let source = """
        - First item with text
        - Second item with text
        - Third item with text
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )

        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func nestedListItemPublishesTextLeafFragments() throws {
        let source = """
        - Top level
          - Nested item
          - Another nested
        - Back to top
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )

        #expect(fragments.count >= 4)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func emitsTextLeafSelectionFragmentsChecksSelectionInlineLayoutForLists() throws {
        let source = """
        - Item one
        - Item two
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        #expect(listContent.emitsTextLeafSelectionFragments)
    }

    @Test
    @MainActor
    func listItemFragmentsHaveDistinctRects() throws {
        let source = """
        - First
        - Second
        - Third
        - Fourth
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )

        #expect(fragments.count >= 4)
        let origins = Set(fragments.map { RectOrigin($0.rect) })
        #expect(origins.count > 1)
    }

    @Test
    @MainActor
    func listItemFragmentsCoverAllItems() throws {
        let source = """
        - Alpha
        - Beta
        - Gamma
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )

        for itemRange in listContent.listItems.map({ $0.sourceRange.byteRange }) {
            let hasOverlap = fragments.contains {
                $0.sourceRange.byteRange.overlaps(itemRange)
            }
            #expect(hasOverlap, "No fragment overlaps item source range \(itemRange)")
        }
    }

    @Test
    @MainActor
    func taskListItemsPublishTextGeometryFragments() throws {
        let source = """
        - [x] Completed task
        - [ ] Pending task
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .taskList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )

        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }
}

// MARK: - Part 03: Code block selection tests

@Suite(.serialized)
struct MarkdownCodeBlockSelectionTests {
    @Test
    @MainActor
    func fragmentsChecksSelectionInlineLayout() throws {
        let source = """
        ```swift
        let x = 42
        let y = "hello"
        ```
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let codeBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .codeBlock }))
        let codeContent = try #require(prepared.preparedContentByBlockID[codeBlock.id])

        #expect(codeContent.inlineLayout == nil)
        #expect(codeContent.selectionInlineLayout != nil)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: codeBlock,
            preparedContent: codeContent,
            rect: testRect
        )

        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func codeBlockWithHeaderPublishesTextLeafFragments() throws {
        let source = """
        ```python title="example.py"
        def hello():
            print("world")
        ```
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let codeBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .codeBlock }))
        let codeContent = try #require(prepared.preparedContentByBlockID[codeBlock.id])

        #expect(codeContent.emitsTextLeafSelectionFragments)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: codeBlock,
            preparedContent: codeContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
    }

    @Test
    @MainActor
    func codeBlockSelectionInlineLayoutProducesMultipleLineFragments() throws {
        let source = """
        ```
        line one
        line two
        line three
        ```
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let codeBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .codeBlock }))
        let codeContent = try #require(prepared.preparedContentByBlockID[codeBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: codeBlock,
            preparedContent: codeContent,
            rect: testRect
        )

        #expect(fragments.count >= 3)
    }

    @Test
    @MainActor
    func policyDeniedCodeBlockPublishesSourceBackedFragments() throws {
        var configuration = MarkdownRendererConfiguration.document
        configuration.codePolicy = DenyAllCodePolicy()

        let source = """
        ```swift
        let x = 42
        ```
        """
        let (_, prepared, _) = prepareSnapshot(source, configuration: configuration)
        let codeBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .codeBlock }))
        let codeContent = try #require(prepared.preparedContentByBlockID[codeBlock.id])

        #expect(codeContent.policyDenialReason != nil)
        #expect(!codeContent.emitsTextLeafSelectionFragments)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: codeBlock,
            preparedContent: codeContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.blockID == codeBlock.id })
    }

    @Test
    @MainActor
    func copyCodeBlockProducesCorrectSourceWithFences() throws {
        let source = """
        ```swift
        let x = 42
        ```
        """
        let (_, prepared, config) = prepareSnapshot(source)
        let codeBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .codeBlock }))

        let copied = config.copyProvider?.markdown(codeBlock.sourceRange)
        #expect(copied != nil)
        #expect(copied?.contains("```") == true)
        #expect(copied?.contains("let x = 42") == true)
    }
}

// MARK: - Part 04: Math block selection tests

@Suite(.serialized)
struct MarkdownMathBlockSelectionTests {
    @Test
    @MainActor
    func textMathBlockPublishesTextLeafFragments() throws {
        let source = "$$E = mc^2$$\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let mathBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .mathBlock }))
        let mathContent = try #require(prepared.preparedContentByBlockID[mathBlock.id])

        #expect(mathContent.selectionInlineLayout != nil)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: mathBlock,
            preparedContent: mathContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func policyDeniedMathBlockPublishesSourceBackedFragments() throws {
        var configuration = MarkdownRendererConfiguration.document
        configuration.mathPolicy = DenyAllMathPolicy()

        let source = "$$E = mc^2$$\n"
        let (_, prepared, _) = prepareSnapshot(source, configuration: configuration)
        let mathBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .mathBlock }))
        let mathContent = try #require(prepared.preparedContentByBlockID[mathBlock.id])

        #expect(mathContent.policyDenialReason != nil)

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: mathBlock,
            preparedContent: mathContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.sourceRange == mathBlock.sourceRange })
    }

    @Test
    @MainActor
    func mathSelectionSourceRangeIncludesDelimiters() throws {
        let source = "$$E = mc^2$$\n"
        let (_, prepared, config) = prepareSnapshot(source)
        let mathBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .mathBlock }))

        let copied = config.copyProvider?.markdown(mathBlock.sourceRange)
        #expect(copied?.contains("$$") == true)
        #expect(copied?.contains("E = mc^2") == true)
    }

    @Test
    @MainActor
    func bracketMathBlockPublishesTextLeafFragments() throws {
        let source = "\\[E = mc^2\\]\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let mathBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .mathBlock }))
        let mathContent = try #require(prepared.preparedContentByBlockID[mathBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: mathBlock,
            preparedContent: mathContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
    }
}

// MARK: - Part 05: Cross-block selection tests

@Suite(.serialized)
struct MarkdownCrossBlockSelectionTests {
    @Test
    @MainActor
    func paragraphFragmentsHaveTextGeometry() throws {
        let source = "This is a paragraph with enough text to produce inline layout.\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let block = try #require(prepared.snapshot.blocks.first)
        let content = try #require(prepared.preparedContentByBlockID[block.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.textGeometry != nil })
    }

    @Test
    @MainActor
    func headingFragmentsHaveTextGeometry() throws {
        let source = "# Heading Text\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let block = try #require(prepared.snapshot.blocks.first)
        let content = try #require(prepared.preparedContentByBlockID[block.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.textGeometry != nil })
    }

    @Test
    @MainActor
    func blockQuoteFragmentsHaveTextGeometry() throws {
        let source = "> This is a block quote with text.\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let block = try #require(prepared.snapshot.blocks.first)
        let content = try #require(prepared.preparedContentByBlockID[block.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0.textGeometry != nil })
    }

    @Test
    @MainActor
    func allBlockTypesInMixedDocumentProduceFragments() throws {
        let source = """
        # Title

        A paragraph with text.

        - List item one
        - List item two

        | Col A | Col B |
        |-------|-------|
        | 1     | 2     |

        ```swift
        let x = 42
        ```

        $$E = mc^2$$
        """
        let (_, prepared, _) = prepareSnapshot(source)

        for block in prepared.snapshot.blocks {
            let content = try #require(prepared.preparedContentByBlockID[block.id])
            let fragments = MarkdownDocumentSelectionFragment.fragments(
                for: block,
                preparedContent: content,
                rect: testRect
            )
            #expect(!fragments.isEmpty, "Block of kind \(block.kind) produced no fragments")
            #expect(fragments.allSatisfy { $0.blockID == block.id })
        }
    }

    @Test
    @MainActor
    func orderedListItemsPublishTextGeometryFragments() throws {
        let source = """
        1. First ordered item
        2. Second ordered item
        3. Third ordered item
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .orderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func htmlBlockFragmentsHaveTextGeometry() throws {
        var configuration = MarkdownRendererConfiguration.document
        configuration.htmlPolicy = AllowAllHTMLPolicy()

        let source = "<div>Hello world</div>\n"
        let (_, prepared, _) = prepareSnapshot(source, configuration: configuration)
        let block = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .htmlBlock }))
        let content = try #require(prepared.preparedContentByBlockID[block.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: testRect
        )
        #expect(!fragments.isEmpty)
        let fragmentsWithTextGeometry = fragments.filter { $0.textGeometry != nil }
        #expect(!fragmentsWithTextGeometry.isEmpty)
    }

    @Test
    @MainActor
    func emitsTextLeafSelectionFragmentsIsAccurateForAllBlockTypes() throws {
        let source = """
        # Title

        Paragraph text.

        - List item

        | A | B |
        |---|---|
        | 1 | 2 |

        ```swift
        let x = 42
        ```
        """
        let (_, prepared, _) = prepareSnapshot(source)

        for block in prepared.snapshot.blocks {
            let content = try #require(prepared.preparedContentByBlockID[block.id])
            #expect(
                content.emitsTextLeafSelectionFragments,
                "Block of kind \(block.kind) should emit text-leaf selection fragments"
            )
        }
    }
}

// MARK: - Part 01 (continued): Table cell drag/copy tests

extension MarkdownTableCellSelectionTests {
    @Test
    @MainActor
    func dragSelectionAcrossTableCellsProducesContiguousRange() throws {
        let source = """
        | Alpha | Beta |
        |-------|------|
        | A1    | B1   |
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: tableBlock,
            preparedContent: tableContent,
            rect: testRect
        ).sortedForSelection()

        #expect(fragments.count >= 2)
        guard let first = fragments.first, let last = fragments.last, first.id != last.id else { return }

        let (ranges, blockIDs) = MarkdownDocumentSelectionFragment.selection(
            from: first,
            to: last,
            in: fragments
        )

        #expect(!ranges.isEmpty)
        #expect(blockIDs.contains(tableBlock.id))
        #expect(ranges.first?.byteRange.lowerBound == first.sourceRange.byteRange.lowerBound)
        #expect(ranges.first?.byteRange.upperBound == last.sourceRange.byteRange.upperBound)
    }

    @Test
    @MainActor
    func copyFirstTableCellProducesCorrectMarkdownSource() throws {
        let source = """
        | Alpha | Beta |
        |-------|------|
        | A1    | B1   |
        """
        let (_, prepared, config) = prepareSnapshot(source)
        let tableBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .table }))
        let tableContent = try #require(prepared.preparedContentByBlockID[tableBlock.id])
        let table = try #require(tableContent.table)

        let firstHeaderCell = try #require(table.header.first)
        let copied = config.copyProvider?.markdown(firstHeaderCell.sourceRange)
        #expect(copied != nil)
        #expect(copied?.contains("Alpha") == true)
    }
}

// MARK: - Part 02 (continued): List item drag/copy tests

extension MarkdownListItemSelectionTests {
    @Test
    @MainActor
    func dragSelectionAcrossListItemsProducesContiguousRange() throws {
        let source = """
        - First item
        - Second item
        - Third item
        """
        let (_, prepared, _) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: listBlock,
            preparedContent: listContent,
            rect: testRect
        ).sortedForSelection()

        #expect(fragments.count >= 2)
        guard let first = fragments.first, let last = fragments.last, first.id != last.id else { return }

        let (ranges, blockIDs) = MarkdownDocumentSelectionFragment.selection(
            from: first,
            to: last,
            in: fragments
        )

        #expect(!ranges.isEmpty)
        #expect(blockIDs.contains(listBlock.id))
        #expect(ranges.first?.byteRange.lowerBound == first.sourceRange.byteRange.lowerBound)
        #expect(ranges.first?.byteRange.upperBound == last.sourceRange.byteRange.upperBound)
    }

    @Test
    @MainActor
    func copyFirstListItemProducesCorrectMarkdownSource() throws {
        let source = """
        - Alpha item
        - Beta item
        """
        let (_, prepared, config) = prepareSnapshot(source)
        let listBlock = try #require(prepared.snapshot.blocks.first(where: { $0.kind == .unorderedList }))
        let listContent = try #require(prepared.preparedContentByBlockID[listBlock.id])

        let firstItem = try #require(listContent.listItems.first)
        let copied = config.copyProvider?.markdown(firstItem.sourceRange)
        #expect(copied != nil)
        #expect(copied?.contains("Alpha") == true)
    }
}

// MARK: - Part 05 (continued): Cross-block drag/highlight/copy tests

extension MarkdownCrossBlockSelectionTests {
    @Test
    @MainActor
    func dragSelectionAcrossParagraphAndCodeBlockProducesContiguousRange() throws {
        let source = """
        First paragraph.

        ```
        code line
        ```

        Second paragraph.
        """
        let (_, prepared, _) = prepareSnapshot(source)

        var allFragments: [MarkdownDocumentSelectionFragment] = []
        var yOffset: CGFloat = 0
        for block in prepared.snapshot.blocks {
            guard let content = prepared.preparedContentByBlockID[block.id] else { continue }
            let blockRect = CGRect(x: 0, y: yOffset, width: 400, height: 50)
            allFragments.append(contentsOf: MarkdownDocumentSelectionFragment.fragments(
                for: block,
                preparedContent: content,
                rect: blockRect
            ))
            yOffset += 60
        }
        allFragments = allFragments.sortedForSelection()

        #expect(allFragments.count >= 3)
        guard let first = allFragments.first, let last = allFragments.last, first.id != last.id else { return }

        let (ranges, blockIDs) = MarkdownDocumentSelectionFragment.selection(
            from: first,
            to: last,
            in: allFragments
        )

        #expect(!ranges.isEmpty)
        #expect(blockIDs.count == prepared.snapshot.blocks.count)
        #expect(ranges.first?.byteRange.lowerBound == first.sourceRange.byteRange.lowerBound)
        #expect(ranges.first?.byteRange.upperBound == last.sourceRange.byteRange.upperBound)
    }

    @Test
    @MainActor
    func textGeometryFragmentHighlightIsNarrowerThanBlockRect() throws {
        let source = "Hi.\n"
        let (_, prepared, _) = prepareSnapshot(source)
        let block = try #require(prepared.snapshot.blocks.first)
        let content = try #require(prepared.preparedContentByBlockID[block.id])

        let fragments = MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: content,
            rect: testRect
        )
        let fragment = try #require(fragments.first)
        #expect(fragment.textGeometry != nil, "Short-text fragment must carry text geometry for highlight clipping (INV-S4)")

        let highlights = fragment.highlightRects(for: [fragment.sourceRange])
        let highlight = try #require(highlights.first)
        #expect(highlight.rect.width < testRect.width, "Highlight for short text must be narrower than block rect (INV-S4)")
    }

    @Test
    @MainActor
    func copyAcrossParagraphAndCodeBlockProducesCorrectMarkdown() throws {
        let source = """
        Intro paragraph.

        ```
        code here
        ```

        Closing paragraph.
        """
        let (_, prepared, config) = prepareSnapshot(source)

        let blocks = prepared.snapshot.blocks
        #expect(blocks.count >= 3)
        guard blocks.count >= 3 else { return }

        let fullRange = MarkdownSourceRange(
            byteRange: blocks[0].sourceRange.byteRange.lowerBound..<blocks[blocks.count - 1].sourceRange.byteRange.upperBound,
            lineRange: blocks[0].sourceRange.lineRange.lowerBound..<blocks[blocks.count - 1].sourceRange.lineRange.upperBound
        )

        let copied = config.copyProvider?.markdown(fullRange)
        #expect(copied != nil)
        #expect(copied?.contains("Intro paragraph") == true)
        #expect(copied?.contains("code here") == true)
        #expect(copied?.contains("Closing paragraph") == true)
    }
}

// MARK: - Test policies

private struct DenyAllCodePolicy: MarkdownCodePolicy, MarkdownCodePolicyCacheIdentifying {
    var codePolicyCacheIdentity: String { "test.deny-all-code" }
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision {
        .deny(reason: "Code blocks are denied for testing")
    }
}

private struct DenyAllMathPolicy: MarkdownMathPolicy, MarkdownMathPolicyCacheIdentifying {
    var mathPolicyCacheIdentity: String { "test.deny-all-math" }
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .deny(reason: "Math blocks are denied for testing")
    }
}

private struct AllowAllHTMLPolicy: MarkdownHTMLPolicy, MarkdownHTMLPolicyCacheIdentifying {
    var htmlPolicyCacheIdentity: String { "test.allow-all-html" }
    func evaluateHTML(_ source: String) -> MarkdownPolicyDecision {
        .allow
    }
}
