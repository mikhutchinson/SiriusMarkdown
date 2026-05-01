import Foundation
import Testing
@testable import SiriusMarkdownCore

private let streamingCorpus = """
# Title

Paragraph with **strong**, *emphasis*, `code`, [link](https://example.com), and ![alt](image.png).

- [ ] Task one
- [x] Task two


> Quote line
> continued

```swift
let fence = "``` inside text"
```

$$
x^2 + y^2
$$

| A | B |
| - | - |
| 1 | 2 |

<div>

raw html block

</div>

Final paragraph.
"""

@Test(arguments: Array(1...80))
func streamedParseEqualsStaticParseForChunkSize(chunkSize: Int) {
    var streamed = MarkdownStream()
    var current = ""

    for character in streamingCorpus {
        current.append(character)
        if current.count == chunkSize {
            streamed.append(current)
            current.removeAll(keepingCapacity: true)
        }
    }

    if !current.isEmpty {
        streamed.append(current)
    }
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(streamingCorpus)
    oneShot.finish()

    let streamedSnapshot = streamed.snapshot()
    let oneShotSnapshot = oneShot.snapshot()

    #expect(streamedSnapshot.blocks.map(\.kind) == oneShotSnapshot.blocks.map(\.kind))
    #expect(streamedSnapshot.blocks.map(\.text) == oneShotSnapshot.blocks.map(\.text))
    #expect(streamedSnapshot.blocks.map(\.id) == oneShotSnapshot.blocks.map(\.id))
    #expect(streamedSnapshot.isFinished)
    #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
}

private struct SourceCase: Sendable {
    var name: String
    var chunks: [String]
    var expectedText: String
    var expectedByteCount: Int
    var probeOffset: Int
    var expectedLine: Int
}

private let sourceCases: [SourceCase] = [
    SourceCase(name: "empty chunk ignored by caller", chunks: [""], expectedText: "", expectedByteCount: 0, probeOffset: 0, expectedLine: 1),
    SourceCase(name: "ascii single line", chunks: ["abc"], expectedText: "abc", expectedByteCount: 3, probeOffset: 2, expectedLine: 1),
    SourceCase(name: "ascii split chunks", chunks: ["ab", "cd"], expectedText: "abcd", expectedByteCount: 4, probeOffset: 3, expectedLine: 1),
    SourceCase(name: "trailing newline", chunks: ["a\n"], expectedText: "a\n", expectedByteCount: 2, probeOffset: 1, expectedLine: 1),
    SourceCase(name: "two lines", chunks: ["a\nb"], expectedText: "a\nb", expectedByteCount: 3, probeOffset: 2, expectedLine: 2),
    SourceCase(name: "three chunks lines", chunks: ["a\n", "b\n", "c"], expectedText: "a\nb\nc", expectedByteCount: 5, probeOffset: 4, expectedLine: 3),
    SourceCase(name: "blank line", chunks: ["a\n\nb"], expectedText: "a\n\nb", expectedByteCount: 4, probeOffset: 3, expectedLine: 3),
    SourceCase(name: "emoji", chunks: ["hi ", "🚀"], expectedText: "hi 🚀", expectedByteCount: 7, probeOffset: 3, expectedLine: 1),
    SourceCase(name: "cjk", chunks: ["春", "天"], expectedText: "春天", expectedByteCount: 6, probeOffset: 3, expectedLine: 1),
    SourceCase(name: "rtl", chunks: ["بدأت\n", "الرحلة"], expectedText: "بدأت\nالرحلة", expectedByteCount: 21, probeOffset: 9, expectedLine: 2),
    SourceCase(name: "mixed unicode lines", chunks: ["a🚀\n", "春天\n", "end"], expectedText: "a🚀\n春天\nend", expectedByteCount: 16, probeOffset: 13, expectedLine: 3),
    SourceCase(name: "windows text preserved", chunks: ["a\r\nb"], expectedText: "a\r\nb", expectedByteCount: 4, probeOffset: 3, expectedLine: 2),
    SourceCase(name: "tabs", chunks: ["a\tb\nc"], expectedText: "a\tb\nc", expectedByteCount: 5, probeOffset: 4, expectedLine: 2),
    SourceCase(name: "many newlines", chunks: ["\n\n\n"], expectedText: "\n\n\n", expectedByteCount: 3, probeOffset: 2, expectedLine: 3),
    SourceCase(name: "markdown", chunks: ["# H\n\n", "Body"], expectedText: "# H\n\nBody", expectedByteCount: 9, probeOffset: 5, expectedLine: 3)
]

