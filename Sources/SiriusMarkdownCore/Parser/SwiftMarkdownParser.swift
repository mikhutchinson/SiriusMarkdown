import Foundation
import Markdown

public struct SwiftMarkdownParser: Sendable {
    private let tableCellConversionCache: MarkdownTableCellConversionCache

    public init() {
        self.tableCellConversionCache = MarkdownTableCellConversionCache(capacity: 4_096)
    }

    init(tableCellConversionCacheCapacity: Int) {
        self.tableCellConversionCache = MarkdownTableCellConversionCache(
            capacity: tableCellConversionCacheCapacity
        )
    }

    var cachedTableCellConversionCount: Int {
        tableCellConversionCache.count
    }

    public func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        referenceDefinitionsPrefix: String = ""
    ) -> [MarkdownBlock] {
        parse(
            slice,
            lineMap: lineMap,
            idNamespace: idNamespace,
            isSealed: isSealed,
            referenceDefinitionsPrefix: referenceDefinitionsPrefix,
            diagnosticsRecorder: nil
        )
    }

    func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        referenceDefinitionsPrefix: String = "",
        diagnosticsRecorder: MarkdownDiagnosticsRecorder?
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
            referenceDefinitionsPrefix: referenceDefinitionsPrefix,
            tableCellConversionCache: tableCellConversionCache,
            diagnosticsRecorder: diagnosticsRecorder
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
    private let sourceLocationIndex: MarkdownSourceLocationIndex
    private let tableCellConversionCache: MarkdownTableCellConversionCache
    private let diagnosticsRecorder: MarkdownDiagnosticsRecorder?

    init(
        source: String,
        baseOffset: Int,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        referenceDefinitionsPrefix: String,
        tableCellConversionCache: MarkdownTableCellConversionCache,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder?,
        allowParagraphDisplayMathSplitting: Bool = true
    ) {
        self.source = source
        self.baseOffset = baseOffset
        self.lineMap = lineMap
        self.idNamespace = idNamespace
        self.isSealed = isSealed
        self.referenceDefinitionsPrefix = referenceDefinitionsPrefix
        self.allowParagraphDisplayMathSplitting = allowParagraphDisplayMathSplitting
        self.sourceLocationIndex = MarkdownSourceLocationIndex(source: source)
        self.tableCellConversionCache = tableCellConversionCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

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
        let table = tableBlock(for: markup)
        let inlines = inlineRuns(for: markup, fallbackRange: range, table: table)
        let contentHash = stableContentHash(rawText)
        let id = stableBlockID(kind: kind, range: range, sequence: sequence)
        let richContent: MarkdownRichContent? = if let htmlBlock = markup as? HTMLBlock {
            MarkdownHTMLSemanticAdapter.richContent(
                from: htmlBlock.rawHTML,
                sourceRange: range,
                lineMap: lineMap,
                parentID: id,
                isSealed: isSealed
            )
        } else {
            nil
        }

        return MarkdownBlock(
            id: id,
            kind: kind,
            sourceRange: range,
            text: displayText(for: markup, rawText: rawText),
            inlines: inlines,
            listItems: listItems(for: markup),
            table: table,
            contentHash: contentHash,
            orderedListStart: (markup as? OrderedList)?.startIndex,
            headingLevel: (markup as? Heading)?.level,
            infoString: (markup as? CodeBlock)?.language,
            isSealed: isSealed,
            richContent: richContent
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

    private func inlineRuns(
        for markup: Markup,
        fallbackRange: MarkdownSourceRange,
        table: MarkdownTableBlock?
    ) -> [MarkdownInlineRun] {
        switch markup {
        case let heading as Heading:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: heading.children)
        case let paragraph as Paragraph:
            let rawText = sourceText(for: fallbackRange.byteRange)
            if let mathContentRange = MarkdownMathDelimiterScanner.blockContentRange(in: rawText) {
                let mathContent = String(rawText[mathContentRange])
                return [
                    MarkdownInlineRun(
                        kind: .math,
                        text: mathContent,
                        sourceRange: sourceRange(in: rawText, localRange: mathContentRange, baseRange: fallbackRange)
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
        case is Table:
            guard let table else {
                return []
            }
            return (table.header + table.rows.flatMap { $0 }).flatMap(\.inlines)
        case let codeBlock as CodeBlock:
            return [
                MarkdownInlineRun(
                    kind: .code,
                    text: codeBlock.code,
                    sourceRange: codeContentSourceRange(for: codeBlock)
                )
            ]
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
                tableCellConversionCache: tableCellConversionCache,
                diagnosticsRecorder: diagnosticsRecorder,
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
        let trimmedContentRange = trimmedNonEmptyRange(in: rawText, localRange: span.content) ?? span.content
        let contentRange = sourceRange(in: rawText, localRange: trimmedContentRange, baseRange: paragraphRange)
        let text = String(rawText[span.full])
        let math = String(rawText[trimmedContentRange])
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
            fallbackRange: fallbackRange,
            sourceLocationIndex: sourceLocationIndex
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
                    sourceRange: codeContentSourceRange(for: codeBlock)
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

    private func codeContentSourceRange(for codeBlock: CodeBlock) -> MarkdownSourceRange {
        let blockRange = markdownSourceRange(for: codeBlock)
        let rawText = sourceText(for: blockRange.byteRange)
        let code = codeBlock.code
        guard !code.isEmpty else {
            let emptyRange = blockRange.byteRange.lowerBound..<blockRange.byteRange.lowerBound
            return MarkdownSourceRange(byteRange: emptyRange, lineRange: lineMap.lineRange(for: emptyRange))
        }

        let searchLower = fencedCodeContentSearchLowerBound(in: rawText)
        if let codeRange = rawText.range(of: code, range: searchLower..<rawText.endIndex) {
            return sourceRange(in: rawText, localRange: codeRange, baseRange: blockRange)
        }

        if let codeRange = rawText.range(of: code) {
            return sourceRange(in: rawText, localRange: codeRange, baseRange: blockRange)
        }

        return blockRange
    }

    private func fencedCodeContentSearchLowerBound(in rawText: String) -> String.Index {
        let trimmedLeading = rawText.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix("```") || trimmedLeading.hasPrefix("~~~"),
              let firstNewline = rawText.firstIndex(of: "\n")
        else {
            return rawText.startIndex
        }

        return rawText.index(after: firstNewline)
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
        let rawText = sourceText(for: range.byteRange)
        let key = tableCellConversionCacheKey(for: cell, range: range, rawText: rawText)
        if let cached = tableCellConversionCache.cell(forKey: key) {
            diagnosticsRecorder?.recordTableCellModelCacheHit()
            return cached
        }

        let inlines = inlineRunConverter(fallbackRange: range).runs(in: cell.children)
        let converted = MarkdownTableCell(
            sourceRange: range,
            text: inlines.map(\.text).joined(),
            inlines: inlines,
            contentHash: stableContentHash(rawText),
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
        tableCellConversionCache.insert(converted, forKey: key)
        diagnosticsRecorder?.recordTableCellModelConversion()
        return converted
    }

    private func tableCellConversionCacheKey(
        for cell: Table.Cell,
        range: MarkdownSourceRange,
        rawText: String
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "table-cell-render-model-v1")
        fingerprint.combine(rawText)
        fingerprint.combine(cell.colspan)
        fingerprint.combine(cell.rowspan)
        combineResolvedResourceSemantics(in: cell, into: &fingerprint)
        return MarkdownCacheKey(
            sourceRange: range,
            contentFingerprint: fingerprint,
            namespace: "swift-markdown-table-cell"
        )
    }

    private func combineResolvedResourceSemantics(
        in markup: Markup,
        into fingerprint: inout MarkdownContentFingerprint
    ) {
        switch markup {
        case let link as Link:
            fingerprint.combine("link")
            fingerprint.combine(link.destination ?? "")
        case let image as Markdown.Image:
            fingerprint.combine("image")
            fingerprint.combine(image.source ?? "")
        default:
            break
        }

        for child in markup.children {
            combineResolvedResourceSemantics(in: child, into: &fingerprint)
        }
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
        sourceLocationIndex.byteOffset(for: location, baseOffset: baseOffset)
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
        guard let range = blockContentRange(in: rawText) else {
            return nil
        }
        return String(rawText[range])
    }

    static func blockContentRange(in rawText: String) -> Range<String.Index>? {
        guard let trimmedRange = trimmedNonEmptyRange(
            in: rawText,
            localRange: rawText.startIndex..<rawText.endIndex
        ) else {
            return nil
        }
        let trimmed = rawText[trimmedRange]
        if trimmed.hasPrefix("\\begin{"), trimmed.hasSuffix("}"), trimmed.contains("\\end{") {
            return trimmedRange
        }

        if let range = delimitedContentRange(in: rawText, trimmedRange: trimmedRange, open: "$$", close: "$$") {
            return range
        }

        if let range = delimitedContentRange(in: rawText, trimmedRange: trimmedRange, open: "\\[", close: "\\]") {
            return range
        }

        if let range = bareDisplayBracketsContentRange(in: rawText, trimmedRange: trimmedRange),
           looksLikeTex(String(rawText[range])) {
            return range
        }

        return nil
    }

    static func standaloneDisplayMathSpans(in text: String) -> [DisplayMathSpan] {
        var spans: [DisplayMathSpan] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if let span = singleLineDisplayMathSpan(open: "\\[", close: "\\]", in: text, at: cursor) {
                spans.append(span)
                cursor = span.full.upperBound
                continue
            }

            if let span = singleLineDisplayMathSpan(open: "$$", close: "$$", in: text, at: cursor) {
                spans.append(span)
                cursor = span.full.upperBound
                continue
            }

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
        guard let trimmedRange = trimmedNonEmptyRange(
            in: text,
            localRange: text.startIndex..<text.endIndex
        ) else {
            return false
        }

        return span.full.lowerBound == trimmedRange.lowerBound && span.full.upperBound == trimmedRange.upperBound
    }

    private static func delimitedContentRange(
        in text: String,
        trimmedRange: Range<String.Index>,
        open: String,
        close: String
    ) -> Range<String.Index>? {
        let trimmed = text[trimmedRange]
        guard trimmed.hasPrefix(open),
              trimmed.hasSuffix(close),
              trimmed.count >= open.count + close.count
        else {
            return nil
        }

        let start = text.index(trimmedRange.lowerBound, offsetBy: open.count)
        let end = text.index(trimmedRange.upperBound, offsetBy: -close.count)
        guard start <= end else {
            return nil
        }

        return trimmedNonEmptyRange(in: text, localRange: start..<end)
    }

    private static func bareDisplayBracketsContentRange(
        in text: String,
        trimmedRange: Range<String.Index>
    ) -> Range<String.Index>? {
        let trimmed = text[trimmedRange]
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

        return trimmedNonEmptyRange(
            in: text,
            localRange: text.index(after: firstLineEnd)..<lastLineStart
        )
    }

    private static func trimmedNonEmptyRange(
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

    private static func singleLineDisplayMathSpan(
        open: String,
        close: String,
        in text: String,
        at cursor: String.Index
    ) -> DisplayMathSpan? {
        guard hasToken(open, in: text, at: cursor),
              let openUpper = text.index(cursor, offsetBy: open.count, limitedBy: text.endIndex)
        else {
            return nil
        }

        let lineStart = startOfLine(containing: cursor, in: text)
        var prefixCursor = lineStart
        while prefixCursor < cursor {
            guard text[prefixCursor].isWhitespace, !text[prefixCursor].isNewline else {
                return nil
            }
            prefixCursor = text.index(after: prefixCursor)
        }

        let lineEnd = endOfLine(containing: cursor, in: text)
        guard openUpper < lineEnd,
              let closeRange = text.range(
                of: close,
                options: .backwards,
                range: openUpper..<lineEnd
              ),
              let content = trimmedNonEmptyRange(
                in: text,
                localRange: openUpper..<closeRange.lowerBound
              )
        else {
            return nil
        }

        var suffixCursor = closeRange.upperBound
        while suffixCursor < lineEnd {
            guard text[suffixCursor].isWhitespace, !text[suffixCursor].isNewline else {
                return nil
            }
            suffixCursor = text.index(after: suffixCursor)
        }

        return DisplayMathSpan(
            full: cursor..<closeRange.upperBound,
            content: content
        )
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

    private static func endOfLine(containing index: String.Index, in text: String) -> String.Index {
        var cursor = index
        while cursor < text.endIndex, !text[cursor].isNewline {
            cursor = text.index(after: cursor)
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
            "\\rightarrow", "\\leftarrow", "\\infty", "\\operatorname",
            "\\mathrm", "\\mathbf", "\\mathbb", "\\mathcal", "\\partial",
            "\\nabla", "\\Pr"
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
    var sourceLocationIndex: MarkdownSourceLocationIndex

    private static let currencyCodeSuffixes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
    private static let bareTexCommands: Set<String> = [
        "aleph", "alpha", "amalg", "angle", "approx", "arccos", "arcsin", "arctan", "arg", "asymp", "ast", "bar",
        "because", "begin", "beta", "bf", "bigcap", "bigcup", "bigodot", "bigoplus", "bigotimes", "bigsqcup",
        "biguplus", "bigvee", "bigwedge", "binom", "bm", "bot", "bullet", "cal", "cap", "cdot",
        "cdotp", "cdots", "chi", "circ", "cong", "coprod", "cos", "cosh", "cot", "coth", "csc", "cup",
        "dagger", "dbinom", "ddagger", "ddots", "deg", "degree", "delta", "det", "dfrac", "dim", "displaystyle",
        "div", "doteq", "dots", "downarrow",
        "ell", "emptyset", "end", "epsilon", "equiv", "eta", "exists", "exp",
        "forall", "frac", "frak", "gamma", "gcd", "ge", "geq", "gg", "gt", "hat", "hbar", "hom", "iff", "im", "imath",
        "impliedby", "implies", "in", "inf",
        "infty", "int", "iota", "jmath", "kappa", "ker", "land",
        "lambda", "langle", "lceil", "ldots", "le", "left", "leftarrow", "leftrightarrow", "leq", "lfloor",
        "lg", "lim", "liminf", "limsup", "ll", "ln", "log", "longleftarrow", "longleftrightarrow", "longrightarrow",
        "lor", "lgroup", "lt", "lvert", "mapsto", "mathbb", "mathbf", "mathcal", "mathrm",
        "mathbfit", "mathfrak", "mathit", "mathnormal", "mathsf", "mathtt", "max", "mho", "mid", "min", "mit", "mod", "models", "mp", "mu", "nabla",
        "ne", "nearrow", "neq", "ni", "notin", "nu", "neg", "nwarrow", "odot", "oint", "omega", "ominus", "oplus",
        "operatorname", "oslash", "otimes", "overline", "parallel", "partial", "perp", "phi", "pi", "pm",
        "pr", "prec", "prime", "prod", "propto", "psi", "qquad", "quad", "rank", "re", "rightarrow",
        "rangle", "rceil", "rfloor", "rgroup", "rho", "right", "rvert", "scriptscriptstyle", "scriptstyle", "searrow", "sec", "setminus", "sigma", "sim",
        "simeq", "sin", "sinh", "sqcap", "sqcup", "sqrt", "sqsubset", "sqsubseteq", "sqsupset", "sqsupseteq", "star", "subset",
        "subseteq", "succ", "sum", "sup", "supset", "supseteq", "swarrow", "tan", "tanh", "tau", "tbinom", "text", "textstyle", "tfrac",
        "textbf", "textit", "textrm", "textsf", "texttt", "therefore", "theta", "tilde", "times", "to", "top", "tr", "trace",
        "triangle", "uparrow", "updownarrow", "uplus", "upsilon", "varepsilon", "varphi", "varpi", "varrho",
        "varsigma", "vartheta", "vdots", "vec", "vee", "vert", "wedge", "widehat", "widetilde", "wp", "wr", "xi", "zeta"
    ]
    private static let bareTexInfixCommands: Set<String> = [
        "amalg", "approx", "asymp", "ast", "cap", "cdot", "cdotp", "circ", "cong", "cup", "dagger", "ddagger",
        "div", "doteq", "downarrow", "equiv", "ge", "geq", "gg", "gt",
        "iff", "in", "land", "le", "leftarrow", "leftrightarrow", "leq", "longleftarrow", "longleftrightarrow",
        "longrightarrow", "lor", "lt", "mapsto", "mid", "models", "mp", "ne", "nearrow", "neq",
        "ni", "notin", "nwarrow", "odot", "ominus", "oplus", "oslash", "otimes", "parallel", "perp", "pm", "prec",
        "propto", "rightarrow", "searrow", "setminus", "sim", "simeq", "sqcap", "sqcup", "sqsubset", "sqsubseteq",
        "sqsupset", "sqsupseteq", "star", "subset", "subseteq", "succ", "supset", "supseteq", "swarrow", "times",
        "to", "uparrow", "updownarrow", "uplus", "vee", "wedge", "wr"
    ]

    private enum DisplayMathRunDelimiter {
        case bracket
        case dollar
        case bareBracket
    }

    func runs(in children: MarkupChildren) -> [MarkdownInlineRun] {
        let converted = MarkdownHTMLSemanticAdapter.normalizeInlineRuns(
            rawRuns(in: children, presentation: [], destination: nil)
        )
        return coalescedStandaloneDisplayMathRuns(
            coalescedBareTexEnvironmentRuns(
                resolvedLineBreakSourceRanges(in: converted)
            )
        )
    }

    private func rawRuns(
        in children: MarkupChildren,
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        children.flatMap {
            rawRuns(in: $0, presentation: presentation, destination: destination)
        }
    }

    private func rawRuns(
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
                lineBreakRun(
                    kind: .softBreak,
                    text: "\n",
                    markup: softBreak,
                    destination: destination,
                    presentation: presentation
                )
            ]
        case let lineBreak as LineBreak:
            return [
                lineBreakRun(
                    kind: .hardBreak,
                    text: "\n",
                    markup: lineBreak,
                    destination: destination,
                    presentation: presentation
                )
            ]
        case let emphasis as Emphasis:
            return rawRuns(
                in: emphasis.children,
                presentation: presentation.union(.emphasis),
                destination: destination
            )
        case let strong as Strong:
            return rawRuns(
                in: strong.children,
                presentation: presentation.union(.strong),
                destination: destination
            )
        case let strikethrough as Strikethrough:
            return rawRuns(
                in: strikethrough.children,
                presentation: presentation.union(.strikethrough),
                destination: destination
            )
        case let link as Link:
            return rawRuns(
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
            return rawRuns(in: markup.children, presentation: presentation, destination: destination)
        }
    }

    private func resolvedLineBreakSourceRanges(in runs: [MarkdownInlineRun]) -> [MarkdownInlineRun] {
        guard runs.contains(where: isLineBreakRun) else {
            return runs
        }

        var resolved = runs
        for index in resolved.indices where isLineBreakRun(resolved[index]) {
            guard let sourceRange = resolvedLineBreakSourceRange(at: index, in: resolved) else {
                continue
            }
            resolved[index].sourceRange = sourceRange
        }
        return resolved
    }

    private func resolvedLineBreakSourceRange(
        at index: Int,
        in runs: [MarkdownInlineRun]
    ) -> MarkdownSourceRange? {
        let kind = runs[index].kind
        if let previous = nearestSourceRange(before: index, in: runs),
           let next = nearestSourceRange(after: index, in: runs),
           previous.byteRange.upperBound <= next.byteRange.lowerBound,
           let breakRange = lineBreakByteRange(
            near: previous.byteRange.upperBound..<next.byteRange.lowerBound,
            kind: kind
           ) {
            return markdownSourceRange(forByteRange: breakRange)
        }

        if let sourceRange = runs[index].sourceRange,
           sourceRange != fallbackRange,
           let breakRange = lineBreakByteRange(near: sourceRange.byteRange, kind: kind) {
            return markdownSourceRange(forByteRange: breakRange)
        }

        if let previous = nearestSourceRange(before: index, in: runs),
           let breakRange = lineBreakByteRange(
            near: previous.byteRange.upperBound..<previous.byteRange.upperBound,
            kind: kind
           ) {
            return markdownSourceRange(forByteRange: breakRange)
        }

        if let next = nearestSourceRange(after: index, in: runs),
           let breakRange = lineBreakByteRange(
            near: next.byteRange.lowerBound..<next.byteRange.lowerBound,
            kind: kind
           ) {
            return markdownSourceRange(forByteRange: breakRange)
        }

        return nil
    }

    private func nearestSourceRange(
        before index: Int,
        in runs: [MarkdownInlineRun]
    ) -> MarkdownSourceRange? {
        guard index > runs.startIndex else {
            return nil
        }
        var cursor = runs.index(before: index)
        while cursor >= runs.startIndex {
            if let range = runs[cursor].sourceRange, range != fallbackRange {
                return range
            }
            if cursor == runs.startIndex {
                break
            }
            cursor = runs.index(before: cursor)
        }
        return nil
    }

    private func nearestSourceRange(
        after index: Int,
        in runs: [MarkdownInlineRun]
    ) -> MarkdownSourceRange? {
        var cursor = runs.index(after: index)
        while cursor < runs.endIndex {
            if let range = runs[cursor].sourceRange, range != fallbackRange {
                return range
            }
            cursor = runs.index(after: cursor)
        }
        return nil
    }

    private func markdownSourceRange(forByteRange byteRange: Range<Int>) -> MarkdownSourceRange {
        MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
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

    private func coalescedBareTexEnvironmentRuns(_ runs: [MarkdownInlineRun]) -> [MarkdownInlineRun] {
        guard runs.count >= 2 else {
            return runs
        }

        var coalesced: [MarkdownInlineRun] = []
        coalesced.reserveCapacity(runs.count)

        var index = runs.startIndex
        while index < runs.endIndex {
            let run = runs[index]
            guard run.kind == .math,
                  run.destination == nil,
                  run.text.contains("\\begin{"),
                  !run.text.contains("\\end{")
            else {
                coalesced.append(run)
                index += 1
                continue
            }

            var scan = runs.index(after: index)
            var closingIndex: Int?
            var canMerge = true

            while scan < runs.endIndex {
                let candidate = runs[scan]
                if candidate.kind == .math, candidate.destination == nil {
                    if candidate.text.contains("\\end{") {
                        closingIndex = scan
                        break
                    }
                    scan = runs.index(after: scan)
                    continue
                }

                if isBareTexEnvironmentSeparatorRun(candidate) {
                    scan = runs.index(after: scan)
                    continue
                }

                canMerge = false
                break
            }

            guard canMerge,
                  let closingIndex,
                  let mergedRange = mergedSourceRange(from: run, through: runs[closingIndex])
            else {
                coalesced.append(run)
                index += 1
                continue
            }

            coalesced.append(
                MarkdownInlineRun(
                    kind: .math,
                    text: sourceText(for: mergedRange.byteRange),
                    sourceRange: mergedRange
                )
            )
            index = runs.index(after: closingIndex)
        }

        return coalesced
    }

    private func isBareTexEnvironmentSeparatorRun(_ run: MarkdownInlineRun) -> Bool {
        if isLineBreakRun(run) {
            return true
        }

        guard run.kind == .text,
              run.destination == nil
        else {
            return false
        }

        return run.text.allSatisfy { character in
            character.isWhitespace || character == "\\"
        }
    }

    private func mergedSourceRange(
        from first: MarkdownInlineRun,
        through last: MarkdownInlineRun
    ) -> MarkdownSourceRange? {
        guard let firstRange = first.sourceRange,
              let lastRange = last.sourceRange,
              firstRange.byteRange.lowerBound <= lastRange.byteRange.upperBound
        else {
            return nil
        }

        let byteRange = firstRange.byteRange.lowerBound..<lastRange.byteRange.upperBound
        return MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func rawDisplayMathText(
        opening: MarkdownInlineRun,
        closing: MarkdownInlineRun
    ) -> String {
        guard let openingRange = displayMathDelimiterByteRange(for: opening),
              let closingRange = displayMathDelimiterByteRange(for: closing),
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
              let delimiterRange = displayMathDelimiterByteRange(for: run),
              displayMathDelimiterIsStandaloneSourceRun(delimiterRange)
        else {
            return nil
        }

        switch sourceText(for: delimiterRange).trimmingCharacters(in: .whitespacesAndNewlines) {
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
              let delimiterRange = displayMathDelimiterByteRange(for: run),
              displayMathDelimiterIsStandaloneSourceRun(delimiterRange)
        else {
            return nil
        }

        switch sourceText(for: delimiterRange).trimmingCharacters(in: .whitespacesAndNewlines) {
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

    private func displayMathDelimiterByteRange(for run: MarkdownInlineRun) -> Range<Int>? {
        guard let byteRange = run.sourceRange?.byteRange else {
            return nil
        }

        let raw = sourceText(for: byteRange)
        if raw == "\\",
           byteRange.upperBound < baseOffset + source.utf8.count {
            let extended = byteRange.lowerBound..<(byteRange.upperBound + 1)
            let extendedRaw = sourceText(for: extended)
            if extendedRaw == "\\[" || extendedRaw == "\\]" {
                return extended
            }
        }

        return byteRange
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
        guard let openingRange = displayMathDelimiterByteRange(for: opening),
              let closingRange = displayMathDelimiterByteRange(for: closing)
        else {
            return nil
        }

        let contentByteRange = openingRange.upperBound..<closingRange.lowerBound
        let contentText = sourceText(for: contentByteRange)
        let baseRange = MarkdownSourceRange(
            byteRange: contentByteRange,
            lineRange: lineMap.lineRange(for: contentByteRange)
        )
        guard let trimmedRange = trimmedNonEmptyRange(
            in: contentText,
            localRange: contentText.startIndex..<contentText.endIndex
        ) else {
            return baseRange
        }
        return sourceRange(in: contentText, localRange: trimmedRange, baseRange: baseRange)
    }

    private func textRuns(
        for text: Markdown.Text,
        presentation: MarkdownInlinePresentation,
        destination: String?
    ) -> [MarkdownInlineRun] {
        guard let sourceRange = sourceRange(for: text) else {
            return applyInlineContext(
                linkifiedBareURLRuns(
                    splitInlineMath(in: text.string, baseRange: fallbackRange),
                    alreadyLinked: destination != nil
                ),
                presentation: presentation,
                destination: destination
            )
        }

        let rawText = sourceText(for: sourceRange.byteRange)
        if rawText != text.string, containsMathDelimiterCandidate(rawText) {
            return applyInlineContext(
                linkifiedBareURLRuns(
                    splitInlineMathInSource(rawText, baseRange: sourceRange),
                    alreadyLinked: destination != nil
                ),
                presentation: presentation,
                destination: destination
            )
        }

        return applyInlineContext(
            linkifiedBareURLRuns(
                splitInlineMath(in: text.string, baseRange: sourceRange),
                alreadyLinked: destination != nil
            ),
            presentation: presentation,
            destination: destination
        )
    }

    private func linkifiedBareURLRuns(
        _ runs: [MarkdownInlineRun],
        alreadyLinked: Bool
    ) -> [MarkdownInlineRun] {
        guard !alreadyLinked else {
            return runs
        }

        return runs.flatMap { run -> [MarkdownInlineRun] in
            guard run.kind == .text,
                  run.destination == nil,
                  !run.presentation.contains(.code),
                  !run.presentation.contains(.math),
                  !run.presentation.contains(.html),
                  let sourceRange = run.sourceRange
            else {
                return [run]
            }
            return bareURLRuns(in: run.text, baseRange: sourceRange, presentation: run.presentation)
        }
    }

    private func bareURLRuns(
        in text: String,
        baseRange: MarkdownSourceRange,
        presentation: MarkdownInlinePresentation
    ) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        var cursor = text.startIndex
        var plainStart = cursor

        func appendPlain(upTo end: String.Index) {
            guard plainStart < end else {
                return
            }
            runs.append(
                MarkdownInlineRun(
                    kind: primaryStyleKind(for: presentation),
                    text: String(text[plainStart..<end]),
                    sourceRange: sourceRange(in: text, localRange: plainStart..<end, baseRange: baseRange),
                    presentation: presentation
                )
            )
        }

        while cursor < text.endIndex {
            guard let match = bareURLMatch(in: text, at: cursor) else {
                cursor = text.index(after: cursor)
                continue
            }

            appendPlain(upTo: match.full.lowerBound)
            let destination = String(text[match.url])
            runs.append(
                MarkdownInlineRun(
                    kind: .link,
                    text: destination,
                    sourceRange: sourceRange(in: text, localRange: match.url, baseRange: baseRange),
                    destination: destination,
                    presentation: presentation
                )
            )
            cursor = match.full.upperBound
            plainStart = cursor
        }

        appendPlain(upTo: text.endIndex)
        return runs.isEmpty ? [
            MarkdownInlineRun(
                kind: primaryStyleKind(for: presentation),
                text: text,
                sourceRange: baseRange,
                presentation: presentation
            )
        ] : runs
    }

    private func bareURLMatch(
        in text: String,
        at cursor: String.Index
    ) -> (url: Range<String.Index>, full: Range<String.Index>)? {
        guard startsBareURLScheme(in: text, at: cursor),
              bareURLCanStart(in: text, at: cursor),
              !bareURLIsReferenceDefinitionDestination(in: text, at: cursor)
        else {
            return nil
        }

        var scan = cursor
        while scan < text.endIndex, bareURLCanContain(text[scan]) {
            scan = text.index(after: scan)
        }

        let full = cursor..<scan
        let trimmedUpper = trimmedBareURLUpperBound(in: text, range: full)
        guard cursor < trimmedUpper else {
            return nil
        }

        let url = cursor..<trimmedUpper
        guard bareURLHasHostLikeContent(String(text[url])) else {
            return nil
        }
        return (url: url, full: full)
    }

    private func bareURLIsReferenceDefinitionDestination(
        in text: String,
        at cursor: String.Index
    ) -> Bool {
        let lineStart = startOfLine(containing: cursor, in: text)
        let prefix = String(text[lineStart..<cursor])
        return linePrefixLooksLikeReferenceDefinitionDestination(prefix)
    }

    private func linePrefixLooksLikeReferenceDefinitionDestination(_ prefix: String) -> Bool {
        var current = prefix
        while true {
            let stripped = current.drop { $0 == " " || $0 == "\t" }
            current = String(stripped)
            if let quote = stripLeadingBlockQuoteMarker(from: current) {
                current = quote
                continue
            }
            if let list = stripLeadingListItemMarker(from: current) {
                current = list
                continue
            }
            break
        }

        let trimmed = current.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["),
              let separator = trimmed.range(of: "]:")
        else {
            return false
        }
        let destinationPrefix = trimmed[separator.upperBound...]
        return destinationPrefix.allSatisfy { $0 == " " || $0 == "\t" || $0 == "<" }
    }

    private func startOfLine(containing index: String.Index, in text: String) -> String.Index {
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

    private func startsBareURLScheme(in text: String, at cursor: String.Index) -> Bool {
        text[cursor...].hasPrefix("https://") || text[cursor...].hasPrefix("http://")
    }

    private func bareURLCanStart(in text: String, at cursor: String.Index) -> Bool {
        guard cursor > text.startIndex else {
            return true
        }
        let previous = text[text.index(before: cursor)]
        return previous.isWhitespace || "([{\"'".contains(previous)
    }

    private func bareURLCanContain(_ character: Character) -> Bool {
        !character.isWhitespace && !"<>\"".contains(character)
    }

    private func trimmedBareURLUpperBound(
        in text: String,
        range: Range<String.Index>
    ) -> String.Index {
        var upper = range.upperBound
        while upper > range.lowerBound {
            let previous = text.index(before: upper)
            let character = text[previous]
            if ".,;:!?".contains(character) {
                upper = previous
                continue
            }
            if ")]}".contains(character),
               closingBareURLDelimiterIsUnmatched(character, in: String(text[range.lowerBound..<upper])) {
                upper = previous
                continue
            }
            break
        }
        return upper
    }

    private func closingBareURLDelimiterIsUnmatched(_ delimiter: Character, in candidate: String) -> Bool {
        let opener: Character
        switch delimiter {
        case ")":
            opener = "("
        case "]":
            opener = "["
        case "}":
            opener = "{"
        default:
            return false
        }
        return candidate.filter { $0 == delimiter }.count > candidate.filter { $0 == opener }.count
    }

    private func bareURLHasHostLikeContent(_ candidate: String) -> Bool {
        guard let schemeRange = candidate.range(of: "://") else {
            return false
        }
        let hostStart = schemeRange.upperBound
        guard hostStart < candidate.endIndex else {
            return false
        }
        let hostEnd = candidate[hostStart...].firstIndex { "/?#".contains($0) } ?? candidate.endIndex
        let host = candidate[hostStart..<hostEnd]
        return host.contains(".") || host == "localhost" || host.hasPrefix("localhost:")
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
               let dollarMath = dollarInlineMathRange(in: rawText, at: cursor) {
                appendPlain(upTo: cursor)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(rawText[dollarMath.content]),
                        sourceRange: sourceRange(
                            in: rawText,
                            localRange: dollarMath.full,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = dollarMath.full.upperBound
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

            if rawText[cursor] == "\\",
               let bareTex = bareTexMathRange(in: rawText, at: cursor) {
                appendPlain(upTo: bareTex.full.lowerBound)
                runs.append(
                    MarkdownInlineRun(
                        kind: .math,
                        text: String(rawText[bareTex.content]),
                        sourceRange: sourceRange(
                            in: rawText,
                            localRange: bareTex.full,
                            baseRange: baseRange
                        )
                    )
                )
                cursor = bareTex.full.upperBound
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
                  let dollarMath = dollarInlineMathRange(in: text, at: cursor)
            else {
                if text[cursor] == "\\",
                   let latex = latexInlineMathRange(in: text, at: cursor) {
                    appendPlain(upTo: cursor)
                    runs.append(
                        MarkdownInlineRun(
                            kind: .math,
                            text: String(text[latex.content]),
                            sourceRange: sourceRange(
                                in: text,
                                localRange: latex.full,
                                baseRange: baseRange
                            )
                        )
                    )
                    cursor = latex.full.upperBound
                    plainStart = cursor
                    continue
                }

                if text[cursor] == "\\",
                   let bareTex = bareTexMathRange(in: text, at: cursor) {
                    appendPlain(upTo: bareTex.full.lowerBound)
                    runs.append(
                        MarkdownInlineRun(
                            kind: .math,
                            text: String(text[bareTex.content]),
                            sourceRange: sourceRange(
                                in: text,
                                localRange: bareTex.full,
                                baseRange: baseRange
                            )
                        )
                    )
                    cursor = bareTex.full.upperBound
                    plainStart = cursor
                    continue
                }

                cursor = text.index(after: cursor)
                continue
            }

            appendPlain(upTo: cursor)
            runs.append(
                MarkdownInlineRun(
                    kind: .math,
                    text: String(text[dollarMath.content]),
                    sourceRange: sourceRange(
                        in: text,
                        localRange: dollarMath.full,
                        baseRange: baseRange
                    )
                )
            )
            cursor = dollarMath.full.upperBound
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
            text.contains("\n[") ||
            containsBareTexCommandCandidate(text)
    }

    private func containsBareTexCommandCandidate(_ text: String) -> Bool {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard text[cursor] == "\\" else {
                cursor = text.index(after: cursor)
                continue
            }

            if let command = texCommandName(in: text, at: cursor),
               Self.bareTexCommands.contains(command.name) {
                return true
            }

            cursor = text.index(after: cursor)
        }
        return false
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

    private func bareTexMathRange(
        in text: String,
        at cursor: String.Index
    ) -> (content: Range<String.Index>, full: Range<String.Index>)? {
        guard text[cursor] == "\\",
              !isEscapedDelimiter(in: text, at: cursor),
              bareTexCommandCanStart(in: text, at: cursor),
              let command = texCommandName(in: text, at: cursor),
              Self.bareTexCommands.contains(command.name)
        else {
            return nil
        }

        let lower: String.Index
        if let expressionStart = leftBareTexExpressionStart(before: cursor, in: text) {
            lower = expressionStart
        } else if Self.bareTexInfixCommands.contains(command.name),
                  let operandStart = leftMathOperandStart(before: cursor, in: text) {
            lower = operandStart
        } else {
            lower = cursor
        }

        let upper = bareTexExpressionUpperBound(in: text, from: cursor, lowerBound: lower)
        guard lower < upper else {
            return nil
        }

        let expression = String(text[lower..<upper])
        guard bareTexExpressionLooksSafe(expression) else {
            return nil
        }

        return (lower..<upper, lower..<upper)
    }

    private func bareTexCommandCanStart(in text: String, at cursor: String.Index) -> Bool {
        guard cursor > text.startIndex else {
            return true
        }

        let previous = text[text.index(before: cursor)]
        return previous.isWhitespace || isBareTexOperator(previous) || "([{".contains(previous)
    }

    private func bareTexExpressionUpperBound(
        in text: String,
        from commandStart: String.Index,
        lowerBound: String.Index
    ) -> String.Index {
        var cursor = commandStart
        var lastContentEnd = commandStart
        var openDelimiters = unmatchedOpeningDelimiters(
            in: text,
            range: lowerBound..<commandStart
        )

        while cursor < text.endIndex {
            let tokenStart = cursor
            if let command = texCommandName(in: text, at: cursor),
               Self.bareTexCommands.contains(command.name),
               !isEscapedDelimiter(in: text, at: cursor) {
                cursor = command.upperBound
                while let groupEnd = balancedGroupUpperBound(in: text, at: cursor, open: "{", close: "}") {
                    cursor = groupEnd
                }
                lastContentEnd = cursor
                continue
            }

            if let symbolEnd = texSymbolUpperBound(in: text, at: cursor) {
                cursor = symbolEnd
                lastContentEnd = cursor
                continue
            }

            if text[cursor].isWhitespace {
                let whitespaceStart = cursor
                repeat {
                    cursor = text.index(after: cursor)
                } while cursor < text.endIndex && text[cursor].isWhitespace && !text[cursor].isNewline

                guard cursor < text.endIndex,
                      !text[cursor].isNewline,
                      canContinueBareTexExpression(in: text, at: cursor)
                else {
                    return lastContentEnd
                }

                lastContentEnd = whitespaceStart
                continue
            }

            if let groupEnd = balancedGroupUpperBound(in: text, at: cursor, open: "(", close: ")") {
                cursor = groupEnd
                lastContentEnd = cursor
                continue
            }

            if let groupEnd = balancedGroupUpperBound(in: text, at: cursor, open: "[", close: "]") {
                cursor = groupEnd
                lastContentEnd = cursor
                continue
            }

            if let groupEnd = balancedGroupUpperBound(in: text, at: cursor, open: "{", close: "}") {
                cursor = groupEnd
                lastContentEnd = cursor
                continue
            }

            if closesOpenBareTexDelimiter(text[cursor], stack: &openDelimiters) {
                cursor = text.index(after: cursor)
                lastContentEnd = cursor
                continue
            }

            if isBareTexInternalSeparator(text[cursor]) {
                let separatorEnd = text.index(after: cursor)
                var continuation = separatorEnd
                while continuation < text.endIndex,
                      text[continuation].isWhitespace,
                      !text[continuation].isNewline {
                    continuation = text.index(after: continuation)
                }

                guard continuation < text.endIndex,
                      !text[continuation].isNewline,
                      canContinueBareTexExpression(in: text, at: continuation)
                else {
                    return tokenStart == commandStart ? commandStart : lastContentEnd
                }

                cursor = separatorEnd
                lastContentEnd = cursor
                continue
            }

            if isBareTexOperator(text[cursor]) {
                cursor = text.index(after: cursor)
                lastContentEnd = cursor
                continue
            }

            if let operandEnd = simpleBareTexOperandUpperBound(in: text, at: cursor) {
                cursor = operandEnd
                lastContentEnd = cursor
                continue
            }

            return tokenStart == commandStart ? commandStart : lastContentEnd
        }

        return lastContentEnd
    }

    private func unmatchedOpeningDelimiters(
        in text: String,
        range: Range<String.Index>
    ) -> [Character] {
        var stack: [Character] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            let character = text[cursor]
            if isBareTexOpeningDelimiter(character) {
                stack.append(character)
            } else if let expected = matchingBareTexOpeningDelimiter(forClosing: character),
                      stack.last == expected {
                stack.removeLast()
            }
            cursor = text.index(after: cursor)
        }

        return stack
    }

    private func closesOpenBareTexDelimiter(
        _ character: Character,
        stack: inout [Character]
    ) -> Bool {
        guard let expected = matchingBareTexOpeningDelimiter(forClosing: character),
              stack.last == expected
        else {
            return false
        }

        stack.removeLast()
        return true
    }

    private func isBareTexOpeningDelimiter(_ character: Character) -> Bool {
        character == "(" || character == "[" || character == "{"
    }

    private func matchingBareTexOpeningDelimiter(forClosing character: Character) -> Character? {
        switch character {
        case ")":
            return "("
        case "]":
            return "["
        case "}":
            return "{"
        default:
            return nil
        }
    }

    private func canContinueBareTexExpression(in text: String, at cursor: String.Index) -> Bool {
        if let command = texCommandName(in: text, at: cursor),
           Self.bareTexCommands.contains(command.name),
           !isEscapedDelimiter(in: text, at: cursor) {
            return true
        }

        if isBareTexOperator(text[cursor]) {
            return true
        }

        return simpleBareTexOperandUpperBound(in: text, at: cursor) != nil
    }

    private func simpleBareTexOperandUpperBound(
        in text: String,
        at cursor: String.Index
    ) -> String.Index? {
        guard cursor < text.endIndex else {
            return nil
        }

        var scan = cursor
        while scan < text.endIndex, isBareTexOperandCharacter(text[scan]) {
            scan = text.index(after: scan)
        }

        if let trimmed = trimmedBareTexOperandUpperBound(in: text, lower: cursor, upper: scan) {
            return trimmed
        }

        return nil
    }

    private func trimmedBareTexOperandUpperBound(
        in text: String,
        lower: String.Index,
        upper: String.Index
    ) -> String.Index? {
        var candidateUpper = upper
        while lower < candidateUpper {
            let token = String(text[lower..<candidateUpper])
            if bareTexOperandTokenLooksSafe(token) {
                return candidateUpper
            }

            let previous = text.index(before: candidateUpper)
            guard text[previous] == "." else {
                return nil
            }
            candidateUpper = previous
        }

        return nil
    }

    private func leftBareTexExpressionStart(
        before commandStart: String.Index,
        in text: String
    ) -> String.Index? {
        guard commandStart > text.startIndex else {
            return nil
        }

        var cursor = commandStart
        var lower = commandStart
        var sawOperator = false

        while cursor > text.startIndex {
            while cursor > text.startIndex {
                let previous = text.index(before: cursor)
                guard text[previous].isWhitespace, !text[previous].isNewline else {
                    break
                }
                cursor = previous
            }

            guard cursor > text.startIndex else {
                break
            }

            let previous = text.index(before: cursor)
            if isBareTexOperator(text[previous]) {
                sawOperator = true
                lower = previous
                cursor = previous
                continue
            }

            if let groupedOperandStart = simpleBareTexGroupedOperandLowerBound(
                endingAt: cursor,
                in: text
            ) {
                lower = groupedOperandStart
                cursor = groupedOperandStart
                continue
            }

            if let operandStart = simpleBareTexOperandLowerBound(endingAt: cursor, in: text) {
                lower = operandStart
                cursor = operandStart
                continue
            }

            if text[previous] == "(",
               let functionStart = simpleBareTexOperandLowerBound(endingAt: previous, in: text) {
                lower = functionStart
                cursor = functionStart
                sawOperator = true
                continue
            }

            break
        }

        guard sawOperator, lower < commandStart else {
            return nil
        }

        return lower
    }

    private func simpleBareTexGroupedOperandLowerBound(
        endingAt upperBound: String.Index,
        in text: String
    ) -> String.Index? {
        guard upperBound > text.startIndex else {
            return nil
        }

        let closingIndex = text.index(before: upperBound)
        guard let expectedOpening = matchingBareTexOpeningDelimiter(forClosing: text[closingIndex]) else {
            return nil
        }

        var depth = 1
        var scan = closingIndex
        while scan > text.startIndex {
            scan = text.index(before: scan)
            let character = text[scan]
            if character == text[closingIndex] {
                depth += 1
            } else if character == expectedOpening {
                depth -= 1
                if depth == 0 {
                    if let functionStart = simpleBareTexOperandLowerBound(endingAt: scan, in: text) {
                        return functionStart
                    }
                    return scan
                }
            } else if character.isNewline {
                return nil
            }
        }

        return nil
    }

    private func simpleBareTexOperandLowerBound(
        endingAt upperBound: String.Index,
        in text: String
    ) -> String.Index? {
        guard upperBound > text.startIndex else {
            return nil
        }

        var scan = upperBound
        while scan > text.startIndex {
            let previous = text.index(before: scan)
            guard isBareTexOperandCharacter(text[previous]) else {
                break
            }
            scan = previous
        }

        while scan < upperBound {
            let token = String(text[scan..<upperBound])
            if bareTexOperandTokenLooksSafe(token) {
                return scan
            }

            guard text[scan] == "." else {
                return nil
            }
            scan = text.index(after: scan)
        }

        return nil
    }

    private func leftMathOperandStart(
        before commandStart: String.Index,
        in text: String
    ) -> String.Index? {
        guard commandStart > text.startIndex else {
            return nil
        }

        var cursor = commandStart
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            guard text[previous].isWhitespace, !text[previous].isNewline else {
                break
            }
            cursor = previous
        }

        let operandEnd = cursor
        guard operandEnd > text.startIndex else {
            return nil
        }

        guard let operandStart = simpleBareTexOperandLowerBound(endingAt: operandEnd, in: text) else {
            return nil
        }

        return operandStart
    }

    private func isBareTexOperandCharacter(_ character: Character) -> Bool {
        character.isLetter ||
            character.isNumber ||
            character == "." ||
            character == "_" ||
            character == "^" ||
            isScriptCharacter(character)
    }

    private func bareTexOperandTokenLooksSafe(_ token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }

        let scalars = Array(token.unicodeScalars)
        let isNumeric = scalars.allSatisfy { scalar in
            CharacterSet.decimalDigits.contains(scalar) || scalar == "."
        }
        if isNumeric {
            let dotCount = scalars.filter { $0 == "." }.count
            return scalars.contains { CharacterSet.decimalDigits.contains($0) } &&
                dotCount <= 1 &&
                !token.hasPrefix(".") &&
                !token.hasSuffix(".")
        }

        guard !token.hasPrefix("."),
              !token.hasSuffix(".")
        else {
            return false
        }

        let containsScriptMarker = token.contains("_") ||
            token.contains("^") ||
            token.contains(where: isScriptCharacter)
        if containsScriptMarker {
            return token.count <= 8 && token.contains(where: { $0.isLetter || $0.isNumber })
        }

        if token.count == 1, token.first?.isLetter == true {
            return true
        }

        if token.count <= 3,
           token.first?.isLetter == true,
           token.dropFirst().allSatisfy(\.isNumber) {
            return true
        }

        if isCompactNumberLetterProduct(token) {
            return true
        }

        return false
    }

    private func bareTexExpressionLooksSafe(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\\"),
              trimmed.range(of: #"\\[A-Za-z]+"#, options: .regularExpression) != nil
        else {
            return false
        }

        return trimmed.contains(where: { character in
            character == "{" ||
                character == "}" ||
                character == "_" ||
                character == "^" ||
                character == "=" ||
                character.isNumber ||
                character == "\\"
        })
    }

    private func texCommandName(
        in text: String,
        at cursor: String.Index
    ) -> (name: String, upperBound: String.Index)? {
        guard cursor < text.endIndex,
              text[cursor] == "\\"
        else {
            return nil
        }

        var scan = text.index(after: cursor)
        guard scan < text.endIndex,
              text[scan].isLetter
        else {
            return nil
        }

        let nameStart = scan
        repeat {
            scan = text.index(after: scan)
        } while scan < text.endIndex && text[scan].isLetter

        return (String(text[nameStart..<scan]).lowercased(), scan)
    }

    private func balancedGroupUpperBound(
        in text: String,
        at cursor: String.Index,
        open: Character,
        close: Character
    ) -> String.Index? {
        guard cursor < text.endIndex,
              text[cursor] == open
        else {
            return nil
        }

        var depth = 0
        var scan = cursor
        while scan < text.endIndex {
            if text[scan] == open {
                depth += 1
            } else if text[scan] == close {
                depth -= 1
                if depth == 0 {
                    return text.index(after: scan)
                }
            } else if text[scan].isNewline {
                return nil
            }
            scan = text.index(after: scan)
        }
        return nil
    }

    private func texSymbolUpperBound(in text: String, at cursor: String.Index) -> String.Index? {
        guard cursor < text.endIndex,
              text[cursor] == "\\"
        else {
            return nil
        }

        let symbol = text.index(after: cursor)
        guard symbol < text.endIndex,
              !text[symbol].isLetter,
              text[symbol] == "\\" || "|{}[](),;:!".contains(text[symbol])
        else {
            return nil
        }

        return text.index(after: symbol)
    }

    private func isBareTexOperator(_ character: Character) -> Bool {
        "+-=*/_^·−×÷≤≥<>|&".contains(character)
    }

    private func isBareTexInternalSeparator(_ character: Character) -> Bool {
        character == ","
    }

    private func isScriptCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }

        return scalar.value == 0x00B2 ||
            scalar.value == 0x00B3 ||
            scalar.value == 0x00B9 ||
            (0x2070...0x209F).contains(scalar.value)
    }

    private func dollarInlineMathRange(
        in text: String,
        at opening: String.Index
    ) -> (content: Range<String.Index>, full: Range<String.Index>)? {
        guard text[opening] == "$",
              isPotentialOpeningDollar(in: text, at: opening),
              let close = closingDollar(in: text, after: opening)
        else {
            return nil
        }

        let contentStart = text.index(after: opening)
        let contentRange = contentStart..<close
        guard isValidDollarMathContent(in: text, contentRange: contentRange, opening: opening) else {
            return nil
        }

        return (contentRange, opening..<text.index(after: close))
    }

    private func isValidDollarMathContent(
        in text: String,
        contentRange: Range<String.Index>,
        opening: String.Index
    ) -> Bool {
        guard !contentRange.isEmpty,
              !containsUnescapedDollar(in: text, range: contentRange)
        else {
            return false
        }

        let firstContent = text.index(after: opening)
        if firstContent < text.endIndex, text[firstContent].isNumber {
            return numericLeadingDollarMathContentLooksLikeMath(String(text[contentRange]))
        }

        return true
    }

    private func containsUnescapedDollar(in text: String, range: Range<String.Index>) -> Bool {
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if text[cursor] == "$", !isEscapedDelimiter(in: text, at: cursor) {
                return true
            }
            cursor = text.index(after: cursor)
        }
        return false
    }

    private func numericLeadingDollarMathContentLooksLikeMath(_ content: String) -> Bool {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return false
        }

        if body.contains("\\") ||
            body.contains("_") ||
            body.contains("^") ||
            body.contains("=") ||
            body.contains("+") ||
            body.contains("*") ||
            body.contains("/") ||
            body.contains("{") ||
            body.contains("}") ||
            body.contains("(") ||
            body.contains(")") ||
            body.contains("[") ||
            body.contains("]") {
            return true
        }

        if isSimpleNumericExpression(body) {
            return true
        }

        return isCompactNumberLetterProduct(body)
    }

    private func isSimpleNumericExpression(_ body: String) -> Bool {
        guard !body.isEmpty,
              !body.contains(where: { $0.isWhitespace || $0 == "," || $0 == "$" })
        else {
            return false
        }

        var cursor = body.startIndex
        var sawDigit = false
        var previousWasOperator = true

        while cursor < body.endIndex {
            let character = body[cursor]
            if character.isNumber {
                sawDigit = true
                previousWasOperator = false
                cursor = body.index(after: cursor)
                continue
            }

            if character == "." {
                let next = body.index(after: cursor)
                guard next < body.endIndex, body[next].isNumber else {
                    return false
                }
                cursor = next
                continue
            }

            if character == "-" {
                guard !previousWasOperator else {
                    return false
                }
                previousWasOperator = true
                cursor = body.index(after: cursor)
                continue
            }

            return false
        }

        return sawDigit && !previousWasOperator
    }

    private func isCompactNumberLetterProduct(_ body: String) -> Bool {
        guard !body.contains(where: { $0.isWhitespace || $0 == "," }) else {
            return false
        }

        var cursor = body.startIndex
        var sawDigit = false
        while cursor < body.endIndex, body[cursor].isNumber {
            sawDigit = true
            cursor = body.index(after: cursor)
        }

        if cursor < body.endIndex, body[cursor] == "." {
            let decimalPoint = cursor
            cursor = body.index(after: cursor)
            var sawFractionDigit = false
            while cursor < body.endIndex, body[cursor].isNumber {
                sawFractionDigit = true
                cursor = body.index(after: cursor)
            }

            if !sawFractionDigit {
                cursor = decimalPoint
            }
        }

        guard sawDigit, cursor < body.endIndex else {
            return false
        }

        var sawLetter = false
        var suffix = ""
        while cursor < body.endIndex {
            let character = body[cursor]
            guard character.isLetter || character.isNumber else {
                return false
            }
            if character.isLetter {
                sawLetter = true
            }
            suffix.append(character)
            cursor = body.index(after: cursor)
        }

        if isCurrencyCodeSuffix(suffix) {
            return false
        }

        return sawLetter
    }

    private func isCurrencyCodeSuffix(_ suffix: String) -> Bool {
        Self.currencyCodeSuffixes.contains(suffix.uppercased())
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

    private func lineBreakRun(
        kind: MarkdownInlineKind,
        text: String,
        markup: Markup,
        destination: String? = nil,
        presentation: MarkdownInlinePresentation? = nil
    ) -> MarkdownInlineRun {
        let sourceRange = lineBreakSourceRange(for: markup, kind: kind)
        return MarkdownInlineRun(
            kind: kind,
            text: text,
            sourceRange: sourceRange,
            destination: destination,
            presentation: presentation
        )
    }

    private func lineBreakSourceRange(for markup: Markup, kind: MarkdownInlineKind) -> MarkdownSourceRange {
        guard let markupRange = sourceRange(for: markup),
              let breakRange = lineBreakByteRange(near: markupRange.byteRange, kind: kind)
        else {
            return sourceRange(for: markup) ?? fallbackRange
        }
        return MarkdownSourceRange(
            byteRange: breakRange,
            lineRange: lineMap.lineRange(for: breakRange)
        )
    }

    private func lineBreakByteRange(
        near absoluteRange: Range<Int>,
        kind: MarkdownInlineKind
    ) -> Range<Int>? {
        let localLower = clampedLocalByteOffset(absoluteRange.lowerBound)
        let localUpper = clampedLocalByteOffset(absoluteRange.upperBound)
        guard let lineFeed = lineFeedOffset(near: localLower..<localUpper) else {
            return nil
        }

        let breakLower = lineFeed > 0 && byte(atLocalOffset: lineFeed - 1) == 13
            ? lineFeed - 1
            : lineFeed
        let breakUpper = min(source.utf8.count, lineFeed + 1)
        var sourceLower = breakLower

        if kind == .hardBreak {
            if sourceLower > 0, byte(atLocalOffset: sourceLower - 1) == 92 {
                sourceLower -= 1
            } else {
                let whitespaceLower = trailingInlineWhitespaceLowerBound(before: sourceLower)
                if sourceLower - whitespaceLower >= 2 {
                    sourceLower = whitespaceLower
                }
            }
        }

        let absoluteLower = baseOffset + sourceLower
        let absoluteUpper = baseOffset + breakUpper
        guard absoluteLower <= absoluteUpper else {
            return nil
        }
        return absoluteLower..<absoluteUpper
    }

    private func lineFeedOffset(near localRange: Range<Int>) -> Int? {
        let count = source.utf8.count
        guard count > 0 else {
            return nil
        }

        let anchorLower = min(max(0, localRange.lowerBound), count)
        let anchorUpper = min(max(anchorLower, localRange.upperBound), count)
        let searchLower = max(0, anchorLower - 8)
        let searchUpper = min(count, max(anchorUpper, anchorLower + 8))

        if anchorLower < count, byte(atLocalOffset: anchorLower) == 10 {
            return anchorLower
        }
        if anchorLower > 0, byte(atLocalOffset: anchorLower - 1) == 10 {
            return anchorLower - 1
        }

        var forward = anchorLower
        while forward < searchUpper {
            if byte(atLocalOffset: forward) == 10 {
                return forward
            }
            forward += 1
        }

        var backward = min(count - 1, max(searchLower, anchorLower - 1))
        while backward >= searchLower {
            if byte(atLocalOffset: backward) == 10 {
                return backward
            }
            if backward == 0 {
                break
            }
            backward -= 1
        }

        return nil
    }

    private func trailingInlineWhitespaceLowerBound(before localOffset: Int) -> Int {
        var cursor = min(max(0, localOffset), source.utf8.count)
        while cursor > 0 {
            let previous = cursor - 1
            let byte = byte(atLocalOffset: previous)
            guard byte == 32 || byte == 9 else {
                break
            }
            cursor = previous
        }
        return cursor
    }

    private func clampedLocalByteOffset(_ absoluteOffset: Int) -> Int {
        min(max(0, absoluteOffset - baseOffset), source.utf8.count)
    }

    private func byte(atLocalOffset offset: Int) -> UInt8? {
        guard offset >= 0, offset < source.utf8.count else {
            return nil
        }
        let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
        return source.utf8[index]
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
        sourceLocationIndex.byteOffset(for: location, baseOffset: baseOffset)
    }
}

/// `swift-markdown` reports AST ranges as one-based line/UTF-8-column
/// locations. Converting each location by rescanning `source` from byte zero
/// makes AST conversion quadratic for large single blocks (tables are the
/// worst case because every cell and inline has its own range). Build the
/// line-start table once per parser boundary and share its copy-on-write
/// storage with every inline converter instead.
private struct MarkdownSourceLocationIndex: Sendable {
    private let lineStartByteOffsets: [Int]
    private let sourceByteCount: Int

    init(source: String) {
        var lineStarts = [0]
        lineStarts.reserveCapacity(64)
        for (offset, byte) in source.utf8.enumerated() where byte == 10 {
            lineStarts.append(offset + 1)
        }
        self.lineStartByteOffsets = lineStarts
        self.sourceByteCount = source.utf8.count
    }

    func byteOffset(for location: SourceLocation, baseOffset: Int) -> Int {
        let lineIndex = min(
            max(0, location.line - 1),
            lineStartByteOffsets.count - 1
        )
        let lineStart = lineStartByteOffsets[lineIndex]
        let localOffset = min(
            sourceByteCount,
            lineStart + max(0, location.column - 1)
        )
        return baseOffset + localOffset
    }
}
