import Foundation

struct MarkdownBoundaryFence: Sendable, Hashable {
    var marker: Character
    var length: Int
}

struct MarkdownBoundaryHTMLBlock: Sendable, Hashable {
    var closingToken: String
}

public struct MarkdownBoundaryScanState: Sendable, Hashable {
    var lowerBound: Int
    var scannedUpperBound: Int
    var candidateUpperBound: Int?
    var openFence: MarkdownBoundaryFence?
    var openMathFence: Bool
    var openHTMLBlock: MarkdownBoundaryHTMLBlock?
    var consecutiveBlankLines: Int
    var lastNonBlankWasListLike: Bool

    public init(lowerBound: Int = 0) {
        self.lowerBound = lowerBound
        self.scannedUpperBound = lowerBound
        self.candidateUpperBound = nil
        self.openFence = nil
        self.openMathFence = false
        self.openHTMLBlock = nil
        self.consecutiveBlankLines = 0
        self.lastNonBlankWasListLike = false
    }

    public mutating func reset(lowerBound: Int) {
        self = MarkdownBoundaryScanState(lowerBound: lowerBound)
    }
}

public struct MarkdownBoundaryScanResult: Sendable, Hashable {
    public var safeUpperBound: Int?
    public var scannedByteCount: Int
    public var scannedLineCount: Int

    public init(safeUpperBound: Int?, scannedByteCount: Int, scannedLineCount: Int) {
        self.safeUpperBound = safeUpperBound
        self.scannedByteCount = scannedByteCount
        self.scannedLineCount = scannedLineCount
    }
}

public struct MarkdownBoundaryScanner: Sendable, Hashable {
    public init() {}

    public func safeSealUpperBound(in source: MarkdownSourceBuffer, after lowerBound: Int) -> Int? {
        var state = MarkdownBoundaryScanState(lowerBound: lowerBound)
        return scan(in: source, state: &state).safeUpperBound
    }

    public func scan(
        in source: MarkdownSourceBuffer,
        state: inout MarkdownBoundaryScanState
    ) -> MarkdownBoundaryScanResult {
        if state.scannedUpperBound < state.lowerBound || state.scannedUpperBound > source.byteCount {
            state.reset(lowerBound: state.lowerBound)
        }

        let lines = source.lines(in: state.scannedUpperBound..<source.byteCount)
        guard !lines.isEmpty else {
            return MarkdownBoundaryScanResult(
                safeUpperBound: currentSafeUpperBound(in: state),
                scannedByteCount: 0,
                scannedLineCount: 0
            )
        }

        var scannedByteCount = 0
        var scannedLineCount = 0

        for line in lines {
            guard line.includesTerminatingNewline else {
                break
            }

            let nextLineStart = line.includesTerminatingNewline
                ? line.byteRange.upperBound + 1
                : line.byteRange.upperBound
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if let fence = state.openFence {
                if closesFence(trimmed, fence: fence) {
                    state.openFence = nil
                }
            } else if let html = state.openHTMLBlock {
                if closesHTMLBlock(trimmed, html: html) {
                    state.openHTMLBlock = nil
                }
            } else if state.openMathFence {
                if trimmed == "$$" {
                    state.openMathFence = false
                }
            } else if let fence = opensFence(trimmed) {
                state.openFence = fence
                state.lastNonBlankWasListLike = false
            } else if let html = opensHTMLBlock(trimmed) {
                state.openHTMLBlock = html
                state.lastNonBlankWasListLike = false
            } else if trimmed == "$$" {
                state.openMathFence = true
                state.lastNonBlankWasListLike = false
            } else if trimmed.isEmpty {
                state.consecutiveBlankLines += 1
                if !state.lastNonBlankWasListLike || state.consecutiveBlankLines >= 2 {
                    state.candidateUpperBound = min(nextLineStart, source.byteCount)
                }
            } else {
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = isListLike(trimmed)
            }

            scannedByteCount += max(0, nextLineStart - state.scannedUpperBound)
            scannedLineCount += 1
            state.scannedUpperBound = nextLineStart
        }

        return MarkdownBoundaryScanResult(
            safeUpperBound: currentSafeUpperBound(in: state),
            scannedByteCount: scannedByteCount,
            scannedLineCount: scannedLineCount
        )
    }

    private func currentSafeUpperBound(in state: MarkdownBoundaryScanState) -> Int? {
        if state.openFence != nil || state.openMathFence || state.openHTMLBlock != nil {
            return nil
        }

        return state.candidateUpperBound.flatMap { $0 > state.lowerBound ? $0 : nil }
    }

    private func opensFence(_ line: String) -> MarkdownBoundaryFence? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else {
            return nil
        }

        let marker = line.first ?? "`"
        let count = line.prefix { $0 == marker }.count
        guard count >= 3 else {
            return nil
        }

        return MarkdownBoundaryFence(marker: marker, length: count)
    }

    private func closesFence(_ line: String, fence: MarkdownBoundaryFence) -> Bool {
        let count = line.prefix { $0 == fence.marker }.count
        return count >= fence.length
    }

    private func opensHTMLBlock(_ line: String) -> MarkdownBoundaryHTMLBlock? {
        let lowercased = line.lowercased()

        if lowercased.hasPrefix("<!--") && !lowercased.contains("-->") {
            return MarkdownBoundaryHTMLBlock(closingToken: "-->")
        }

        for tag in ["script", "style", "pre", "table", "div", "section", "article", "aside"] {
            if lowercased.hasPrefix("<\(tag)") && !lowercased.contains("</\(tag)>") {
                return MarkdownBoundaryHTMLBlock(closingToken: "</\(tag)>")
            }
        }

        return nil
    }

    private func closesHTMLBlock(_ line: String, html: MarkdownBoundaryHTMLBlock) -> Bool {
        line.lowercased().contains(html.closingToken)
    }

    private func isListLike(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") ||
            line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") ||
            line.hasPrefix("* [ ]") || line.hasPrefix("* [x]") {
            return true
        }

        var index = line.startIndex
        var sawDigit = false
        while index < line.endIndex, line[index].isNumber {
            sawDigit = true
            index = line.index(after: index)
        }

        guard sawDigit, index < line.endIndex, line[index] == "." else {
            return false
        }

        let next = line.index(after: index)
        return next < line.endIndex && line[next] == " "
    }
}