@Test(arguments: sourceCases)
private func sourceBufferRoundTripsChunksAndLineMap(sourceCase: SourceCase) {
    var buffer = MarkdownSourceBuffer()

    for chunk in sourceCase.chunks {
        if !chunk.isEmpty {
            buffer.append(chunk)
        }
    }

    #expect(buffer.fullText() == sourceCase.expectedText)
    #expect(buffer.byteCount == sourceCase.expectedByteCount)
    #expect(buffer.slice(0..<buffer.byteCount).text == sourceCase.expectedText)

    if buffer.byteCount > 0 {
        #expect(buffer.lineMap.lineNumber(containingByteOffset: sourceCase.probeOffset) == sourceCase.expectedLine)
    }
}

@Test(arguments: sourceCases.filter { !$0.expectedText.isEmpty })
private func sourceRangeCoversFullBuffer(sourceCase: SourceCase) {
    var buffer = MarkdownSourceBuffer()
    for chunk in sourceCase.chunks where !chunk.isEmpty {
        buffer.append(chunk)
    }

    let range = buffer.sourceRange(for: 0..<buffer.byteCount)
    #expect(range.byteRange == 0..<buffer.byteCount)
    #expect(range.lineRange.lowerBound == 1)
    #expect(range.lineRange.upperBound >= range.lineRange.lowerBound + 1)
}

private struct BlockCase: Sendable {
    var markdown: String
    var expectedKind: MarkdownBlockKind
    var headingLevel: Int?
    var infoString: String?
}

private let blockCases: [BlockCase] = [
    BlockCase(markdown: "plain paragraph", expectedKind: .paragraph, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "# h1", expectedKind: .heading, headingLevel: 1, infoString: nil),
    BlockCase(markdown: "setext\n======", expectedKind: .heading, headingLevel: 1, infoString: nil),
    BlockCase(markdown: "setext\n------", expectedKind: .heading, headingLevel: 2, infoString: nil),
    BlockCase(markdown: "## h2", expectedKind: .heading, headingLevel: 2, infoString: nil),
    BlockCase(markdown: "### h3", expectedKind: .heading, headingLevel: 3, infoString: nil),
    BlockCase(markdown: "#### h4", expectedKind: .heading, headingLevel: 4, infoString: nil),
    BlockCase(markdown: "##### h5", expectedKind: .heading, headingLevel: 5, infoString: nil),
    BlockCase(markdown: "###### h6", expectedKind: .heading, headingLevel: 6, infoString: nil),
    BlockCase(markdown: "- item", expectedKind: .unorderedList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "* item", expectedKind: .unorderedList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "+ item", expectedKind: .unorderedList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "1. item", expectedKind: .orderedList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "42. item", expectedKind: .orderedList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "- [ ] todo", expectedKind: .taskList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "- [x] done", expectedKind: .taskList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "* [ ] todo", expectedKind: .taskList, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "> quote", expectedKind: .blockQuote, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "---", expectedKind: .thematicBreak, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "***", expectedKind: .thematicBreak, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "___", expectedKind: .thematicBreak, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "| A | B |\n| - | - |", expectedKind: .table, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "<div>html</div>", expectedKind: .htmlBlock, headingLevel: nil, infoString: nil),
    BlockCase(markdown: "```swift\nlet x = 1\n```", expectedKind: .codeBlock, headingLevel: nil, infoString: "swift"),
    BlockCase(markdown: "~~~python\nprint(1)\n~~~", expectedKind: .codeBlock, headingLevel: nil, infoString: "python"),
    BlockCase(markdown: "$$\nx^2\n$$", expectedKind: .mathBlock, headingLevel: nil, infoString: nil)
]

