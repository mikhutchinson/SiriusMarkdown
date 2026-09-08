import Foundation
import SiriusMarkdownCore

/// Maps prepared runs to the explicit-line attributed string consumed by
/// TextKit. Inserted newlines and discarded wrap whitespace change storage
/// offsets; original source offsets must never be used to replace attachments.
enum MarkdownNativeLineSourceMap {
    static func runRanges(prepared: PreparedInlineContent, layout: InlineLayoutResult) -> [NSRange?] {
        var runByteRanges: [Range<Int>] = []
        var endpoints: Set<Int> = []
        var byteOffset = 0
        for run in prepared.runs {
            let end = byteOffset + run.text.utf8.count
            runByteRanges.append(byteOffset..<end)
            endpoints.insert(byteOffset)
            endpoints.insert(end)
            byteOffset = end
        }
        for line in layout.lines {
            endpoints.insert(line.byteRange.lowerBound)
            endpoints.insert(line.byteRange.upperBound)
        }

        // One UTF-8 walk supplies every requested UTF-16 boundary, including
        // supplementary scalars. No repeated prefix decoding per attachment.
        var utf16Offsets: [Int: Int] = [:]
        var utf16Offset = 0
        for (index, byte) in prepared.naturalText.utf8.enumerated() {
            if endpoints.contains(index) { utf16Offsets[index] = utf16Offset }
            if byte < 0x80 || byte >= 0xC0 {
                utf16Offset += byte >= 0xF0 ? 2 : 1
            }
        }
        utf16Offsets[prepared.naturalTextUTF8Count] = utf16Offset

        var lineMappings: [(bytes: Range<Int>, sourceUTF16Start: Int, displayUTF16Start: Int)] = []
        var displayOffset = 0
        for (index, line) in layout.lines.enumerated() {
            if index > 0 { displayOffset += 1 }
            guard let lower = utf16Offsets[line.byteRange.lowerBound],
                  let upper = utf16Offsets[line.byteRange.upperBound], upper >= lower else { continue }
            lineMappings.append((line.byteRange, lower, displayOffset))
            displayOffset += max(1, upper - lower)
        }

        var lineIndex = 0
        return runByteRanges.map { range in
            while lineIndex < lineMappings.count,
                  range.lowerBound >= lineMappings[lineIndex].bytes.upperBound {
                lineIndex += 1
            }
            guard lineIndex < lineMappings.count,
                  !range.isEmpty,
                  range.lowerBound >= lineMappings[lineIndex].bytes.lowerBound,
                  range.upperBound <= lineMappings[lineIndex].bytes.upperBound,
                  let lower = utf16Offsets[range.lowerBound],
                  let upper = utf16Offsets[range.upperBound] else { return nil }
            let line = lineMappings[lineIndex]
            return NSRange(location: line.displayUTF16Start + lower - line.sourceUTF16Start, length: upper - lower)
        }
    }
}
