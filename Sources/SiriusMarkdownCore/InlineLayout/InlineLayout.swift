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
    public var presentation: MarkdownInlinePresentation
    public var text: String
    public var byteRange: Range<Int>
    public var isHardBreak: Bool
    public var isBreakOpportunity: Bool

    public init(
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation? = nil,
        text: String,
        byteRange: Range<Int>,
        isHardBreak: Bool = false,
        isBreakOpportunity: Bool = false
    ) {
        self.kind = kind
        self.presentation = presentation ?? MarkdownInlinePresentation.defaultPresentation(for: kind)
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
                        presentation: run.presentation,
                        text: run.text,
                        byteRange: cursor..<upper,
                        isHardBreak: true,
                        isBreakOpportunity: true
                    )
                )
                cursor = upper
                continue
            }

            if run.isAtomicInlineLayoutRun {
                let upper = cursor + run.text.utf8.count
                segments.append(
                    PreparedInlineSegment(
                        kind: run.kind,
                        presentation: run.presentation,
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
                        presentation: run.presentation,
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

private extension MarkdownInlineRun {
    var isAtomicInlineLayoutRun: Bool {
        kind == .code ||
            kind == .image ||
            kind == .math ||
            presentation.contains(.code) ||
            presentation.contains(.image) ||
            presentation.contains(.math)
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
    public var startsPreferredBreakUnit: Bool

    public init(
        byteRange: Range<Int>,
        width: Double,
        startsPreferredBreakUnit: Bool = false
    ) {
        self.byteRange = byteRange
        self.width = width
        self.startsPreferredBreakUnit = startsPreferredBreakUnit
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
    var measurementCacheKey: String { get }
    func width(of text: String, fontSize: Double) -> Double
    func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double
}

public extension InlineMeasuring {
    var measurementCacheKey: String {
        String(reflecting: Self.self)
    }

    func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        width(of: segment.text, fontSize: fontSize)
    }
}

public typealias TextMeasurer = InlineMeasuring

public struct CoreTextInlineMeasurer: InlineMeasuring {
    public var profiles: MarkdownInlineFontProfiles

    public var fontName: String {
        get {
            switch profiles.body {
            case let .named(name, _):
                return name
            default:
                return ".system"
            }
        }
        set {
            profiles = MarkdownInlineFontProfiles(uniform: .named(newValue))
        }
    }

    public var measurementCacheKey: String {
        "coretext:\(profiles.cacheKey)"
    }

    public init() {
        self.profiles = MarkdownInlineFontProfiles()
    }

    public init(fontName: String) {
        self.profiles = MarkdownInlineFontProfiles(uniform: .named(fontName))
    }

    public init(profiles: MarkdownInlineFontProfiles) {
        self.profiles = profiles
    }

    public func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        width(
            of: segment.text,
            fontSize: fontSize,
            profile: profiles.profile(for: segment.presentation, kind: segment.kind)
        )
    }

    public func width(of text: String, fontSize: Double) -> Double {
        width(of: text, fontSize: fontSize, profile: profiles.body)
    }

    private func width(of text: String, fontSize: Double, profile: MarkdownFontProfile) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        #if canImport(CoreText)
        let font = makeFont(profile: profile, fontSize: fontSize)
        if selectedFontCoversEveryScalar(in: text, font: font) {
            return shapedWidth(of: text, font: font)
        }

        return baseFontAdvanceWidth(of: text, font: font)
        #else
        return Double(text.count) * fontSize * 0.5
        #endif
    }

    #if canImport(CoreText)
    private func makeFont(profile: MarkdownFontProfile, fontSize: Double) -> CTFont {
        switch profile {
        case let .named(name, weight):
            let base = CTFontCreateWithName(name as CFString, fontSize, nil)
            return apply(weight: weight, to: base, fontSize: fontSize)
        case let .system(weight, design):
            let base = systemFont(design: design, fontSize: fontSize)
            return apply(weight: weight, design: design, to: base, fontSize: fontSize)
        case let .monospacedSystem(weight):
            let base = systemFont(design: .default, fontSize: fontSize)
            return apply(weight: weight, design: .monospaced, to: base, fontSize: fontSize)
        }
    }

    private func apply(
        weight: MarkdownFontWeight,
        design: MarkdownFontDesign = .default,
        to font: CTFont,
        fontSize: Double
    ) -> CTFont {
        let symbolicTraits: CTFontSymbolicTraits
        switch design {
        case .default, .serif, .rounded:
            symbolicTraits = []
        case .monospaced:
            symbolicTraits = .traitMonoSpace
        }

        var traits: [CFString: Any] = [:]
        if let weightValue = fontWeightValue(for: weight) {
            traits[kCTFontWeightTrait] = weightValue
        }

        let attributes: [CFString: Any] = [
            kCTFontTraitsAttribute: traits
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let weighted = CTFontCreateCopyWithAttributes(font, CGFloat(fontSize), nil, descriptor)
        guard symbolicTraits != [] else {
            return weighted
        }

        return CTFontCreateCopyWithSymbolicTraits(
            weighted,
            CGFloat(fontSize),
            nil,
            symbolicTraits,
            symbolicTraits
        ) ?? weighted
    }

    private func systemFont(design: MarkdownFontDesign, fontSize: Double) -> CTFont {
        switch design {
        case .serif:
            return CTFontCreateWithName("Times" as CFString, fontSize, nil)
        case .monospaced:
            return CTFontCreateUIFontForLanguage(.system, CGFloat(fontSize), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        case .default, .rounded:
            return CTFontCreateUIFontForLanguage(.system, CGFloat(fontSize), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        }
    }

    private func fontWeightValue(for weight: MarkdownFontWeight) -> CGFloat? {
        switch weight {
        case .regular:
            return nil
        case .medium:
            return 0.23
        case .semibold:
            return 0.3
        case .bold:
            return 0.4
        }
    }

    private func shapedWidth(of text: String, font: CTFont) -> Double {
        let attributed = CFAttributedStringCreate(
            nil,
            text as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )
        guard let attributed else {
            return 0
        }
        let line = CTLineCreateWithAttributedString(attributed)
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
        let fontSize = sanitizedPositive(fontSize, fallback: 14)
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

            let width = measuredWidth(of: segment, fontSize: fontSize)
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

        let containerWidth = options.containerWidth.isFinite
            ? max(0, options.containerWidth)
            : 0
        let lineHeight = sanitizedPositive(
            options.lineHeight,
            fallback: sanitizedPositive(measured.fontSize, fallback: 14)
        )
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
            height: Double(lines.count) * lineHeight
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
            ? measuredUnits(
                for: measuredSegment.segment,
                fontSize: fontSize,
                containerWidth: containerWidth
            )
            : measuredSegment.units

        for unit in units {
            if unit.startsPreferredBreakUnit, width > 0 {
                lines.append(InlineLineRange(byteRange: lineStart..<unit.byteRange.lowerBound, width: width))
                lineStart = unit.byteRange.lowerBound
                width = 0
            }

            if width > 0, width + unit.width > containerWidth {
                lines.append(InlineLineRange(byteRange: lineStart..<unit.byteRange.lowerBound, width: width))
                lineStart = unit.byteRange.lowerBound
                width = 0
            }

            width += unit.width
        }

        return (lines, lineStart, width)
    }

    private func measuredUnits(
        for segment: PreparedInlineSegment,
        fontSize: Double,
        containerWidth: Double? = nil
    ) -> [MeasuredInlineUnit] {
        guard !segment.isBreakOpportunity else {
            return []
        }

        if let containerWidth, containerWidth.isFinite, containerWidth > 0 {
            return measuredPreferredBreakUnits(
                for: segment,
                fontSize: fontSize,
                containerWidth: containerWidth
            )
        }

        return measuredGraphemeUnits(for: segment, fontSize: fontSize)
    }

    private func measuredPreferredBreakUnits(
        for segment: PreparedInlineSegment,
        fontSize: Double,
        containerWidth: Double
    ) -> [MeasuredInlineUnit] {
        preferredBreakPieces(for: segment).enumerated().flatMap { index, piece -> [MeasuredInlineUnit] in
            let pieceSegment = PreparedInlineSegment(
                kind: segment.kind,
                presentation: segment.presentation,
                text: piece.text,
                byteRange: piece.byteRange,
                isHardBreak: false,
                isBreakOpportunity: false
            )
            let width = measuredWidth(of: pieceSegment, fontSize: fontSize)
            guard width > containerWidth, piece.text.count > 1 else {
                return [
                    MeasuredInlineUnit(
                        byteRange: piece.byteRange,
                        width: width
                    )
                ]
            }
            var units = measuredGraphemeUnits(for: pieceSegment, fontSize: fontSize)
            if index > 0, !units.isEmpty {
                units[0].startsPreferredBreakUnit = true
            }
            return units
        }
    }

    private func measuredGraphemeUnits(for segment: PreparedInlineSegment, fontSize: Double) -> [MeasuredInlineUnit] {
        var units: [MeasuredInlineUnit] = []
        var cursor = segment.byteRange.lowerBound

        for character in segment.text {
            let characterText = String(character)
            let upper = cursor + characterText.utf8.count
            units.append(
                MeasuredInlineUnit(
                    byteRange: cursor..<upper,
                    width: measuredWidth(
                        of: PreparedInlineSegment(
                            kind: segment.kind,
                            presentation: segment.presentation,
                            text: characterText,
                            byteRange: cursor..<upper,
                            isHardBreak: false,
                            isBreakOpportunity: false
                        ),
                        fontSize: fontSize
                    )
                )
            )
            cursor = upper
        }

        return units
    }

    private func preferredBreakPieces(
        for segment: PreparedInlineSegment
    ) -> [(text: String, byteRange: Range<Int>)] {
        var pieces: [(String, Range<Int>)] = []
        var current = ""
        var currentStart: Int?
        var cursor = segment.byteRange.lowerBound

        func flush(upTo upper: Int) {
            guard let start = currentStart, !current.isEmpty else {
                return
            }
            pieces.append((current, start..<upper))
            current.removeAll(keepingCapacity: true)
            currentStart = nil
        }

        for character in segment.text {
            let characterText = String(character)
            let upper = cursor + characterText.utf8.count

            if character == "/" || character == "\\" {
                flush(upTo: cursor)
                pieces.append((characterText, cursor..<upper))
                cursor = upper
                continue
            }

            if currentStart == nil {
                currentStart = cursor
            }
            current.append(character)

            if character == "-" || character == "." || character == ":" {
                flush(upTo: upper)
            }

            cursor = upper
        }

        flush(upTo: cursor)
        return pieces.isEmpty ? [(segment.text, segment.byteRange)] : pieces
    }

    private func measuredWidth(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        let width = measurer.width(of: segment, fontSize: fontSize)
        guard width.isFinite, width > 0 else {
            return 0
        }
        return width
    }

    private func sanitizedPositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
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
        let containerWidth = sanitizedContainerWidth(options.containerWidth)
        let measuredForLayout = allowsOverwideFallback
            ? measuredWithCachedOverwideUnits(measured, containerWidth: containerWidth)
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

            let key = overwideUnitCacheKey(
                for: measuredSegment,
                fontSize: measured.fontSize,
                containerWidth: containerWidth
            )
            if let cached = overwideUnitCache.value(forKey: key) {
                diagnosticsRecorder.recordCacheHit()
                updated.segments[index].units = cached
                continue
            }

            diagnosticsRecorder.recordCacheMiss()
            diagnosticsRecorder.recordOverwideUnitFallback()
            let units = measuredUnits(
                for: measuredSegment.segment,
                fontSize: measured.fontSize,
                containerWidth: containerWidth
            )
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
        let byteCount = runs.reduce(0) {
            $0 + $1.text.utf8.count + ($1.destination?.utf8.count ?? 0) + ($1.imageSource?.utf8.count ?? 0)
        }
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
            contentHash: preparedContentHash(
                prepared,
                salt: "font:\(fontSize)|measurer:\(walker.measurer.measurementCacheKey)"
            ),
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
                salt: "font:\(options.fontSize)|line:\(options.lineHeight)|width:\(options.containerWidth)|overwide:\(allowsOverwideFallback)|measurer:\(walker.measurer.measurementCacheKey)"
            ),
            namespace: "inline-layout"
        )
    }

    private func overwideUnitCacheKey(
        for measuredSegment: MeasuredInlineSegment,
        fontSize: Double,
        containerWidth: Double
    ) -> MarkdownCacheKey {
        MarkdownCacheKey(
            sourceRange: MarkdownSourceRange(
                byteRange: measuredSegment.segment.byteRange,
                lineRange: 1..<2
            ),
            contentHash: preparedSegmentHash(
                measuredSegment.segment,
                salt: "font:\(fontSize)|width:\(containerWidth)|measurer:\(walker.measurer.measurementCacheKey)"
            ),
            namespace: "overwide-inline-units"
        )
    }

    private func inlineContentHash(_ runs: [MarkdownInlineRun]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for run in runs {
            hash = appendField("run", value: "start", to: hash)
            hash = appendField("kind", value: run.kind.rawValue, to: hash)
            hash = appendField("presentation", value: String(run.presentation.rawValue), to: hash)
            hash = appendField("text", value: run.text, to: hash)
            hash = appendOptionalField("destination", value: run.destination, to: hash)
            hash = appendOptionalField("imageSource", value: run.imageSource, to: hash)
            if let sourceRange = run.sourceRange {
                hash = appendField("source.present", value: "1", to: hash)
                hash = appendField("source.byte.lower", value: String(sourceRange.byteRange.lowerBound), to: hash)
                hash = appendField("source.byte.upper", value: String(sourceRange.byteRange.upperBound), to: hash)
                hash = appendField("source.line.lower", value: String(sourceRange.lineRange.lowerBound), to: hash)
                hash = appendField("source.line.upper", value: String(sourceRange.lineRange.upperBound), to: hash)
            } else {
                hash = appendField("source.present", value: "0", to: hash)
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
        hash = appendField("segment.kind", value: segment.kind.rawValue, to: hash)
        hash = appendField("segment.presentation", value: String(segment.presentation.rawValue), to: hash)
        hash = appendField("segment.text", value: segment.text, to: hash)
        hash = appendField("segment.byte.lower", value: String(segment.byteRange.lowerBound), to: hash)
        hash = appendField("segment.byte.upper", value: String(segment.byteRange.upperBound), to: hash)
        hash = appendField("segment.breakKind", value: segment.isHardBreak ? "hard" : "soft", to: hash)
        hash = appendField("segment.breakOpportunity", value: segment.isBreakOpportunity ? "break" : "nobreak", to: hash)
        return hash
    }

    private func measuredUnits(
        for segment: PreparedInlineSegment,
        fontSize: Double,
        containerWidth: Double? = nil
    ) -> [MeasuredInlineUnit] {
        guard !segment.isBreakOpportunity else {
            return []
        }

        if let containerWidth, containerWidth.isFinite, containerWidth > 0 {
            return measuredPreferredBreakUnits(
                for: segment,
                fontSize: fontSize,
                containerWidth: containerWidth
            )
        }

        return measuredGraphemeUnits(for: segment, fontSize: fontSize)
    }

    private func measuredPreferredBreakUnits(
        for segment: PreparedInlineSegment,
        fontSize: Double,
        containerWidth: Double
    ) -> [MeasuredInlineUnit] {
        preferredBreakPieces(for: segment).enumerated().flatMap { index, piece -> [MeasuredInlineUnit] in
            let pieceSegment = PreparedInlineSegment(
                kind: segment.kind,
                presentation: segment.presentation,
                text: piece.text,
                byteRange: piece.byteRange,
                isHardBreak: false,
                isBreakOpportunity: false
            )
            let width = measuredWidth(of: pieceSegment, fontSize: fontSize)
            guard width > containerWidth, piece.text.count > 1 else {
                return [
                    MeasuredInlineUnit(
                        byteRange: piece.byteRange,
                        width: width
                    )
                ]
            }
            var units = measuredGraphemeUnits(for: pieceSegment, fontSize: fontSize)
            if index > 0, !units.isEmpty {
                units[0].startsPreferredBreakUnit = true
            }
            return units
        }
    }

    private func measuredGraphemeUnits(for segment: PreparedInlineSegment, fontSize: Double) -> [MeasuredInlineUnit] {
        var units: [MeasuredInlineUnit] = []
        var cursor = segment.byteRange.lowerBound

        for character in segment.text {
            let characterText = String(character)
            let upper = cursor + characterText.utf8.count
            let characterSegment = PreparedInlineSegment(
                kind: segment.kind,
                presentation: segment.presentation,
                text: characterText,
                byteRange: cursor..<upper,
                isHardBreak: false,
                isBreakOpportunity: false
            )
            units.append(
                MeasuredInlineUnit(
                    byteRange: cursor..<upper,
                    width: measuredWidth(of: characterSegment, fontSize: fontSize)
                )
            )
            cursor = upper
        }

        return units
    }

    private func measuredWidth(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        let width = walker.measurer.width(of: segment, fontSize: fontSize)
        guard width.isFinite, width > 0 else {
            return 0
        }
        return width
    }

    private func sanitizedContainerWidth(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private func preferredBreakPieces(
        for segment: PreparedInlineSegment
    ) -> [(text: String, byteRange: Range<Int>)] {
        var pieces: [(String, Range<Int>)] = []
        var current = ""
        var currentStart: Int?
        var cursor = segment.byteRange.lowerBound

        func flush(upTo upper: Int) {
            guard let start = currentStart, !current.isEmpty else {
                return
            }
            pieces.append((current, start..<upper))
            current.removeAll(keepingCapacity: true)
            currentStart = nil
        }

        for character in segment.text {
            let characterText = String(character)
            let upper = cursor + characterText.utf8.count

            if character == "/" || character == "\\" {
                flush(upTo: cursor)
                pieces.append((characterText, cursor..<upper))
                cursor = upper
                continue
            }

            if currentStart == nil {
                currentStart = cursor
            }
            current.append(character)

            if character == "-" || character == "." || character == ":" {
                flush(upTo: upper)
            }

            cursor = upper
        }

        flush(upTo: cursor)
        return pieces.isEmpty ? [(segment.text, segment.byteRange)] : pieces
    }

    private func append(_ text: String, to initialHash: UInt64) -> UInt64 {
        var hash = initialHash
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private func appendOptionalField(_ name: String, value: String?, to initialHash: UInt64) -> UInt64 {
        var hash = appendField("\(name).present", value: value == nil ? "0" : "1", to: initialHash)
        if let value {
            hash = appendField("\(name).value", value: value, to: hash)
        }
        return hash
    }

    private func appendField(_ name: String, value: String, to initialHash: UInt64) -> UInt64 {
        var hash = append(name, to: initialHash)
        hash = append("#\(value.utf8.count):", to: hash)
        hash = append(value, to: hash)
        hash = append("|", to: hash)
        return hash
    }
}

private final class OverwideUnitCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MarkdownCacheKey: [MeasuredInlineUnit]] = [:]
    private var order: [MarkdownCacheKey] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func value(forKey key: MarkdownCacheKey) -> [MeasuredInlineUnit]? {
        withLock {
            guard let value = storage[key] else {
                return nil
            }

            removeKeyFromOrder(key)
            order.append(key)
            return value
        }
    }

    func insert(_ value: [MeasuredInlineUnit], forKey key: MarkdownCacheKey) {
        withLock {
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