@Test(arguments: blockCases)
private func parserClassifiesBlockKinds(blockCase: BlockCase) {
    var stream = MarkdownStream()
    stream.append(blockCase.markdown)
    stream.finish()

    let block = stream.snapshot().blocks.first
    #expect(block?.kind == blockCase.expectedKind)
    #expect(block?.headingLevel == blockCase.headingLevel)
    #expect(block?.infoString == blockCase.infoString)
}

private struct InlineCase: Sendable {
    var markdown: String
    var expectedKinds: [MarkdownInlineKind]
    var expectedTexts: [String]
    var expectedDestination: String?
}

private let inlineCases: [InlineCase] = [
    InlineCase(markdown: "hello", expectedKinds: [.text], expectedTexts: ["hello"], expectedDestination: nil),
    InlineCase(markdown: "`code`", expectedKinds: [.code], expectedTexts: ["code"], expectedDestination: nil),
    InlineCase(markdown: "**bold**", expectedKinds: [.strong], expectedTexts: ["bold"], expectedDestination: nil),
    InlineCase(markdown: "*em*", expectedKinds: [.emphasis], expectedTexts: ["em"], expectedDestination: nil),
    InlineCase(markdown: "_em_", expectedKinds: [.emphasis], expectedTexts: ["em"], expectedDestination: nil),
    InlineCase(markdown: "~~gone~~", expectedKinds: [.strikethrough], expectedTexts: ["gone"], expectedDestination: nil),
    InlineCase(markdown: "[label](https://example.com)", expectedKinds: [.link], expectedTexts: ["label"], expectedDestination: "https://example.com"),
    InlineCase(markdown: "![alt](image.png)", expectedKinds: [.image], expectedTexts: ["alt"], expectedDestination: "image.png"),
    InlineCase(markdown: "a `b` c", expectedKinds: [.text, .code, .text], expectedTexts: ["a ", "b", " c"], expectedDestination: nil),
    InlineCase(markdown: "a **b** c", expectedKinds: [.text, .strong, .text], expectedTexts: ["a ", "b", " c"], expectedDestination: nil),
    InlineCase(markdown: "a *b* c", expectedKinds: [.text, .emphasis, .text], expectedTexts: ["a ", "b", " c"], expectedDestination: nil),
    InlineCase(markdown: "a ~~b~~ c", expectedKinds: [.text, .strikethrough, .text], expectedTexts: ["a ", "b", " c"], expectedDestination: nil),
    InlineCase(markdown: "a\nb", expectedKinds: [.text, .softBreak, .text], expectedTexts: ["a", "\n", "b"], expectedDestination: nil)
]

@Test(arguments: inlineCases)
private func parserClassifiesInlineRuns(inlineCase: InlineCase) {
    var stream = MarkdownStream()
    stream.append(inlineCase.markdown)
    stream.finish()

    let runs = stream.snapshot().blocks.first?.inlines ?? []
    #expect(runs.map(\.kind) == inlineCase.expectedKinds)
    #expect(runs.map(\.text) == inlineCase.expectedTexts)
    if let expectedDestination = inlineCase.expectedDestination {
        #expect(runs.first?.destination == expectedDestination)
    }
}

@Test
private func parserConvertsStructuredTaskListItemsFromAST() {
    var stream = MarkdownStream()
    stream.append("- [ ] first\n- [x] second")
    stream.finish()

    let block = stream.snapshot().blocks.first
    #expect(block?.kind == .taskList)
    #expect(block?.listItems.map(\.taskState) == [.unchecked, .checked])
    #expect(block?.listItems.map { $0.inlines.map(\.text).joined() } == ["first", "second"])
}

@Test
private func parserConvertsOrderedListStartFromAST() {
    var stream = MarkdownStream()
    stream.append("42. first\n43. second")
    stream.finish()

    let block = stream.snapshot().blocks.first
    #expect(block?.kind == .orderedList)
    #expect(block?.orderedListStart == 42)
    #expect(block?.listItems.count == 2)
}

@Test
private func parserConvertsNestedListItemsFromAST() {
    var stream = MarkdownStream()
    stream.append("- parent\n  - child")
    stream.finish()

    let item = stream.snapshot().blocks.first?.listItems.first
    #expect(item?.text == "parent")
    #expect(item?.inlines.map(\.text).joined() == "parent")
    #expect(item?.childItems.count == 1)
    #expect(item?.childItems.first?.text.contains("child") == true)
}

