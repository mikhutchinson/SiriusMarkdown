import Foundation

#if canImport(CoreText)
import CoreText
#endif

public struct PreparedInlineContent: Sendable, Hashable {
    public var runs: [MarkdownInlineRun] {
        didSet { refreshCacheFingerprint() }
    }
    public var segments: [PreparedInlineSegment] {
        didSet { refreshCacheFingerprint() }
    }
    public var sourceRange: MarkdownSourceRange? {
        didSet { refreshCacheFingerprint() }
    }
    public var naturalText: String {
        didSet { refreshCacheFingerprint() }
    }
    /// Cached because UTF-8 length is otherwise a linear String traversal at
    /// nil-source-range cache-key and selection-mapping call sites.
    public private(set) var naturalTextUTF8Count: Int = 0
    /// Precomputed identity for cache lookup and view invalidation. Building
    /// it is intentionally paid when prepared content is created or mutated,
    /// never from a SwiftUI layout/selection cache hit.
    public private(set) var cacheFingerprint = MarkdownContentFingerprint(
        domain: "prepared-inline-empty"
    )
    /// Measurement/layout-only identity. Link destinations and caller-owned
    /// source metadata must still rebind on a measured-cache hit, but they do
    /// not change glyph widths or line breaks.
    public private(set) var layoutCacheFingerprint = MarkdownContentFingerprint(
        domain: "prepared-inline-layout-empty"
    )

    public init(runs: [MarkdownInlineRun], sourceRange: MarkdownSourceRange? = nil) {
        self.runs = runs
        self.segments = PreparedInlineSegment.prepare(from: runs)
        self.sourceRange = sourceRange
        self.naturalText = segments.map(\.text).joined()
        refreshCacheFingerprint()
    }

    private mutating func refreshCacheFingerprint() {
        naturalTextUTF8Count = naturalText.utf8.count
        cacheFingerprint = preparedInlineContentFingerprint(
            runs: runs,
            segments: segments,
            sourceRange: sourceRange,
            naturalText: naturalText
        )
        layoutCacheFingerprint = preparedInlineLayoutFingerprint(segments: segments)
    }
}

public struct PreparedInlineSegment: Sendable, Hashable {
    public var kind: MarkdownInlineKind {
        didSet { refreshCacheFingerprint() }
    }
    public var presentation: MarkdownInlinePresentation {
        didSet { refreshCacheFingerprint() }
    }
    public var text: String {
        didSet { refreshCacheFingerprint() }
    }
    public var byteRange: Range<Int> {
        didSet { refreshCacheFingerprint() }
    }
    public var isHardBreak: Bool {
        didSet { refreshCacheFingerprint() }
    }
    public var isBreakOpportunity: Bool {
        didSet { refreshCacheFingerprint() }
    }
    /// Reserved box metrics for an allowed attachment segment (Inline
    /// Attachments Part 01). When non-nil, measurement must use
    /// `attachmentMetrics.pointWidth` instead of measuring `text`.
    public var attachmentMetrics: MarkdownInlineAttachmentMetrics? {
        didSet { refreshCacheFingerprint() }
    }
    public private(set) var cacheFingerprint = MarkdownContentFingerprint(
        domain: "prepared-inline-segment-empty"
    )

    public init(
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation? = nil,
        text: String,
        byteRange: Range<Int>,
        isHardBreak: Bool = false,
        isBreakOpportunity: Bool = false,
        attachmentMetrics: MarkdownInlineAttachmentMetrics? = nil
    ) {
        self.kind = kind
        self.presentation = presentation ?? MarkdownInlinePresentation.defaultPresentation(for: kind)
        self.text = text
        self.byteRange = byteRange
        self.isHardBreak = isHardBreak
        self.isBreakOpportunity = isBreakOpportunity
        self.attachmentMetrics = attachmentMetrics
        refreshCacheFingerprint()
    }

