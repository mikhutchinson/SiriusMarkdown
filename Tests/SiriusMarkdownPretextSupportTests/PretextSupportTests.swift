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
