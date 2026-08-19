import Foundation

private final class MarkdownBoundaryScanStateStorage: @unchecked Sendable {
    var state: MarkdownBoundaryScanState

    init(state: MarkdownBoundaryScanState = MarkdownBoundaryScanState()) {
        self.state = state
    }

    func copy() -> MarkdownBoundaryScanStateStorage {
        MarkdownBoundaryScanStateStorage(state: state)
    }
}

public struct MarkdownStream: Sendable {
    private var source: MarkdownSourceBuffer
    private var sealedUpperBound: Int
    private var sealedBlocks: [MarkdownBlock]
    private var hostBoundaries: [MarkdownHostBoundary]
    private var referenceDefinitionsPrefix: String
    private var sealedReferenceDefinitionLabels: Set<String>
    private var generation: Int
    private var finished: Bool
    private let parser: SwiftMarkdownParser
    private let boundaryScanner: MarkdownBoundaryScanner
    private var boundaryScanStateStorage: MarkdownBoundaryScanStateStorage
    private let parserCache: MarkdownParserCache
    private let diagnosticsRecorder: MarkdownDiagnosticsRecorder

    public init() {
        self.init(
            parserCacheCapacity: 256,
            diagnosticsRecorder: MarkdownDiagnosticsRecorder()
        )
    }