    private mutating func refreshCacheFingerprint() {
        cacheFingerprint = preparedInlineSegmentFingerprint(
            kind: kind,
            presentation: presentation,
            text: text,
            byteRange: byteRange,
            isHardBreak: isHardBreak,
            isBreakOpportunity: isBreakOpportunity,
            attachmentMetrics: attachmentMetrics
        )
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
                        isBreakOpportunity: false,
                        attachmentMetrics: run.attachmentMetrics
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
    public var prepared: PreparedInlineContent {
        didSet { refreshCacheFingerprint() }
    }
    public var segments: [MeasuredInlineSegment] {
        didSet { refreshCacheFingerprint() }
    }
    public var naturalWidth: Double {
        didSet { refreshCacheFingerprint() }
    }
    public var fontSize: Double {
        didSet { refreshCacheFingerprint() }
    }
    /// Precomputed identity of every input that can change line layout.
    public private(set) var cacheFingerprint = MarkdownContentFingerprint(
        domain: "measured-inline-empty"
    )

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
        refreshCacheFingerprint()
    }

    private mutating func refreshCacheFingerprint() {
        cacheFingerprint = measuredInlineContentFingerprint(
            prepared: prepared,
            segments: segments,
            naturalWidth: naturalWidth,
            fontSize: fontSize
        )
    }
}

public struct InlineLayoutResult: Sendable, Hashable {
    public var lines: [InlineLineRange] {
        didSet { refreshCacheFingerprint() }
    }
    public var naturalWidth: Double {
        didSet { refreshCacheFingerprint() }
    }
    public var height: Double {
        didSet { refreshCacheFingerprint() }
    }
    /// Precomputed line-layout identity used by selection caches.
    public private(set) var cacheFingerprint = MarkdownContentFingerprint(
        domain: "inline-layout-result-empty"
    )

    public init(lines: [InlineLineRange], naturalWidth: Double, height: Double) {
        self.lines = lines
        self.naturalWidth = naturalWidth
        self.height = height
        refreshCacheFingerprint()
    }

