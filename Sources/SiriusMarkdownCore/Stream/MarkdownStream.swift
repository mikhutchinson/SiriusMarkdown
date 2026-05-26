import Foundation

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
    private var boundaryScanState: MarkdownBoundaryScanState
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
        self.boundaryScanState = MarkdownBoundaryScanState()
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
        if boundaryScanState.lowerBound != sealedUpperBound {
            resetBoundaryScanState(lowerBound: sealedUpperBound)
        }

        let result = MarkdownDiagnostics().signpost("BoundaryScan", category: "Stream") {
            boundaryScanner.scan(in: source, state: &boundaryScanState)
        }
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
        boundaryScanState.reset(lowerBound: lowerBound)
        boundaryScanState.definedReferenceLabels = sealedReferenceDefinitionLabels
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
                referenceDefinitionsPrefix: referenceDefinitionsPrefix
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

    private mutating func recordReferenceDefinitions(
        in slice: MarkdownSourceSlice,
        excluding excludedRanges: [Range<Int>]
    ) {
        for sourceLine in source.lines(in: slice.byteRange) {
            guard !lineIsExcludedFromReferenceDefinitionScan(sourceLine.byteRange, excludedRanges: excludedRanges) else {
                continue
            }

            let line = normalizedLineText(sourceLine.text)
            guard let label = referenceDefinitionLabel(in: line),
                  sealedReferenceDefinitionLabels.insert(label).inserted
            else {
                continue
            }

            referenceDefinitionsPrefix += line
            referenceDefinitionsPrefix += "\n"
        }
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
        case .codeBlock, .htmlBlock:
            ranges.append(block.sourceRange.byteRange)
        default:
            break
        }

        appendReferenceDefinitionExclusionRanges(from: block.inlines, to: &ranges)
        for item in block.listItems {
            appendReferenceDefinitionExclusionRanges(from: item, to: &ranges)
        }
        if let table = block.table {
            for cell in table.header {
                appendReferenceDefinitionExclusionRanges(from: cell.inlines, to: &ranges)
            }
            for row in table.rows {
                for cell in row {
                    appendReferenceDefinitionExclusionRanges(from: cell.inlines, to: &ranges)
                }
            }
        }
    }

    private func appendReferenceDefinitionExclusionRanges(
        from item: MarkdownListItem,
        to ranges: inout [Range<Int>]
    ) {
        appendReferenceDefinitionExclusionRanges(from: item.inlines, to: &ranges)
        for child in item.childItems {
            appendReferenceDefinitionExclusionRanges(from: child, to: &ranges)
        }
    }

    private func appendReferenceDefinitionExclusionRanges(
        from runs: [MarkdownInlineRun],
        to ranges: inout [Range<Int>]
    ) {
        for run in runs where run.kind == .code {
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
        var escaped = false
        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "]" {
                return cursor
            }
            cursor = line.index(after: cursor)
        }
        return nil
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
        var remainingBoundaries = hostBoundaries.sorted { $0.sourceOffset < $1.sourceOffset }

        for block in blocks.sorted(by: { $0.sourceRange.byteRange.lowerBound < $1.sourceRange.byteRange.lowerBound }) {
            while let boundary = remainingBoundaries.first,
                  boundary.sourceOffset <= block.sourceRange.byteRange.lowerBound {
                items.append(.hostBoundary(boundary))
                remainingBoundaries.removeFirst()
            }

            items.append(.block(block))

            while let boundary = remainingBoundaries.first,
                  boundary.sourceOffset <= block.sourceRange.byteRange.upperBound {
                items.append(.hostBoundary(boundary))
                remainingBoundaries.removeFirst()
            }
        }

        items.append(contentsOf: remainingBoundaries.map { .hostBoundary($0) })
        return items
    }
}