    public init(
        parserCacheCapacity: Int = 256,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.source = MarkdownSourceBuffer()
        self.sealedUpperBound = 0
        self.sealedBlocks = []
        self.hostBoundaries = []
        self.referenceDefinitionsPrefix = ""
        self.sealedReferenceDefinitionLabels = []
        self.generation = 0
        self.finished = false
        self.parser = SwiftMarkdownParser()
        self.boundaryScanner = MarkdownBoundaryScanner()
        self.boundaryScanStateStorage = MarkdownBoundaryScanStateStorage()
        self.parserCache = MarkdownParserCache(capacity: parserCacheCapacity)
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public var sourceLength: Int {
        source.byteCount
    }

    public var diagnosticsCounters: MarkdownDiagnosticsCounters {
        diagnosticsRecorder.snapshot()
    }

    public mutating func append(_ text: String) {
        precondition(!finished, "Cannot append after finish().")
        guard !text.isEmpty else {
            return
        }

        source.append(text)
        generation += 1
        sealBoundaryIfPossible()
    }

    public mutating func sealBoundaryIfPossible() {
        ensureUniqueBoundaryScanStateStorage()
        if boundaryScanStateStorage.state.lowerBound != sealedUpperBound {
            resetBoundaryScanState(lowerBound: sealedUpperBound)
        }

        var scanState = boundaryScanStateStorage.state
        let result = MarkdownDiagnostics().signpost("BoundaryScan", category: "Stream") {
            boundaryScanner.scan(in: source, state: &scanState)
        }
        boundaryScanStateStorage.state = scanState
        diagnosticsRecorder.recordBoundaryScan(
            bytes: result.scannedByteCount,
            lines: result.scannedLineCount
        )

        guard let upperBound = result.safeUpperBound,
              upperBound > sealedUpperBound
        else {
            return
        }

        seal(upTo: upperBound)
    }

    public mutating func appendHostBoundary(id: MarkdownHostBoundaryID? = nil) {
        guard sealedUpperBound < source.byteCount else {
            let boundaryID = id ?? MarkdownHostBoundaryID("host:\(hostBoundaries.count):\(source.byteCount)")
            hostBoundaries.append(MarkdownHostBoundary(id: boundaryID, sourceOffset: source.byteCount))
            resetBoundaryScanState(lowerBound: sealedUpperBound)
            generation += 1
            return
        }

        seal(upTo: source.byteCount)
        let boundaryID = id ?? MarkdownHostBoundaryID("host:\(hostBoundaries.count):\(source.byteCount)")
        hostBoundaries.append(MarkdownHostBoundary(id: boundaryID, sourceOffset: source.byteCount))
        generation += 1
    }

    public func markdown(in sourceRange: MarkdownSourceRange) -> String {
        source.slice(sourceRange.byteRange).text
    }

    public mutating func finish() {
        guard !finished else {
            return
        }

        if sealedUpperBound < source.byteCount {
            seal(upTo: source.byteCount)
        }

        finished = true
        generation += 1
    }

    public func snapshot() -> MarkdownSnapshot {
        let tailBlocks: [MarkdownBlock]

        if sealedUpperBound < source.byteCount, !finished {
            let tail = source.slice(sealedUpperBound..<source.byteCount)
            tailBlocks = parse(
                tail,
                lineMap: source.lineMap,
                idNamespace: "stream",
                isSealed: false,
                isSealedRegion: false,
                referenceDefinitionsPrefix: referenceDefinitionsPrefix
            )
        } else {
            tailBlocks = []
        }

        let blocks = sealedBlocks + tailBlocks
        return MarkdownSnapshot(
            blocks: blocks,
            items: snapshotItems(blocks: blocks),
            sourceLength: source.byteCount,
            generation: generation,
            isFinished: finished
        )
    }

    private mutating func seal(upTo upperBound: Int) {
        let slice = source.slice(sealedUpperBound..<upperBound)
        let blocks = parse(
            slice,
            lineMap: source.lineMap,
            idNamespace: "stream",
            isSealed: true,
            isSealedRegion: true,
            referenceDefinitionsPrefix: referenceDefinitionsPrefix
        )
        sealedBlocks.append(contentsOf: blocks)
        recordReferenceDefinitions(
            in: slice,
            excluding: referenceDefinitionExclusionRanges(in: blocks)
        )
        sealedUpperBound = upperBound
        resetBoundaryScanState(lowerBound: upperBound)
    }

    private mutating func resetBoundaryScanState(lowerBound: Int) {
        ensureUniqueBoundaryScanStateStorage()
        boundaryScanStateStorage.state.reset(lowerBound: lowerBound)
        boundaryScanStateStorage.state.definedReferenceLabels = sealedReferenceDefinitionLabels
    }

    private mutating func ensureUniqueBoundaryScanStateStorage() {
        if !isKnownUniquelyReferenced(&boundaryScanStateStorage) {
            boundaryScanStateStorage = boundaryScanStateStorage.copy()
        }
    }

    private func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        isSealedRegion: Bool,
        referenceDefinitionsPrefix: String = ""
    ) -> [MarkdownBlock] {
        let key = MarkdownCacheKey(
            sourceRange: lineMapSourceRange(for: slice),
            contentHash: slice.contentHash,
            namespace: cacheNamespace(idNamespace, referenceDefinitionsPrefix: referenceDefinitionsPrefix)
        )

        if let cached = parserCache.blocks(forKey: key, isSealed: isSealed) {
            diagnosticsRecorder.recordCacheHit(isSealedRegion: isSealedRegion)
            return cached
        }

        diagnosticsRecorder.recordCacheMiss(isSealedRegion: isSealedRegion)
        diagnosticsRecorder.recordParse(isSealedRegion: isSealedRegion)
        let blocks = MarkdownDiagnostics().signpost("Parse", category: "Parser") {
            parser.parse(
                slice,
                lineMap: lineMap,
                idNamespace: idNamespace,
                isSealed: isSealed,
                referenceDefinitionsPrefix: referenceDefinitionsPrefix,
                diagnosticsRecorder: diagnosticsRecorder
            )
        }
        parserCache.insert(blocks, forKey: key)
        return blocks
    }

    private func cacheNamespace(
        _ idNamespace: String,
        referenceDefinitionsPrefix: String
    ) -> String {
        guard !referenceDefinitionsPrefix.isEmpty else {
            return idNamespace
        }

        return "\(idNamespace):refs:\(stableContentHash(referenceDefinitionsPrefix))"
    }

    private struct MultilineReferenceDefinition {
        var label: String
        var closingLineIndex: [MarkdownSourceLine].Index
        var remainderAfterColon: String
    }