    private mutating func refreshCacheFingerprint() {
        cacheFingerprint = inlineLayoutResultFingerprint(
            lines: lines,
            naturalWidth: naturalWidth,
            height: height
        )
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

private func preparedInlineContentFingerprint(
    runs: [MarkdownInlineRun],
    segments: [PreparedInlineSegment],
    sourceRange: MarkdownSourceRange?,
    naturalText: String
) -> MarkdownContentFingerprint {
    var fingerprint = MarkdownContentFingerprint(domain: "prepared-inline-content-v1")
    combine(sourceRange, into: &fingerprint)
    fingerprint.combine(runs.count)
    for run in runs {
        combine(run, into: &fingerprint)
    }
    fingerprint.combine(segments.count)
    for segment in segments {
        fingerprint.combine(segment.cacheFingerprint)
    }
    // `naturalText` is derived in package-owned construction, but it remains
    // publicly mutable for source compatibility. Include it so a caller's
    // direct mutation cannot leave a stale cache identity.
    fingerprint.combine(naturalText)
    return fingerprint
}

private func preparedInlineSegmentFingerprint(
    kind: MarkdownInlineKind,
    presentation: MarkdownInlinePresentation,
    text: String,
    byteRange: Range<Int>,
    isHardBreak: Bool,
    isBreakOpportunity: Bool,
    attachmentMetrics: MarkdownInlineAttachmentMetrics?
) -> MarkdownContentFingerprint {
    var fingerprint = MarkdownContentFingerprint(domain: "prepared-inline-segment-v1")
    fingerprint.combine(kind.rawValue)
    fingerprint.combine(presentation.rawValue)
    fingerprint.combine(text)
    combine(byteRange, into: &fingerprint)
    fingerprint.combine(isHardBreak)
    fingerprint.combine(isBreakOpportunity)
    combine(attachmentMetrics, into: &fingerprint)
    return fingerprint
}

private func preparedInlineLayoutFingerprint(
    segments: [PreparedInlineSegment]
) -> MarkdownContentFingerprint {
    var fingerprint = MarkdownContentFingerprint(domain: "prepared-inline-layout-v1")
    fingerprint.combine(segments.count)
    for segment in segments {
        fingerprint.combine(segment.cacheFingerprint)
    }
    return fingerprint
}

private func measuredInlineContentFingerprint(
    prepared: PreparedInlineContent,
    segments: [MeasuredInlineSegment],
    naturalWidth: Double,
    fontSize: Double
) -> MarkdownContentFingerprint {
    var fingerprint = MarkdownContentFingerprint(domain: "measured-inline-content-v1")
    fingerprint.combine(prepared.layoutCacheFingerprint)
    fingerprint.combine(segments.count)
    for measuredSegment in segments {
        fingerprint.combine(measuredSegment.segment.cacheFingerprint)
        fingerprint.combine(measuredSegment.width)
        fingerprint.combine(measuredSegment.units.count)
        for unit in measuredSegment.units {
            combine(unit.byteRange, into: &fingerprint)
            fingerprint.combine(unit.width)
            fingerprint.combine(unit.startsPreferredBreakUnit)
        }
    }
    fingerprint.combine(naturalWidth)
    fingerprint.combine(fontSize)
    return fingerprint
}

private func inlineLayoutResultFingerprint(
    lines: [InlineLineRange],
    naturalWidth: Double,
    height: Double
) -> MarkdownContentFingerprint {
    var fingerprint = MarkdownContentFingerprint(domain: "inline-layout-result-v1")
    fingerprint.combine(lines.count)
    for line in lines {
        combine(line.byteRange, into: &fingerprint)
        combine(line.consumedByteRange, into: &fingerprint)
        fingerprint.combine(line.width)
    }
    fingerprint.combine(naturalWidth)
    fingerprint.combine(height)
    return fingerprint
}

private func combine(
    _ run: MarkdownInlineRun,
    into fingerprint: inout MarkdownContentFingerprint
) {
    fingerprint.combine(run.kind.rawValue)
    fingerprint.combine(run.presentation.rawValue)
    fingerprint.combine(run.text)
    combine(run.sourceRange, into: &fingerprint)
    combine(run.destination, into: &fingerprint)
    combine(run.imageSource, into: &fingerprint)
    combine(run.attachmentMetrics, into: &fingerprint)
}

private func combine(
    _ sourceRange: MarkdownSourceRange?,
    into fingerprint: inout MarkdownContentFingerprint
) {
    guard let sourceRange else {
        fingerprint.combine(false)
        return
    }
    fingerprint.combine(true)
    combine(sourceRange.byteRange, into: &fingerprint)
    combine(sourceRange.lineRange, into: &fingerprint)
}

private func combine(
    _ range: Range<Int>,
    into fingerprint: inout MarkdownContentFingerprint
) {
    fingerprint.combine(range.lowerBound)
    fingerprint.combine(range.upperBound)
}

private func combine(
    _ value: String?,
    into fingerprint: inout MarkdownContentFingerprint
) {
    guard let value else {
        fingerprint.combine(false)
        return
    }
    fingerprint.combine(true)
    fingerprint.combine(value)
}

private func combine(
    _ metrics: MarkdownInlineAttachmentMetrics?,
    into fingerprint: inout MarkdownContentFingerprint
) {
    guard let metrics else {
        fingerprint.combine(false)
        return
    }
    fingerprint.combine(true)
    fingerprint.combine(metrics.id.rawValue)
    fingerprint.combine(metrics.pointWidth)
    fingerprint.combine(metrics.pointHeight)
    fingerprint.combine(metrics.ascent)
    fingerprint.combine(metrics.descent)
    switch metrics.sizingSource {
    case .themeDefault:
        fingerprint.combine(0)
    case .aspectPlaceholder:
        fingerprint.combine(1)
    case .intrinsicHint:
        fingerprint.combine(2)
    case .decoded:
        fingerprint.combine(3)
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
        if let attachmentMetrics = segment.attachmentMetrics {
            return attachmentMetrics.pointWidth
        }

        return width(of: segment.text, fontSize: fontSize)
    }
}

public typealias TextMeasurer = InlineMeasuring

public enum MarkdownMissingGlyphMeasurement: String, Sendable, Hashable {
    /// Shape with CoreText's real cascade list so preparation matches the
    /// glyphs the native paint path will draw.
    case nativeFallbackShaping
    /// Use the selected base font's missing-glyph advance for unsupported
    /// scalars, matching Pretext's canvas oracle fixtures.
    case pretextBaseFontAdvances
}

struct MarkdownCoreTextFontKey: Sendable, Hashable {
    var profile: MarkdownFontProfile
    var fontSizeBits: UInt64
    var kind: MarkdownInlineKind
    var presentation: MarkdownInlinePresentation
}

private struct MarkdownCoreTextWidthKey: Sendable, Hashable {
    var font: MarkdownCoreTextFontKey
    var missingGlyphMeasurement: MarkdownMissingGlyphMeasurement
    var text: String
}

/// A bounded, thread-safe cache shared by the prepared inline content in one
/// render session.
///
/// Streaming reparses one mutable tail. That tail frequently contains all of
/// the text seen by its previous generation, especially for an open code
/// fence. Recreating an equivalent CoreText font and reshaping every unchanged
/// token makes cumulative preparation quadratic even though the sealed
/// document is already incremental. This cache gives those unchanged tokens a
/// constant-time reuse path while keeping the cache key sensitive to every
/// input that can change glyph advances.
public final class MarkdownCoreTextMeasurementCache: @unchecked Sendable {
    public struct Statistics: Sendable, Hashable {
        public var widthHitCount: UInt64
        public var widthMissCount: UInt64
        public var cachedWidthCount: Int
        public var cachedFontCount: Int
    }

    private let lock = NSLock()
    private let widthCapacity: Int
    private let fontCapacity: Int
    private var widths: [MarkdownCoreTextWidthKey: Double] = [:]
    #if canImport(CoreText)
    private var fonts: [MarkdownCoreTextFontKey: CTFont] = [:]
    #endif
    private var widthHitCount: UInt64 = 0
    private var widthMissCount: UInt64 = 0

    public init(widthCapacity: Int = 16_384, fontCapacity: Int = 64) {
        self.widthCapacity = max(1, widthCapacity)
        self.fontCapacity = max(1, fontCapacity)
    }

    func width(
        of text: String,
        fontKey: MarkdownCoreTextFontKey,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement
    ) -> Double? {
        let key = MarkdownCoreTextWidthKey(
            font: fontKey,
            missingGlyphMeasurement: missingGlyphMeasurement,
            text: text
        )
        return lock.withLock {
            guard let width = widths[key] else {
                widthMissCount &+= 1
                return nil
            }
            widthHitCount &+= 1
            return width
        }
    }

    func insertWidth(
        _ width: Double,
        of text: String,
        fontKey: MarkdownCoreTextFontKey,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement
    ) {
        let key = MarkdownCoreTextWidthKey(
            font: fontKey,
            missingGlyphMeasurement: missingGlyphMeasurement,
            text: text
        )
        lock.withLock {
            if widths[key] == nil, widths.count >= widthCapacity {
                evictQuarter(from: &widths, capacity: widthCapacity)
            }
            widths[key] = width
        }
    }

    #if canImport(CoreText)
    func font(for key: MarkdownCoreTextFontKey, make: () -> CTFont) -> CTFont {
        if let cached = lock.withLock({ fonts[key] }) {
            return cached
        }

        let created = make()
        return lock.withLock {
            if let raced = fonts[key] {
                return raced
            }
            if fonts.count >= fontCapacity {
                evictQuarter(from: &fonts, capacity: fontCapacity)
            }
            fonts[key] = created
            return created
        }
    }
    #endif

    public var statistics: Statistics {
        lock.withLock {
            Statistics(
                widthHitCount: widthHitCount,
                widthMissCount: widthMissCount,
                cachedWidthCount: widths.count,
                cachedFontCount: cachedFontCount
            )
        }
    }

    public func removeAll() {
        lock.withLock {
            widths.removeAll(keepingCapacity: true)
            #if canImport(CoreText)
            fonts.removeAll(keepingCapacity: true)
            #endif
            widthHitCount = 0
            widthMissCount = 0
        }
    }

    private var cachedFontCount: Int {
        #if canImport(CoreText)
        fonts.count
        #else
        0
        #endif
    }

    private func evictQuarter<Key: Hashable, Value>(
        from storage: inout [Key: Value],
        capacity: Int
    ) {
        let victims = Array(storage.keys.prefix(max(1, capacity / 4)))
        for key in victims {
            storage.removeValue(forKey: key)
        }
    }
}

public struct CoreTextInlineMeasurer: InlineMeasuring {
    public var profiles: MarkdownInlineFontProfiles
    public var missingGlyphMeasurement: MarkdownMissingGlyphMeasurement
    private let measurementCache: MarkdownCoreTextMeasurementCache

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
        "coretext:\(profiles.cacheKey):missing:\(missingGlyphMeasurement.rawValue)"
    }

    public init() {
        self.init(measurementCache: MarkdownCoreTextMeasurementCache())
    }

    public init(measurementCache: MarkdownCoreTextMeasurementCache) {
        self.profiles = MarkdownInlineFontProfiles()
        self.missingGlyphMeasurement = .nativeFallbackShaping
        self.measurementCache = measurementCache
    }

    public init(
        fontName: String,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement = .nativeFallbackShaping
    ) {
        self.init(
            fontName: fontName,
            missingGlyphMeasurement: missingGlyphMeasurement,
            measurementCache: MarkdownCoreTextMeasurementCache()
        )
    }

    public init(
        fontName: String,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement = .nativeFallbackShaping,
        measurementCache: MarkdownCoreTextMeasurementCache
    ) {
        self.profiles = MarkdownInlineFontProfiles(uniform: .named(fontName))
        self.missingGlyphMeasurement = missingGlyphMeasurement
        self.measurementCache = measurementCache
    }

    public init(
        profiles: MarkdownInlineFontProfiles,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement = .nativeFallbackShaping
    ) {
        self.init(
            profiles: profiles,
            missingGlyphMeasurement: missingGlyphMeasurement,
            measurementCache: MarkdownCoreTextMeasurementCache()
        )
    }

    public init(
        profiles: MarkdownInlineFontProfiles,
        missingGlyphMeasurement: MarkdownMissingGlyphMeasurement = .nativeFallbackShaping,
        measurementCache: MarkdownCoreTextMeasurementCache
    ) {
        self.profiles = profiles
        self.missingGlyphMeasurement = missingGlyphMeasurement
        self.measurementCache = measurementCache
    }

    public func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        if let attachmentMetrics = segment.attachmentMetrics {
            return attachmentMetrics.pointWidth
        }

        return width(
            of: segment.text,
            fontSize: Self.inlineScriptFontSize(
                fontSize,
                presentation: segment.presentation
            ),
            profile: profiles.profile(for: segment.presentation, kind: segment.kind),
            kind: segment.kind,
            presentation: segment.presentation
        )
    }