@Test
private func parserConvertsTableCellsAndAlignmentsFromAST() {
    var stream = MarkdownStream()
    stream.append("| Left | Center | Right |\n| :--- | :----: | ----: |\n| a | **b** | `c` |")
    stream.finish()

    let table = stream.snapshot().blocks.first?.table
    #expect(table?.columnAlignments == [.left, .center, .right])
    #expect(table?.header.map(\.text) == ["Left", "Center", "Right"])
    #expect(table?.rows.first?.map { $0.inlines.map(\.kind) } == [[.text], [.strong], [.code]])
}

@Test
private func parserUsesSourceRangeAndContentHashInStableBlockID() {
    var stream = MarkdownStream()
    stream.append("# Title")
    stream.finish()

    let block = stream.snapshot().blocks.first
    #expect(block?.sourceRange.byteRange == 0..<7)
    #expect(block?.contentHash != 0)
    #expect(block?.id.rawValue == "stream:0:0:heading")
    #expect(block?.id.rawValue.hasSuffix(":heading") == true)
}

private struct BoundaryCase: Sendable {
    var markdown: String
    var shouldSeal: Bool
}

private let boundaryCases: [BoundaryCase] = [
    // Blank line terminates a seal candidate unless inside a construct.
    BoundaryCase(markdown: "paragraph\n\n", shouldSeal: true),
    BoundaryCase(markdown: "paragraph\n", shouldSeal: false),
    BoundaryCase(markdown: "first\n\nsecond\n\n", shouldSeal: true),
    BoundaryCase(markdown: "first\nsecond\n\n", shouldSeal: true),

    // Fenced code: depth is marker-run length; close line must prefix enough matching markers.
    BoundaryCase(markdown: "```\nopen\n\n", shouldSeal: false),
    BoundaryCase(markdown: "```\nclosed\n```\n\n", shouldSeal: true),
    BoundaryCase(markdown: "````\n``` inner\n````\n\n", shouldSeal: true),
    BoundaryCase(markdown: "````\n``` inner\n\n", shouldSeal: false),
    BoundaryCase(markdown: "````\nbody\n```\n\n", shouldSeal: false),
    BoundaryCase(markdown: "`````\nbody\n````\n\n", shouldSeal: false),
    BoundaryCase(markdown: "`````\nbody\n`````\n\n", shouldSeal: true),
    BoundaryCase(markdown: "~~~\nopen\n\n", shouldSeal: false),
    BoundaryCase(markdown: "~~~\nclosed\n~~~\n\n", shouldSeal: true),
    BoundaryCase(markdown: "~~~\nwrong close\n```\n\n", shouldSeal: false),
    BoundaryCase(markdown: "```\na\n\nb\n```\n\n", shouldSeal: true),

    // Math: trimmed line $$ toggles fence; stray lines leave it open.
    BoundaryCase(markdown: "$$\nopen\n\n", shouldSeal: false),
    BoundaryCase(markdown: "$$\nclosed\n$$\n\n", shouldSeal: true),
    BoundaryCase(markdown: "$$\n$x + y$\n\n", shouldSeal: false),
    BoundaryCase(markdown: "$$\n$f(x)$\n$$\n\n", shouldSeal: true),
    BoundaryCase(markdown: "$$\n$$\n\n", shouldSeal: true),

    // HTML blocks: heuristic open/close via closing token appearing on a completed line.
    BoundaryCase(markdown: "<div>\n\ninside\n", shouldSeal: false),
    BoundaryCase(markdown: "<div>\ninside\n</div>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<DIV>\ndata\n</div>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<script>\nvar x;\n</script>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<style>\n\ninside\n", shouldSeal: false),
    BoundaryCase(markdown: "<style>\n*{color:red}\n</style>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<pre>\n\n<code>\n", shouldSeal: false),
    BoundaryCase(markdown: "<pre>\nhi\n</pre>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<table>\n<tr>\n", shouldSeal: false),
    BoundaryCase(markdown: "<table>\n<td></td>\n</table>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<section>\n</section>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<article>\nopen\n", shouldSeal: false),
    BoundaryCase(markdown: "<aside>\ntext\n</aside>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<!-- comment\n\n", shouldSeal: false),
    BoundaryCase(markdown: "<!-- comment -->\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<!-- multi\nline\n-->\n\n", shouldSeal: true),

    // Blank line inside fences does not seal until the fence closes.
    BoundaryCase(markdown: "```\n\n\n````\n\n", shouldSeal: true),

    // Loose lists: one blank after list-like line defers seal; two consecutive blanks still allow.
    BoundaryCase(markdown: "- item\n\n", shouldSeal: false),
    BoundaryCase(markdown: "- item\n\n\n", shouldSeal: true),
    BoundaryCase(markdown: "1. item\n\n", shouldSeal: false),
    BoundaryCase(markdown: "1. item\n\n\n", shouldSeal: true),
    BoundaryCase(markdown: "10. item\n\n", shouldSeal: false),
    BoundaryCase(markdown: "* item\n\n", shouldSeal: false),
    BoundaryCase(markdown: "+ item\n\n", shouldSeal: false),
    BoundaryCase(markdown: "- [ ] task\n\n", shouldSeal: false),
    BoundaryCase(markdown: "- [ ] task\n\n\n", shouldSeal: true),
    BoundaryCase(markdown: "- [x] task\n\n", shouldSeal: false)
]

