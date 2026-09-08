import Foundation
import SiriusMarkdownCore
#if os(macOS)
import AppKit
#endif

/// Serializes existing semantic models at copy time. It never reparses source,
/// imports HTML through AppKit, resolves resources, or copies decoration icons.
@MainActor
enum MarkdownRichCopy {
    struct TableCellLocation: Hashable {
        var tableID: MarkdownBlockID
        var rowIndex: Int
        var cellIndex: Int
    }

    struct TextRun {
        var text: String
        var presentation: MarkdownInlinePresentation = []
        var link: URL? = nil
        var headingLevel: Int? = nil
        var indentation: Double = 0
        var tableCell: TableCellLocation? = nil
    }

    struct Fragment {
        var html = ""
        var runs: [TextRun] = []

        mutating func append(_ other: Fragment) {
            html += other.html
            runs.append(contentsOf: other.runs)
        }

        func wrapped(_ tag: String, attributes: String = "", separator: String = "") -> Fragment {
            guard !html.isEmpty else { return self }
            return Fragment(html: "<\(tag)\(attributes)>\(html)</\(tag)>", runs: runs + (separator.isEmpty ? [] : [TextRun(text: separator)]))
        }
    }

    static func addingRichRepresentations(
        to payload: MarkdownPasteboardPayload,
        snapshot: MarkdownPreparedSnapshot,
        ranges: [MarkdownSourceRange]
    ) -> MarkdownPasteboardPayload {
        guard !payload.plainText.isEmpty else { return payload }
        let result = semanticFragment(snapshot: snapshot, ranges: ranges)
        guard !result.html.isEmpty else { return payload }
        var enriched = payload
        enriched.html = Data(("<!doctype html><html><head><meta charset=\"utf-8\"></head><body>" + result.html + "</body></html>").utf8)
        #if os(macOS)
        let attributed = nativeAttributedString(for: result)
        enriched.rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        #endif
        return enriched
    }

    static func semanticFragment(snapshot: MarkdownPreparedSnapshot, ranges: [MarkdownSourceRange]) -> Fragment {
        var result = Fragment()
        for range in ranges {
            for block in snapshot.snapshot.blocks {
                result.append(fragment(block, prepared: snapshot[block.id], selected: range.byteRange))
            }
        }
        return result
    }