    public func width(of text: String, fontSize: Double) -> Double {
        width(
            of: text,
            fontSize: fontSize,
            profile: profiles.body,
            kind: .text,
            presentation: []
        )
    }

    private func width(
        of text: String,
        fontSize: Double,
        profile: MarkdownFontProfile,
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation
    ) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        #if canImport(CoreText)
        let fontKey = MarkdownCoreTextFontKey(
            profile: profile,
            fontSizeBits: fontSize.bitPattern,
            kind: kind,
            presentation: presentation
        )
        if let cached = measurementCache.width(
            of: text,
            fontKey: fontKey,
            missingGlyphMeasurement: missingGlyphMeasurement
        ) {
            return cached
        }

        let font = measurementCache.font(for: fontKey) {
            makeFont(
                profile: profile,
                fontSize: fontSize,
                kind: kind,
                presentation: presentation
            )
        }
        let width: Double
        switch missingGlyphMeasurement {
        case .nativeFallbackShaping:
            width = shapedWidth(of: text, font: font)
        case .pretextBaseFontAdvances:
            if selectedFontCoversEveryScalar(in: text, font: font) {
                width = shapedWidth(of: text, font: font)
            } else {
                width = baseFontAdvanceWidth(of: text, font: font)
            }
        }
        measurementCache.insertWidth(
            width,
            of: text,
            fontKey: fontKey,
            missingGlyphMeasurement: missingGlyphMeasurement
        )
        return width
        #else
        return Double(text.count) * fontSize * 0.5
        #endif
    }

    private static func inlineScriptFontSize(
        _ fontSize: Double,
        presentation: MarkdownInlinePresentation
    ) -> Double {
        if presentation.contains(.subscriptText) || presentation.contains(.superscriptText) {
            return fontSize * 0.76
        }
        return fontSize
    }

    #if canImport(CoreText)
    private func makeFont(
        profile: MarkdownFontProfile,
        fontSize: Double,
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation
    ) -> CTFont {
        let semanticTraits = semanticTraits(kind: kind, presentation: presentation)
        switch profile {
        case let .named(name, weight):
            let base = CTFontCreateWithName(name as CFString, fontSize, nil)
            return apply(
                weight: weight,
                symbolicTraits: semanticTraits,
                to: base,
                fontSize: fontSize
            )
        case let .system(weight, design):
            let base = systemFont(design: design, fontSize: fontSize)
            return apply(
                weight: weight,
                symbolicTraits: fontSymbolicTraits(for: design).union(semanticTraits),
                to: base,
                fontSize: fontSize
            )
        case let .monospacedSystem(weight):
            let base = systemFont(design: .default, fontSize: fontSize)
            return apply(
                weight: weight,
                symbolicTraits: CTFontSymbolicTraits.traitMonoSpace.union(semanticTraits),
                to: base,
                fontSize: fontSize
            )
        }
    }

    private func apply(
        weight: MarkdownFontWeight,
        symbolicTraits: CTFontSymbolicTraits,
        to font: CTFont,
        fontSize: Double
    ) -> CTFont {
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

    private func semanticTraits(
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation
    ) -> CTFontSymbolicTraits {
        var traits: CTFontSymbolicTraits = []
        if kind == .emphasis || presentation.contains(.emphasis) {
            traits.insert(.traitItalic)
        }
        if kind == .code || kind == .math ||
            presentation.contains(.code) || presentation.contains(.math) {
            traits.insert(.traitMonoSpace)
        }
        return traits
    }

    private func fontSymbolicTraits(for design: MarkdownFontDesign) -> CTFontSymbolicTraits {
        switch design {
        case .monospaced:
            return .traitMonoSpace
        case .default, .serif, .rounded:
            return []
        }
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
               segment.attachmentMetrics == nil,
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

        if var cached = measuredCache.value(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            cached.prepared = prepared
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
        var updatedSegments = measured.segments
        var changed = false
        for index in updatedSegments.indices {
            let measuredSegment = updatedSegments[index]
            guard measuredSegment.units.isEmpty,
                  !measuredSegment.segment.isBreakOpportunity,
                  measuredSegment.segment.attachmentMetrics == nil,
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
                updatedSegments[index].units = cached
                changed = true
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
            updatedSegments[index].units = units
            changed = true
        }
        guard changed else {
            return measured
        }
        // Rebuild the measured fingerprint once after all fallback-unit
        // changes. Mutating `MeasuredInlineContent.segments[index]` directly
        // would trigger its source-compatible property observer once per
        // segment and turn a multi-segment fallback into O(n²) hashing.
        return MeasuredInlineContent(
            prepared: measured.prepared,
            segments: updatedSegments,
            naturalWidth: measured.naturalWidth,
            fontSize: measured.fontSize
        )
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
        var fingerprint = MarkdownContentFingerprint(domain: "prepared-inline-cache-v2")
        fingerprint.combine(runs.count)
        for run in runs {
            combine(run, into: &fingerprint)
        }
        return MarkdownCacheKey(
            sourceRange: range,
            contentFingerprint: fingerprint,
            namespace: namespace
        )
    }

    private func measuredCacheKey(
        for prepared: PreparedInlineContent,
        fontSize: Double
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "measured-inline-cache-v1")
        fingerprint.combine(prepared.layoutCacheFingerprint)
        fingerprint.combine(fontSize)
        fingerprint.combine(walker.measurer.measurementCacheKey)
        return MarkdownCacheKey(
            sourceRange: prepared.sourceRange ?? MarkdownSourceRange(
                byteRange: 0..<prepared.naturalTextUTF8Count,
                lineRange: 1..<2
            ),
            contentFingerprint: fingerprint,
            namespace: "measured-inline"
        )
    }

    private func layoutCacheKey(
        for measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "inline-layout-cache-v1")
        fingerprint.combine(measured.cacheFingerprint)
        fingerprint.combine(options.fontSize)
        fingerprint.combine(options.lineHeight)
        fingerprint.combine(options.containerWidth)
        fingerprint.combine(allowsOverwideFallback)
        fingerprint.combine(walker.measurer.measurementCacheKey)
        return MarkdownCacheKey(
            sourceRange: measured.prepared.sourceRange ?? MarkdownSourceRange(
                byteRange: 0..<measured.prepared.naturalTextUTF8Count,
                lineRange: 1..<2
            ),
            contentFingerprint: fingerprint,
            namespace: "inline-layout"
        )
    }

    private func overwideUnitCacheKey(
        for measuredSegment: MeasuredInlineSegment,
        fontSize: Double,
        containerWidth: Double
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "overwide-inline-units-v1")
        fingerprint.combine(measuredSegment.segment.cacheFingerprint)
        fingerprint.combine(fontSize)
        fingerprint.combine(containerWidth)
        fingerprint.combine(walker.measurer.measurementCacheKey)
        return MarkdownCacheKey(
            sourceRange: MarkdownSourceRange(
                byteRange: measuredSegment.segment.byteRange,
                lineRange: 1..<2
            ),
            contentFingerprint: fingerprint,
            namespace: "overwide-inline-units"
        )
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
