import Foundation

public struct MarkdownBoundaryScanner: Sendable, Hashable {
    public init() {}

    public func safeSealUpperBound(in source: MarkdownSourceBuffer, after lowerBound: Int) -> Int? {
        let lines = source.lines(in: lowerBound..<source.byteCount)
        guard !lines.isEmpty else {
            return nil
        }

        var candidate: Int?
        var openFence: Fence?
        var openMathFence = false
        var openHTMLBlock: HTMLBlock?
        var consecutiveBlankLines = 0
        var lastNonBlankWasListLike = false

        for line in lines {
            let nextLineStart = line.includesTerminatingNewline
                ? line.byteRange.upperBound + 1
                : line.byteRange.upperBound
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if let fence = openFence {
                if closesFence(trimmed, fence: fence) {
                    openFence = nil
                }
            } else if let html = openHTMLBlock {
                if closesHTMLBlock(trimmed, html: html) {
                    openHTMLBlock = nil
                }
            } else if openMathFence {
                if trimmed == "$$" {
                    openMathFence = false
                }
            } else if let fence = opensFence(trimmed) {
                openFence = fence
                lastNonBlankWasListLike = false
            } else if let html = opensHTMLBlock(trimmed) {
                openHTMLBlock = html
                lastNonBlankWasListLike = false
            } else if trimmed == "$$" {
                openMathFence = true
                lastNonBlankWasListLike = false
            } else if trimmed.isEmpty {
                consecutiveBlankLines += 1
                if !lastNonBlankWasListLike || consecutiveBlankLines >= 2 {
                    candidate = min(nextLineStart, source.byteCount)
                }
            } else {
                consecutiveBlankLines = 0
                lastNonBlankWasListLike = isListLike(trimmed)
            }
        }

        if openFence != nil || openMathFence || openHTMLBlock != nil {
            return nil
        }

        return candidate.flatMap { $0 > lowerBound ? $0 : nil }
    }

    private struct Fence: Sendable, Hashable {
        var marker: Character
        var length: Int
    }

    private struct HTMLBlock: Sendable, Hashable {
        var closingToken: String
    }

    private func opensFence(_ line: String) -> Fence? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else {
            return nil
        }

        let marker = line.first ?? "`"
        let count = line.prefix { $0 == marker }.count
        guard count >= 3 else {
            return nil
        }

        return Fence(marker: marker, length: count)
    }

    private func closesFence(_ line: String, fence: Fence) -> Bool {
        let count = line.prefix { $0 == fence.marker }.count
        return count >= fence.length
    }

    private func opensHTMLBlock(_ line: String) -> HTMLBlock? {
        let lowercased = line.lowercased()

        if lowercased.hasPrefix("<!--") && !lowercased.contains("-->") {
            return HTMLBlock(closingToken: "-->")
        }

        for tag in ["script", "style", "pre", "table", "div", "section", "article", "aside"] {
            if lowercased.hasPrefix("<\(tag)") && !lowercased.contains("</\(tag)>") {
                return HTMLBlock(closingToken: "</\(tag)>")
            }
        }

        return nil
    }

    private func closesHTMLBlock(_ line: String, html: HTMLBlock) -> Bool {
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
