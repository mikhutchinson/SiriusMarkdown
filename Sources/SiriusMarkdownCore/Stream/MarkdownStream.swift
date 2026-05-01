import Foundation

public struct MarkdownStream: Sendable {
    private var source: MarkdownSourceBuffer
    private var sealedUpperBound: Int
    private var sealedBlocks: [MarkdownBlock]
    private var hostBoundaries: [MarkdownHostBoundary]
    private var generation: Int
    private var finished: Bool
    private let parser: SwiftMarkdownParser
    private let boundaryScanner: MarkdownBoundaryScanner
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
        self.generation = 0
        self.finished = false
        self.parser = SwiftMarkdownParser()
        self.boundaryScanner = MarkdownBoundaryScanner()
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
        guard let upperBound = boundaryScanner.safeSealUpperBound(in: source, after: sealedUpperBound),
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
            generation += 1
            return
        }

        seal(upTo: source.byteCount)
        let boundaryID = id ?? MarkdownHostBoundaryID("host:\(hostBoundaries.count):\(source.byteCount)")
        hostBoundaries.append(MarkdownHostBoundary(id: boundaryID, sourceOffset: source.byteCount))
        generation += 1
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
                isSealedRegion: false
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
            isSealedRegion: true
        )
        sealedBlocks.append(contentsOf: blocks)
        sealedUpperBound = upperBound
    }

    private func parse(
        _ slice: MarkdownSourceSlice,
        lineMap: MarkdownLineMap,
        idNamespace: String,
        isSealed: Bool,
        isSealedRegion: Bool
    ) -> [MarkdownBlock] {
        let key = MarkdownCacheKey(
            sourceRange: lineMapSourceRange(for: slice),
            contentHash: slice.contentHash,
            namespace: idNamespace
        )

        if let cached = parserCache.blocks(forKey: key, isSealed: isSealed) {
            diagnosticsRecorder.recordCacheHit(isSealedRegion: isSealedRegion)
            return cached
        }

        diagnosticsRecorder.recordCacheMiss(isSealedRegion: isSealedRegion)
        diagnosticsRecorder.recordParse(isSealedRegion: isSealedRegion)
        let blocks = parser.parse(
            slice,
            lineMap: lineMap,
            idNamespace: idNamespace,
            isSealed: isSealed
        )
        parserCache.insert(blocks, forKey: key)
        return blocks
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
