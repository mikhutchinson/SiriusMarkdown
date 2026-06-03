import Foundation
import Markdown

public struct SwiftMarkdownParser: Sendable {
    public init() {}

    public func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        referenceDefinitionsPrefix: String = ""
    ) -> [MarkdownBlock] {
        let sliceText = slice.text
        let source = referenceDefinitionsPrefix + sliceText
        guard !source.isEmpty else {
            return []
        }

        let document = Document(parsing: source, options: [.disableSmartOpts])
        let baseOffset = slice.byteRange.lowerBound - referenceDefinitionsPrefix.utf8.count
        return SwiftMarkdownRenderModelConverter(
            source: source,
            baseOffset: baseOffset,
            lineMap: lineMap,
            idNamespace: idNamespace,
            isSealed: isSealed,
            referenceDefinitionsPrefix: referenceDefinitionsPrefix
        ).convert(document)
    }
}

private struct SwiftMarkdownRenderModelConverter {
    var source: String
    var baseOffset: Int
    var lineMap: MarkdownLineMap
    var idNamespace: String
    var isSealed: Bool
    var referenceDefinitionsPrefix: String
    var allowParagraphDisplayMathSplitting: Bool = true

    private var sliceByteCount: Int {
        source.utf8.count
    }

    func convert(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var sequence = 0
        for child in document.children {
            let converted = convertBlocks(child, sequence: sequence)
            blocks.append(contentsOf: converted)
            sequence += converted.count
        }
        return blocks
    }

    private func convertBlocks(_ markup: Markup, sequence: Int) -> [MarkdownBlock] {
        if allowParagraphDisplayMathSplitting,
           let paragraph = markup as? Paragraph,
           let splitBlocks = displayMathSplitBlocks(for: paragraph, sequence: sequence) {
            return splitBlocks
        }

        return [convertBlock(markup, sequence: sequence)]
    }

    private func convertBlock(_ markup: Markup, sequence: Int) -> MarkdownBlock {
        let range = markdownSourceRange(for: markup)
        let rawText = sourceText(for: range.byteRange)
        let kind = blockKind(for: markup, rawText: rawText)
        let inlines = inlineRuns(for: markup, fallbackRange: range)
        let contentHash = stableContentHash(rawText)
        let id = stableBlockID(kind: kind, range: range, sequence: sequence)

        return MarkdownBlock(
            id: id,
            kind: kind,
            sourceRange: range,
            text: displayText(for: markup, rawText: rawText),
            inlines: inlines,
            listItems: listItems(for: markup),
            table: tableBlock(for: markup),
            contentHash: contentHash,
            orderedListStart: (markup as? OrderedList)?.startIndex,
            headingLevel: (markup as? Heading)?.level,
            infoString: (markup as? CodeBlock)?.language,
            isSealed: isSealed
        )
    }

    private func blockKind(for markup: Markup, rawText: String) -> MarkdownBlockKind {
        switch markup {
        case is Heading:
            return .heading
        case is CodeBlock:
            return .codeBlock
        case is BlockQuote:
            return .blockQuote
        case is ThematicBreak:
            return .thematicBreak
        case is HTMLBlock:
            return .htmlBlock
        case let list as UnorderedList:
            return listContainsTaskItems(list) ? .taskList : .unorderedList
        case let list as OrderedList:
            return listContainsTaskItems(list) ? .taskList : .orderedList
        case is Table:
            return .table
        case is Paragraph where MarkdownMathDelimiterScanner.blockContent(in: rawText) != nil:
            return .mathBlock
        case is Paragraph:
            return .paragraph
        default:
            return .paragraph
        }
    }

    private func displayText(for markup: Markup, rawText: String) -> String {
        switch markup {
        case let codeBlock as CodeBlock:
            return codeBlock.code
        case let htmlBlock as HTMLBlock:
            return htmlBlock.rawHTML
        case is ThematicBreak:
            return ""
        default:
            return rawText
        }
    }

