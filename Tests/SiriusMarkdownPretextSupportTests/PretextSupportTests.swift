import Testing
import SiriusMarkdownCore
import SiriusMarkdownPretextSupport

@Test
func goldenComparatorReportsNoDifferencesInsideTolerance() {
    let fixture = PretextFixture(
        name: "simple",
        markdown: "Hello",
        containerWidth: 320,
        expected: PretextExpectedLayout(
            lineCount: 1,
            naturalWidth: 42,
            height: 18,
            lines: [
                PretextExpectedLine(
                    text: "Hello",
                    width: 42,
                    byteRange: PretextByteRange(lowerBound: 0, upperBound: 5),
                    start: PretextLayoutCursor(segmentIndex: 0, graphemeIndex: 0),
                    end: PretextLayoutCursor(segmentIndex: 1, graphemeIndex: 0)
                )
            ]
        )
    )
    let actual = InlineLayoutResult(
        lines: [InlineLineRange(byteRange: 0..<5, width: 42)],
        naturalWidth: 42.25,
        height: 18.2
    )

    #expect(PretextGoldenComparator.compare(fixture: fixture, actual: actual, naturalText: "Hello", tolerance: 0.5).isEmpty)
}

@Test
func bundledPretextFixturesCompareAgainstSwiftLayout() throws {
    let fixtures = try PretextFixture.bundledFixtures()
    #expect(fixtures.count >= 9)

    var engine = InlineLayoutEngine()
    for fixture in fixtures {
        let runs = try parsedInlineRuns(for: fixture)
        if let expectedInlineKinds = fixture.expectedInlineKinds {
            #expect(runs.map(\.kind) == expectedInlineKinds, "\(fixture.name) inline kinds must come from swift-markdown")
        }

        let prepared = PreparedInlineContent(runs: runs)
        #expect(prepared.naturalText == fixture.oracleText ?? fixture.markdown)
        if let expectedPreparedSegments = fixture.expectedPreparedSegments {
            #expect(prepared.segments.map(PretextExpectedPreparedSegment.init) == expectedPreparedSegments)
        }

        let measured = engine.prepareMeasuredContent(prepared, fontSize: 16)
        let result = engine.layout(
            measured,
            options: InlineLayoutOptions(
                containerWidth: fixture.containerWidth,
                fontSize: 16,
                lineHeight: 18
            )
        )
        let differences = PretextGoldenComparator.compare(
            fixture: fixture,
            actual: result,
            naturalText: prepared.naturalText,
            tolerance: 2
        )
        #expect(differences.isEmpty, "Pretext drift for \(fixture.name): \(differences)")
    }
}

private func parsedInlineRuns(for fixture: PretextFixture) throws -> [MarkdownInlineRun] {
    var stream = MarkdownStream()
    stream.append(fixture.markdown)
    stream.finish()
    let block = try #require(stream.snapshot().blocks.first)
    return block.inlines
}

private extension PretextExpectedPreparedSegment {
    init(_ segment: PreparedInlineSegment) {
        self.init(
            kind: segment.kind,
            text: segment.text,
            byteRange: PretextByteRange(
                lowerBound: segment.byteRange.lowerBound,
                upperBound: segment.byteRange.upperBound
            ),
            isHardBreak: segment.isHardBreak,
            isBreakOpportunity: segment.isBreakOpportunity
        )
    }
}
