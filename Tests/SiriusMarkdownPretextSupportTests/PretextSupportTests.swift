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
    assertProductFixtureCoverage(fixtures)

    for fixture in fixtures {
        let runs = try parsedInlineRuns(for: fixture)
        if let expectedInlineKinds = fixture.expectedInlineKinds {
            let actualInlineKinds = runs.reduce(into: [MarkdownInlineKind]()) { kinds, run in
                kinds.append(run.kind)
            }
            if actualInlineKinds != expectedInlineKinds {
                Issue.record("\(fixture.name) inline kinds must come from swift-markdown")
            }
        }

        let prepared = PreparedInlineContent(runs: runs)
        if prepared.naturalText != fixture.oracleText ?? fixture.markdown {
            Issue.record("\(fixture.name) prepared natural text drifted from oracle text.")
        }
        if let expectedPreparedSegments = fixture.expectedPreparedSegments {
            if prepared.segments.map(PretextExpectedPreparedSegment.init) != expectedPreparedSegments {
                Issue.record("\(fixture.name) prepared segments drifted from fixture.")
            }
        }

        let font = fontProfile(for: fixture)
        var engine = InlineLayoutEngine(measurer: CoreTextInlineMeasurer(fontName: font.name))
        let measured = engine.prepareMeasuredContent(prepared, fontSize: font.size)
        let result = engine.layout(
            measured,
            options: InlineLayoutOptions(
                containerWidth: fixture.containerWidth,
                fontSize: font.size,
                lineHeight: fixture.lineHeight ?? 18
            )
        )
        let differences = PretextGoldenComparator.compare(
            fixture: fixture,
            actual: result,
            naturalText: prepared.naturalText,
            tolerance: 2
        )
        if !differences.isEmpty {
            Issue.record("Pretext drift for \(fixture.name): \(differences)")
        }
    }
}

private func assertProductFixtureCoverage(_ fixtures: [PretextFixture]) {
    let names = fixtures.map(\.name)
    #expect(Set(names).count == names.count, "Pretext fixtures must not duplicate names: \(duplicateValues(in: names))")

    let groups = fixtures.compactMap(\.group)
    #expect(groups.count == fixtures.count, "Every bundled Pretext fixture must declare a product group.")
    #expect(Set(groups).count == groups.count, "Pretext fixtures must not duplicate groups: \(duplicateValues(in: groups))")

    let missingGroups = PretextFixture.requiredProductGroups.subtracting(groups).sorted()
    #expect(missingGroups.isEmpty, "Missing required Pretext product fixture groups: \(missingGroups)")

    for fixture in fixtures {
        #expect(fixture.description?.isEmpty == false, "\(fixture.name) must describe the contract it covers.")
        #expect(fixture.font?.isEmpty == false, "\(fixture.name) must pin the Pretext font profile.")
        #expect(fixture.lineHeight != nil, "\(fixture.name) must pin lineHeight.")
        #expect(fixture.whiteSpace?.isEmpty == false, "\(fixture.name) must pin whiteSpace.")
        #expect(fixture.wordBreak?.isEmpty == false, "\(fixture.name) must pin wordBreak.")
    }
}

private func duplicateValues(in values: [String]) -> [String] {
    var seen = Set<String>()
    var duplicates = Set<String>()
    for value in values where !seen.insert(value).inserted {
        duplicates.insert(value)
    }
    return duplicates.sorted()
}

private func fontProfile(for fixture: PretextFixture) -> (name: String, size: Double) {
    guard let font = fixture.font else {
        return ("Helvetica", 16)
    }

    let parts = font.split(separator: " ", maxSplits: 1).map(String.init)
    let size = parts.first?.hasSuffix("px") == true
        ? Double(parts[0].dropLast(2)) ?? 16
        : 16
    let name = parts.count > 1 ? parts[1] : "Helvetica"
    return (name, size)
}

private func parsedInlineRuns(for fixture: PretextFixture) throws -> [MarkdownInlineRun] {
    var stream = MarkdownStream()
    stream.append(fixture.markdown)
    stream.finish()
    let block = try #require(stream.snapshot().blocks.first)
    switch fixture.group {
    case "list-cell-inline":
        return try #require(block.listItems.first?.inlines)
    case "nested-list-path-wrap":
        return try #require(block.listItems.first?.childItems.first?.inlines)
    case "table-cell-inline":
        return try #require(block.table?.rows.first?.first?.inlines)
    default:
        break
    }
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
