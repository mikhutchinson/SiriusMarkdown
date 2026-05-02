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

            if run.kind == .code || run.kind == .image || run.kind == .math {
                let upper = cursor + run.text.utf8.count
                segments.append(
                    PreparedInlineSegment(
                        kind: run.kind,
                        text: run.text,
                        byteRange: cursor..<upper,
                        isHardBreak: false,
                        isBreakOpportunity: false
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
    public var consumedByteRange: Range<Int>
    public var width: Double

    public init(byteRange: Range<Int>, width: Double) {
        self.init(byteRange: byteRange, consumedByteRange: nil, width: width)
    }

    public init(byteRange: Range<Int>, consumedByteRange: Range<Int>? = nil, width: Double) {
        self.byteRange = byteRange
        self.consumedByteRange = consumedByteRange ?? byteRange
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

public typealias TextMeasurer = InlineMeasuring

public struct CoreTextInlineMeasurer: InlineMeasuring {
    public var fontName: String

    public init(fontName: String = "Helvetica") {
        self.fontName = fontName
    }

    public func width(of text: String, fontSize: Double) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        #if canImport(CoreText)
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        if selectedFontCoversEveryScalar(in: text, font: font) {
            return shapedWidth(of: text, font: font)
        }

        return baseFontAdvanceWidth(of: text, font: font)
        #else
        return Double(text.count) * fontSize * 0.5
        #endif
    }

    #if canImport(CoreText)
    private func shapedWidth(of text: String, font: CTFont) -> Double {
        let attributed = CFAttributedStringCreate(
            nil,
            text as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )
        let line = CTLineCreateWithAttributedString(attributed!)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func baseFontAdvanceWidth(of text: String, font: CTFont) -> Double {
        var width = 0.0
        var coveredRun = ""
        let missingAdvance = missingGlyphAdvance(font: font)

        func flushCoveredRun() {
            guard !coveredRun.isEmpty else {
                return
            }

            width += shapedWidth(of: coveredRun, font: font)
            coveredRun.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if selectedFontCovers(scalar, font: font) {
                coveredRun.unicodeScalars.append(scalar)
            } else {
                flushCoveredRun()
                width += missingAdvance
            }
        }

        flushCoveredRun()
        return width
    }

    private func selectedFontCoversEveryScalar(in text: String, font: CTFont) -> Bool {
        text.unicodeScalars.allSatisfy { selectedFontCovers($0, font: font) }
    }

    private func selectedFontCovers(_ scalar: Unicode.Scalar, font: CTFont) -> Bool {
        guard scalar.value <= UInt16.max else {
            return false
        }

        var character = UniChar(scalar.value)
        var glyph = CGGlyph()
        return CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
    }

    private func missingGlyphAdvance(font: CTFont) -> Double {
        var glyph = CGGlyph()
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }
    #endif
}

public struct VariableWidthLineWalker<Measurer: InlineMeasuring>: Sendable {
    public var measurer: Measurer

    public init(measurer: Measurer) {
        self.measurer = measurer
    }

    public func prepare(
        _ prepared: PreparedInlineContent,
        fontSize: Double = 14,
        includesUnitMeasurements: Bool = false
    ) -> MeasuredInlineContent {
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
                units: includesUnitMeasurements && !segment.isBreakOpportunity
                    ? measuredUnits(for: segment, fontSize: fontSize)
                    : []
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

    public func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = true
    ) -> InlineLayoutResult {
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
                lines.append(
                    InlineLineRange(
                        byteRange: currentStart..<segment.byteRange.lowerBound,
                        consumedByteRange: currentStart..<segment.byteRange.upperBound,
                        width: currentWidth
                    )
                )
                currentWidth = 0
                currentStart = segment.byteRange.upperBound
                continue
            }

            if currentWidth > 0, currentWidth + measuredSegment.width > containerWidth {
                if segment.isBreakOpportunity {
                    currentWidth += measuredSegment.width
                    continue
                }

                lines.append(InlineLineRange(byteRange: currentStart..<segment.byteRange.lowerBound, width: currentWidth))
                currentStart = segment.byteRange.lowerBound
                currentWidth = 0
            }

            if measuredSegment.width > containerWidth,
               !segment.isBreakOpportunity,
               (allowsOverwideFallback || !measuredSegment.units.isEmpty) {
                let split = splitOverwideSegment(
                    measuredSegment,
                    containerWidth: containerWidth,
                    currentStart: currentStart,
                    currentWidth: currentWidth,
                    fontSize: measured.fontSize
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
        currentWidth: Double,
        fontSize: Double
    ) -> (closedLines: [InlineLineRange], currentStart: Int, currentWidth: Double) {
        var lines: [InlineLineRange] = []
        var lineStart = currentStart
        var width = currentWidth
        let units = measuredSegment.units.isEmpty
            ? measuredUnits(for: measuredSegment.segment, fontSize: fontSize)
            : measuredSegment.units

        for unit in units {
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

public struct InlineLayoutEngine<Measurer: InlineMeasuring>: Sendable {
    public var walker: VariableWidthLineWalker<Measurer>
    public let diagnosticsRecorder: MarkdownDiagnosticsRecorder

    private var preparedCache: BoundedMarkdownCache<PreparedInlineContent>
    private var measuredCache: BoundedMarkdownCache<MeasuredInlineContent>
    private var layoutCache: BoundedMarkdownCache<InlineLayoutResult>
    private let overwideUnitCache: OverwideUnitCache

    public init(
        measurer: Measurer,
        cacheCapacity: Int = 256,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.walker = VariableWidthLineWalker(measurer: measurer)
        self.diagnosticsRecorder = diagnosticsRecorder
        self.preparedCache = BoundedMarkdownCache(capacity: cacheCapacity)
        self.measuredCache = BoundedMarkdownCache(capacity: cacheCapacity)
        self.layoutCache = BoundedMarkdownCache(capacity: cacheCapacity)
        self.overwideUnitCache = OverwideUnitCache(capacity: cacheCapacity)
    }

    public var diagnosticsCounters: MarkdownDiagnosticsCounters {
        diagnosticsRecorder.snapshot()
    }

    public mutating func prepare(
        runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange? = nil
    ) -> PreparedInlineContent {
        let key = inlineCacheKey(
            runs: runs,
            sourceRange: sourceRange,
            namespace: "prepared-inline"
        )

        if let cached = preparedCache.value(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        diagnosticsRecorder.recordCacheMiss()
        let prepared = PreparedInlineContent(runs: runs, sourceRange: sourceRange)
        preparedCache[key] = prepared
        return prepared
    }

    public mutating func prepareMeasuredContent(
        runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange? = nil,
        fontSize: Double = 14
    ) -> MeasuredInlineContent {
        let prepared = prepare(runs: runs, sourceRange: sourceRange)
        return prepareMeasuredContent(prepared, fontSize: fontSize)
    }

    public mutating func prepareMeasuredContent(
        _ prepared: PreparedInlineContent,
        fontSize: Double = 14
    ) -> MeasuredInlineContent {
        let key = measuredCacheKey(for: prepared, fontSize: fontSize)

        if let cached = measuredCache.value(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        diagnosticsRecorder.recordCacheMiss()
        diagnosticsRecorder.recordPrepare()
        let measured = MarkdownDiagnostics().signpost("InlinePrepare", category: "InlineLayout") {
            walker.prepare(prepared, fontSize: fontSize)
        }
        measuredCache[key] = measured
        return measured
    }

    public mutating func layout(
        runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange? = nil,
        options: InlineLayoutOptions
    ) -> InlineLayoutResult {
        layout(
            runs: runs,
            sourceRange: sourceRange,
            options: options,
            allowsOverwideFallback: true
        )
    }

    public mutating func layout(
        runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange? = nil,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool
    ) -> InlineLayoutResult {
        let measured = prepareMeasuredContent(
            runs: runs,
            sourceRange: sourceRange,
            fontSize: options.fontSize
        )
        return layout(measured, options: options, allowsOverwideFallback: allowsOverwideFallback)
    }

    public mutating func layout(
        _ prepared: PreparedInlineContent,
        options: InlineLayoutOptions
    ) -> InlineLayoutResult {
        layout(
            prepared,
            options: options,
            allowsOverwideFallback: true
        )
    }

    public mutating func layout(
        _ prepared: PreparedInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool
    ) -> InlineLayoutResult {
        let measured = prepareMeasuredContent(prepared, fontSize: options.fontSize)
        return layout(measured, options: options, allowsOverwideFallback: allowsOverwideFallback)
    }

    public mutating func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions
    ) -> InlineLayoutResult {
        layout(
            measured,
            options: options,
            allowsOverwideFallback: true
        )
    }

    public mutating func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool
    ) -> InlineLayoutResult {
        let key = layoutCacheKey(
            for: measured,
            options: options,
            allowsOverwideFallback: allowsOverwideFallback
        )

        if let cached = layoutCache.value(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        diagnosticsRecorder.recordCacheMiss()
        diagnosticsRecorder.recordWidthRelayout()
        diagnosticsRecorder.recordLayout()
        let measuredForLayout = allowsOverwideFallback
            ? measuredWithCachedOverwideUnits(measured, containerWidth: options.containerWidth)
            : measured
        let result = MarkdownDiagnostics().signpost("InlineLayout", category: "InlineLayout") {
            walker.layout(
                measuredForLayout,
                options: options,
                allowsOverwideFallback: allowsOverwideFallback
            )
        }
        layoutCache[key] = result
        return result
    }

    private mutating func measuredWithCachedOverwideUnits(
        _ measured: MeasuredInlineContent,
        containerWidth: Double
    ) -> MeasuredInlineContent {
        var updated = measured
        for index in updated.segments.indices {
            let measuredSegment = updated.segments[index]
            guard measuredSegment.units.isEmpty,
                  !measuredSegment.segment.isBreakOpportunity,
                  measuredSegment.width > containerWidth
            else {
                continue
            }

            let key = overwideUnitCacheKey(for: measuredSegment, fontSize: measured.fontSize)
            if let cached = overwideUnitCache.value(forKey: key) {
                diagnosticsRecorder.recordCacheHit()
                updated.segments[index].units = cached
                continue
            }

            diagnosticsRecorder.recordCacheMiss()
            diagnosticsRecorder.recordOverwideUnitFallback()
            let units = measuredUnits(for: measuredSegment.segment, fontSize: measured.fontSize)
            overwideUnitCache.insert(units, forKey: key)
            updated.segments[index].units = units
        }
        return updated
    }

    private func inlineCacheKey(
        runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange?,
        namespace: String
    ) -> MarkdownCacheKey {
        let byteCount = runs.reduce(0) { $0 + $1.text.utf8.count + ($1.destination?.utf8.count ?? 0) }
        let range = sourceRange ?? MarkdownSourceRange(byteRange: 0..<byteCount, lineRange: 1..<2)
        return MarkdownCacheKey(
            sourceRange: range,
            contentHash: inlineContentHash(runs),
            namespace: namespace
        )
    }

    private func measuredCacheKey(
        for prepared: PreparedInlineContent,
        fontSize: Double
    ) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: prepared.sourceRange ?? MarkdownSourceRange(
                byteRange: 0..<prepared.naturalText.utf8.count,
                lineRange: 1..<2
            ),
            contentHash: preparedContentHash(prepared, salt: "font:\(fontSize)"),
            namespace: "measured-inline"
        )
    }

    private func layoutCacheKey(
        for measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool
    ) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: measured.prepared.sourceRange ?? MarkdownSourceRange(
                byteRange: 0..<measured.prepared.naturalText.utf8.count,
                lineRange: 1..<2
            ),
            contentHash: preparedContentHash(
                measured.prepared,
                salt: "font:\(options.fontSize)|width:\(options.containerWidth)|line:\(options.lineHeight)|overwide:\(allowsOverwideFallback)"
            ),
            namespace: "inline-layout"
        )
    }

    private func overwideUnitCacheKey(
        for measuredSegment: MeasuredInlineSegment,
        fontSize: Double
    ) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: MarkdownSourceRange(
                byteRange: measuredSegment.segment.byteRange,
                lineRange: 1..<2
            ),
            contentHash: preparedSegmentHash(measuredSegment.segment, salt: "font:\(fontSize)"),
            namespace: "overwide-inline-units"
        )
    }

    private func inlineContentHash(_ runs: [MarkdownInlineRun]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for run in runs {
            hash = append(run.kind.rawValue, to: hash)
            hash = append(run.text, to: hash)
            if let destination = run.destination {
                hash = append(destination, to: hash)
            }
        }
        return hash
    }

    private func preparedContentHash(_ prepared: PreparedInlineContent, salt: String) -> UInt64 {
        var hash = append(salt, to: 0xcbf29ce484222325)
        for segment in prepared.segments {
            hash = preparedSegmentHash(segment, initialHash: hash)
        }
        return hash
    }

    private func preparedSegmentHash(_ segment: PreparedInlineSegment, salt: String) -> UInt64 {
        preparedSegmentHash(segment, initialHash: append(salt, to: 0xcbf29ce484222325))
    }

    private func preparedSegmentHash(_ segment: PreparedInlineSegment, initialHash: UInt64) -> UInt64 {
        var hash = initialHash
        hash = append(segment.kind.rawValue, to: hash)
        hash = append(segment.text, to: hash)
        hash = append("\(segment.byteRange.lowerBound)..<\(segment.byteRange.upperBound)", to: hash)
        hash = append(segment.isHardBreak ? "hard" : "soft", to: hash)
        hash = append(segment.isBreakOpportunity ? "break" : "nobreak", to: hash)
        return hash
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
                    width: walker.measurer.width(of: characterText, fontSize: fontSize)
                )
            )
            cursor = upper
        }

        return units
    }

    private func append(_ text: String, to initialHash: UInt64) -> UInt64 {
        var hash = initialHash
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

private final class OverwideUnitCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MarkdownCacheKey: [MeasuredInlineUnit]] = [:]
    private var order: [MarkdownCacheKey] = []
    private let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func value(forKey key: MarkdownCacheKey) -> [MeasuredInlineUnit]? {
        lock.withLock {
            guard let value = storage[key] else {
                return nil
            }

            removeKeyFromOrder(key)
            order.append(key)
            return value
        }
    }

    func insert(_ value: [MeasuredInlineUnit], forKey key: MarkdownCacheKey) {
        lock.withLock {
            removeKeyFromOrder(key)
            order.append(key)
            storage[key] = value

            while order.count > capacity, let oldest = order.first {
                order.removeFirst()
                storage.removeValue(forKey: oldest)
            }
        }
    }

    private func removeKeyFromOrder(_ key: MarkdownCacheKey) {
        guard !order.isEmpty else {
            return
        }

        var compacted: [MarkdownCacheKey] = []
        compacted.reserveCapacity(order.count)
        for existing in order where existing != key {
            compacted.append(existing)
        }
        order = compacted
    }
}

public extension InlineLayoutEngine where Measurer == CoreTextInlineMeasurer {
    init(
        cacheCapacity: Int = 256,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.init(
            measurer: CoreTextInlineMeasurer(),
            cacheCapacity: cacheCapacity,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }
}
