import Foundation
import Markdown

public struct SwiftMarkdownParser: Sendable {
    public init() {}

    public func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool
    ) -> [MarkdownBlock] {
        let source = slice.text
        guard !source.isEmpty else {
            return []
        }

        let document = Document(parsing: source, options: [.disableSmartOpts])
        return SwiftMarkdownRenderModelConverter(
            source: source,
            baseOffset: slice.byteRange.lowerBound,
            lineMap: lineMap,
            idNamespace: idNamespace,
            isSealed: isSealed
        ).convert(document)
    }
}

private struct SwiftMarkdownRenderModelConverter {
    var source: String
    var baseOffset: Int
    var lineMap: MarkdownLineMap
    var idNamespace: String
    var isSealed: Bool

    private var sliceByteCount: Int {
        source.utf8.count
    }

    func convert(_ document: Document) -> [MarkdownBlock] {
        document.children.enumerated().map { sequence, child in
            convertBlock(child, sequence: sequence)
        }
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
        case is OrderedList:
            return .orderedList
        case is Table:
            return .table
        case is Paragraph where isMathBlock(rawText):
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
            if isMathBlock(sourceText(for: fallbackRange.byteRange)) {
                return [
                    MarkdownInlineRun(
                        kind: .math,
                        text: mathContent(sourceText(for: fallbackRange.byteRange)),
                        sourceRange: fallbackRange
                    )
                ]
            }
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: paragraph.children)
        case let quote as BlockQuote:
            return inlineRunConverter(fallbackRange: fallbackRange).runs(in: quote.children)
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

    private func inlineRunConverter(fallbackRange: MarkdownSourceRange) -> InlineRunConverter {
        InlineRunConverter(
            source: source,
            baseOffset: baseOffset,
            lineMap: lineMap,
            fallbackRange: fallbackRange
        )
    }

    private func listContainsTaskItems(_ list: UnorderedList) -> Bool {
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
        return item.children.flatMap { child -> [MarkdownInlineRun] in
            switch child {
            case is UnorderedList, is OrderedList:
                return []
            case let paragraph as Paragraph:
                return converter.runs(in: paragraph.children)
            default:
                return converter.runs(in: child.children)
            }
        }
    }

    private func nestedListMetadata(in item: ListItem) -> (kind: MarkdownBlockKind?, orderedStart: UInt?) {
        for child in item.children {
            if let list = child as? UnorderedList {
                return (listContainsTaskItems(list) ? .taskList : .unorderedList, nil)
            }

            if let list = child as? OrderedList {
                return (.orderedList, list.startIndex)
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

    private func isMathBlock(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count >= 4
    }

    private func mathContent(_ rawText: String) -> String {
        var lines = rawText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "$$" {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "$$" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func stableContentHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

private struct InlineRunConverter {
    var source: String
    var baseOffset: Int
    var lineMap: MarkdownLineMap
    var fallbackRange: MarkdownSourceRange

    func runs(in children: MarkupChildren) -> [MarkdownInlineRun] {
        children.flatMap { runs(in: $0) }
    }

    private func runs(in markup: Markup) -> [MarkdownInlineRun] {
        switch markup {
        case let text as Markdown.Text:
            return textRuns(for: text)
        case let code as InlineCode:
            return [run(kind: .code, text: code.code, markup: code)]
        case let softBreak as SoftBreak:
            return [run(kind: .softBreak, text: "\n", markup: softBreak)]
        case let lineBreak as LineBreak:
            return [run(kind: .hardBreak, text: "\n", markup: lineBreak)]
        case let emphasis as Emphasis:
            return [run(kind: .emphasis, text: plainText(in: emphasis.children), markup: emphasis)]
        case let strong as Strong:
            return [run(kind: .strong, text: plainText(in: strong.children), markup: strong)]
        case let strikethrough as Strikethrough:
            return [run(kind: .strikethrough, text: plainText(in: strikethrough.children), markup: strikethrough)]
        case let link as Link:
            return [
                run(
                    kind: .link,
                    text: plainText(in: link.children),
                    markup: link,
                    destination: link.destination
                )
            ]
        case let image as Markdown.Image:
            return [
                run(
                    kind: .image,
                    text: plainText(in: image.children),
                    markup: image,
                    destination: image.source
                )
            ]
        case let html as InlineHTML:
            return [run(kind: .text, text: html.rawHTML, markup: html)]
        default:
            return runs(in: markup.children)
        }
    }

    private func textRuns(for text: Markdown.Text) -> [MarkdownInlineRun] {
        guard let sourceRange = sourceRange(for: text) else {
            return splitInlineMath(in: text.string, baseRange: fallbackRange)
        }

        let rawText = sourceText(for: sourceRange.byteRange)
        if rawText != text.string, rawText.contains("$") {
            return splitInlineMathInSource(rawText, baseRange: sourceRange)
        }

        return splitInlineMath(in: text.string, baseRange: sourceRange)
    }

    private func splitInlineMathInSource(
        _ rawText: String,
        baseRange: MarkdownSourceRange
    ) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRun] = []
        var cursor = rawText.startIndex
        var plainStart = cursor

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
            guard rawText[cursor] == "$",
                  isPotentialOpeningDollar(in: rawText, at: cursor),
                  let close = closingDollar(in: rawText, after: cursor)
            else {
                cursor = rawText.index(after: cursor)
                continue
            }

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
        guard text.contains("$") else {
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

    private func isPotentialOpeningDollar(in text: String, at index: String.Index) -> Bool {
        if index > text.startIndex, text[text.index(before: index)] == "\\" {
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

    private func closingDollar(in text: String, after opening: String.Index) -> String.Index? {
        var cursor = text.index(after: opening)
        while cursor < text.endIndex {
            defer {
                cursor = text.index(after: cursor)
            }

            guard text[cursor] == "$" else {
                continue
            }

            if cursor > text.startIndex, text[text.index(before: cursor)] == "\\" {
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
        destination: String? = nil
    ) -> MarkdownInlineRun {
        MarkdownInlineRun(
            kind: kind,
            text: text,
            sourceRange: sourceRange(for: markup) ?? fallbackRange,
            destination: destination
        )
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