    #if os(macOS)
    static func nativeAttributedString(for result: Fragment) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: "")
        for run in result.runs where !run.text.isEmpty {
            let size = run.headingLevel.map { max(14, 30 - Double($0) * 3) } ?? 12
            var font = run.presentation.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : NSFont.systemFont(ofSize: size)
            if run.presentation.contains(.strong) || run.headingLevel != nil {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if run.presentation.contains(.emphasis) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = run.indentation
            paragraph.firstLineHeadIndent = run.indentation
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
            if run.presentation.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.presentation.contains(.superscriptText) { attributes[.superscript] = 1 }
            if run.presentation.contains(.subscriptText) { attributes[.superscript] = -1 }
            if let link = run.link { attributes[.link] = link }
            attributed.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return attributed
    }
    #endif

    private static func fragment(_ block: MarkdownBlock, prepared: MarkdownPreparedBlockContent?, selected: Range<Int>) -> Fragment {
        guard selected.overlaps(block.sourceRange.byteRange) else { return Fragment() }
        switch block.kind {
        case .htmlBlock:
            if prepared?.htmlAllowed == true, let rich = prepared?.richContent {
                return rich.blocks.reduce(into: Fragment()) { result, child in
                    result.append(fragment(child.block, prepared: child.preparedContent, selected: selected))
                }
            }
            return leaf(block.inlines, fallback: block.text, sourceRange: block.sourceRange, prepared: nil, attributed: nil, selected: selected).wrapped("pre", separator: "\n")
        case .blockQuote where !block.childBlocks.isEmpty:
            var body = childBlocks(block.childBlocks, prepared: prepared?.childBlocks ?? [], selected: selected)
            for index in body.runs.indices { body.runs[index].indentation += 18 }
            return body.wrapped("blockquote")
        case .unorderedList, .orderedList, .taskList:
            return list(block.listItems, prepared: prepared?.listItems ?? [], kind: block.kind, start: block.orderedListStart, selected: selected)
        case .table:
            guard let table = block.table else { break }
            var rows = Fragment()
            for (index, row) in ([table.header] + table.rows).enumerated() {
                let preparedCells = index == 0 ? prepared?.table?.header ?? [] : prepared?.table?.rows[safe: index - 1]?.cells ?? []
                var cells = Fragment()
                for (column, cell) in row.enumerated() where selected.contains(block.sourceRange.byteRange) || selected.overlaps(cell.sourceRange.byteRange) {
                    let preparedCell = preparedCells[safe: column]
                    let body = leaf(cell.inlines, fallback: cell.text, sourceRange: cell.sourceRange, prepared: preparedCell?.inlineLayout, attributed: preparedCell?.inline, selected: selected)
                    let spans = (cell.colspan > 1 ? " colspan=\"\(cell.colspan)\"" : "") + (cell.rowspan > 1 ? " rowspan=\"\(cell.rowspan)\"" : "")
                    let tag = index == 0 ? "th" : "td"
                    var cellRuns = body.runs + [TextRun(text: "\t")]
                    for runIndex in cellRuns.indices {
                        cellRuns[runIndex].tableCell = TableCellLocation(tableID: block.id, rowIndex: index, cellIndex: column)
                    }
                    cells.append(Fragment(html: "<\(tag)\(spans)>\(body.html)</\(tag)>", runs: cellRuns))
                }
                if cells.runs.last?.text == "\t" { cells.runs[cells.runs.count - 1].text = "\n" }
                rows.append(cells.wrapped("tr"))
            }
            return rows.wrapped("table")
        case .thematicBreak:
            return Fragment(html: "<hr>", runs: [TextRun(text: "—\n")])
        case .blank:
            return Fragment()
        default:
            break
        }
        var body = leaf(block.inlines, fallback: block.text, sourceRange: block.sourceRange, prepared: prepared?.inlineLayout, attributed: prepared?.inline, selected: selected)
        if block.kind == .mathBlock {
            for index in body.runs.indices { body.runs[index].presentation.insert(.math) }
        }
        switch block.kind {
        case .heading:
            let level = min(6, max(1, block.headingLevel ?? 1))
            for index in body.runs.indices { body.runs[index].headingLevel = level }
            return body.wrapped("h\(level)", separator: "\n")
        case .codeBlock:
            for index in body.runs.indices { body.runs[index].presentation.insert(.code) }
            return body.wrapped("code").wrapped("pre", separator: "\n")
        case .blockQuote:
            for index in body.runs.indices { body.runs[index].indentation += 18 }
            return body.wrapped("blockquote", separator: "\n")
        default:
            return body.wrapped("p", separator: "\n")
        }
    }

    private static func childBlocks(_ blocks: [MarkdownBlock], prepared: [MarkdownPreparedChildBlock], selected: Range<Int>) -> Fragment {
        let byID = Dictionary(prepared.map { ($0.block.id, $0.preparedContent) }, uniquingKeysWith: { first, _ in first })
        return blocks.reduce(into: Fragment()) { result, block in
            result.append(fragment(block, prepared: byID[block.id], selected: selected))
        }
    }

    private static func list(_ items: [MarkdownListItem], prepared: [MarkdownPreparedListItem], kind: MarkdownBlockKind, start: UInt?, selected: Range<Int>) -> Fragment {
        var result = Fragment()
        var firstOrdinal: UInt?
        for (index, item) in items.enumerated() where selected.overlaps(item.sourceRange.byteRange) {
            let preparedItem = prepared[safe: index]
            var body: Fragment
            if !item.childBlocks.isEmpty {
                body = childBlocks(item.childBlocks, prepared: preparedItem?.childBlocks ?? [], selected: selected)
            } else {
                body = leaf(item.inlines, fallback: item.text, sourceRange: item.sourceRange, prepared: preparedItem?.inlineLayout, attributed: preparedItem?.inline, selected: selected)
                if !item.childItems.isEmpty {
                    body.append(list(item.childItems, prepared: preparedItem?.childItems ?? [], kind: item.childListKind ?? .unorderedList, start: item.childOrderedListStart, selected: selected))
                }
            }
            guard !body.html.isEmpty else { continue }
            let addition = (start ?? 1).addingReportingOverflow(UInt(index))
            let ordinal = addition.overflow ? UInt.max : addition.partialValue
            if firstOrdinal == nil { firstOrdinal = ordinal }
            let marker: String
            switch item.taskState {
            case .checked: marker = "[x] "
            case .unchecked: marker = "[ ] "
            case nil: marker = kind == .orderedList ? "\(ordinal). " : "• "
            }
            if item.taskState != nil { body.html = escape(marker) + body.html }
            body.runs.insert(TextRun(text: marker), at: 0)
            for runIndex in body.runs.indices { body.runs[runIndex].indentation += 12 }
            result.append(body.wrapped("li", separator: "\n"))
        }
        return result.wrapped(kind == .orderedList ? "ol" : "ul", attributes: kind == .orderedList ? " start=\"\(firstOrdinal ?? start ?? 1)\"" : "")
    }

    private static func leaf(_ runs: [MarkdownInlineRun], fallback: String, sourceRange: MarkdownSourceRange, prepared: MarkdownPreparedInlineContent?, attributed: AttributedString?, selected: Range<Int>) -> Fragment {
        guard selected.overlaps(sourceRange.byteRange) else { return Fragment() }
        let approvedLinks = approvedDestinations(runs: prepared?.prepared.runs ?? runs, attributed: prepared?.attributed ?? attributed)
        var result = Fragment()
        for run in runs where !run.presentation.contains(.linkDecoration) {
            let text = selected.contains(sourceRange.byteRange) ? run.text : MarkdownSelectionController.plainText(in: selected, for: run)
            guard !text.isEmpty else { continue }
            let link = run.destination.flatMap { approvedLinks[$0] }
            var html = escape(text).replacingOccurrences(of: "\n", with: "<br>")
            for (flag, tag) in [(MarkdownInlinePresentation.code, "code"), (.strong, "strong"), (.emphasis, "em"), (.strikethrough, "s"), (.subscriptText, "sub"), (.superscriptText, "sup")] where run.presentation.contains(flag) {
                html = "<\(tag)>\(html)</\(tag)>"
            }
            if let link { html = "<a href=\"\(escape(link.absoluteString))\">\(html)</a>" }
            result.append(Fragment(html: html, runs: [TextRun(text: text, presentation: run.presentation, link: link)]))
        }
        if runs.isEmpty, let text = MarkdownSelectionController.plainText(in: selected, runs: [], fallbackText: fallback, fallbackSourceRange: sourceRange.byteRange) {
            result = Fragment(html: escape(text).replacingOccurrences(of: "\n", with: "<br>"), runs: [TextRun(text: text)])
        }
        return result
    }

    private static func approvedDestinations(runs: [MarkdownInlineRun], attributed: AttributedString?) -> [String: URL] {
        guard let attributed else { return [:] }
        var result: [String: URL] = [:]
        var offset = 0
        let text = String(attributed.characters)
        for run in runs {
            let upper = offset + run.text.utf8.count
            defer { offset = upper }
            guard let destination = run.destination,
                  let link = InlineRunsView.attributedSlice(attributed, text: text, byteRange: offset..<upper).runs.compactMap(\.link).first else { continue }
            // A rich paste must not introduce active HTML URL schemes even
            // when a host's native activation policy supports custom routing.
            guard DefaultMarkdownPolicy().evaluateLink(destination: link.absoluteString) == .allow else { continue }
            result[destination] = link
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension Range where Bound == Int {
    func contains(_ other: Range<Int>) -> Bool {
        lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }
}