    private mutating func recordReferenceDefinitions(
        in slice: MarkdownSourceSlice,
        excluding excludedRanges: [Range<Int>]
    ) {
        let sourceLines = source.lines(in: slice.byteRange)
        var lineIndex = sourceLines.startIndex

        while lineIndex < sourceLines.endIndex {
            let sourceLine = sourceLines[lineIndex]
            guard !lineIsExcludedFromReferenceDefinitionScan(sourceLine.byteRange, excludedRanges: excludedRanges) else {
                lineIndex += 1
                continue
            }

            let line = referenceDefinitionScanLine(normalizedLineText(sourceLine.text))
            if let multilineDefinition = multilineReferenceDefinition(
                startingAt: lineIndex,
                in: sourceLines,
                excluding: excludedRanges
            ) {
                let continuationEnd = referenceDefinitionContinuationEnd(
                    startingAfter: multilineDefinition.closingLineIndex,
                    in: sourceLines,
                    excluding: excludedRanges
                )

                if multilineReferenceDefinitionHasValidDestination(
                    multilineDefinition,
                    endingAt: continuationEnd,
                    in: sourceLines
                ),
                    sealedReferenceDefinitionLabels.insert(multilineDefinition.label).inserted {
                    appendReferenceDefinitionPrefixLines(sourceLines[lineIndex..<continuationEnd])
                }

                lineIndex = continuationEnd
                continue
            }

            guard let label = referenceDefinitionLabel(in: line) else {
                lineIndex += 1
                continue
            }

            let continuationEnd = referenceDefinitionContinuationEnd(
                startingAfter: lineIndex,
                in: sourceLines,
                excluding: excludedRanges
            )

            if referenceDefinitionHasValidDestination(
                startingAt: lineIndex,
                endingAt: continuationEnd,
                in: sourceLines
            ),
                sealedReferenceDefinitionLabels.insert(label).inserted {
                appendReferenceDefinitionPrefixLines(sourceLines[lineIndex..<continuationEnd])
            }

            lineIndex = continuationEnd
        }
    }

    private mutating func appendReferenceDefinitionPrefixLines(
        _ definitionLines: ArraySlice<MarkdownSourceLine>
    ) {
        for definitionLine in definitionLines {
            referenceDefinitionsPrefix += referenceDefinitionScanLine(
                normalizedLineText(definitionLine.text)
            )
            referenceDefinitionsPrefix += "\n"
        }
        referenceDefinitionsPrefix += "\n"
    }

    private func referenceDefinitionContinuationEnd(
        startingAfter definitionLineIndex: [MarkdownSourceLine].Index,
        in sourceLines: [MarkdownSourceLine],
        excluding excludedRanges: [Range<Int>]
    ) -> [MarkdownSourceLine].Index {
        var lineIndex = definitionLineIndex + 1

        while lineIndex < sourceLines.endIndex {
            let sourceLine = sourceLines[lineIndex]
            guard !lineIsExcludedFromReferenceDefinitionScan(sourceLine.byteRange, excludedRanges: excludedRanges) else {
                break
            }

            let line = referenceDefinitionScanLine(normalizedLineText(sourceLine.text))
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            if referenceDefinitionLabel(in: line) != nil {
                break
            }
            guard isReferenceDefinitionContinuationLine(line) else {
                break
            }

            lineIndex += 1
        }

        return lineIndex
    }

    private func multilineReferenceDefinition(
        startingAt lineIndex: [MarkdownSourceLine].Index,
        in sourceLines: [MarkdownSourceLine],
        excluding excludedRanges: [Range<Int>]
    ) -> MultilineReferenceDefinition? {
        guard lineIndex < sourceLines.endIndex else {
            return nil
        }

        let openingSourceLine = sourceLines[lineIndex]
        guard !lineIsExcludedFromReferenceDefinitionScan(
            openingSourceLine.byteRange,
            excludedRanges: excludedRanges
        ) else {
            return nil
        }

        let openingLine = referenceDefinitionScanLine(normalizedLineText(openingSourceLine.text))
        var cursor = openingLine.startIndex
        var leadingSpaces = 0
        while cursor < openingLine.endIndex, openingLine[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return nil
            }
            cursor = openingLine.index(after: cursor)
        }

        guard cursor < openingLine.endIndex, openingLine[cursor] == "[",
              closingBracket(in: openingLine, after: cursor) == nil
        else {
            return nil
        }

        var label = String(openingLine[openingLine.index(after: cursor)...])
        var continuationIndex = lineIndex + 1
        while continuationIndex < sourceLines.endIndex {
            let sourceLine = sourceLines[continuationIndex]
            guard !lineIsExcludedFromReferenceDefinitionScan(
                sourceLine.byteRange,
                excludedRanges: excludedRanges
            ) else {
                return nil
            }

            let line = referenceDefinitionScanLine(normalizedLineText(sourceLine.text))
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }

            if let closing = closingMultilineReferenceLabel(in: line) {
                label += "\n" + String(line[..<closing])
                let afterClosing = line.index(after: closing)
                guard afterClosing < line.endIndex, line[afterClosing] == ":" else {
                    return nil
                }
                guard let normalized = normalizedReferenceLabel(label[...]) else {
                    return nil
                }

                return MultilineReferenceDefinition(
                    label: normalized,
                    closingLineIndex: continuationIndex,
                    remainderAfterColon: String(line[line.index(after: afterClosing)...])
                )
            }