@Test(arguments: boundaryCases)
private func boundaryScannerIsConservative(boundaryCase: BoundaryCase) {
    var buffer = MarkdownSourceBuffer()
    buffer.append(boundaryCase.markdown)
    let scanner = MarkdownBoundaryScanner()

    let seal = scanner.safeSealUpperBound(in: buffer, after: 0)
    #expect((seal != nil) == boundaryCase.shouldSeal)
}

private struct PolicyCase: Sendable {
    var destination: String
    var allowed: Bool
}

private let policyCases: [PolicyCase] = [
    PolicyCase(destination: "https://example.com", allowed: true),
    PolicyCase(destination: "http://example.com", allowed: true),
    PolicyCase(destination: "mailto:user@example.com", allowed: true),
    PolicyCase(destination: "/relative/path", allowed: true),
    PolicyCase(destination: "#fragment", allowed: true),
    PolicyCase(destination: "javascript:alert(1)", allowed: false),
    PolicyCase(destination: "JaVaScRiPt:alert(1)", allowed: false),
    PolicyCase(destination: "data:text/html;base64,PGgxPkJvb208L2gxPg==", allowed: false),
    PolicyCase(destination: "file:///tmp/local", allowed: false),
    PolicyCase(destination: "unknown-scheme:value", allowed: false)
]

@Test(arguments: policyCases)
private func defaultPolicyHandlesLinkDestinations(policyCase: PolicyCase) {
    let policy = DefaultMarkdownPolicy()
    let decision = policy.evaluateLink(destination: policyCase.destination)

    switch (decision, policyCase.allowed) {
    case (.allow, true), (.deny, false):
        break
    default:
        Issue.record("Unexpected policy decision \(decision) for \(policyCase.destination)")
    }
}

struct FixedWidthMeasurer: InlineMeasuring {
    var widthPerByte: Double = 1

    func width(of text: String, fontSize: Double) -> Double {
        Double(text.utf8.count) * widthPerByte
    }
}

final class CountingWidthMeasurer: InlineMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var widthCallCount = 0
    var widthPerByte: Double = 1

    func width(of text: String, fontSize: Double) -> Double {
        lock.withLock {
            widthCallCount += 1
        }
        return Double(text.utf8.count) * widthPerByte
    }

    var count: Int {
        lock.withLock {
            widthCallCount
        }
    }
}

private struct LayoutCase: Sendable {
    var text: String
    var width: Double
    var expectedLineCount: Int
    var expectedHeight: Double
}

