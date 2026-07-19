import Foundation
import SwiftSoup

/// Converts SwiftSoup's HTML5 tree into SiriusMarkdown's native value models.
/// No SwiftSoup node escapes this synchronous adapter boundary.
struct MarkdownHTMLSemanticAdapter {
    private static let containerTags: Set<String> = [
        "article", "aside", "body", "dd", "details", "div", "dl", "figcaption", "figure",
        "footer", "header", "main", "nav", "section"
    ]
    private static let paragraphTags: Set<String> = ["address", "p", "summary"]
    private static let headingLevels: [String: Int] = [
        "h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6
    ]
    private static let inlineTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "cite", "code", "data", "del", "dfn", "em", "i",
        "ins", "kbd", "mark", "q", "ruby", "s", "samp", "small", "span", "strike", "strong",
        "sub", "sup", "time", "u", "var"
    ]
    private static let droppedSubtreeTags: Set<String> = [
        "applet", "audio", "base", "canvas", "embed", "head", "iframe", "link", "meta", "noscript",
        "object", "script", "style", "svg", "template", "video"
    ]
    private static let ignoredLeafTags: Set<String> = [
        "area", "button", "datalist", "input", "option", "select", "source", "textarea", "track"
    ]

    static func richContent(
        from html: String,
        sourceRange: MarkdownSourceRange,
        lineMap: MarkdownLineMap,
        parentID: MarkdownBlockID,
        isSealed: Bool
    ) -> MarkdownRichContent {
        guard !html.isEmpty else {
            return MarkdownRichContent(blocks: [])
        }

        do {
            let document = try SwiftSoup.parseBodyFragment(html)
            guard let body = document.body() else {
                return inertFallback(
                    html: html,
                    sourceRange: sourceRange,
                    parentID: parentID,
                    isSealed: isSealed,
                    sourceMappingFallbackCount: 1
                )
            }

            let sourceMapper = MarkdownHTMLSourceMapper(
                html: html,
                absoluteSourceRange: sourceRange,
                lineMap: lineMap
            )
            var converter = BlockConverter(
                sourceMapper: sourceMapper,
                fallbackRange: sourceRange,
                parentID: parentID,
                isSealed: isSealed
            )
            let blocks = converter.blocks(from: body.getChildNodes())
            return MarkdownRichContent(blocks: blocks, diagnostics: converter.diagnostics)
        } catch {
            return inertFallback(
                html: html,
                sourceRange: sourceRange,
                parentID: parentID,
                isSealed: isSealed,
                sourceMappingFallbackCount: 1
            )
        }
    }

    /// Reconstructs an inline HTML fragment around opaque placeholders for the
    /// already-parsed Markdown runs. SwiftSoup therefore owns malformed-tag
    /// recovery and nesting semantics without taking Markdown semantics away
    /// from swift-markdown.
    static func normalizeInlineRuns(_ runs: [MarkdownInlineRun]) -> [MarkdownInlineRun] {
        guard runs.contains(where: { $0.presentation.contains(.html) }) else {
            return runs
        }

        var fragment = ""
        fragment.reserveCapacity(runs.reduce(0) { $0 + $1.text.utf8.count + 48 })
        var tagSourceRanges: [String: [MarkdownSourceRange]] = [:]
        for (index, run) in runs.enumerated() {
            if run.presentation.contains(.html) {
                fragment.append(run.text)
                if let tagName = lexicalTagName(in: run.text), let sourceRange = run.sourceRange {
                    tagSourceRanges[tagName, default: []].append(sourceRange)
                }
            } else {
                fragment.append("<sirius-markdown-run data-index=\"")
                fragment.append(String(index))
                fragment.append("\"></sirius-markdown-run>")
            }
        }

        do {
            let document = try SwiftSoup.parseBodyFragment(fragment)
            guard let body = document.body() else {
                return runs.filter { !$0.presentation.contains(.html) }
            }
            var state = InlineTreeState(originalRuns: runs, tagSourceRanges: tagSourceRanges)
            let normalized = body.getChildNodes().flatMap { node in
                inlineRuns(from: node, context: InlineContext(), state: &state)
            }
            return collapseHTMLWhitespace(in: normalized)
        } catch {
            return runs.filter { !$0.presentation.contains(.html) }
        }
    }

    private static func inertFallback(
        html: String,
        sourceRange: MarkdownSourceRange,
        parentID: MarkdownBlockID,
        isSealed: Bool,
        sourceMappingFallbackCount: Int
    ) -> MarkdownRichContent {
        let hash = stableHash(html)
        let block = MarkdownBlock(
            id: MarkdownBlockID("\(parentID.rawValue):html-fallback:\(String(hash, radix: 16))"),
            kind: .codeBlock,
            sourceRange: sourceRange,
            text: html,
            inlines: [
                MarkdownInlineRun(
                    kind: .code,
                    text: html,
                    sourceRange: sourceRange
                )
            ],
            contentHash: hash,
            infoString: "html",
            isSealed: isSealed
        )
        return MarkdownRichContent(
            blocks: [block],
            diagnostics: MarkdownRichContentDiagnostics(
                parsedNodeCount: 0,
                droppedNodeCount: 0,
                unwrappedNodeCount: 0,
                sourceMappingFallbackCount: sourceMappingFallbackCount
            )
        )
    }

    private struct InlineContext {
        var presentation: MarkdownInlinePresentation = []
        var destination: String?
        var preservesWhitespace = false
    }

    private struct InlineTreeState {
        var originalRuns: [MarkdownInlineRun]
        var tagSourceRanges: [String: [MarkdownSourceRange]]

        mutating func sourceRange(for tagName: String) -> MarkdownSourceRange? {
            guard var ranges = tagSourceRanges[tagName], !ranges.isEmpty else {
                return nil
            }
            let first = ranges.removeFirst()
            tagSourceRanges[tagName] = ranges
            return first
        }
    }

    private static func inlineRuns(
        from node: Node,
        context: InlineContext,
        state: inout InlineTreeState
    ) -> [MarkdownInlineRun] {
        if let text = node as? TextNode {
            let value = text.getWholeText()
            guard !value.isEmpty else { return [] }
            return [
                MarkdownInlineRun(
                    kind: context.destination == nil ? primaryKind(for: context.presentation) : .link,
                    text: value,
                    destination: context.destination,
                    presentation: context.presentation
                )
            ]
        }

        guard let element = node as? Element else {
            return []
        }
        let tagName = element.tagNameNormal()
        if tagName == "sirius-markdown-run" {
            guard let rawIndex = try? element.attr("data-index"),
                  let index = Int(rawIndex),
                  state.originalRuns.indices.contains(index)
            else {
                return []
            }
            var run = state.originalRuns[index]
            run.presentation.formUnion(context.presentation)
            if run.destination == nil {
                run.destination = context.destination
            }
            if run.destination != nil,
               run.kind != .softBreak,
               run.kind != .hardBreak {
                run.kind = .link
            }
            return [run]
        }
        if droppedSubtreeTags.contains(tagName) || ignoredLeafTags.contains(tagName) {
            return []
        }
        if tagName == "br" {
            return [
                MarkdownInlineRun(
                    kind: .hardBreak,
                    text: "\n",
                    sourceRange: state.sourceRange(for: tagName),
                    destination: context.destination,
                    presentation: context.presentation
                )
            ]
        }
        if tagName == "wbr" {
            return [
                MarkdownInlineRun(
                    kind: .softBreak,
                    text: "",
                    sourceRange: state.sourceRange(for: tagName),
                    destination: context.destination,
                    presentation: context.presentation
                )
            ]
        }
        if tagName == "img" {
            let source = ((try? element.attr("src")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { return [] }
            let alt = (try? element.attr("alt")) ?? ""
            let sourceRange = state.sourceRange(for: tagName)
            return [
                MarkdownInlineRun(
                    kind: context.destination == nil ? .image : .link,
                    text: alt,
                    sourceRange: sourceRange,
                    destination: context.destination ?? source,
                    imageSource: source,
                    presentation: context.presentation.union(.image)
                )
            ]
        }

        var childContext = context
        applyInlineSemantics(of: element, tagName: tagName, to: &childContext)
        return element.getChildNodes().flatMap { child in
            inlineRuns(from: child, context: childContext, state: &state)
        }
    }

    private static func applyInlineSemantics(
        of element: Element,
        tagName: String,
        to context: inout InlineContext
    ) {
        switch tagName {
        case "a":
            let href = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !href.isEmpty {
                context.destination = href
            }
        case "b", "strong":
            context.presentation.insert(.strong)
        case "em", "i", "cite", "dfn", "var":
            context.presentation.insert(.emphasis)
        case "del", "s", "strike":
            context.presentation.insert(.strikethrough)
        case "code", "kbd", "samp":
            context.presentation.insert(.code)
        case "sub":
            context.presentation.insert(.subscriptText)
        case "sup":
            context.presentation.insert(.superscriptText)
        case "pre":
            context.presentation.insert(.code)
            context.preservesWhitespace = true
        default:
            break
        }
    }

    private static func primaryKind(for presentation: MarkdownInlinePresentation) -> MarkdownInlineKind {
        if presentation.contains(.code) { return .code }
        if presentation.contains(.strong) { return .strong }
        if presentation.contains(.emphasis) { return .emphasis }
        if presentation.contains(.strikethrough) { return .strikethrough }
        return .text
    }

    private static func collapseHTMLWhitespace(in runs: [MarkdownInlineRun]) -> [MarkdownInlineRun] {
        var result: [MarkdownInlineRun] = []
        result.reserveCapacity(runs.count)
        var atBoundary = true

        for var run in runs {
            if run.kind == .hardBreak {
                while let last = result.last,
                      last.kind != .hardBreak,
                      last.text.last?.isWhitespace == true {
                    var trimmed = last
                    trimmed.text = trimmed.text.trimmingCharacters(in: .whitespaces)
                    result.removeLast()
                    if !trimmed.text.isEmpty { result.append(trimmed) }
                }
                if result.last?.kind != .hardBreak {
                    result.append(run)
                }
                atBoundary = true
                continue
            }
            if run.kind == .image || run.presentation.contains(.image) {
                result.append(run)
                atBoundary = false
                continue
            }

            var output = ""
            var pendingSpace = false
            for character in run.text {
                if character.isWhitespace {
                    pendingSpace = true
                } else {
                    if pendingSpace, !atBoundary, !output.isEmpty || !result.isEmpty {
                        output.append(" ")
                    }
                    output.append(character)
                    pendingSpace = false
                    atBoundary = false
                }
            }
            if pendingSpace, !atBoundary {
                output.append(" ")
            }
            run.text = output
            if !run.text.isEmpty {
                result.append(run)
            }
        }

        while let last = result.last,
              last.kind != .hardBreak,
              last.text.last?.isWhitespace == true {
            var trimmed = last
            trimmed.text = trimmed.text.trimmingCharacters(in: .whitespaces)
            result.removeLast()
            if !trimmed.text.isEmpty { result.append(trimmed) }
        }
        while result.last?.kind == .hardBreak {
            result.removeLast()
        }
        return result
    }

    private static func lexicalTagName(in rawHTML: String) -> String? {
        let bytes = Array(rawHTML.utf8)
        guard let opening = bytes.firstIndex(of: 0x3C) else { return nil }
        var cursor = opening + 1
        if cursor < bytes.count, bytes[cursor] == 0x2F { cursor += 1 }
        while cursor < bytes.count, bytes[cursor] == 0x20 || bytes[cursor] == 0x09 { cursor += 1 }
        let start = cursor
        while cursor < bytes.count {
            let byte = bytes[cursor]
            let isName = (byte >= 0x41 && byte <= 0x5A) ||
                (byte >= 0x61 && byte <= 0x7A) ||
                (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x3A
            guard isName else { break }
            cursor += 1
        }
        guard start < cursor else { return nil }
        return String(decoding: bytes[start..<cursor], as: UTF8.self).lowercased()
    }

    private struct BlockConverter {
        var sourceMapper: MarkdownHTMLSourceMapper
        var fallbackRange: MarkdownSourceRange
        var parentID: MarkdownBlockID
        var isSealed: Bool
        var diagnostics = MarkdownRichContentDiagnostics()
        private var fallbackIdentityCounts: [String: Int] = [:]

        init(
            sourceMapper: MarkdownHTMLSourceMapper,
            fallbackRange: MarkdownSourceRange,
            parentID: MarkdownBlockID,
            isSealed: Bool
        ) {
            self.sourceMapper = sourceMapper
            self.fallbackRange = fallbackRange
            self.parentID = parentID
            self.isSealed = isSealed
        }

        mutating func blocks(from nodes: [Node]) -> [MarkdownBlock] {
            var output: [MarkdownBlock] = []
            var pendingInlineNodes: [Node] = []

            func isWhitespaceText(_ node: Node) -> Bool {
                guard let text = node as? TextNode else { return false }
                return text.getWholeText().allSatisfy(\.isWhitespace)
            }

            for node in nodes {
                diagnostics.parsedNodeCount += 1
                if isWhitespaceText(node) { continue }
                guard let element = node as? Element else {
                    pendingInlineNodes.append(node)
                    continue
                }
                let tagName = element.tagNameNormal()
                if MarkdownHTMLSemanticAdapter.droppedSubtreeTags.contains(tagName) {
                    diagnostics.droppedNodeCount += 1
                    continue
                }
                if MarkdownHTMLSemanticAdapter.inlineTags.contains(tagName) || tagName == "img" || tagName == "br" || tagName == "wbr" {
                    pendingInlineNodes.append(node)
                    continue
                }

                flushInlineNodes(&pendingInlineNodes, into: &output)
                output.append(contentsOf: blocks(from: element, tagName: tagName))
            }
            flushInlineNodes(&pendingInlineNodes, into: &output)
            return output
        }

        private mutating func flushInlineNodes(
            _ pendingInlineNodes: inout [Node],
            into output: inout [MarkdownBlock]
        ) {
            guard !pendingInlineNodes.isEmpty else { return }
            let runs = inlineRuns(from: pendingInlineNodes, preservesWhitespace: false)
            pendingInlineNodes.removeAll(keepingCapacity: true)
            if let block = makeBlock(kind: .paragraph, runs: runs) {
                output.append(block)
            }
        }

        private mutating func blocks(from element: Element, tagName: String) -> [MarkdownBlock] {
            if let level = MarkdownHTMLSemanticAdapter.headingLevels[tagName] {
                let runs = inlineRuns(from: element.getChildNodes(), preservesWhitespace: false)
                return makeBlock(kind: .heading, runs: runs, headingLevel: level).map { [$0] } ?? []
            }
            if MarkdownHTMLSemanticAdapter.paragraphTags.contains(tagName) {
                let runs = inlineRuns(from: element.getChildNodes(), preservesWhitespace: false)
                return makeBlock(kind: .paragraph, runs: runs).map { [$0] } ?? []
            }
            if tagName == "blockquote" {
                let runs = inlineRuns(from: element.getChildNodes(), preservesWhitespace: false, separatesBlocks: true)
                return makeBlock(kind: .blockQuote, runs: runs).map { [$0] } ?? []
            }
            if tagName == "ul" || tagName == "ol" {
                return listBlock(from: element, ordered: tagName == "ol").map { [$0] } ?? []
            }
            if tagName == "pre" {
                let runs = inlineRuns(from: element.getChildNodes(), preservesWhitespace: true)
                let text = runs.map(\.text).joined()
                guard !text.isEmpty else { return [] }
                let range = resolvedRange(for: runs)
                let infoString = codeLanguage(in: element)
                return [makeBlock(kind: .codeBlock, text: text, runs: runs, range: range, infoString: infoString)]
            }
            if tagName == "table" {
                return tableBlock(from: element).map { [$0] } ?? []
            }
            if tagName == "hr" {
                let range = sourceMapper.sourceRange(for: element) ?? fallbackRange
                return [makeBlock(kind: .thematicBreak, text: "", runs: [], range: range)]
            }
            if tagName == "form" || MarkdownHTMLSemanticAdapter.containerTags.contains(tagName) {
                diagnostics.unwrappedNodeCount += 1
                return blocks(from: element.getChildNodes())
            }
            if MarkdownHTMLSemanticAdapter.ignoredLeafTags.contains(tagName) {
                diagnostics.droppedNodeCount += 1
                return []
            }

            diagnostics.unwrappedNodeCount += 1
            return blocks(from: element.getChildNodes())
        }

        private mutating func inlineRuns(
            from nodes: [Node],
            preservesWhitespace: Bool,
            separatesBlocks: Bool = false,
            context: InlineContext = InlineContext()
        ) -> [MarkdownInlineRun] {
            var output: [MarkdownInlineRun] = []
            var childContext = context
            childContext.preservesWhitespace = preservesWhitespace || context.preservesWhitespace

            for node in nodes {
                diagnostics.parsedNodeCount += 1
                if let textNode = node as? TextNode {
                    let text = textNode.getWholeText()
                    guard !text.isEmpty else { continue }
                    let range = sourceMapper.sourceRange(for: textNode)
                    if range == nil { diagnostics.sourceMappingFallbackCount += 1 }
                    output.append(
                        MarkdownInlineRun(
                            kind: childContext.destination == nil
                                ? MarkdownHTMLSemanticAdapter.primaryKind(for: childContext.presentation)
                                : .link,
                            text: text,
                            sourceRange: range ?? fallbackRange,
                            destination: childContext.destination,
                            presentation: childContext.presentation
                        )
                    )
                    continue
                }
                guard let element = node as? Element else { continue }
                let tagName = element.tagNameNormal()
                if MarkdownHTMLSemanticAdapter.droppedSubtreeTags.contains(tagName) {
                    diagnostics.droppedNodeCount += 1
                    continue
                }
                if MarkdownHTMLSemanticAdapter.ignoredLeafTags.contains(tagName) {
                    diagnostics.droppedNodeCount += 1
                    continue
                }
                if tagName == "br" || tagName == "wbr" {
                    let range = sourceMapper.sourceRange(for: element)
                    if range == nil { diagnostics.sourceMappingFallbackCount += 1 }
                    output.append(
                        MarkdownInlineRun(
                            kind: tagName == "br" ? .hardBreak : .softBreak,
                            text: tagName == "br" ? "\n" : "",
                            sourceRange: range ?? fallbackRange,
                            destination: childContext.destination,
                            presentation: childContext.presentation
                        )
                    )
                    continue
                }
                if tagName == "img" {
                    let source = ((try? element.attr("src")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !source.isEmpty else {
                        diagnostics.droppedNodeCount += 1
                        continue
                    }
                    let alt = (try? element.attr("alt")) ?? ""
                    let range = sourceMapper.sourceRange(for: element)
                    if range == nil { diagnostics.sourceMappingFallbackCount += 1 }
                    output.append(
                        MarkdownInlineRun(
                            kind: childContext.destination == nil ? .image : .link,
                            text: alt,
                            sourceRange: range ?? fallbackRange,
                            destination: childContext.destination ?? source,
                            imageSource: source,
                            presentation: childContext.presentation.union(.image)
                        )
                    )
                    continue
                }

                var nestedContext = childContext
                MarkdownHTMLSemanticAdapter.applyInlineSemantics(of: element, tagName: tagName, to: &nestedContext)
                let isNestedBlock = separatesBlocks && isBlockElement(tagName)
                if isNestedBlock, !output.isEmpty, output.last?.kind != .hardBreak {
                    output.append(MarkdownInlineRun(kind: .hardBreak, text: "\n", sourceRange: fallbackRange))
                }
                output.append(contentsOf: inlineRuns(
                    from: element.getChildNodes(),
                    preservesWhitespace: nestedContext.preservesWhitespace,
                    separatesBlocks: separatesBlocks,
                    context: nestedContext
                ))
                if isNestedBlock, !output.isEmpty, output.last?.kind != .hardBreak {
                    output.append(MarkdownInlineRun(kind: .hardBreak, text: "\n", sourceRange: fallbackRange))
                }
            }

            return preservesWhitespace ? output : MarkdownHTMLSemanticAdapter.collapseHTMLWhitespace(in: output)
        }

        private mutating func listBlock(from element: Element, ordered: Bool) -> MarkdownBlock? {
            let itemElements = element.getChildNodes().compactMap { node -> Element? in
                guard let child = node as? Element, child.tagNameNormal() == "li" else { return nil }
                return child
            }
            let items = itemElements.compactMap { listItem(from: $0) }
            guard !items.isEmpty else { return nil }
            let ranges = items.map(\.sourceRange)
            let range = coveringRange(ranges) ?? fallbackRange
            let kind: MarkdownBlockKind = ordered ? .orderedList : .unorderedList
            let start = ordered ? positiveUIntAttribute("start", in: element) : nil
            let text = items.map(\.text).joined(separator: "\n")
            return makeBlock(
                kind: kind,
                text: text,
                runs: items.flatMap(\.inlines),
                range: range,
                listItems: items,
                orderedListStart: start
            )
        }

        private mutating func listItem(from element: Element) -> MarkdownListItem? {
            var inlineNodes: [Node] = []
            var nestedListElement: Element?
            for child in element.getChildNodes() {
                if let childElement = child as? Element,
                   childElement.tagNameNormal() == "ul" || childElement.tagNameNormal() == "ol" {
                    nestedListElement = childElement
                } else {
                    inlineNodes.append(child)
                }
            }
            let runs = inlineRuns(from: inlineNodes, preservesWhitespace: false, separatesBlocks: true)
            let nestedOrdered = nestedListElement?.tagNameNormal() == "ol"
            let nestedItems = nestedListElement?.getChildNodes().compactMap { node -> MarkdownListItem? in
                guard let child = node as? Element, child.tagNameNormal() == "li" else { return nil }
                return listItem(from: child)
            } ?? []
            guard !runs.isEmpty || !nestedItems.isEmpty else { return nil }
            let range = coveringRange(runs.compactMap(\.sourceRange) + nestedItems.map(\.sourceRange)) ?? fallbackRange
            return MarkdownListItem(
                sourceRange: range,
                text: runs.map(\.text).joined(),
                inlines: runs,
                childListKind: nestedListElement == nil ? nil : (nestedOrdered ? .orderedList : .unorderedList),
                childOrderedListStart: nestedOrdered ? positiveUIntAttribute("start", in: nestedListElement) : nil,
                childItems: nestedItems
            )
        }

        private mutating func tableBlock(from element: Element) -> MarkdownBlock? {
            let rows = descendantRows(in: element)
            guard !rows.isEmpty else { return nil }
            var convertedRows: [[MarkdownTableCell]] = []
            var headerRow: [MarkdownTableCell] = []
            var columnAlignments: [MarkdownTableColumnAlignment?] = []

            for (rowIndex, rowElement) in rows.enumerated() {
                let cellElements = rowElement.getChildNodes().compactMap { node -> Element? in
                    guard let child = node as? Element else { return nil }
                    return child.tagNameNormal() == "td" || child.tagNameNormal() == "th" ? child : nil
                }
                let cells = cellElements.map { cellElement -> MarkdownTableCell in
                    let runs = inlineRuns(from: cellElement.getChildNodes(), preservesWhitespace: false, separatesBlocks: true)
                    let range = resolvedRange(for: runs)
                    return MarkdownTableCell(
                        sourceRange: range,
                        text: runs.map(\.text).joined(),
                        inlines: runs,
                        colspan: positiveUIntAttribute("colspan", in: cellElement) ?? 1,
                        rowspan: positiveUIntAttribute("rowspan", in: cellElement) ?? 1
                    )
                }
                guard !cells.isEmpty else { continue }
                let isHeader = rowIndex == 0 && cellElements.contains { $0.tagNameNormal() == "th" }
                if isHeader {
                    headerRow = cells
                    columnAlignments = cellElements.map(alignment(in:))
                } else {
                    convertedRows.append(cells)
                }
            }
            if headerRow.isEmpty, let first = convertedRows.first {
                headerRow = first
                convertedRows.removeFirst()
                columnAlignments = Array(repeating: nil, count: first.count)
            }
            guard !headerRow.isEmpty else { return nil }

            let table = MarkdownTableBlock(
                columnAlignments: columnAlignments,
                header: headerRow,
                rows: convertedRows
            )
            let ranges = headerRow.map(\.sourceRange) + convertedRows.flatMap { $0.map(\.sourceRange) }
            let range = coveringRange(ranges) ?? fallbackRange
            let text = (headerRow + convertedRows.flatMap { $0 }).map(\.text).joined(separator: "\n")
            return makeBlock(kind: .table, text: text, runs: [], range: range, table: table)
        }

        private func descendantRows(in element: Element) -> [Element] {
            var rows: [Element] = []
            func visit(_ node: Node, isNestedTable: Bool) {
                guard let child = node as? Element else { return }
                let name = child.tagNameNormal()
                if isNestedTable || (name == "table" && child !== element) { return }
                if name == "tr" {
                    rows.append(child)
                    return
                }
                for descendant in child.getChildNodes() {
                    visit(descendant, isNestedTable: false)
                }
            }
            for child in element.getChildNodes() {
                visit(child, isNestedTable: false)
            }
            return rows
        }

        private func alignment(in element: Element) -> MarkdownTableColumnAlignment? {
            switch ((try? element.attr("align")) ?? "").lowercased() {
            case "left": return .left
            case "center", "middle": return .center
            case "right": return .right
            default: return nil
            }
        }

        private func positiveUIntAttribute(_ name: String, in element: Element?) -> UInt? {
            guard let element,
                  let raw = try? element.attr(name),
                  let value = UInt(raw),
                  value > 0
            else { return nil }
            return min(value, 10_000)
        }

        private func codeLanguage(in pre: Element) -> String? {
            let code = pre.getChildNodes().compactMap { $0 as? Element }.first { $0.tagNameNormal() == "code" }
            guard let code, let className = try? code.className() else { return nil }
            return className.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
                let value = String(token)
                for prefix in ["language-", "lang-"] where value.hasPrefix(prefix) {
                    return String(value.dropFirst(prefix.count))
                }
                return nil
            }.first
        }

        private func isBlockElement(_ tagName: String) -> Bool {
            MarkdownHTMLSemanticAdapter.containerTags.contains(tagName) ||
                MarkdownHTMLSemanticAdapter.paragraphTags.contains(tagName) ||
                MarkdownHTMLSemanticAdapter.headingLevels[tagName] != nil ||
                ["blockquote", "ul", "ol", "pre", "table", "hr"].contains(tagName)
        }

        private mutating func makeBlock(
            kind: MarkdownBlockKind,
            runs: [MarkdownInlineRun],
            headingLevel: Int? = nil
        ) -> MarkdownBlock? {
            let cleaned = MarkdownHTMLSemanticAdapter.collapseHTMLWhitespace(in: runs)
            guard !cleaned.isEmpty else { return nil }
            let text = cleaned.map(\.text).joined()
            return makeBlock(
                kind: kind,
                text: text,
                runs: cleaned,
                range: resolvedRange(for: cleaned),
                headingLevel: headingLevel
            )
        }

        private mutating func makeBlock(
            kind: MarkdownBlockKind,
            text: String,
            runs: [MarkdownInlineRun],
            range: MarkdownSourceRange,
            listItems: [MarkdownListItem] = [],
            table: MarkdownTableBlock? = nil,
            orderedListStart: UInt? = nil,
            headingLevel: Int? = nil,
            infoString: String? = nil
        ) -> MarkdownBlock {
            let contentHash = MarkdownHTMLSemanticAdapter.stableHash(text)
            let baseIdentity = "\(kind.rawValue):\(range.byteRange.lowerBound)-\(range.byteRange.upperBound):\(String(contentHash, radix: 16))"
            let occurrence = fallbackIdentityCounts[baseIdentity, default: 0]
            fallbackIdentityCounts[baseIdentity] = occurrence + 1
            let suffix = occurrence == 0 ? "" : ":\(occurrence)"
            return MarkdownBlock(
                id: MarkdownBlockID("\(parentID.rawValue):html:\(baseIdentity)\(suffix)"),
                kind: kind,
                sourceRange: range,
                text: text,
                inlines: runs,
                listItems: listItems,
                table: table,
                contentHash: contentHash,
                orderedListStart: orderedListStart,
                headingLevel: headingLevel,
                infoString: infoString,
                isSealed: isSealed
            )
        }

        private func resolvedRange(for runs: [MarkdownInlineRun]) -> MarkdownSourceRange {
            coveringRange(runs.compactMap(\.sourceRange)) ?? fallbackRange
        }

        private func coveringRange(_ ranges: [MarkdownSourceRange]) -> MarkdownSourceRange? {
            guard let lower = ranges.map(\.byteRange.lowerBound).min(),
                  let upper = ranges.map(\.byteRange.upperBound).max()
            else { return nil }
            let linesLower = ranges.map(\.lineRange.lowerBound).min() ?? fallbackRange.lineRange.lowerBound
            let linesUpper = ranges.map(\.lineRange.upperBound).max() ?? fallbackRange.lineRange.upperBound
            return MarkdownSourceRange(byteRange: lower..<max(lower, upper), lineRange: linesLower..<max(linesLower, linesUpper))
        }
    }

    private final class MarkdownHTMLSourceMapper {
        private let source: Data
        private let absoluteSourceRange: MarkdownSourceRange
        private let lineMap: MarkdownLineMap
        private var cursor = 0

        init(html: String, absoluteSourceRange: MarkdownSourceRange, lineMap: MarkdownLineMap) {
            source = Data(html.utf8)
            self.absoluteSourceRange = absoluteSourceRange
            self.lineMap = lineMap
        }

        func sourceRange(for node: Node) -> MarkdownSourceRange? {
            // SwiftSoup exposes decoded text through TextNode, while outerHtml()
            // may serialize a different (but equivalent) entity spelling. Match
            // text nodes against decoded source text so selection and copy keep
            // the exact raw byte range (for example, `&copy;` rather than `©`).
            if let textNode = node as? TextNode,
               let rawRange = rawTextRange(matching: textNode.getWholeText()) {
                cursor = max(cursor, rawRange.upperBound)
                return absoluteRange(for: rawRange)
            }
            if let element = node as? Element,
               let rawRange = rawElementRange(matching: element.tagNameNormal()) {
                cursor = max(cursor, rawRange.upperBound)
                return absoluteRange(for: rawRange)
            }

            guard let serialized = try? node.outerHtml(), !serialized.isEmpty else {
                return nil
            }
            let needle = Data(serialized.utf8)
            guard !needle.isEmpty, needle.count <= source.count else { return nil }
            let preferredRange = cursor..<source.count
            let found = source.range(of: needle, options: [], in: preferredRange) ??
                source.range(of: needle, options: [], in: 0..<source.count)
            guard let found else { return nil }
            cursor = max(cursor, found.upperBound)
            return absoluteRange(for: found)
        }

        /// Walks visible text spans without reparsing the source or searching
        /// from the beginning for every node. Markup boundaries are ASCII, so
        /// byte scanning preserves exact UTF-8 source offsets.
        private func rawTextRange(matching decodedText: String) -> Range<Int>? {
            guard !decodedText.isEmpty, cursor < source.count else { return nil }
            var scan = cursor

            while scan < source.count {
                if source[scan] == Self.lessThan {
                    scan = markupEnd(startingAt: scan)
                    continue
                }

                let lower = scan
                while scan < source.count, source[scan] != Self.lessThan {
                    scan += 1
                }
                let candidateRange = lower..<scan
                guard !candidateRange.isEmpty else { continue }
                let rawText = String(decoding: source[candidateRange], as: UTF8.self)
                let unescaped = (try? Entities.unescape(rawText)) ?? rawText
                if unescaped == decodedText {
                    return candidateRange
                }
            }

            return nil
        }

        private func rawElementRange(matching tagName: String) -> Range<Int>? {
            guard !tagName.isEmpty, cursor < source.count else { return nil }
            var scan = cursor
            while scan < source.count {
                guard source[scan] == Self.lessThan else {
                    scan += 1
                    continue
                }
                let upper = markupEnd(startingAt: scan)
                if rawStartTagName(in: scan..<upper) == tagName {
                    return scan..<upper
                }
                scan = max(scan + 1, upper)
            }
            return nil
        }

        private func rawStartTagName(in range: Range<Int>) -> String? {
            var scan = range.lowerBound + 1
            while scan < range.upperBound,
                  source[scan] == Self.space || source[scan] == Self.horizontalTab {
                scan += 1
            }
            guard scan < range.upperBound,
                  source[scan] != Self.slash,
                  source[scan] != Self.exclamation,
                  source[scan] != Self.questionMark
            else {
                return nil
            }
            let lower = scan
            while scan < range.upperBound, Self.isTagNameByte(source[scan]) {
                scan += 1
            }
            guard lower < scan else { return nil }
            return String(decoding: source[lower..<scan], as: UTF8.self).lowercased()
        }

        private func markupEnd(startingAt lower: Int) -> Int {
            if matchesASCII("<!--", at: lower),
               let close = source.range(
                   of: Data("-->".utf8),
                   options: [],
                   in: min(lower + 4, source.count)..<source.count
               ) {
                return close.upperBound
            }

            var scan = min(lower + 1, source.count)
            var quote: UInt8?
            while scan < source.count {
                let byte = source[scan]
                if let activeQuote = quote {
                    if byte == activeQuote { quote = nil }
                } else if byte == Self.singleQuote || byte == Self.doubleQuote {
                    quote = byte
                } else if byte == Self.greaterThan {
                    return scan + 1
                }
                scan += 1
            }
            return source.count
        }

        private func matchesASCII(_ value: String, at offset: Int) -> Bool {
            let bytes = Data(value.utf8)
            guard offset >= 0, offset + bytes.count <= source.count else { return false }
            return source[offset..<(offset + bytes.count)].elementsEqual(bytes)
        }

        private func absoluteRange(for localRange: Range<Int>) -> MarkdownSourceRange? {
            guard localRange.lowerBound >= 0, localRange.upperBound <= source.count else { return nil }
            let lower = absoluteSourceRange.byteRange.lowerBound + localRange.lowerBound
            let upper = absoluteSourceRange.byteRange.lowerBound + localRange.upperBound
            guard lower >= absoluteSourceRange.byteRange.lowerBound,
                  upper <= absoluteSourceRange.byteRange.upperBound
            else { return nil }
            let byteRange = lower..<upper
            return MarkdownSourceRange(byteRange: byteRange, lineRange: lineMap.lineRange(for: byteRange))
        }

        private static let lessThan = UInt8(ascii: "<")
        private static let greaterThan = UInt8(ascii: ">")
        private static let singleQuote = UInt8(ascii: "'")
        private static let doubleQuote = UInt8(ascii: "\"")
        private static let slash = UInt8(ascii: "/")
        private static let exclamation = UInt8(ascii: "!")
        private static let questionMark = UInt8(ascii: "?")
        private static let space = UInt8(ascii: " ")
        private static let horizontalTab = UInt8(ascii: "\t")

        private static func isTagNameByte(_ byte: UInt8) -> Bool {
            (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ||
                (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) ||
                (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) ||
                byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":")
        }
    }

    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