            label += "\n" + line
            continuationIndex += 1
        }

        return nil
    }

    private func multilineReferenceDefinitionHasValidDestination(
        _ definition: MultilineReferenceDefinition,
        endingAt continuationEnd: [MarkdownSourceLine].Index,
        in sourceLines: [MarkdownSourceLine]
    ) -> Bool {
        if referenceDefinitionRemainderHasDestination(definition.remainderAfterColon[...]) {
            return true
        }

        var lineIndex = definition.closingLineIndex + 1
        while lineIndex < continuationEnd {
            let line = referenceDefinitionScanLine(
                normalizedLineText(sourceLines[lineIndex].text)
            )
            if referenceDefinitionContinuationLineHasDestination(line) {
                return true
            }
            lineIndex += 1
        }

        return false
    }

    private func referenceDefinitionExclusionRanges(in blocks: [MarkdownBlock]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(blocks.count)

        for block in blocks {
            appendReferenceDefinitionExclusionRanges(from: block, to: &ranges)
        }

        return ranges.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound {
                return lhs.upperBound < rhs.upperBound
            }
            return lhs.lowerBound < rhs.lowerBound
        }
    }

    private func appendReferenceDefinitionExclusionRanges(
        from block: MarkdownBlock,
        to ranges: inout [Range<Int>]
    ) {
        switch block.kind {
        case .codeBlock, .htmlBlock, .mathBlock:
            ranges.append(block.sourceRange.byteRange)
        case .blockQuote:
            appendReferenceDefinitionContentExclusionRanges(from: block.inlines, to: &ranges)
        default:
            break
        }

        appendReferenceDefinitionExclusionRanges(from: block.inlines, to: &ranges)
        for childBlock in block.childBlocks {
            appendReferenceDefinitionExclusionRanges(from: childBlock, to: &ranges)
        }
        for item in block.listItems {
            appendReferenceDefinitionExclusionRanges(from: item, to: &ranges)
        }
        if let table = block.table {
            for cell in table.header {
                appendReferenceDefinitionContentExclusionRanges(from: cell.inlines, to: &ranges)
            }
            for row in table.rows {
                for cell in row {
                    appendReferenceDefinitionContentExclusionRanges(from: cell.inlines, to: &ranges)
                }
            }
        }
    }

    private func appendReferenceDefinitionExclusionRanges(
        from item: MarkdownListItem,
        to ranges: inout [Range<Int>]
    ) {
        appendReferenceDefinitionContentExclusionRanges(from: item.inlines, to: &ranges)
        appendReferenceDefinitionExclusionRanges(from: item.inlines, to: &ranges)
        for childBlock in item.childBlocks {
            appendReferenceDefinitionExclusionRanges(from: childBlock, to: &ranges)
        }
        for child in item.childItems {
            appendReferenceDefinitionExclusionRanges(from: child, to: &ranges)
        }
    }

    private func appendReferenceDefinitionExclusionRanges(
        from runs: [MarkdownInlineRun],
        to ranges: inout [Range<Int>]
    ) {
        for run in runs where run.kind == .code ||
            run.kind == .math ||
            run.presentation.contains(.math) ||
            run.presentation.contains(.html) {
            if let sourceRange = run.sourceRange {
                ranges.append(sourceRange.byteRange)
            }
        }
    }

    private func appendReferenceDefinitionContentExclusionRanges(
        from runs: [MarkdownInlineRun],
        to ranges: inout [Range<Int>]
    ) {
        for run in runs {
            if let sourceRange = run.sourceRange {
                ranges.append(sourceRange.byteRange)
            }
        }
    }

    private func lineIsExcludedFromReferenceDefinitionScan(
        _ lineRange: Range<Int>,
        excludedRanges: [Range<Int>]
    ) -> Bool {
        guard !lineRange.isEmpty else {
            return false
        }

        for range in excludedRanges {
            if range.lowerBound >= lineRange.upperBound {
                return false
            }
            if range.overlaps(lineRange) {
                return true
            }
        }
        return false
    }

    private func referenceDefinitionLabel(in line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return nil
            }
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == "[" else {
            return nil
        }

        let opening = cursor
        guard let closing = closingBracket(in: line, after: opening) else {
            return nil
        }

        let afterClosing = line.index(after: closing)
        guard afterClosing < line.endIndex, line[afterClosing] == ":" else {
            return nil
        }

        return normalizedReferenceLabel(line[line.index(after: opening)..<closing])
    }

    private func closingBracket(in line: String, after opening: String.Index) -> String.Index? {
        var cursor = line.index(after: opening)
        var depth = 1
        var escaped = false
        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = line.index(after: cursor)
        }
        return nil
    }

    private func closingMultilineReferenceLabel(in line: String) -> String.Index? {
        var cursor = line.startIndex
        var depth = 1
        var escaped = false
        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = line.index(after: cursor)
        }
        return nil
    }

    private func isReferenceDefinitionContinuationLine(_ line: String) -> Bool {
        referenceDefinitionContinuationContentStart(in: line) != nil
    }

    private func referenceDefinitionHasValidDestination(
        startingAt definitionLineIndex: [MarkdownSourceLine].Index,
        endingAt continuationEnd: [MarkdownSourceLine].Index,
        in sourceLines: [MarkdownSourceLine]
    ) -> Bool {
        guard definitionLineIndex < continuationEnd else {
            return false
        }

        let openingLine = referenceDefinitionScanLine(
            normalizedLineText(sourceLines[definitionLineIndex].text)
        )
        if let remainder = referenceDefinitionRemainderAfterOpeningColon(in: openingLine),
           referenceDefinitionRemainderHasDestination(remainder) {
            return true
        }

        var lineIndex = definitionLineIndex + 1
        while lineIndex < continuationEnd {
            let line = referenceDefinitionScanLine(
                normalizedLineText(sourceLines[lineIndex].text)
            )
            if referenceDefinitionContinuationLineHasDestination(line) {
                return true
            }
            lineIndex += 1
        }

        return false
    }

    private func referenceDefinitionRemainderAfterOpeningColon(in line: String) -> Substring? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return nil
            }
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == "[",
              let closing = closingBracket(in: line, after: cursor)
        else {
            return nil
        }

        let afterClosing = line.index(after: closing)
        guard afterClosing < line.endIndex, line[afterClosing] == ":" else {
            return nil
        }

        return line[line.index(after: afterClosing)...]
    }

    private func referenceDefinitionContinuationLineHasDestination(_ line: String) -> Bool {
        guard let cursor = referenceDefinitionContinuationContentStart(in: line) else {
            return false
        }

        return referenceDefinitionRemainderHasDestination(line[cursor...])
    }

    private func referenceDefinitionScanLine(_ line: String) -> String {
        var current = line
        while true {
            if let stripped = stripLeadingBlockQuoteMarker(from: current) {
                current = stripped
                continue
            }
            if let stripped = stripLeadingListItemMarker(from: current) {
                current = stripped
                continue
            }
            return current
        }
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
            guard afterMarker < line.endIndex,
                  line[afterMarker] == " " || line[afterMarker] == "\t"
            else {
                return nil
            }
            return String(line[skipInlineSpaces(in: line[afterMarker...], from: afterMarker)...])
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
        guard afterMarker < line.endIndex,
              line[afterMarker] == " " || line[afterMarker] == "\t"
        else {
            return nil
        }
        return String(line[skipInlineSpaces(in: line[afterMarker...], from: afterMarker)...])
    }

    private func referenceDefinitionContinuationContentStart(in line: String) -> String.Index? {
        var cursor = line.startIndex
        var sawIndent = false
        while cursor < line.endIndex,
              line[cursor] == " " || line[cursor] == "\t" {
            sawIndent = true
            cursor = line.index(after: cursor)
        }

        guard sawIndent, cursor < line.endIndex else {
            return nil
        }
        return cursor
    }

    private func referenceDefinitionRemainderHasDestination(_ remainder: Substring) -> Bool {
        var cursor = skipInlineSpaces(in: remainder, from: remainder.startIndex)
        guard cursor < remainder.endIndex else {
            return false
        }

        guard let destinationEnd = referenceDefinitionDestinationEnd(in: remainder, from: cursor) else {
            return false
        }

        cursor = skipInlineSpaces(in: remainder, from: destinationEnd)
        guard cursor < remainder.endIndex else {
            return true
        }

        guard let titleEnd = referenceDefinitionTitleEnd(in: remainder, from: cursor) else {
            return false
        }

        cursor = skipInlineSpaces(in: remainder, from: titleEnd)
        return cursor == remainder.endIndex
    }

    private func referenceDefinitionDestinationEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        guard start < remainder.endIndex else {
            return nil
        }

        if remainder[start] == "<" {
            return angleReferenceDefinitionDestinationEnd(in: remainder, from: start)
        }

        var cursor = start
        var parenDepth = 0
        var sawContent = false

        while cursor < remainder.endIndex {
            let character = remainder[cursor]
            if character == " " || character == "\t" {
                break
            }
            if character == "<" || character.isNewline || isASCIIControl(character) {
                return nil
            }
            if character == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex,
                      !remainder[next].isNewline,
                      !isASCIIControl(remainder[next]),
                      remainder[next] != " ",
                      remainder[next] != "\t"
                else {
                    return nil
                }
                sawContent = true
                cursor = remainder.index(after: next)
                continue
            }
            if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                guard parenDepth > 0 else {
                    return nil
                }
                parenDepth -= 1
            }
            sawContent = true
            cursor = remainder.index(after: cursor)
        }

        return sawContent && parenDepth == 0 ? cursor : nil
    }

    private func angleReferenceDefinitionDestinationEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        var cursor = remainder.index(after: start)

        while cursor < remainder.endIndex {
            let character = remainder[cursor]
            if character == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex,
                      !remainder[next].isNewline
                else {
                    return nil
                }
                cursor = remainder.index(after: next)
                continue
            }
            if character == ">" {
                return remainder.index(after: cursor)
            }
            if character == "<" || character.isNewline {
                return nil
            }
            cursor = remainder.index(after: cursor)
        }

        return nil
    }

    private func referenceDefinitionTitleEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        guard start < remainder.endIndex else {
            return nil
        }

        let opener = remainder[start]
        let closer: Character
        switch opener {
        case "\"", "'":
            closer = opener
        case "(":
            closer = ")"
        default:
            return nil
        }

        var cursor = remainder.index(after: start)
        while cursor < remainder.endIndex {
            if remainder[cursor] == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex else {
                    return nil
                }
                cursor = remainder.index(after: next)
                continue
            }

            if remainder[cursor] == closer {
                return remainder.index(after: cursor)
            }

            cursor = remainder.index(after: cursor)
        }

        return nil
    }

    private func skipInlineSpaces(
        in text: Substring,
        from start: Substring.Index
    ) -> Substring.Index {
        var cursor = start
        while cursor < text.endIndex,
              text[cursor] == " " || text[cursor] == "\t" {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private func isASCIIControl(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }

        return scalar.value < 0x20 || scalar.value == 0x7f
    }

    private func normalizedReferenceLabel(_ label: Substring) -> String? {
        let normalized = label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedLineText(_ line: String) -> String {
        if line.last == "\r" {
            return String(line.dropLast())
        }
        return line
    }

    private func stableContentHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private func lineMapSourceRange(for slice: MarkdownSourceSlice) -> MarkdownSourceRange {
        source.sourceRange(for: slice.byteRange)
    }

    private func snapshotItems(blocks: [MarkdownBlock]) -> [MarkdownSnapshotItem] {
        var items: [MarkdownSnapshotItem] = []
        let orderedBoundaries = hostBoundaries.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sourceOffset == rhs.element.sourceOffset {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.sourceOffset < rhs.element.sourceOffset
            }
            .map(\.element)
        var boundaryIndex = orderedBoundaries.startIndex

        for block in blocks {
            while boundaryIndex < orderedBoundaries.endIndex {
                let boundary = orderedBoundaries[boundaryIndex]
                if boundary.sourceOffset > block.sourceRange.byteRange.lowerBound {
                    break
                }
                items.append(.hostBoundary(boundary))
                boundaryIndex = orderedBoundaries.index(after: boundaryIndex)
            }

            items.append(.block(block))

            while boundaryIndex < orderedBoundaries.endIndex {
                let boundary = orderedBoundaries[boundaryIndex]
                if boundary.sourceOffset > block.sourceRange.byteRange.upperBound {
                    break
                }
                items.append(.hostBoundary(boundary))
                boundaryIndex = orderedBoundaries.index(after: boundaryIndex)
            }
        }

        items.append(contentsOf: orderedBoundaries[boundaryIndex...].map { .hostBoundary($0) })
        return items
    }
}