private let layoutCases: [LayoutCase] = [
    LayoutCase(text: "abc", width: 10, expectedLineCount: 1, expectedHeight: 2),
    LayoutCase(text: "abc", width: 2, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "abcdef", width: 3, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "abcdef", width: 1, expectedLineCount: 6, expectedHeight: 12),
    LayoutCase(text: "a\nb", width: 10, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "a\nb\nc", width: 10, expectedLineCount: 3, expectedHeight: 6),
    LayoutCase(text: "春天", width: 3, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "🚀🚀", width: 4, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "ab cd", width: 3, expectedLineCount: 2, expectedHeight: 4),
    LayoutCase(text: "ab cd", width: 100, expectedLineCount: 1, expectedHeight: 2)
]

@Test(arguments: layoutCases)
private func layoutWalkerProducesDeterministicLineCounts(layoutCase: LayoutCase) {
    let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: layoutCase.text)])
    let walker = VariableWidthLineWalker(measurer: FixedWidthMeasurer())
    let result = walker.layout(
        prepared,
        options: InlineLayoutOptions(containerWidth: layoutCase.width, fontSize: 1, lineHeight: 2)
    )

    #expect(result.lines.count == layoutCase.expectedLineCount)
    #expect(result.height == layoutCase.expectedHeight)
    #expect(result.lines.allSatisfy { !$0.byteRange.isEmpty })
}

@Test
private func coreTextMeasurerMatchesPretextBaseFontProfileForMissingGlyphs() {
    #if canImport(CoreText)
    let measurer = CoreTextInlineMeasurer()

    #expect(abs(measurer.width(of: "Hello SiriusMarkdown", fontSize: 16) - 154.72) < 0.5)
    #expect(abs(measurer.width(of: "🚀🚀 春天 emoji wrap", fontSize: 16) - 126.82) < 0.5)
    #expect(abs(measurer.width(of: "بدأت الرحلة ثم اكتملت", fontSize: 16) - 195.87) < 0.5)
    #endif
}

@Test
private func measuredInlineContentReusesWidthsAcrossLayoutPasses() {
    let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: "abcdef ghij")])
    let measurer = CountingWidthMeasurer()
    let walker = VariableWidthLineWalker(measurer: measurer)

    let measured = walker.prepare(prepared, fontSize: 1)
    let measurementCount = measurer.count

    let narrow = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 7, fontSize: 1, lineHeight: 2)
    )
    let wide = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 20, fontSize: 1, lineHeight: 2)
    )

    #expect(measurementCount > 0)
    #expect(measurer.count == measurementCount)
    #expect(narrow.lines.count > wide.lines.count)
}

@Test
private func preparedUnitMeasurementsAvoidOverwideLayoutMeasurement() {
    let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: "abcdef")])
    let measurer = CountingWidthMeasurer()
    let walker = VariableWidthLineWalker(measurer: measurer)

    let measured = walker.prepare(prepared, fontSize: 1, includesUnitMeasurements: true)
    let countAfterPrepare = measurer.count
    let narrow = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 2, fontSize: 1, lineHeight: 2)
    )
    let wide = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 20, fontSize: 1, lineHeight: 2)
    )

    #expect(measured.segments.first?.units.count == 6)
    #expect(countAfterPrepare == 7)
    #expect(measurer.count == countAfterPrepare)
    #expect(narrow.lines.count > wide.lines.count)
}

@Test
private func layoutCanRefuseViewTimeOverwideUnitMeasurement() {
    let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: "abcdef")])
    let measurer = CountingWidthMeasurer()
    let walker = VariableWidthLineWalker(measurer: measurer)

    let measured = walker.prepare(prepared, fontSize: 1)
    let countAfterPrepare = measurer.count
    let result = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 2, fontSize: 1, lineHeight: 2),
        allowsOverwideFallback: false
    )

    #expect(measured.segments.first?.units.isEmpty == true)
    #expect(measurer.count == countAfterPrepare)
    #expect(result.lines.count == 1)
    #expect(result.lines.first?.width == 6)
}

