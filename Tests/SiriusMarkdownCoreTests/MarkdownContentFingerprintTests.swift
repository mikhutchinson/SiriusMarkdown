import Testing
@testable import SiriusMarkdownCore

@Test
func contentFingerprintIsDeterministicAndLengthDelimited() {
    var first = MarkdownContentFingerprint(domain: "test-domain")
    first.combine("ab")
    first.combine("c")
    first.combine(42)

    var identical = MarkdownContentFingerprint(domain: "test-domain")
    identical.combine("ab")
    identical.combine("c")
    identical.combine(42)

    var differentBoundary = MarkdownContentFingerprint(domain: "test-domain")
    differentBoundary.combine("a")
    differentBoundary.combine("bc")
    differentBoundary.combine(42)

    var differentDomain = MarkdownContentFingerprint(domain: "other-domain")
    differentDomain.combine("ab")
    differentDomain.combine("c")
    differentDomain.combine(42)

    #expect(first == identical)
    #expect(first != differentBoundary)
    #expect(first != differentDomain)
    #expect(first.low != first.high)
}

@Test
func cacheKeyUsesBothFingerprintLanes() {
    let range = MarkdownSourceRange(byteRange: 0..<4, lineRange: 1..<2)
    let first = MarkdownCacheKey(
        sourceRange: range,
        contentFingerprint: MarkdownContentFingerprint(low: 7, high: 11),
        namespace: "fingerprint-test"
    )
    let differentHighLane = MarkdownCacheKey(
        sourceRange: range,
        contentFingerprint: MarkdownContentFingerprint(low: 7, high: 12),
        namespace: "fingerprint-test"
    )

    #expect(first.contentHash == 7)
    #expect(first.contentHashHigh == 11)
    #expect(first != differentHighLane)
}

@Test
func preparedInlineFingerprintTracksEveryMutableIdentityBoundary() {
    let runRange = MarkdownSourceRange(byteRange: 4..<9, lineRange: 1..<2)
    var prepared = PreparedInlineContent(
        runs: [
            MarkdownInlineRun(
                kind: .link,
                text: "alpha",
                sourceRange: runRange,
                destination: "https://example.com/one"
            )
        ],
        sourceRange: MarkdownSourceRange(byteRange: 0..<9, lineRange: 1..<2)
    )

    let original = prepared.cacheFingerprint
    let originalLayout = prepared.layoutCacheFingerprint
    prepared.runs[0].destination = "https://example.com/two"
    let changedRun = prepared.cacheFingerprint
    let metadataOnlyLayout = prepared.layoutCacheFingerprint
    prepared.segments[0].presentation = .strong
    let changedSegment = prepared.cacheFingerprint
    let changedSegmentLayout = prepared.layoutCacheFingerprint
    prepared.sourceRange = MarkdownSourceRange(byteRange: 10..<19, lineRange: 2..<3)
    let changedRange = prepared.cacheFingerprint
    prepared.naturalText = "omega"
    let changedText = prepared.cacheFingerprint

    #expect(original != changedRun)
    #expect(originalLayout == metadataOnlyLayout)
    #expect(changedRun != changedSegment)
    #expect(metadataOnlyLayout != changedSegmentLayout)
    #expect(changedSegment != changedRange)
    #expect(changedRange != changedText)
    #expect(prepared.naturalTextUTF8Count == 5)
}

@Test
func measuredAndLayoutFingerprintsTrackSuppliedGeometry() {
    let prepared = PreparedInlineContent(
        runs: [MarkdownInlineRun(kind: .text, text: "alpha beta")]
    )
    var measured = MeasuredInlineContent(
        prepared: prepared,
        segments: prepared.segments.map {
            MeasuredInlineSegment(segment: $0, width: Double($0.text.utf8.count))
        },
        naturalWidth: 10,
        fontSize: 14
    )
    let originalMeasured = measured.cacheFingerprint
    measured.segments[0].width += 1
    let changedSegmentWidth = measured.cacheFingerprint
    measured.segments[0].units = [
        MeasuredInlineUnit(byteRange: 0..<1, width: 1)
    ]
    let changedUnits = measured.cacheFingerprint
    measured.naturalWidth = 11
    let changedNaturalWidth = measured.cacheFingerprint
    measured.fontSize = 15
    let changedFontSize = measured.cacheFingerprint

    #expect(originalMeasured != changedSegmentWidth)
    #expect(changedSegmentWidth != changedUnits)
    #expect(changedUnits != changedNaturalWidth)
    #expect(changedNaturalWidth != changedFontSize)

    var layout = InlineLayoutResult(
        lines: [InlineLineRange(byteRange: 0..<5, width: 5)],
        naturalWidth: 5,
        height: 18
    )
    let originalLayout = layout.cacheFingerprint
    layout.lines[0].width = 6
    let changedLine = layout.cacheFingerprint
    layout.height = 20

    #expect(originalLayout != changedLine)
    #expect(changedLine != layout.cacheFingerprint)
}