    private func inlineRuns(for markup: Markup, fallbackRange: MarkdownSourceRange) -> [MarkdownInlineRun] {
        switch markup {
        case let heading as Heading:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: heading.children)
        case let paragraph as Paragraph:
            if let mathContent = MarkdownMathDelimiterScanner.blockContent(in: sourceText(for: fallbackRange.byteRange)) {
                return [
                    MarkdownInlineRun(
                        kind: .math,
                        text: mathContent,
                        sourceRange: fallbackRange
                    )
                ]
            }
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: paragraph.children)
        case let quote as BlockQuote:
            return blockContainerInlineRuns(in: quote.children, fallbackRange: fallbackRange)
        case let list as UnorderedList:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: list.children)
        case let list as OrderedList:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: list.children)
        case let table as Table:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: table.children)
        default:
            return []
        }
    }

    private func displayMathSplitBlocks(for paragraph: Paragraph, sequence: Int) -> [MarkdownBlock]? {
        let paragraphRange = markdownSourceRange(for: paragraph)
        let rawText = sourceText(for: paragraphRange.byteRange)
        let spans = MarkdownMathDelimiterScanner.standaloneDisplayMathSpans(in: rawText)
        guard !spans.isEmpty else {
            return nil
        }

        if spans.count == 1,
           MarkdownMathDelimiterScanner.spanCoversTrimmedText(spans[0], in: rawText) {
            return nil
        }

        var blocks: [MarkdownBlock] = []
        var cursor = rawText.startIndex

        func appendParagraphSegment(_ localRange: Range<String.Index>) {
            guard let trimmedRange = trimmedNonEmptyRange(in: rawText, localRange: localRange) else {
                return
            }

            let segmentRange = sourceRange(
                in: rawText,
                localRange: trimmedRange,
                baseRange: paragraphRange
            )
            let segmentText = String(rawText[trimmedRange])
            let source = referenceDefinitionsPrefix + segmentText
            let document = Document(parsing: source, options: [.disableSmartOpts])
            let segmentBlocks = SwiftMarkdownRenderModelConverter(
                source: source,
                baseOffset: segmentRange.byteRange.lowerBound - referenceDefinitionsPrefix.utf8.count,
                lineMap: lineMap,
                idNamespace: idNamespace,
                isSealed: isSealed,
                referenceDefinitionsPrefix: referenceDefinitionsPrefix,
                allowParagraphDisplayMathSplitting: false
            ).convert(document)

            if segmentBlocks.isEmpty {
                blocks.append(
                    MarkdownBlock(
                        id: stableBlockID(kind: .paragraph, range: segmentRange, sequence: sequence + blocks.count),
                        kind: .paragraph,
                        sourceRange: segmentRange,
                        text: segmentText,
                        inlines: [
                            MarkdownInlineRun(kind: .text, text: segmentText, sourceRange: segmentRange)
                        ],
                        contentHash: stableContentHash(segmentText),
                        isSealed: isSealed
                    )
                )
            } else {
                blocks.append(contentsOf: segmentBlocks)
            }
        }

        for span in spans {
            appendParagraphSegment(cursor..<span.full.lowerBound)
            blocks.append(mathBlock(from: span, in: rawText, paragraphRange: paragraphRange, sequence: sequence + blocks.count))
            cursor = span.full.upperBound
        }

        appendParagraphSegment(cursor..<rawText.endIndex)
        return blocks.isEmpty ? nil : blocks
    }

    private func mathBlock(
        from span: MarkdownMathDelimiterScanner.DisplayMathSpan,
        in rawText: String,
        paragraphRange: MarkdownSourceRange,
        sequence: Int
    ) -> MarkdownBlock {
        let range = sourceRange(in: rawText, localRange: span.full, baseRange: paragraphRange)
        let contentRange = sourceRange(in: rawText, localRange: span.content, baseRange: paragraphRange)
        let text = String(rawText[span.full])
        let math = String(rawText[span.content]).trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownBlock(
            id: stableBlockID(kind: .mathBlock, range: range, sequence: sequence),
            kind: .mathBlock,
            sourceRange: range,
            text: text,
            inlines: [
                MarkdownInlineRun(kind: .math, text: math, sourceRange: contentRange)
            ],
            contentHash: stableContentHash(text),
            isSealed: isSealed
        )
    }

    private func inlineRunConverter(fallbackRange: MarkdownSourceRange) -> InlineRunConverter {
        InlineRunConverter(
            source: source,
            baseOffset: baseOffset,
            lineMap: lineMap,
            fallbackRange: fallbackRange
        )
    }

    private func listContainsTaskItems(_ list: Markup) -> Bool {
        list.children.contains { child in
            (child as? ListItem)?.checkbox != nil
        }
    }

    private func listItems(for markup: Markup) -> [MarkdownListItem] {
        switch markup {
        case let list as UnorderedList:
            return list.children.compactMap { ($0 as? ListItem).map(markdownListItem) }
        case let list as OrderedList:
            return list.children.compactMap { ($0 as? ListItem).map(markdownListItem) }
        default:
            return []
        }
    }

    private func markdownListItem(_ item: ListItem) -> MarkdownListItem {
        let range = markdownSourceRange(for: item)
        let nestedMetadata = nestedListMetadata(in: item)
        let inlines = listItemInlineRuns(in: item, fallbackRange: range)
        return MarkdownListItem(
            sourceRange: range,
            taskState: taskState(for: item.checkbox),
            text: inlines.map(\.text).joined(),
            inlines: inlines,
            childListKind: nestedMetadata.kind,
            childOrderedListStart: nestedMetadata.orderedStart,
            childItems: nestedListItems(in: item)
        )
    }

    private func listItemInlineRuns(in item: ListItem, fallbackRange: MarkdownSourceRange) -> [MarkdownInlineRun] {
        let converter = inlineRunConverter(fallbackRange: fallbackRange)
        let inlineChildren = Array(item.children).filter { child in
            !(child is UnorderedList) && !(child is OrderedList)
        }

        return inlineChildren.enumerated().flatMap { index, child -> [MarkdownInlineRun] in
            var runs: [MarkdownInlineRun]
            switch child {
            case let paragraph as Paragraph:
                runs = converter.runs(in: paragraph.children)
            default:
                runs = blockInlineRuns(for: child, fallbackRange: fallbackRange)
            }

            if index < inlineChildren.count - 1, !runs.isEmpty {
                runs.append(
                    MarkdownInlineRun(
                        kind: .hardBreak,
                        text: "\n",
                        sourceRange: runs.last?.sourceRange ?? fallbackRange
                    )
                )
            }
            return runs
        }
    }

    private func blockContainerInlineRuns(
        in children: MarkupChildren,
        fallbackRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        let childArray = Array(children)
        return childArray.enumerated().flatMap { index, child -> [MarkdownInlineRun] in
            var runs = blockInlineRuns(for: child, fallbackRange: fallbackRange)
            if index < childArray.count - 1, !runs.isEmpty {
                runs.append(
                    MarkdownInlineRun(
                        kind: .hardBreak,
                        text: "\n",
                        sourceRange: runs.last?.sourceRange ?? fallbackRange
                    )
                )
            }
            return runs
        }
    }

    private func blockInlineRuns(
        for markup: Markup,
        fallbackRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        let converter = inlineRunConverter(fallbackRange: fallbackRange)
        switch markup {
        case let paragraph as Paragraph:
            return converter.runs(in: paragraph.children)
        case let heading as Heading:
            return converter.runs(in: heading.children)
        case let codeBlock as CodeBlock:
            return [
                MarkdownInlineRun(
                    kind: .code,
                    text: codeBlock.code,
                    sourceRange: markdownSourceRange(for: codeBlock)
                )
            ]
        case let htmlBlock as HTMLBlock:
            return [
                MarkdownInlineRun(
                    kind: .text,
                    text: htmlBlock.rawHTML,
                    sourceRange: markdownSourceRange(for: htmlBlock),
                    presentation: .html
                )
            ]
        case let table as Table:
            return tableInlineRuns(table, fallbackRange: fallbackRange)
        case let list as UnorderedList:
            let items = Array(list.children).compactMap { $0 as? ListItem }
            return items.enumerated().flatMap { index, item in
                var runs = listItemInlineRuns(in: item, fallbackRange: markdownSourceRange(for: item))
                if index < items.count - 1, !runs.isEmpty {
                    runs.append(MarkdownInlineRun(kind: .hardBreak, text: "\n", sourceRange: markdownSourceRange(for: item)))
                }
                return runs
            }
        case let list as OrderedList:
            let items = Array(list.children).compactMap { $0 as? ListItem }
            return items.enumerated().flatMap { index, item in
                var runs = listItemInlineRuns(in: item, fallbackRange: markdownSourceRange(for: item))
                if index < items.count - 1, !runs.isEmpty {
                    runs.append(MarkdownInlineRun(kind: .hardBreak, text: "\n", sourceRange: markdownSourceRange(for: item)))
                }
                return runs
            }
        default:
            return converter.runs(in: markup.children)
        }
    }

    private func tableInlineRuns(
        _ table: Table,
        fallbackRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        let rows = [table.head.cells] + table.body.rows.map(\.cells)
        for (rowIndex, row) in rows.enumerated() {
            let cells = Array(row)
            for (cellIndex, cell) in cells.enumerated() {
                runs.append(contentsOf: inlineRunConverter(fallbackRange: fallbackRange).runs(in: cell.children))
                if cellIndex < cells.count - 1 {
                    runs.append(MarkdownInlineRun(kind: .text, text: " | ", sourceRange: markdownSourceRange(for: cell)))
                }
            }
            if rowIndex < rows.count - 1 {
                runs.append(MarkdownInlineRun(kind: .hardBreak, text: "\n", sourceRange: fallbackRange))
            }
        }
        return runs
    }

    private func nestedListMetadata(in item: ListItem) -> (kind: MarkdownBlockKind?, orderedStart: UInt?) {
        for child in item.children {
            if let list = child as? UnorderedList {
                return (listContainsTaskItems(list) ? .taskList : .unorderedList, nil)
            }

            if let list = child as? OrderedList {
                return (listContainsTaskItems(list) ? .taskList : .orderedList, list.startIndex)
            }
        }

        return (nil, nil)
    }

    private func nestedListItems(in item: ListItem) -> [MarkdownListItem] {
        item.children.flatMap { child -> [MarkdownListItem] in
            switch child {
            case let list as UnorderedList:
                return list.children.compactMap { ($0 as? ListItem).map(markdownListItem) }
            case let list as OrderedList:
                return list.children.compactMap { ($0 as? ListItem).map(markdownListItem) }
            default:
                return []
            }
        }
    }

    private func taskState(for checkbox: Checkbox?) -> MarkdownTaskState? {
        switch checkbox {
        case .checked:
            return .checked
        case .unchecked:
            return .unchecked
        case nil:
            return nil
        }
    }

    private func tableBlock(for markup: Markup) -> MarkdownTableBlock? {
        guard let table = markup as? Table else {
            return nil
        }

        return MarkdownTableBlock(
            columnAlignments: table.columnAlignments.map(tableColumnAlignment),
            header: table.head.cells.map(markdownTableCell),
            rows: table.body.rows.map { row in
                row.cells.map(markdownTableCell)
            }
        )
    }

    private func markdownTableCell(_ cell: Table.Cell) -> MarkdownTableCell {
        let range = markdownSourceRange(for: cell)
        let inlines = inlineRunConverter(fallbackRange: range).runs(in: cell.children)
        return MarkdownTableCell(
            sourceRange: range,
            text: inlines.map(\.text).joined(),
            inlines: inlines,
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
    }

    private func tableColumnAlignment(_ alignment: Table.ColumnAlignment?) -> MarkdownTableColumnAlignment? {
        switch alignment {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        case nil:
            return nil
        }
    }

    private func stableBlockID(
        kind: MarkdownBlockKind,
        range: MarkdownSourceRange,
        sequence _: Int
    ) -> MarkdownBlockID {
        let stableSequence = max(0, lineMap.lineNumber(containingByteOffset: range.byteRange.lowerBound) - 1)
        return MarkdownBlockID("\(idNamespace):\(range.byteRange.lowerBound):\(stableSequence):\(kind.rawValue)")
    }

    private func markdownSourceRange(for markup: Markup) -> MarkdownSourceRange {
        let byteRange: Range<Int>
        if let sourceRange = markup.range {
            byteRange = clampedByteRange(
                lower: byteOffset(for: sourceRange.lowerBound),
                upper: byteOffset(for: sourceRange.upperBound)
            )
        } else {
            byteRange = baseOffset..<(baseOffset + sliceByteCount)
        }

        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func byteOffset(for location: SourceLocation) -> Int {
        var lineStart = baseOffset
        if location.line > 1 {
            var remainingNewlines = location.line - 1
            var cursor = source.utf8.startIndex

            while cursor < source.utf8.endIndex, remainingNewlines > 0 {
                if source.utf8[cursor] == 10 {
                    remainingNewlines -= 1
                    if remainingNewlines == 0 {
                        lineStart = baseOffset + source.utf8.distance(from: source.utf8.startIndex, to: source.utf8.index(after: cursor))
                        break
                    }
                }
                cursor = source.utf8.index(after: cursor)
            }
        }

        return lineStart + max(0, location.column - 1)
    }

    private func clampedByteRange(lower: Int, upper: Int) -> Range<Int> {
        let sliceLower = baseOffset
        let sliceUpper = baseOffset + sliceByteCount
        let clampedLower = min(max(lower, sliceLower), sliceUpper)
        let clampedUpper = min(max(upper, clampedLower), sliceUpper)
        return clampedLower..<clampedUpper
    }

    private func sourceText(for byteRange: Range<Int>) -> String {
        let localLower = max(0, byteRange.lowerBound - baseOffset)
        let localUpper = min(sliceByteCount, byteRange.upperBound - baseOffset)
        guard localLower < localUpper else {
            return ""
        }

        let lower = source.utf8.index(source.utf8.startIndex, offsetBy: localLower)
        let upper = source.utf8.index(source.utf8.startIndex, offsetBy: localUpper)
        return String(decoding: source.utf8[lower..<upper], as: UTF8.self)
    }

    private func stableContentHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private func sourceRange(
        in text: String,
        localRange: Range<String.Index>,
        baseRange: MarkdownSourceRange
    ) -> MarkdownSourceRange {
        let lowerOffset = text.utf8.distance(
            from: text.utf8.startIndex,
            to: localRange.lowerBound.samePosition(in: text.utf8) ?? text.utf8.startIndex
        )
        let upperOffset = text.utf8.distance(
            from: text.utf8.startIndex,
            to: localRange.upperBound.samePosition(in: text.utf8) ?? text.utf8.endIndex
        )
        let byteRange = (baseRange.byteRange.lowerBound + lowerOffset)..<(baseRange.byteRange.lowerBound + upperOffset)
        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func trimmedNonEmptyRange(
        in text: String,
        localRange: Range<String.Index>
    ) -> Range<String.Index>? {
        var lower = localRange.lowerBound
        var upper = localRange.upperBound

        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }

        while lower < upper {
            let beforeUpper = text.index(before: upper)
            guard text[beforeUpper].isWhitespace else {
                break
            }
            upper = beforeUpper
        }

        return lower < upper ? lower..<upper : nil
    }
}

private struct MarkdownMathDelimiterScanner {
    struct DisplayMathSpan {
        var full: Range<String.Index>
        var content: Range<String.Index>
    }

    static func blockContent(in rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("\\begin{"), trimmed.hasSuffix("}"), trimmed.contains("\\end{") {
            return trimmed
        }

        if let stripped = strippedMathDelimiters(trimmed, open: "$$", close: "$$") {
            return stripped
        }

        if let stripped = strippedMathDelimiters(trimmed, open: "\\[", close: "\\]") {
            return stripped
        }

        if let stripped = strippedBareDisplayBrackets(trimmed), looksLikeTex(stripped) {
            return stripped
        }

        return nil
    }

    static func standaloneDisplayMathSpans(in text: String) -> [DisplayMathSpan] {
        var spans: [DisplayMathSpan] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if hasToken("\\[", in: text, at: cursor),
               let openUpper = text.index(cursor, offsetBy: 2, limitedBy: text.endIndex),
               isOnlyTokenOnLine(cursor..<openUpper, in: text),
               let close = closingStandaloneToken("\\]", in: text, after: openUpper) {
                spans.append(displaySpan(open: cursor..<openUpper, close: close, in: text))
                cursor = close.upperBound
                continue
            }

            if hasToken("$$", in: text, at: cursor),
               let openUpper = text.index(cursor, offsetBy: 2, limitedBy: text.endIndex),
               isOnlyTokenOnLine(cursor..<openUpper, in: text),
               let close = closingStandaloneToken("$$", in: text, after: openUpper) {
                spans.append(displaySpan(open: cursor..<openUpper, close: close, in: text))
                cursor = close.upperBound
                continue
            }

            if text[cursor] == "[",
               let openUpper = text.index(cursor, offsetBy: 1, limitedBy: text.endIndex),
               isOnlyTokenOnLine(cursor..<openUpper, in: text),
               let close = closingStandaloneToken("]", in: text, after: openUpper) {
                let span = displaySpan(open: cursor..<openUpper, close: close, in: text)
                if looksLikeTex(String(text[span.content])) {
                    spans.append(span)
                    cursor = close.upperBound
                    continue
                }
            }

            cursor = text.index(after: cursor)
        }

        return spans
    }

    static func spanCoversTrimmedText(_ span: DisplayMathSpan, in text: String) -> Bool {
        var lower = text.startIndex
        var upper = text.endIndex

        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }

        while lower < upper {
            let beforeUpper = text.index(before: upper)
            guard text[beforeUpper].isWhitespace else {
                break
            }
            upper = beforeUpper
        }

        return span.full.lowerBound == lower && span.full.upperBound == upper
    }

    private static func strippedMathDelimiters(_ trimmed: String, open: String, close: String) -> String? {
        guard trimmed.hasPrefix(open),
              trimmed.hasSuffix(close),
              trimmed.count >= open.count + close.count
        else {
            return nil
        }

        let start = trimmed.index(trimmed.startIndex, offsetBy: open.count)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -close.count)
        guard start <= end else {
            return nil
        }

        return String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippedBareDisplayBrackets(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("["),
              trimmed.hasSuffix("]"),
              let firstLineEnd = trimmed.firstIndex(where: { $0.isNewline }),
              let lastLineStart = trimmed.lastIndex(where: { $0.isNewline })
        else {
            return nil
        }

        let firstLine = trimmed[..<firstLineEnd].trimmingCharacters(in: .whitespaces)
        let lastLine = trimmed[trimmed.index(after: lastLineStart)...].trimmingCharacters(in: .whitespaces)
        guard firstLine == "[", lastLine == "]" else {
            return nil
        }

        return String(trimmed[trimmed.index(after: firstLineEnd)..<lastLineStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasToken(_ token: String, in text: String, at index: String.Index) -> Bool {
        text[index...].hasPrefix(token)
    }

    private static func closingStandaloneToken(
        _ token: String,
        in text: String,
        after lowerBound: String.Index
    ) -> Range<String.Index>? {
        var searchStart = lowerBound
        while searchStart < text.endIndex,
              let range = text.range(of: token, range: searchStart..<text.endIndex) {
            if isOnlyTokenOnLine(range, in: text) {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func displaySpan(
        open: Range<String.Index>,
        close: Range<String.Index>,
        in text: String
    ) -> DisplayMathSpan {
        let contentLower = startOfNextLine(after: open.upperBound, in: text) ?? open.upperBound
        let contentUpper = startOfLine(containing: close.lowerBound, in: text)
        return DisplayMathSpan(
            full: open.lowerBound..<close.upperBound,
            content: min(contentLower, contentUpper)..<max(contentLower, contentUpper)
        )
    }

    private static func isOnlyTokenOnLine(_ range: Range<String.Index>, in text: String) -> Bool {
        let lineStart = startOfLine(containing: range.lowerBound, in: text)
        var cursor = lineStart
        while cursor < range.lowerBound {
            guard text[cursor].isWhitespace, !text[cursor].isNewline else {
                return false
            }
            cursor = text.index(after: cursor)
        }

        cursor = range.upperBound
        while cursor < text.endIndex, !text[cursor].isNewline {
            guard text[cursor].isWhitespace else {
                return false
            }
            cursor = text.index(after: cursor)
        }

        return true
    }

    private static func startOfLine(containing index: String.Index, in text: String) -> String.Index {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if text[previous].isNewline {
                break
            }
            cursor = previous
        }
        return cursor
    }

    private static func startOfNextLine(after index: String.Index, in text: String) -> String.Index? {
        var cursor = index
        while cursor < text.endIndex {
            if text[cursor].isNewline {
                return text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    static func looksLikeTex(_ content: String) -> Bool {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return false
        }

        let commonCommands = [
            "\\frac", "\\lim", "\\sum", "\\int", "\\sqrt", "\\begin{", "\\end{",
            "\\left", "\\right", "\\sin", "\\cos", "\\tan", "\\log", "\\ln",
            "\\alpha", "\\beta", "\\gamma", "\\delta", "\\theta", "\\lambda",
            "\\rightarrow", "\\leftarrow", "\\infty"
        ]
        if commonCommands.contains(where: { body.contains($0) }) {
            return true
        }

        guard body.range(of: #"\\[A-Za-z]+(\*|\b)"#, options: .regularExpression) != nil else {
            return false
        }

        return body.contains("{") ||
            body.contains("}") ||
            body.contains("_") ||
            body.contains("^") ||
            body.contains("=")
    }
}

private struct InlineRunConverter {
    var source: String
    var baseOffset: Int
    var lineMap: MarkdownLineMap
    var fallbackRange: MarkdownSourceRange

    private enum DisplayMathRunDelimiter {
        case bracket
        case dollar
        case bareBracket
    }

    func runs(in children: MarkupChildren) -> [MarkdownInlineRun] {
        runs(in: children, presentation: [], destination: nil)
    }

    private func runs(
        in children: MarkupChildren,
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        let converted = children.flatMap {
            runs(in: $0, presentation: presentation, destination: destination)
        }
        return coalescedStandaloneDisplayMathRuns(converted)
    }

    private func runs(
        in markup: Markup,
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        switch markup {
        case let text as Markdown.Text:
            return textRuns(for: text, presentation: presentation, destination: destination)
        case let code as InlineCode:
            return [
                run(
                    kind: primaryKind(.code, destination: destination),
                    text: code.code,
                    markup: code,
                    destination: destination,
                    presentation: presentation.union(.code)
                )
            ]
        case let softBreak as SoftBreak:
            return [
                run(
                    kind: .softBreak,
                    text: "\n",
                    markup: softBreak,
                    destination: destination,
                    presentation: presentation
                )
            ]
        case let lineBreak as LineBreak:
            return [
                run(
                    kind: .hardBreak,
                    text: "\n",
                    markup: lineBreak,
                    destination: destination,
                    presentation: presentation
                )
            ]
        case let emphasis as Emphasis:
            return runs(
                in: emphasis.children,
                presentation: presentation.union(.emphasis),
                destination: destination
            )
        case let strong as Strong:
            return runs(
                in: strong.children,
                presentation: presentation.union(.strong),
                destination: destination
            )
        case let strikethrough as Strikethrough:
            return runs(
                in: strikethrough.children,
                presentation: presentation.union(.strikethrough),
                destination: destination
            )
        case let link as Link:
            return runs(
                in: link.children,
                presentation: presentation,
                destination: link.destination
            )
        case let image as Markdown.Image:
            let imagePresentation = presentation.union(.image)
            return [
                run(
                    kind: destination == nil ? .image : .link,
                    text: plainText(in: image.children),
                    markup: image,
                    destination: destination ?? image.source,
                    imageSource: image.source,
                    presentation: imagePresentation
                )
            ]
        case let html as InlineHTML:
            return [
                run(
                    kind: primaryKind(.text, destination: destination),
                    text: html.rawHTML,
                    markup: html,
                    destination: destination,
                    presentation: presentation.union(.html)
                )
            ]
        default:
            return runs(in: markup.children, presentation: presentation, destination: destination)
        }
    }

    private func coalescedStandaloneDisplayMathRuns(_ runs: [MarkdownInlineRun]) -> [MarkdownInlineRun] {
        guard runs.count >= 3 else {
            return runs
        }

        var coalesced: [MarkdownInlineRun] = []
        coalesced.reserveCapacity(runs.count)

        var index = runs.startIndex
        while index < runs.endIndex {
            guard let delimiter = displayMathOpeningDelimiter(for: runs[index]),
                  runHasLineBoundaryBefore(index, in: runs),
                  runHasLineBoundaryAfter(index, in: runs),
                  let closingIndex = closingDisplayMathRunIndex(
                    in: runs,
                    after: index,
                    delimiter: delimiter
                  )
            else {
                coalesced.append(runs[index])
                index += 1
                continue
            }

            let math = rawDisplayMathText(opening: runs[index], closing: runs[closingIndex])
            guard !math.isEmpty,
                  delimiter != .bareBracket || MarkdownMathDelimiterScanner.looksLikeTex(math),
                  let mathSourceRange = displayMathSourceRange(opening: runs[index], closing: runs[closingIndex])
            else {
                coalesced.append(runs[index])
                index += 1
                continue
            }

            var presentation = runs[index].presentation
            presentation.formUnion(.math)
            coalesced.append(
                MarkdownInlineRun(
                    kind: runs[index].destination == nil ? .math : .link,
                    text: math,
                    sourceRange: mathSourceRange,
                    destination: runs[index].destination,
                    presentation: presentation
                )
            )
            index = runs.index(after: closingIndex)
        }

        return coalesced
    }

    private func rawDisplayMathText(
        opening: MarkdownInlineRun,
        closing: MarkdownInlineRun
    ) -> String {
        guard let openingRange = opening.sourceRange?.byteRange,
              let closingRange = closing.sourceRange?.byteRange,
              openingRange.upperBound <= closingRange.lowerBound
        else {
            return ""
        }

        let raw = sourceText(for: openingRange.upperBound..<closingRange.lowerBound)
        return normalizedDisplayMathSource(raw)
    }

    private func normalizedDisplayMathSource(_ raw: String) -> String {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripDisplayMathContainerPrefixes(from: String($0)) }
        let commonIndent = lines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(leadingHorizontalWhitespaceCount)
            .min() ?? 0
        return lines
            .map { removingLeadingHorizontalWhitespace(from: $0, count: commonIndent) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripDisplayMathContainerPrefixes(from line: String) -> String {
        var current = line
        while let stripped = stripLeadingBlockQuoteMarker(from: current) {
            current = stripped
        }
        return current
    }

    private func stripLeadingBlockQuoteMarker(from line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == ">" else {
            return nil
        }

        cursor = line.index(after: cursor)
        if cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        return String(line[cursor...])
    }

    private func leadingHorizontalWhitespaceCount(in line: String) -> Int {
        var count = 0
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            count += 1
            cursor = line.index(after: cursor)
        }
        return count
    }

    private func removingLeadingHorizontalWhitespace(from line: String, count: Int) -> String {
        guard count > 0 else {
            return line
        }

        var remaining = count
        var cursor = line.startIndex
        while remaining > 0,
              cursor < line.endIndex,
              line[cursor] == " " || line[cursor] == "\t" {
            remaining -= 1
            cursor = line.index(after: cursor)
        }
        return String(line[cursor...])
    }

    private func closingDisplayMathRunIndex(
        in runs: [MarkdownInlineRun],
        after openingIndex: Int,
        delimiter: DisplayMathRunDelimiter
    ) -> Int? {
        var index = runs.index(after: openingIndex)
        while index < runs.endIndex {
            if displayMathClosingDelimiter(for: runs[index]) == delimiter,
               runHasLineBoundaryBefore(index, in: runs),
               runHasLineBoundaryAfter(index, in: runs) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func displayMathOpeningDelimiter(for run: MarkdownInlineRun) -> DisplayMathRunDelimiter? {
        guard run.kind == .text || run.kind == .link,
              let sourceRange = run.sourceRange,
              displayMathDelimiterIsStandaloneSourceRun(sourceRange.byteRange)
        else {
            return nil
        }

        switch sourceText(for: sourceRange.byteRange).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "\\[":
            return .bracket
        case "$$":
            return .dollar
        case "[":
            return .bareBracket
        default:
            return nil
        }
    }

    private func displayMathClosingDelimiter(for run: MarkdownInlineRun) -> DisplayMathRunDelimiter? {
        guard run.kind == .text || run.kind == .link,
              let sourceRange = run.sourceRange,
              displayMathDelimiterIsStandaloneSourceRun(sourceRange.byteRange)
        else {
            return nil
        }

        switch sourceText(for: sourceRange.byteRange).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "\\]":
            return .bracket
        case "$$":
            return .dollar
        case "]":
            return .bareBracket
        default:
            return nil
        }
    }

    private func displayMathDelimiterIsStandaloneSourceRun(_ byteRange: Range<Int>) -> Bool {
        guard let context = sourceLineContext(for: byteRange) else {
            return false
        }

        let prefix = String(context.line[..<context.token.lowerBound])
        let suffix = context.line[context.token.upperBound...]
        return sourcePrefixAllowsStandaloneDisplayMathDelimiter(prefix) &&
            suffix.allSatisfy(\.isWhitespace)
    }

    private func sourceLineContext(
        for byteRange: Range<Int>
    ) -> (line: String, token: Range<String.Index>)? {
        let localLower = byteRange.lowerBound - baseOffset
        let localUpper = byteRange.upperBound - baseOffset
        guard localLower >= 0,
              localLower <= localUpper,
              localUpper <= source.utf8.count,
              let lower = source.utf8.index(
                source.utf8.startIndex,
                offsetBy: localLower,
                limitedBy: source.utf8.endIndex
              ),
              let upper = source.utf8.index(
                source.utf8.startIndex,
                offsetBy: localUpper,
                limitedBy: source.utf8.endIndex
              )
        else {
            return nil
        }

        var lineStart = lower
        while lineStart > source.utf8.startIndex {
            let previous = source.utf8.index(before: lineStart)
            guard source.utf8[previous] != 10 else {
                break
            }
            lineStart = previous
        }

        var lineEnd = upper
        while lineEnd < source.utf8.endIndex, source.utf8[lineEnd] != 10 {
            lineEnd = source.utf8.index(after: lineEnd)
        }

        let lineStartOffset = source.utf8.distance(from: source.utf8.startIndex, to: lineStart)
        let tokenLowerOffset = localLower - lineStartOffset
        let tokenUpperOffset = localUpper - lineStartOffset
        let line = String(decoding: source.utf8[lineStart..<lineEnd], as: UTF8.self)
        guard let tokenLowerUTF8 = line.utf8.index(
                line.utf8.startIndex,
                offsetBy: tokenLowerOffset,
                limitedBy: line.utf8.endIndex
              ),
              let tokenUpperUTF8 = line.utf8.index(
                line.utf8.startIndex,
                offsetBy: tokenUpperOffset,
                limitedBy: line.utf8.endIndex
              ),
              let tokenLower = String.Index(tokenLowerUTF8, within: line),
              let tokenUpper = String.Index(tokenUpperUTF8, within: line)
        else {
            return nil
        }

        return (line, tokenLower..<tokenUpper)
    }

    private func sourcePrefixAllowsStandaloneDisplayMathDelimiter(_ prefix: String) -> Bool {
        var current = prefix
        while true {
            if current.allSatisfy(\.isWhitespace) {
                return true
            }

            if let stripped = stripLeadingBlockQuoteMarker(from: current) {
                current = stripped
                continue
            }

            if let stripped = stripLeadingListItemMarker(from: current) {
                current = stripped
                continue
            }

            return false
        }
    }

    private func stripLeadingListItemMarker(from line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex else {
            return nil
        }

        if line[cursor] == "-" || line[cursor] == "+" || line[cursor] == "*" {
            let afterMarker = line.index(after: cursor)
            guard afterMarker == line.endIndex ||
                    line[afterMarker] == " " ||
                    line[afterMarker] == "\t"
            else {
                return nil
            }
            return afterMarker < line.endIndex
                ? String(line[afterMarker...])
                : ""
        }

        guard line[cursor].isNumber else {
            return nil
        }

        var digitCursor = cursor
        var digitCount = 0
        while digitCursor < line.endIndex, line[digitCursor].isNumber, digitCount < 9 {
            digitCount += 1
            digitCursor = line.index(after: digitCursor)
        }

        guard digitCount > 0,
              digitCursor < line.endIndex,
              line[digitCursor] == "." || line[digitCursor] == ")"
        else {
            return nil
        }

        let afterMarker = line.index(after: digitCursor)
        guard afterMarker == line.endIndex ||
                line[afterMarker] == " " ||
                line[afterMarker] == "\t"
        else {
            return nil
        }
        return afterMarker < line.endIndex
            ? String(line[afterMarker...])
            : ""
    }

    private func runHasLineBoundaryBefore(_ index: Int, in runs: [MarkdownInlineRun]) -> Bool {
        guard index > runs.startIndex else {
            return true
        }
        return isLineBreakRun(runs[runs.index(before: index)])
    }

    private func runHasLineBoundaryAfter(_ index: Int, in runs: [MarkdownInlineRun]) -> Bool {
        let next = runs.index(after: index)
        guard next < runs.endIndex else {
            return true
        }
        return isLineBreakRun(runs[next])
    }

    private func isLineBreakRun(_ run: MarkdownInlineRun) -> Bool {
        run.kind == .softBreak || run.kind == .hardBreak
    }

    private func displayMathSourceRange(
        opening: MarkdownInlineRun,
        closing: MarkdownInlineRun
    ) -> MarkdownSourceRange? {
        guard let openingRange = opening.sourceRange?.byteRange,
              let closingRange = closing.sourceRange?.byteRange
        else {
            return nil
        }

        let byteRange = openingRange.lowerBound..<closingRange.upperBound
        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func textRuns(
        for text: Markdown.Text,
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        guard let sourceRange = sourceRange(for: text) else {
            return applyInlineContext(
                splitInlineMath(in: text.string, baseRange: fallbackRange),
                presentation: presentation,
                destination: destination
            )
        }

        let rawText = sourceText(for: sourceRange.byteRange)
        if rawText != text.string, containsMathDelimiterCandidate(rawText) {
            return applyInlineContext(
                splitInlineMathInSource(rawText, baseRange: sourceRange),
                presentation: presentation,
                destination: destination
            )
        }

        return applyInlineContext(
            splitInlineMath(in: text.string, baseRange: sourceRange),
            presentation: presentation,
            destination: destination
        )
    }

    private func splitInlineMathInSource(
        _ rawText: String,
        baseRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        var cursor = rawText.startIndex
        var plainStart = cursor
        let displaySpans = MarkdownMathDelimiterScanner.standaloneDisplayMathSpans(in: rawText)
        var displaySpanIndex = displaySpans.startIndex

        func appendPlain(upTo end: String.Index) {
            guard plainStart < end else {
                return
            }
            let rawRange = plainStart..<end
            let text = markdownUnescapedText(String(rawText[rawRange]))
            guard !text.isEmpty else {
                return
            }
            runs.append(
                MarkdownInlineRun(
                    kind: .text,
                    text: text,
                    sourceRange: sourceRange(
                        in: rawText,
                        localRange: rawRange,
                        baseRange: baseRange
                    )
                )
            )
        }

        while cursor < rawText.endIndex {
            while displaySpanIndex < displaySpans.endIndex,
                  displaySpans[displaySpanIndex].full.lowerBound < cursor {
                displaySpanIndex += 1
            }

            if displaySpanIndex < displaySpans.endIndex,
               displaySpans[displaySpanIndex].full.lowerBound == cursor {
                let span = displaySpans[displaySpanIndex]
                appendPlain(upTo: cursor)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(rawText[span.content]).trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceRange: sourceRange(
                            in: rawText,
                            localRange: span.full,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = span.full.upperBound
                plainStart = cursor
                displaySpanIndex += 1
                continue
            }

            if rawText[cursor] == "$",
               isPotentialOpeningDollar(in: rawText, at: cursor),
               let close = closingDollar(in: rawText, after: cursor) {
                appendPlain(upTo: cursor)
                let contentStart = rawText.index(after: cursor)
                let contentRange = contentStart..<close
                let fullRange = cursor..<rawText.index(after: close)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(rawText[contentRange]),
                        sourceRange: sourceRange(
                            in: rawText,
                            localRange: fullRange,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = rawText.index(after: close)
                plainStart = cursor
                continue
            }

            if rawText[cursor] == "\\",
               let latex = latexInlineMathRange(in: rawText, at: cursor) {
                appendPlain(upTo: cursor)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(rawText[latex.content]),
                        sourceRange: sourceRange(
                            in: rawText,
                            localRange: latex.full,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = latex.full.upperBound
                plainStart = cursor
                continue
            }

            cursor = rawText.index(after: cursor)
        }

        appendPlain(upTo: rawText.endIndex)
        return runs.isEmpty ? [
            MarkdownInlineRun(
                kind: .text,
                text: markdownUnescapedText(rawText),
                sourceRange: baseRange
            )
        ] : runs
    }

    private func splitInlineMath(
        in text: String,
        baseRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        guard containsMathDelimiterCandidate(text) else {
            return [
                MarkdownInlineRun(
                    kind: .text,
                    text: text,
                    sourceRange: baseRange
                )
            ]
        }

        var runs: [MarkdownInlineRun] = []
        var cursor = text.startIndex
        var plainStart = cursor
        let displaySpans = MarkdownMathDelimiterScanner.standaloneDisplayMathSpans(in: text)
        var displaySpanIndex = displaySpans.startIndex

        func appendPlain(upTo end: String.Index) {
            guard plainStart < end else {
                return
            }
            let range = sourceRange(
                in: text,
                localRange: plainStart..<end,
                baseRange: baseRange
            )
            runs.append(
                MarkdownInlineRun(
                    kind: .text,
                    text: String(text[plainStart..<end]),
                    sourceRange: range
                )
            )
        }

        while cursor < text.endIndex {
            while displaySpanIndex < displaySpans.endIndex,
                  displaySpans[displaySpanIndex].full.lowerBound < cursor {
                displaySpanIndex += 1
            }

            if displaySpanIndex < displaySpans.endIndex,
               displaySpans[displaySpanIndex].full.lowerBound == cursor {
                let span = displaySpans[displaySpanIndex]
                appendPlain(upTo: cursor)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(text[span.content]).trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceRange: sourceRange(
                            in: text,
                            localRange: span.full,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = span.full.upperBound
                plainStart = cursor
                displaySpanIndex += 1
                continue
            }

            guard text[cursor] == "$",
                  isPotentialOpeningDollar(in: text, at: cursor),
                  let close = closingDollar(in: text, after: cursor)
            else {
                cursor = text.index(after: cursor)
                continue
            }

            appendPlain(upTo: cursor)
            let contentStart = text.index(after: cursor)
            let contentRange = contentStart..<close
            let fullRange = cursor..<text.index(after: close)
            runs.append(
                MarkdownInlineRun(
                    kind: .math,
                    text: String(text[contentRange]),
                    sourceRange: sourceRange(
                        in: text,
                        localRange: fullRange,
                        baseRange: baseRange
                    )
                )
            )
            cursor = text.index(after: close)
            plainStart = cursor
        }

        appendPlain(upTo: text.endIndex)
        return runs.isEmpty ? [
            MarkdownInlineRun(kind: .text, text: text, sourceRange: baseRange)
        ] : runs
    }

    private func containsMathDelimiterCandidate(_ text: String) -> Bool {
        text.contains("$") ||
            text.contains("\\(") ||
            text.contains("\\[") ||
            text.hasPrefix("[") ||
            text.contains("\n[")
    }

    private func isPotentialOpeningDollar(in text: String, at index: String.Index) -> Bool {
        if isEscapedDelimiter(in: text, at: index) {
            return false
        }

        let next = text.index(after: index)
        guard next < text.endIndex else {
            return false
        }

        if text[next] == "$" || text[next].isWhitespace {
            return false
        }

        return true
    }

    private func latexInlineMathRange(
        in text: String,
        at cursor: String.Index
    ) -> (content: Range<String.Index>, full: Range<String.Index>)? {
        guard text[cursor] == "\\", !isEscapedDelimiter(in: text, at: cursor) else {
            return nil
        }

        let openParen = text.index(after: cursor)
        guard openParen < text.endIndex, text[openParen] == "(" else {
            return nil
        }

        let contentStart = text.index(after: openParen)
        var scan = contentStart
        while scan < text.endIndex {
            if text[scan] == "\\", !isEscapedDelimiter(in: text, at: scan) {
                let next = text.index(after: scan)
                if next < text.endIndex, text[next] == ")" {
                    let content = contentStart..<scan
                    let full = cursor..<text.index(after: next)
                    return (content, full)
                }
            }
            scan = text.index(after: scan)
        }

        return nil
    }

    private func closingDollar(in text: String, after opening: String.Index) -> String.Index? {
        var cursor = text.index(after: opening)
        while cursor < text.endIndex {
            defer {
                cursor = text.index(after: cursor)
            }

            guard text[cursor] == "$" else {
                continue
            }

            if isEscapedDelimiter(in: text, at: cursor) {
                continue
            }

            let previous = text.index(before: cursor)
            if text[previous].isWhitespace {
                continue
            }

            let next = text.index(after: cursor)
            if next < text.endIndex, text[next] == "$" {
                continue
            }

            return cursor
        }

        return nil
    }

    private func isEscapedDelimiter(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        var cursor = text.index(before: index)
        var backslashCount = 0
        while true {
            guard text[cursor] == "\\" else {
                break
            }
            backslashCount += 1
            guard cursor > text.startIndex else {
                break
            }
            cursor = text.index(before: cursor)
        }
        return backslashCount % 2 == 1
    }

    private func markdownUnescapedText(_ rawText: String) -> String {
        var result = ""
        var cursor = rawText.startIndex
        let escapable = "\\`*_{}[]<>()#+-.!|$"

        while cursor < rawText.endIndex {
            if rawText[cursor] == "\\" {
                let next = rawText.index(after: cursor)
                if next < rawText.endIndex, escapable.contains(rawText[next]) {
                    result.append(rawText[next])
                    cursor = rawText.index(after: next)
                    continue
                }
            }

            result.append(rawText[cursor])
            cursor = rawText.index(after: cursor)
        }

        return result
    }

    private func sourceRange(
        in text: String,
        localRange: Range<String.Index>,
        baseRange: MarkdownSourceRange
    ) -> MarkdownSourceRange {
        let lowerOffset = text.utf8.distance(
            from: text.utf8.startIndex,
            to: localRange.lowerBound.samePosition(in: text.utf8) ?? text.utf8.startIndex
        )
        let upperOffset = text.utf8.distance(
            from: text.utf8.startIndex,
            to: localRange.upperBound.samePosition(in: text.utf8) ?? text.utf8.endIndex
        )
        let byteRange = (baseRange.byteRange.lowerBound + lowerOffset)..<(baseRange.byteRange.lowerBound + upperOffset)
        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func sourceText(for byteRange: Range<Int>) -> String {
        let localLower = max(0, byteRange.lowerBound - baseOffset)
        let localUpper = min(source.utf8.count, byteRange.upperBound - baseOffset)
        guard localLower < localUpper else {
            return ""
        }

        let lower = source.utf8.index(source.utf8.startIndex, offsetBy: localLower)
        let upper = source.utf8.index(source.utf8.startIndex, offsetBy: localUpper)
        return String(decoding: source.utf8[lower..<upper], as: UTF8.self)
    }

    private func run(
        kind: MarkdownInlineKind,
        text: String,
        markup: Markup,
        destination: String? = nil,
        imageSource: String? = nil,
        presentation: MarkdownInlinePresentation? = nil
    ) -> MarkdownInlineRun {
        MarkdownInlineRun(
            kind: kind,
            text: text,
            sourceRange: sourceRange(for: markup) ?? fallbackRange,
            destination: destination,
            imageSource: imageSource,
            presentation: presentation
        )
    }

    private func primaryKind(_ kind: MarkdownInlineKind, destination: String?) -> MarkdownInlineKind {
        guard destination != nil else {
            return kind
        }

        switch kind {
        case .text, .emphasis, .strong, .strikethrough, .code, .math:
            return .link
        default:
            return kind
        }
    }

    private func applyInlineContext(
        _ runs: [MarkdownInlineRun],
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        runs.map { run in
            var copy = run
            copy.presentation.formUnion(presentation)
            if let destination {
                copy.kind = primaryKind(copy.kind, destination: destination)
                copy.destination = destination
            } else if copy.kind == .text {
                copy.kind = primaryStyleKind(for: copy.presentation)
            }
            return copy
        }
    }

    private func primaryStyleKind(for presentation: MarkdownInlinePresentation) -> MarkdownInlineKind {
        if presentation.contains(.strong) {
            return .strong
        }

        if presentation.contains(.emphasis) {
            return .emphasis
        }

        if presentation.contains(.strikethrough) {
            return .strikethrough
        }

        return .text
    }

    private func plainText(in children: MarkupChildren) -> String {
        children.map { plainText(in: $0) }.joined()
    }

    private func plainText(in markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return text.string
        case let code as InlineCode:
            return code.code
        case is SoftBreak:
            return "\n"
        case is LineBreak:
            return "\n"
        case let html as InlineHTML:
            return html.rawHTML
        default:
            return plainText(in: markup.children)
        }
    }

    private func sourceRange(for markup: Markup) -> MarkdownSourceRange? {
        guard let range = markup.range else {
            return nil
        }

        let lower = byteOffset(for: range.lowerBound)
        let upper = max(lower, byteOffset(for: range.upperBound))
        let byteRange = lower..<upper
        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func byteOffset(for location: SourceLocation) -> Int {
        var lineStart = baseOffset
        if location.line > 1 {
            var remainingNewlines = location.line - 1
            var cursor = source.utf8.startIndex

            while cursor < source.utf8.endIndex, remainingNewlines > 0 {
                if source.utf8[cursor] == 10 {
                    remainingNewlines -= 1
                    if remainingNewlines == 0 {
                        lineStart = baseOffset + source.utf8.distance(from: source.utf8.startIndex, to: source.utf8.index(after: cursor))
                        break
                    }
                }
                cursor = source.utf8.index(after: cursor)
            }
        }

        return lineStart + max(0, location.column - 1)
    }
}