@Test
private func streamDiagnosticsTrackTailReparseAndCacheReuse() {
    var stream = MarkdownStream()
    stream.append("Active tail")

    _ = stream.snapshot()
    let afterFirstSnapshot = stream.diagnosticsCounters
    #expect(afterFirstSnapshot.parseCount == 1)
    #expect(afterFirstSnapshot.tailReparseCount == 1)

    _ = stream.snapshot()
    let afterSecondSnapshot = stream.diagnosticsCounters
    #expect(afterSecondSnapshot.parseCount == afterFirstSnapshot.parseCount)
    #expect(afterSecondSnapshot.tailReparseCount == afterFirstSnapshot.tailReparseCount)
    #expect(afterSecondSnapshot.cacheHitCount == afterFirstSnapshot.cacheHitCount + 1)

    stream.append(" updated")
    _ = stream.snapshot()
    let afterAppendSnapshot = stream.diagnosticsCounters
    #expect(afterAppendSnapshot.parseCount == afterFirstSnapshot.parseCount + 1)
    #expect(afterAppendSnapshot.tailReparseCount == afterFirstSnapshot.tailReparseCount + 1)
}

@Test
private func hostBoundarySealingReusesCachedTailParse() {
    var stream = MarkdownStream()
    stream.append("Native insertion boundary")
    _ = stream.snapshot()
    let beforeBoundary = stream.diagnosticsCounters

    stream.appendHostBoundary(id: MarkdownHostBoundaryID("native-card"))
    let snapshot = stream.snapshot()
    let afterBoundary = stream.diagnosticsCounters

    #expect(snapshot.blocks.first?.isSealed == true)
    #expect(afterBoundary.parseCount == beforeBoundary.parseCount)
    #expect(afterBoundary.sealedRegionCacheHitCount == beforeBoundary.sealedRegionCacheHitCount + 1)
}

@Test
private func sealedRegionParseMissIsRecordedWhenNoTailCacheExists() {
    var stream = MarkdownStream()
    stream.append("Paragraph\n\n")

    let counters = stream.diagnosticsCounters
    #expect(counters.sealedRegionParseCount == 1)
    #expect(counters.sealedRegionCacheMissCount == 1)
    #expect(counters.tailReparseCount == 0)
}

@Test
private func boundaryScannerScansLongOpenTailLinearly() {
    var stream = MarkdownStream()
    stream.append("```swift\n")
    for index in 0..<1_000 {
        stream.append("let value\(index) = \(index)\n")
    }

    let counters = stream.diagnosticsCounters
    #expect(counters.boundaryScannedLineCount == 1_001)
    #expect(counters.boundaryScannedByteCount <= stream.sourceLength)
    #expect(counters.sealedRegionParseCount == 0)
}

@Test
private func boundaryScannerScansLooseListTailLinearly() {
    var stream = MarkdownStream()
    stream.append("1. item\n")
    for _ in 0..<1_000 {
        stream.append("continuation\n")
    }

    let counters = stream.diagnosticsCounters
    #expect(counters.boundaryScannedLineCount == 1_001)
    #expect(counters.boundaryScannedByteCount <= stream.sourceLength)
}

@Test
private func boundaryScannerScansOpenHTMLAndMathTailsLinearly() {
    var htmlStream = MarkdownStream()
    htmlStream.append("<div>\n")
    for _ in 0..<500 {
        htmlStream.append("content\n")
    }

    var mathStream = MarkdownStream()
    mathStream.append("$$\n")
    for _ in 0..<500 {
        mathStream.append("x^2\n")
    }

    #expect(htmlStream.diagnosticsCounters.boundaryScannedByteCount <= htmlStream.sourceLength)
    #expect(mathStream.diagnosticsCounters.boundaryScannedByteCount <= mathStream.sourceLength)
    #expect(htmlStream.diagnosticsCounters.sealedRegionParseCount == 0)
    #expect(mathStream.diagnosticsCounters.sealedRegionParseCount == 0)
}

@Test
private func sourceBackedCopyReturnsBoundedMarkdownSlice() throws {
    var stream = MarkdownStream()
    stream.append("# Title\n\nParagraph\n\n")
    stream.finish()

    let paragraph = try #require(stream.snapshot().blocks.last)
    #expect(stream.markdown(in: paragraph.sourceRange) == "Paragraph")
}

