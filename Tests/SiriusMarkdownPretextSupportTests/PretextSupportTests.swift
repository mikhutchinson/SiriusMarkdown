import Testing
import SiriusMarkdownCore
import SiriusMarkdownPretextSupport

@Test
func goldenComparatorReportsNoDifferencesInsideTolerance() {
    let fixture = PretextFixture(
        name: "simple",
        markdown: "Hello",
        containerWidth: 320,
        expected: PretextExpectedLayout(lineCount: 1, naturalWidth: 42, height: 18)
    )
    let actual = InlineLayoutResult(
        lines: [InlineLineRange(byteRange: 0..<5, width: 42)],
        naturalWidth: 42.25,
        height: 18.2
    )

    #expect(PretextGoldenComparator.compare(fixture: fixture, actual: actual, tolerance: 0.5).isEmpty)
}

@Test
func bundledPretextFixturesCompareAgainstSwiftLayout() throws {
    let fixtures = try PretextFixture.bundledFixtures()
    #expect(fixtures.count >= 9)

    var engine = InlineLayoutEngine()
    for fixture in fixtures {
        let prepared = PreparedInlineContent(
            runs: [.init(kind: .text, text: fixture.markdown)]
        )
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
            tolerance: 2
        )
        #expect(differences.isEmpty, "Pretext drift for \(fixture.name): \(differences)")
    }
}
