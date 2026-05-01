import Foundation

#if canImport(CoreText)
import CoreText
#endif

public struct PreparedInlineContent: Sendable, Hashable {
    public var runs: [MarkdownInlineRun]
    public var segments: [PreparedInlineSegment]
    public var sourceRange: MarkdownSourceRange?
    public var naturalText: String

    public init(runs: [MarkdownInlineRun], sourceRange: MarkdownSourceRange? = nil) {
        self.runs = runs
        self.segments = PreparedInlineSegment.prepare(from: runs)
        self.sourceRange = sourceRange
        self.naturalText = segments.map(\.text).joined()
    }
}

public struct PreparedInlineSegment: Sendable, Hashable {
    public var kind: MarkdownInlineKind
    public var text: String
    public var byteRange: Range<Int>
    public var isHardBreak: Bool
    public var isBreakOpportunity: Bool

    public init(
        kind: MarkdownInlineKind,
        text: String,
        byteRange: Range<Int>,
        isHardBreak: Bool = false,
        isBreakOpportunity: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.byteRange = byteRange
        self.isHardBreak = isHardBreak
        self.isBreakOpportunity = isBreakOpportunity
    }

    static func prepare(from runs: [MarkdownInlineRun]) -> [PreparedInlineSegment] {
        var segments: [PreparedInlineSegment] = []
        var cursor = 0

        for run in runs {
            if run.kind == .softBreak || run.kind == .hardBreak {
                let upper = cursor + run.text.utf8.count
                segments.append(
                    PreparedInlineSegment(
                        kind: run.kind,
                        text: run.text,
                        byteRange: cursor..<upper,
                        isHardBreak: true,
                        isBreakOpportunity: true
                    )
                )
                cursor = upper
                continue
            }

            for token in tokenize(run.text) {
                let upper = cursor + token.text.utf8.count
                segments.append(
                    PreparedInlineSegment(
                        kind: run.kind,
                        text: token.text,
                        byteRange: cursor..<upper,
                        isHardBreak: token.isHardBreak,
                        isBreakOpportunity: token.isBreakOpportunity
                    )
                )
                cursor = upper
            }
        }

        return segments
    }

    private static func tokenize(_ text: String) -> [(text: String, isHardBreak: Bool, isBreakOpportunity: Bool)] {
        guard !text.isEmpty else {
            return []
        }

        var tokens: [(String, Bool, Bool)] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for character in text {
            if character == "\n" {
                if let currentIsWhitespace {
                    tokens.append((current, false, currentIsWhitespace))
                    current = ""
                }
                tokens.append(("\n", true, true))
                currentIsWhitespace = nil
                continue
            }

            let isWhitespace = character.isWhitespace && character != "\n"
            if let currentIsWhitespace, currentIsWhitespace != isWhitespace {
                tokens.append((current, false, currentIsWhitespace))
                current = ""
            }

            current.append(character)
            currentIsWhitespace = isWhitespace
        }

        if let currentIsWhitespace {
            tokens.append((current, false, currentIsWhitespace))
        }

        return tokens
    }
}

public struct InlineLineRange: Sendable, Hashable {
    public var byteRange: Range<Int>
    public var width: Double

    public init(byteRange: Range<Int>, width: Double) {
        self.byteRange = byteRange
        self.width = width
    }
}

public struct InlineLayoutResult: Sendable, Hashable {
    public var lines: [InlineLineRange]
    public var naturalWidth: Double
    public var height: Double

    public init(lines: [InlineLineRange], naturalWidth: Double, height: Double) {
        self.lines = lines
        self.naturalWidth = naturalWidth
        self.height = height
    }
}

public struct InlineLayoutOptions: Sendable, Hashable {
    public var containerWidth: Double
    public var fontSize: Double
    public var lineHeight: Double

    public init(containerWidth: Double, fontSize: Double = 14, lineHeight: Double = 18) {
        self.containerWidth = containerWidth
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
}

public protocol InlineMeasuring: Sendable {
    func width(of text: String, fontSize: Double) -> Double
}

public struct CoreTextInlineMeasurer: InlineMeasuring {
    public init() {}

    public func width(of text: String, fontSize: Double) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        #if canImport(CoreText)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = CFAttributedStringCreate(
            nil,
            text as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )
        let line = CTLineCreateWithAttributedString(attributed!)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
        #else
        return Double(text.count) * fontSize * 0.5
        #endif
    }
}

public struct VariableWidthLineWalker<Measurer: InlineMeasuring>: Sendable {
    public var measurer: Measurer

    public init(measurer: Measurer) {
        self.measurer = measurer
    }

    public func layout(_ prepared: PreparedInlineContent, options: InlineLayoutOptions) -> InlineLayoutResult {
        guard !prepared.segments.isEmpty else {
            return InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
        }

        let containerWidth = max(0, options.containerWidth)
        var lines: [InlineLineRange] = []
        var currentWidth = 0.0
        var currentStart = 0
        var naturalWidth = 0.0

        for segment in prepared.segments {
            if segment.isHardBreak {
                lines.append(InlineLineRange(byteRange: currentStart..<segment.byteRange.lowerBound, width: currentWidth))
                naturalWidth = max(naturalWidth, currentWidth)
                currentWidth = 0
                currentStart = segment.byteRange.upperBound
                continue
            }

            let segmentWidth = measurer.width(of: segment.text, fontSize: options.fontSize)
            naturalWidth = max(naturalWidth, currentWidth + segmentWidth)

            if currentWidth > 0, currentWidth + segmentWidth > containerWidth {
                lines.append(InlineLineRange(byteRange: currentStart..<segment.byteRange.lowerBound, width: currentWidth))
                currentStart = segment.byteRange.lowerBound
                currentWidth = 0
            }

            if segmentWidth > containerWidth, !segment.isBreakOpportunity {
                let split = splitOverwideSegment(
                    segment,
                    options: options,
                    currentStart: currentStart,
                    currentWidth: currentWidth
                )
                lines.append(contentsOf: split.closedLines)
                currentStart = split.currentStart
                currentWidth = split.currentWidth
            } else {
                currentWidth += segmentWidth
            }
        }

        let end = prepared.segments.last?.byteRange.upperBound ?? currentStart
        if currentStart <= end {
            lines.append(InlineLineRange(byteRange: currentStart..<end, width: currentWidth))
        }

        return InlineLayoutResult(
            lines: lines,
            naturalWidth: naturalWidth,
            height: Double(lines.count) * options.lineHeight
        )
    }

    private func splitOverwideSegment(
        _ segment: PreparedInlineSegment,
        options: InlineLayoutOptions,
        currentStart: Int,
        currentWidth: Double
    ) -> (closedLines: [InlineLineRange], currentStart: Int, currentWidth: Double) {
        var lines: [InlineLineRange] = []
        var lineStart = currentStart
        var width = currentWidth
        var cursor = segment.byteRange.lowerBound
        let containerWidth = max(0, options.containerWidth)

        for character in segment.text {
            let characterText = String(character)
            let characterWidth = measurer.width(of: characterText, fontSize: options.fontSize)

            if width > 0, width + characterWidth > containerWidth {
                lines.append(InlineLineRange(byteRange: lineStart..<cursor, width: width))
                lineStart = cursor
                width = 0
            }

            width += characterWidth
            cursor += characterText.utf8.count
        }

        return (lines, lineStart, width)
    }
}

public extension VariableWidthLineWalker where Measurer == CoreTextInlineMeasurer {
    init() {
        self.measurer = CoreTextInlineMeasurer()
    }
}