@Test
private func inlineLayoutEngineCachesMeasuredContentAndLayoutResults() {
    let runs = [MarkdownInlineRun(kind: .text, text: "abcdef ghij")]
    let range = MarkdownSourceRange(byteRange: 0..<11, lineRange: 1..<2)
    let measurer = CountingWidthMeasurer()
    var engine = InlineLayoutEngine(measurer: measurer, cacheCapacity: 8)

    let measured = engine.prepareMeasuredContent(runs: runs, sourceRange: range, fontSize: 1)
    let measurementCount = measurer.count
    let afterPrepare = engine.diagnosticsCounters

    let cachedMeasured = engine.prepareMeasuredContent(runs: runs, sourceRange: range, fontSize: 1)
    let afterCachedPrepare = engine.diagnosticsCounters
    #expect(cachedMeasured == measured)
    #expect(measurer.count == measurementCount)
    #expect(afterPrepare.prepareCount == 1)
    #expect(afterCachedPrepare.prepareCount == afterPrepare.prepareCount)
    #expect(afterCachedPrepare.cacheHitCount > afterPrepare.cacheHitCount)

    let narrow = engine.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 3, fontSize: 1, lineHeight: 2)
    )
    let afterFirstLayout = engine.diagnosticsCounters
    let afterNarrowMeasurementCount = measurer.count
    #expect(afterFirstLayout.overwideUnitFallbackCount == 2)
    #expect(afterNarrowMeasurementCount > measurementCount)

    let cachedNarrow = engine.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 3, fontSize: 1, lineHeight: 2)
    )
    let afterCachedLayout = engine.diagnosticsCounters
    #expect(cachedNarrow == narrow)
    #expect(afterCachedLayout.layoutCount == afterFirstLayout.layoutCount)
    #expect(measurer.count == afterNarrowMeasurementCount)

    let wide = engine.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 20, fontSize: 1, lineHeight: 2)
    )
    #expect(engine.diagnosticsCounters.layoutCount == afterFirstLayout.layoutCount + 1)
    #expect(measurer.count == afterNarrowMeasurementCount)
    #expect(narrow.lines.count > wide.lines.count)
}

@Test
func tailIDSurvivesSealing() {
    var stream = MarkdownStream()
    stream.append("Paragraph")
    let activeID = stream.snapshot().blocks.first?.id

    stream.append("\n\n")
    let sealedID = stream.snapshot().blocks.first?.id

    #expect(activeID == sealedID)
    #expect(stream.snapshot().blocks.first?.isSealed == true)
}

@Test
func cacheEvictsOldestEntryWhenCapacityIsExceeded() {
    let range = MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2)
    var cache = BoundedMarkdownCache<String>(capacity: 2)
    let first = MarkdownCacheKey(sourceRange: range, contentHash: 1, namespace: "test")
    let second = MarkdownCacheKey(sourceRange: range, contentHash: 2, namespace: "test")
    let third = MarkdownCacheKey(sourceRange: range, contentHash: 3, namespace: "test")

    cache[first] = "first"
    cache[second] = "second"
    cache[third] = "third"

    #expect(cache[first] == nil)
    #expect(cache[second] == "second")
    #expect(cache[third] == "third")
}

@Test
func cacheEvictsLeastRecentlyUsedEntryWhenCapacityIsExceeded() {
    let range = MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2)
    var cache = BoundedMarkdownCache<String>(capacity: 2)
    let first = MarkdownCacheKey(sourceRange: range, contentHash: 1, namespace: "test")
    let second = MarkdownCacheKey(sourceRange: range, contentHash: 2, namespace: "test")
    let third = MarkdownCacheKey(sourceRange: range, contentHash: 3, namespace: "test")

    cache[first] = "first"
    cache[second] = "second"
    #expect(cache.value(forKey: first) == "first")

    cache[third] = "third"

    #expect(cache.value(forKey: first) == "first")
    #expect(cache.value(forKey: second) == nil)
    #expect(cache.value(forKey: third) == "third")
}

@Test
func diagnosticsDumpIncludesStableIDsAndKinds() {
    var stream = MarkdownStream()
    stream.append("# Heading\n\nBody")
    stream.finish()

    let dump = MarkdownDiagnostics().debugDump(stream.snapshot())
    #expect(dump.contains("heading"))
    #expect(dump.contains("paragraph"))
    #expect(dump.contains("stream:0:0:heading"))
}
