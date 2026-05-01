import Foundation

public struct MarkdownSourceSlice: Sendable, Hashable {
    public var byteRange: Range<Int>
    private var segments: [ArraySlice<UInt8>]

    public init(byteRange: Range<Int>, text: String) {
        self.byteRange = byteRange
        let bytes = Array(text.utf8)
        self.segments = [bytes[bytes.startIndex..<bytes.endIndex]]
    }

    init(byteRange: Range<Int>, segments: [ArraySlice<UInt8>]) {
        self.byteRange = byteRange
        self.segments = segments
    }

    public var text: String {
        guard !segments.isEmpty else {
            return ""
        }

        if segments.count == 1, let segment = segments.first {
            return String(decoding: segment, as: UTF8.self)
        }

        var result = ""
        result.reserveCapacity(byteRange.count)
        for segment in segments {
            result += String(decoding: segment, as: UTF8.self)
        }
        return result
    }

    public var contentHash: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for segment in segments {
            for byte in segment {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
        }
        return hash
    }
}

public struct MarkdownSourceLine: Sendable, Hashable {
    private var segments: [ArraySlice<UInt8>]
    public var byteRange: Range<Int>
    public var includesTerminatingNewline: Bool

    public init(
        text: String,
        byteRange: Range<Int>,
        includesTerminatingNewline: Bool
    ) {
        let bytes = Array(text.utf8)
        self.segments = [bytes[bytes.startIndex..<bytes.endIndex]]
        self.byteRange = byteRange
        self.includesTerminatingNewline = includesTerminatingNewline
    }

    init(
        segments: [ArraySlice<UInt8>],
        byteRange: Range<Int>,
        includesTerminatingNewline: Bool
    ) {
        self.segments = segments
        self.byteRange = byteRange
        self.includesTerminatingNewline = includesTerminatingNewline
    }

    public var text: String {
        guard !segments.isEmpty else {
            return ""
        }

        if segments.count == 1, let segment = segments.first {
            return String(decoding: segment, as: UTF8.self)
        }

        var result = ""
        result.reserveCapacity(byteRange.count)
        for segment in segments {
            result += String(decoding: segment, as: UTF8.self)
        }
        return result
    }
}

public struct MarkdownLineMap: Sendable, Hashable {
    public var newlineByteOffsets: [Int]

    public init(newlineByteOffsets: [Int]) {
        self.newlineByteOffsets = newlineByteOffsets
    }

