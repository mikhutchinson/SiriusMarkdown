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

public struct MeasuredInlineSegment: Sendable, Hashable {
    public var segment: PreparedInlineSegment
    public var width: Double
    public var units: [MeasuredInlineUnit]

    public init(
        segment: PreparedInlineSegment,
        width: Double,
        units: [MeasuredInlineUnit] = []
    ) {
        self.segment = segment
        self.width = width
        self.units = units
    }
}

public struct MeasuredInlineUnit: Sendable, Hashable {
    public var byteRange: Range<Int>
    public var width: Double

    public init(byteRange: Range<Int>, width: Double) {
        self.byteRange = byteRange
        self.width = width
    }
}

public struct MeasuredInlineContent: Sendable, Hashable {
    public var prepared: PreparedInlineContent
    public var segments: [MeasuredInlineSegment]
    public var naturalWidth: Double
    public var fontSize: Double

    public init(
        prepared: PreparedInlineContent,
        segments: [MeasuredInlineSegment],
        naturalWidth: Double,
        fontSize: Double
    ) {
        self.prepared = prepared
        self.segments = segments
        self.naturalWidth = naturalWidth
        self.fontSize = fontSize
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

    public func prepare(_ prepared: PreparedInlineContent, fontSize: Double = 14) -> MeasuredInlineContent {
        var measuredSegments: [MeasuredInlineSegment] = []
        var currentLineWidth = 0.0
        var naturalWidth = 0.0

        for segment in prepared.segments {
            if segment.isHardBreak {
                naturalWidth = max(naturalWidth, currentLineWidth)
                currentLineWidth = 0
                measuredSegments.append(MeasuredInlineSegment(segment: segment, width: 0))
                continue
            }

            let width = measurer.width(of: segment.text, fontSize: fontSize)
            let measured = MeasuredInlineSegment(
                segment: segment,
                width: width,
                units: measuredUnits(for: segment, fontSize: fontSize)
            )
            measuredSegments.append(measured)
            currentLineWidth += width
        }

        naturalWidth = max(naturalWidth, currentLineWidth)
        return MeasuredInlineContent(
            prepared: prepared,
            segments: measuredSegments,
            naturalWidth: naturalWidth,
            fontSize: fontSize
        )
    }

    public func layout(_ measured: MeasuredInlineContent, options: InlineLayoutOptions) -> InlineLayoutResult {
        guard !measured.segments.isEmpty else {
            return InlineLayoutResult(lines: [], naturalWidth: 0, height: 0)
        }

        let containerWidth = max(0, options.containerWidth)
        var lines: [InlineLineRange] = []
        var currentWidth = 0.0
        var currentStart = 0

        for measuredSegment in measured.segments {
            let segment = measuredSegment.segment

            if segment.isHardBreak {
                lines.append(InlineLineRange(byteRange: currentStart..<segment.byteRange.lowerBound, width: currentWidth))
                currentWidth = 0
                currentStart = segment.byteRange.upperBound
                continue
            }

            if currentWidth > 0, currentWidth + measuredSegment.width > containerWidth {
                lines.append(InlineLineRange(byteRange: currentStart..<segment.byteRange.lowerBound, width: currentWidth))
                currentStart = segment.byteRange.lowerBound
                currentWidth = 0
            }

            if measuredSegment.width > containerWidth, !segment.isBreakOpportunity {
                let split = splitOverwideSegment(
                    measuredSegment,
                    containerWidth: containerWidth,
                    currentStart: currentStart,
                    currentWidth: currentWidth
                )
                lines.append(contentsOf: split.closedLines)
                currentStart = split.currentStart
                currentWidth = split.currentWidth
            } else {
                currentWidth += measuredSegment.width
            }
        }

        let end = measured.segments.last?.segment.byteRange.upperBound ?? currentStart
        if currentStart <= end {
            lines.append(InlineLineRange(byteRange: currentStart..<end, width: currentWidth))
        }

        return InlineLayoutResult(
            lines: lines,
            naturalWidth: measured.naturalWidth,
            height: Double(lines.count) * options.lineHeight
        )
    }

    public func layout(_ prepared: PreparedInlineContent, options: InlineLayoutOptions) -> InlineLayoutResult {
        layout(prepare(prepared, fontSize: options.fontSize), options: options)
    }

    private func splitOverwideSegment(
        _ measuredSegment: MeasuredInlineSegment,
        containerWidth: Double,
        currentStart: Int,
        currentWidth: Double
    ) -> (closedLines: [InlineLineRange], currentStart: Int, currentWidth: Double) {
        var lines: [InlineLineRange] = []
        var lineStart = currentStart
        var width = currentWidth

        for unit in measuredSegment.units {
            if width > 0, width + unit.width > containerWidth {
                lines.append(InlineLineRange(byteRange: lineStart..<unit.byteRange.lowerBound, width: width))
                lineStart = unit.byteRange.lowerBound
                width = 0
            }

            width += unit.width
        }

        return (lines, lineStart, width)
    }

    private func measuredUnits(for segment: PreparedInlineSegment, fontSize: Double) -> [MeasuredInlineUnit] {
        guard !segment.isBreakOpportunity else {
            return []
        }

        var units: [MeasuredInlineUnit] = []
        var cursor = segment.byteRange.lowerBound

        for character in segment.text {
            let characterText = String(character)
            let upper = cursor + characterText.utf8.count
            units.append(
                MeasuredInlineUnit(
                    byteRange: cursor..<upper,
                    width: measurer.width(of: characterText, fontSize: fontSize)
                )
            )
            cursor = upper
        }

        return units
    }
}

public extension VariableWidthLineWalker where Measurer == CoreTextInlineMeasurer {
    init() {
        self.measurer = CoreTextInlineMeasurer()
    }
}