    public func lineNumber(containingByteOffset offset: Int) -> Int {
        var low = 0
        var high = newlineByteOffsets.count

        while low < high {
            let mid = (low + high) / 2
            if newlineByteOffsets[mid] < offset {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low + 1
    }

    public func lineRange(for byteRange: Range<Int>) -> Range<Int> {
        guard !byteRange.isEmpty else {
            let line = lineNumber(containingByteOffset: byteRange.lowerBound)
            return line..<(line + 1)
        }

        let lower = lineNumber(containingByteOffset: byteRange.lowerBound)
        let upper = lineNumber(containingByteOffset: max(byteRange.lowerBound, byteRange.upperBound - 1)) + 1
        return lower..<upper
    }
}

public struct MarkdownSourceBuffer: Sendable, Hashable {
    private var chunks: [[UInt8]]
    private var chunkStartOffsets: [Int]
    private var newlineByteOffsets: [Int]
    public private(set) var byteCount: Int

    public init() {
        self.chunks = []
        self.chunkStartOffsets = []
        self.newlineByteOffsets = []
        self.byteCount = 0
    }

    public var isEmpty: Bool {
        byteCount == 0
    }

    public var lineMap: MarkdownLineMap {
        MarkdownLineMap(newlineByteOffsets: newlineByteOffsets)
    }

    @discardableResult
    public mutating func append(_ text: String) -> MarkdownSourceRange {
        let bytes = Array(text.utf8)
        let lowerBound = byteCount

        for (index, byte) in bytes.enumerated() where byte == 10 {
            newlineByteOffsets.append(lowerBound + index)
        }

        chunkStartOffsets.append(lowerBound)
        chunks.append(bytes)
        byteCount += bytes.count

        return MarkdownSourceRange(
            byteRange: lowerBound..<byteCount,
            lineRange: lineMap.lineRange(for: lowerBound..<byteCount)
        )
    }

    public func slice(_ byteRange: Range<Int>) -> MarkdownSourceSlice {
        precondition(byteRange.lowerBound >= 0)
        precondition(byteRange.upperBound <= byteCount)

        guard !byteRange.isEmpty else {
            return MarkdownSourceSlice(byteRange: byteRange, text: "")
        }

        var segments: [ArraySlice<UInt8>] = []

        for index in firstChunkIndex(intersecting: byteRange)..<chunks.count {
            let chunk = chunks[index]
            let chunkStart = chunkStartOffsets[index]
            let chunkRange = chunkStart..<(chunkStart + chunk.count)
            let lower = max(byteRange.lowerBound, chunkRange.lowerBound)
            let upper = min(byteRange.upperBound, chunkRange.upperBound)

            if lower < upper {
                let start = lower - chunkRange.lowerBound
                let end = upper - chunkRange.lowerBound
                segments.append(chunk[start..<end])
            }

            if chunkRange.upperBound >= byteRange.upperBound {
                break
            }
        }

        return MarkdownSourceSlice(byteRange: byteRange, segments: segments)
    }

    public func lines(in byteRange: Range<Int>) -> [MarkdownSourceLine] {
        precondition(byteRange.lowerBound >= 0)
        precondition(byteRange.upperBound <= byteCount)

        guard !byteRange.isEmpty else {
            return []
        }

        var lines: [MarkdownSourceLine] = []
        var lineSegments: [ArraySlice<UInt8>] = []
        var segmentStart: Int?
        var lineStart = byteRange.lowerBound

        for chunkIndex in firstChunkIndex(intersecting: byteRange)..<chunks.count {
            let chunk = chunks[chunkIndex]
            let chunkStart = chunkStartOffsets[chunkIndex]
            let chunkRange = chunkStart..<(chunkStart + chunk.count)
            let lower = max(byteRange.lowerBound, chunkRange.lowerBound)
            let upper = min(byteRange.upperBound, chunkRange.upperBound)

            if lower < upper {
                let start = lower - chunkRange.lowerBound
                let end = upper - chunkRange.lowerBound

                for index in start..<end {
                    let byte = chunk[index]
                    let absoluteOffset = chunkRange.lowerBound + index
                    if segmentStart == nil {
                        segmentStart = index
                    }

                    if byte == 10 {
                        if let start = segmentStart, start < index {
                            lineSegments.append(chunk[start..<index])
                        }
                        lines.append(
                            MarkdownSourceLine(
                                segments: lineSegments,
                                byteRange: lineStart..<absoluteOffset,
                                includesTerminatingNewline: true
                            )
                        )
                        lineSegments.removeAll(keepingCapacity: true)
                        segmentStart = nil
                        lineStart = absoluteOffset + 1
                    }
                }

                if let start = segmentStart, start < end {
                    lineSegments.append(chunk[start..<end])
                }
                segmentStart = nil
            }

            if chunkRange.upperBound >= byteRange.upperBound {
                break
            }
        }

        if lineStart < byteRange.upperBound || !lineSegments.isEmpty {
            lines.append(
                MarkdownSourceLine(
                    segments: lineSegments,
                    byteRange: lineStart..<byteRange.upperBound,
                    includesTerminatingNewline: false
                )
            )
        }

        return lines
    }

    public func containsByte(_ target: UInt8, in byteRange: Range<Int>) -> Bool {
        precondition(byteRange.lowerBound >= 0)
        precondition(byteRange.upperBound <= byteCount)

        guard !byteRange.isEmpty else {
            return false
        }

        for index in firstChunkIndex(intersecting: byteRange)..<chunks.count {
            let chunk = chunks[index]
            let chunkStart = chunkStartOffsets[index]
            let chunkRange = chunkStart..<(chunkStart + chunk.count)
            let lower = max(byteRange.lowerBound, chunkRange.lowerBound)
            let upper = min(byteRange.upperBound, chunkRange.upperBound)

            if lower < upper {
                let start = lower - chunkRange.lowerBound
                let end = upper - chunkRange.lowerBound
                if chunk[start..<end].contains(target) {
                    return true
                }
            }

            if chunkRange.upperBound >= byteRange.upperBound {
                break
            }
        }

        return false
    }

    public func fullText() -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for chunk in chunks {
            bytes.append(contentsOf: chunk)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func sourceRange(for byteRange: Range<Int>) -> MarkdownSourceRange {
        MarkdownSourceRange(
            byteRange: byteRange,
            lineRange: lineMap.lineRange(for: byteRange)
        )
    }

    private func firstChunkIndex(intersecting byteRange: Range<Int>) -> Int {
        guard !chunks.isEmpty else {
            return 0
        }

        var low = 0
        var high = chunkStartOffsets.count
        while low < high {
            let mid = (low + high) / 2
            let chunkUpperBound = chunkStartOffsets[mid] + chunks[mid].count
            if chunkUpperBound <= byteRange.lowerBound {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
