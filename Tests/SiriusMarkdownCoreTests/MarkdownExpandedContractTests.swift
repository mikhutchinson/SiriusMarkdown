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
    BlockCase(markdown: "1. [x] done", expectedKind: .taskList, headingLevel: nil, infoString: nil),
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
private func parserPreservesNestedInlinePresentationAndLinks() throws {
    var stream = MarkdownStream()
    stream.append("**[strong link](https://example.com)** and [*em link*](https://example.org) plus ~~[gone](https://example.net)~~")
    stream.finish()

    let runs = try #require(stream.snapshot().blocks.first?.inlines)
    let strongLink = try #require(runs.first { $0.text == "strong link" })
    let emphasisLink = try #require(runs.first { $0.text == "em link" })
    let strikeLink = try #require(runs.first { $0.text == "gone" })

    #expect(strongLink.kind == .link)
    #expect(strongLink.destination == "https://example.com")
    #expect(strongLink.presentation.contains(.strong))

    #expect(emphasisLink.kind == .link)
    #expect(emphasisLink.destination == "https://example.org")
    #expect(emphasisLink.presentation.contains(.emphasis))

    #expect(strikeLink.kind == .link)
    #expect(strikeLink.destination == "https://example.net")
    #expect(strikeLink.presentation.contains(.strikethrough))
}

@Test
private func parserPreservesLinkDestinationAcrossInlineBreaks() throws {
    var stream = MarkdownStream()
    stream.append("[first\nsecond](https://example.com/multiline) and [third  \nfourth](https://example.com/hard)")
    stream.finish()

    let runs = try #require(stream.snapshot().blocks.first?.inlines)
    let multilineRuns = runs.filter { $0.destination == "https://example.com/multiline" }
    let hardBreakRuns = runs.filter { $0.destination == "https://example.com/hard" }

    #expect(multilineRuns.map(\.text) == ["first", "\n", "second"])
    #expect(multilineRuns.map(\.kind) == [.link, .softBreak, .link])
    #expect(hardBreakRuns.map(\.text) == ["third", "\n", "fourth"])
    #expect(hardBreakRuns.map(\.kind) == [.link, .hardBreak, .link])
}

@Test
private func parserAssignsBreakRunsToOriginalSourceBytes() throws {
    let markdown = "alpha soft\nbeta hard  \ngamma slash\\\ndelta"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let runs = try #require(stream.snapshot().blocks.first?.inlines)
    let softBreak = try #require(runs.first { $0.kind == .softBreak })
    let hardBreaks = runs.filter { $0.kind == .hardBreak }
    let hardSpaceBreak = try #require(hardBreaks.first)
    let hardBackslashBreak = try #require(hardBreaks.dropFirst().first)
    let softBreakRange = try utf8Range(of: "\n", in: markdown)
    let hardSpaceRange = try utf8Range(of: "  \n", in: markdown)
    let hardBackslashRange = try utf8Range(of: "\\\n", in: markdown)

    #expect(softBreak.sourceRange?.byteRange == softBreakRange)
    #expect(hardSpaceBreak.sourceRange?.byteRange == hardSpaceRange)
    #expect(hardBackslashBreak.sourceRange?.byteRange == hardBackslashRange)
}

@Test
private func parserPreservesLinkedImagePresentationAndLinkDestination() throws {
    var stream = MarkdownStream()
    stream.append("[![diagram](diagram.png)](https://example.com/diagram)")
    stream.finish()

    let runs = try #require(stream.snapshot().blocks.first?.inlines)
    let linkedImage = try #require(runs.first { $0.presentation.contains(.image) })

    #expect(linkedImage.kind == .link)
    #expect(linkedImage.text == "diagram")
    #expect(linkedImage.destination == "https://example.com/diagram")
    #expect(linkedImage.imageSource == "diagram.png")
}

@Test
private func streamedReferenceLinksResolveLikeWholeDocument() throws {
    let markdown = """
    Intro [later][ref].

    Tail paragraph.

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("Intro [later][ref].\n\n")
    #expect(streamed.snapshot().blocks.first?.isSealed == false)
    streamed.append("Tail paragraph.\n\n")
    streamed.append("[ref]: https://example.com/reference")
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let streamedLink = try #require(streamed.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedLink.text == "later")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceDefinitionsResolveLaterReferencesLikeWholeDocument() throws {
    let markdown = """
    [ref]: https://example.com/reference

    Uses [the ref][ref].
    """

    var streamed = MarkdownStream()
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append("Uses [the ref][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 2)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.text == "the ref")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func hostBoundaryPreservesMultilineReferenceDefinitionLabelsForLaterTail() throws {
    let definition = """
    [multi
    line]: https://example.com/reference

    """
    let laterReference = "Uses [the ref][multi line].\n\n"
    let markdown = definition + laterReference

    var streamed = MarkdownStream()
    streamed.append(definition)
    streamed.appendHostBoundary(id: MarkdownHostBoundaryID("native-card"))
    streamed.append(laterReference)
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(streamed.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link })
    #expect(streamedLink.text == oneShotLink.text)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink.destination == oneShotLink.destination)
}

@Test
private func streamedReferenceDefinitionsIgnoreFencedCodeDefinitionsLikeWholeDocument() throws {
    let codeChunk = "```text\n[ref]: https://code.example\n```\n\n"
    let referenceChunk = "Uses [the ref][ref].\n\n"
    let definitionChunk = "[ref]: https://example.com/reference\n\n"
    let markdown = codeChunk + referenceChunk + definitionChunk

    var streamed = MarkdownStream()
    streamed.append(codeChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(referenceChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(definitionChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 2)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(
        streamed.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    let oneShotLink = try #require(
        oneShot.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    #expect(streamedLink.text == "the ref")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink.text == oneShotLink.text)
    #expect(streamedLink.destination == oneShotLink.destination)
}

@Test
private func streamedReferenceDefinitionsIgnoreHTMLDefinitionsLikeWholeDocument() throws {
    let htmlChunk = "<div>\n[ref]: https://html.example\n</div>\n\n"
    let referenceChunk = "Uses [the ref][ref].\n\n"
    let definitionChunk = "[ref]: https://example.com/reference\n\n"
    let markdown = htmlChunk + referenceChunk + definitionChunk

    var streamed = MarkdownStream()
    streamed.append(htmlChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(referenceChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(definitionChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 2)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(
        streamed.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    let oneShotLink = try #require(
        oneShot.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    #expect(streamedLink.text == "the ref")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink.text == oneShotLink.text)
    #expect(streamedLink.destination == oneShotLink.destination)
}

@Test
private func streamedReferenceDefinitionsIgnoreMathDefinitionsLikeWholeDocument() throws {
    let mathChunk = "\\[\n[ref]: https://math.example\n\\]\n\n"
    let referenceChunk = "Uses [the ref][ref].\n\n"
    let definitionChunk = "[ref]: https://example.com/reference\n\n"
    let markdown = mathChunk + referenceChunk + definitionChunk

    var streamed = MarkdownStream()
    streamed.append(mathChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(referenceChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append(definitionChunk)
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 2)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(
        streamed.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    let oneShotLink = try #require(
        oneShot.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
    )
    #expect(streamedLink.text == "the ref")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink.text == oneShotLink.text)
    #expect(streamedLink.destination == oneShotLink.destination)
}

@Test
private func streamedReferenceDefinitionsIgnoreContainerDisplayMathDefinitionsLikeWholeDocument() throws {
    let cases: [
        (
            mathChunk: String,
            expectedMath: String,
            parseCountAfterMath: Int,
            parseCountAfterReference: Int,
            parseCountAfterDefinition: Int
        )
    ] = [
        (
            "> \\[\n> [ref]: https://math.example\n> \\]\n\n",
            "[ref]: https://math.example",
            1,
            1,
            2
        ),
        (
            "- \\[\n  [ref]: https://math.example\n  \\]\n\n",
            "[ref]: https://math.example",
            0,
            0,
            1
        )
    ]

    for testCase in cases {
        let referenceChunk = "Uses [the ref][ref].\n\n"
        let definitionChunk = "[ref]: https://example.com/reference\n\n"
        let markdown = testCase.mathChunk + referenceChunk + definitionChunk

        var streamed = MarkdownStream()
        streamed.append(testCase.mathChunk)
        #expect(streamed.diagnosticsCounters.sealedRegionParseCount == testCase.parseCountAfterMath)
        streamed.append(referenceChunk)
        #expect(streamed.diagnosticsCounters.sealedRegionParseCount == testCase.parseCountAfterReference)
        streamed.append(definitionChunk)
        #expect(streamed.diagnosticsCounters.sealedRegionParseCount == testCase.parseCountAfterDefinition)

        var oneShot = MarkdownStream()
        oneShot.append(markdown)
        oneShot.finish()

        let streamedLink = try #require(
            streamed.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
        )
        let oneShotLink = try #require(
            oneShot.snapshot().blocks.first(where: { $0.text.contains("Uses") })?.inlines.first { $0.kind == .link }
        )
        let streamedMath = streamed.snapshot().blocks.flatMap(\.inlines).first { $0.kind == .math } ??
            streamed.snapshot().blocks.flatMap(\.listItems).flatMap(\.inlines).first { $0.kind == .math }

        #expect(streamedMath?.text == testCase.expectedMath)
        #expect(streamedLink.text == "the ref")
        #expect(streamedLink.destination == "https://example.com/reference")
        #expect(streamedLink.text == oneShotLink.text)
        #expect(streamedLink.destination == oneShotLink.destination)
    }
}

@Test
private func streamedReferenceDefinitionsIgnoreContainerParagraphTextDefinitionsLikeWholeDocument() throws {
    let cases: [(name: String, chunks: [String], expectedDestinations: [String])] = [
        (
            "list paragraph continuation text",
            [
                "- Item\n  [ref]: https://list.example\n\n",
                "Later [ref].\n\n"
            ],
            []
        ),
        (
            "list paragraph continuation text after unresolved reference",
            [
                "- Item with [ref].\n  [ref]: https://list.example\n\n",
                "Later [ref].\n\n"
            ],
            []
        ),
        (
            "quote paragraph continuation text",
            [
                "> Quote\n> [ref]: https://quote.example\n\n",
                "Later [ref].\n\n"
            ],
            []
        ),
        (
            "quote paragraph continuation text after unresolved reference",
            [
                "> Quote with [ref].\n> [ref]: https://quote.example\n\n",
                "Later [ref].\n\n"
            ],
            []
        ),
        (
            "list item that is a reference definition",
            [
                "- [ref]: https://list.example\n\n",
                "Later [ref].\n\n"
            ],
            ["https://list.example"]
        ),
        (
            "empty list item with indented reference definition",
            [
                "-\n  [ref]: https://empty-list.example\n\n",
                "Later [ref].\n\n"
            ],
            ["https://empty-list.example"]
        ),
        (
            "loose list item followed by indented reference definition",
            [
                "- Item\n\n  [ref]: https://loose-list.example\n\n",
                "Later [ref].\n\n"
            ],
            ["https://loose-list.example"]
        )
    ]

    for testCase in cases {
        var streamed = MarkdownStream()
        for chunk in testCase.chunks {
            streamed.append(chunk)
        }

        var oneShot = MarkdownStream()
        oneShot.append(testCase.chunks.joined())
        oneShot.finish()

        let streamedDestinations = referenceDestinations(in: streamed.snapshot().blocks)
        let oneShotDestinations = referenceDestinations(in: oneShot.snapshot().blocks)
        #expect(
            streamedDestinations == oneShotDestinations,
            "Streamed container reference handling diverged from one-shot parse for \(testCase.name)"
        )
        #expect(
            streamedDestinations == testCase.expectedDestinations,
            "Unexpected reference destinations for \(testCase.name)"
        )
    }
}

@Test
private func streamedReferenceCandidatesSealAfterMatchingDefinitionArrives() throws {
    let markdown = """
    Intro [later][ref].

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("Intro [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceDefinitionDestinationContinuationResolvesLikeWholeDocument() throws {
    let markdown = """
    See [later][ref].

    [ref]:
      https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]:\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("  https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceDefinitionTitleContinuationResolvesLikeWholeDocument() throws {
    let markdown = """
    See [later][ref].

    [ref]: https://example.com/reference
      "title"
    """

    var streamed = MarkdownStream()
    streamed.append("See [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("  \"title\"\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func sealedReferenceDefinitionContinuationResolvesLaterReferences() throws {
    let markdown = """
    [ref]:
      https://example.com/reference

    See [later][ref].
    """

    var streamed = MarkdownStream()
    streamed.append("[ref]:\n  https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)
    streamed.append("See [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 2)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedShortcutReferenceLabelNamedXResolvesLikeWholeDocument() throws {
    let markdown = """
    See [x].

    [x]: https://example.com/x
    """

    var streamed = MarkdownStream()
    streamed.append("See [x].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[x]: https://example.com/x\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/x")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceAfterEscapedBacktickResolvesLikeWholeDocument() throws {
    let markdown = """
    Escaped backticks \\`[ref]\\` still leave a reference candidate.

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("Escaped backticks \\`[ref]\\` still leave a reference candidate.\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceAfterBlankLineInsideUnclosedCodeSpanResolvesLikeWholeDocument() throws {
    let markdown = """
    Literal code starts `

    [ref]
    `

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("Literal code starts `\n\n[ref]\n`\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(streamed.snapshot().blocks.flatMap(\.inlines).first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.flatMap(\.inlines).first { $0.kind == .link })
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceAfterUnclosedInlineCodeOpenerResolvesLikeWholeDocument() throws {
    let markdown = """
    Literal code starts `[ref]

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("Literal code starts `[ref]\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(streamed.snapshot().blocks.flatMap(\.inlines).first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.flatMap(\.inlines).first { $0.kind == .link })
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceInsideInvalidAutolinkSchemeResolvesLikeWholeDocument() throws {
    let markdown = """
    See <x:[ref]>.

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See <x:[ref]>.\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedMultilineShortcutReferenceLabelResolvesLikeWholeDocument() throws {
    let markdown = """
    See [multi
    line].

    [multi line]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [multi\nline].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[multi line]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let streamedLink = try #require(streamed.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedMultilineCollapsedReferenceLabelResolvesLikeWholeDocument() throws {
    let markdown = """
    See [multi
    line][].

    [multi line]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [multi\nline][].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[multi line]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let streamedLink = try #require(streamed.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedMultilineExplicitReferenceLabelResolvesLikeWholeDocument() throws {
    let markdown = """
    See [text][multi
    line].

    [multi line]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [text][multi\nline].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[multi line]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(streamed.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedLink.text == "text")
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedReferenceIgnoresFourSpaceIndentedCodeDefinitionLikeWholeDocument() throws {
    let markdown = """
    See [later][ref].

        [ref]: https://code.example

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("    [ref]: https://code.example\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedBlock = try #require(streamed.snapshot().blocks.first)
    let streamedLink = try #require(streamedBlock.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedBlock.isSealed)
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
private func streamedMalformedReferenceDefinitionDoesNotMaskLaterValidDefinition() throws {
    let markdown = """
    See [later][ref].

    [ref]: <https://example.com/broken

    [ref]: https://example.com/reference
    """

    var streamed = MarkdownStream()
    streamed.append("See [later][ref].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: <https://example.com/broken\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[ref]: https://example.com/reference\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLinks = streamed.snapshot().blocks.flatMap(\.inlines).filter { $0.kind == .link }
    let oneShotLinks = oneShot.snapshot().blocks.flatMap(\.inlines).filter { $0.kind == .link }
    #expect(streamedLinks.map(\.destination) == ["https://example.com/reference", "https://example.com/reference"])
    #expect(streamedLinks == oneShotLinks)
}

@Test
private func streamedNoDestinationReferenceDefinitionDoesNotBorrowSiblingDefinitionDestination() throws {
    let markdown = """
    See [later][a].

    [a]:
    [b]: https://example.com/b

    [a]: https://example.com/a
    """

    var streamed = MarkdownStream()
    streamed.append("See [later][a].\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[a]:\n[b]: https://example.com/b\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 0)
    streamed.append("[a]: https://example.com/a\n\n")
    #expect(streamed.diagnosticsCounters.sealedRegionParseCount == 1)

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLinks = streamed.snapshot().blocks.flatMap(\.inlines).filter { $0.kind == .link }
    let oneShotLinks = oneShot.snapshot().blocks.flatMap(\.inlines).filter { $0.kind == .link }
    #expect(streamedLinks.map(\.destination) == ["https://example.com/a", "https://example.com/a"])
    #expect(streamedLinks == oneShotLinks)
}

private func referenceDestinations(in blocks: [MarkdownBlock]) -> [String] {
    blocks.flatMap { block in
        referenceDestinations(in: block.inlines)
            + block.listItems.flatMap(referenceDestinations)
            + referenceDestinations(in: block.table)
    }
}

private func referenceDestinations(in item: MarkdownListItem) -> [String] {
    referenceDestinations(in: item.inlines) + item.childItems.flatMap(referenceDestinations)
}

private func referenceDestinations(in table: MarkdownTableBlock?) -> [String] {
    guard let table else {
        return []
    }

    return (table.header + table.rows.flatMap { $0 }).flatMap { cell in
        referenceDestinations(in: cell.inlines)
    }
}

private func referenceDestinations(in runs: [MarkdownInlineRun]) -> [String] {
    runs.compactMap(\.destination)
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
private func parserClassifiesOrderedTaskListFromASTCheckboxes() {
    var stream = MarkdownStream()
    stream.append("42. [x] first\n43. [ ] second")
    stream.finish()

    let block = stream.snapshot().blocks.first
    #expect(block?.kind == .taskList)
    #expect(block?.orderedListStart == 42)
    #expect(block?.listItems.map(\.taskState) == [.checked, .unchecked])
    #expect(block?.listItems.map { $0.inlines.map(\.text).joined() } == ["first", "second"])
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
private func parserClassifiesNestedOrderedTaskListMetadataFromASTCheckboxes() throws {
    var stream = MarkdownStream()
    stream.append("- parent\n  1. [x] child")
    stream.finish()

    let item = try #require(stream.snapshot().blocks.first?.listItems.first)
    #expect(item.childListKind == .taskList)
    #expect(item.childOrderedListStart == 1)
    #expect(item.childItems.first?.taskState == .checked)
}

@Test
private func parserDoesNotDropStructuredChildrenInsideBlockQuotesAndListItems() throws {
    var quoteStream = MarkdownStream()
    quoteStream.append("> before\n>\n> ```swift\n> let value = 1\n> ```")
    quoteStream.finish()

    let quote = try #require(quoteStream.snapshot().blocks.first)
    #expect(quote.kind == .blockQuote)
    #expect(quote.inlines.map(\.text).joined().contains("let value = 1"))
    #expect(quote.inlines.contains { $0.kind == .code })

    var listStream = MarkdownStream()
    listStream.append("- before\n\n  ```swift\n  let nested = 2\n  ```")
    listStream.finish()

    let item = try #require(listStream.snapshot().blocks.first?.listItems.first)
    #expect(item.inlines.map(\.text).joined().contains("let nested = 2"))
    #expect(item.inlines.contains { $0.kind == .code })
}

@Test
private func parserPreservesParagraphBreaksInsideLooseListItems() throws {
    var stream = MarkdownStream()
    stream.append("- first paragraph\n\n  second paragraph")
    stream.finish()

    let item = try #require(stream.snapshot().blocks.first?.listItems.first)
    #expect(item.inlines.map(\.text).joined() == "first paragraph\nsecond paragraph")
    #expect(item.inlines.contains { $0.kind == .hardBreak })
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

    // HTML blocks: CommonMark block tags terminate on blank lines; raw forms wait for explicit terminators.
    BoundaryCase(markdown: "<div>\n\ninside\n", shouldSeal: true),
    BoundaryCase(markdown: "<div>\ninside\n</div>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<DIV>\ndata\n</div>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<script>\nvar x;\n</script>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<style>\n\ninside\n", shouldSeal: false),
    BoundaryCase(markdown: "<style>\n*{color:red}\n</style>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<pre>\n\n<code>\n", shouldSeal: false),
    BoundaryCase(markdown: "<pre>\nhi\n</pre>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<table>\n<tr>\n", shouldSeal: false),
    BoundaryCase(markdown: "<table>\n<tr>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<table>\n<td></td>\n</table>\n\n", shouldSeal: true),
    BoundaryCase(markdown: "<section>\n\n", shouldSeal: true),
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
    PolicyCase(destination: "http://localhost", allowed: true),
    PolicyCase(destination: "http://[::1]", allowed: true),
    PolicyCase(destination: "mailto:user@example.com", allowed: true),
    PolicyCase(destination: "/relative/path", allowed: true),
    PolicyCase(destination: "relative/path", allowed: true),
    PolicyCase(destination: "#fragment", allowed: true),
    PolicyCase(destination: "//example.com/path", allowed: false),
    PolicyCase(destination: "http://", allowed: false),
    PolicyCase(destination: "https://", allowed: false),
    PolicyCase(destination: "http:example.com", allowed: false),
    PolicyCase(destination: "http://exa mple.com", allowed: false),
    PolicyCase(destination: "java\nscript:alert(1)", allowed: false),
    PolicyCase(destination: "javascript:alert(1)", allowed: false),
    PolicyCase(destination: "JaVaScRiPt:alert(1)", allowed: false),
    PolicyCase(destination: "java%0ascript:alert(1)", allowed: false),
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

final class SegmentRecordingMeasurer: InlineMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedKinds: [MarkdownInlineKind] = []

    var measurementCacheKey: String {
        "segment-recording"
    }

    func width(of text: String, fontSize: Double) -> Double {
        Double(text.utf8.count)
    }

    func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        lock.withLock {
            recordedKinds.append(segment.kind)
        }
        return Double(segment.text.utf8.count)
    }

    var kinds: [MarkdownInlineKind] {
        lock.withLock {
            recordedKinds
        }
    }
}

final class SegmentPresentationRecordingMeasurer: InlineMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSegments: [(text: String, presentation: MarkdownInlinePresentation)] = []

    var measurementCacheKey: String {
        "segment-presentation-recording"
    }

    func width(of text: String, fontSize: Double) -> Double {
        Double(text.utf8.count)
    }

    func width(of segment: PreparedInlineSegment, fontSize: Double) -> Double {
        lock.withLock {
            recordedSegments.append((segment.text, segment.presentation))
        }
        return Double(segment.text.utf8.count)
    }

    var segments: [(text: String, presentation: MarkdownInlinePresentation)] {
        lock.withLock {
            recordedSegments
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
    let measurer = CoreTextInlineMeasurer(fontName: "Helvetica")

    #expect(abs(measurer.width(of: "Hello SiriusMarkdown", fontSize: 16) - 154.72) < 0.5)
    #expect(abs(measurer.width(of: "🚀🚀 春天 emoji wrap", fontSize: 16) - 126.82) < 0.5)
    #expect(abs(measurer.width(of: "بدأت الرحلة ثم اكتملت", fontSize: 16) - 195.87) < 0.5)
    #endif
}

@Test
private func defaultCoreTextMeasurerUsesSystemProfileInsteadOfHelvetica() {
    let defaultMeasurer = CoreTextInlineMeasurer()
    let helveticaMeasurer = CoreTextInlineMeasurer(fontName: "Helvetica")

    #expect(defaultMeasurer.measurementCacheKey.contains("system"))
    #expect(defaultMeasurer.measurementCacheKey.contains("Helvetica") == false)
    #expect(defaultMeasurer.measurementCacheKey != helveticaMeasurer.measurementCacheKey)
}

@Test
private func fontProfilesProduceDistinctMeasurementCacheKeys() {
    let system = CoreTextInlineMeasurer()
    let helvetica = CoreTextInlineMeasurer(fontName: "Helvetica")
    let menlo = CoreTextInlineMeasurer(fontName: "Menlo")
    let mixed = CoreTextInlineMeasurer(
        profiles: MarkdownInlineFontProfiles(
            body: .system(),
            emphasis: .system(),
            strong: .system(weight: .bold),
            code: .monospacedSystem(),
            math: .monospacedSystem(weight: .semibold),
            imagePlaceholder: .system(weight: .medium)
        )
    )

    #expect(Set([
        system.measurementCacheKey,
        helvetica.measurementCacheKey,
        menlo.measurementCacheKey,
        mixed.measurementCacheKey
    ]).count == 4)
}

@Test
private func measuredInlineCacheIncludesMeasurementProfileIdentity() {
    let recorder = MarkdownDiagnosticsRecorder()
    var engine = InlineLayoutEngine(
        measurer: CoreTextInlineMeasurer(fontName: "Helvetica"),
        cacheCapacity: 8,
        diagnosticsRecorder: recorder
    )
    let range = MarkdownSourceRange(byteRange: 0..<11, lineRange: 1..<2)
    let prepared = PreparedInlineContent(
        runs: [.init(kind: .text, text: "hello world")],
        sourceRange: range
    )

    _ = engine.prepareMeasuredContent(prepared, fontSize: 16)
    let afterFirst = recorder.snapshot()
    _ = engine.prepareMeasuredContent(prepared, fontSize: 16)
    let afterSecond = recorder.snapshot()
    engine.walker.measurer = CoreTextInlineMeasurer(fontName: "Menlo")
    _ = engine.prepareMeasuredContent(prepared, fontSize: 16)
    let afterProfileChange = recorder.snapshot()

    #expect(afterFirst.prepareCount == 1)
    #expect(afterSecond.prepareCount == afterFirst.prepareCount)
    #expect(afterSecond.cacheHitCount == afterFirst.cacheHitCount + 1)
    #expect(afterProfileChange.prepareCount == afterFirst.prepareCount + 1)
}

@Test
private func variableWidthWalkerMeasuresSegmentsWithSemanticKinds() {
    let measurer = SegmentRecordingMeasurer()
    let walker = VariableWidthLineWalker(measurer: measurer)
    let prepared = PreparedInlineContent(
        runs: [
            .init(kind: .text, text: "body "),
            .init(kind: .strong, text: "strong"),
            .init(kind: .code, text: "code"),
            .init(kind: .math, text: "x^2"),
            .init(kind: .image, text: "diagram")
        ]
    )

    _ = walker.prepare(prepared, fontSize: 16)
    let kinds = Set(measurer.kinds)

    #expect(kinds.contains(.text))
    #expect(kinds.contains(.strong))
    #expect(kinds.contains(.code))
    #expect(kinds.contains(.math))
    #expect(kinds.contains(.image))
}

@Test
private func preparedInlineContentKeepsAtomicPresentationRunsAsSingleSegments() {
    let linkedCode = MarkdownInlineRun(
        kind: .link,
        text: "let value = 1",
        destination: "https://example.com/code",
        presentation: .code
    )
    let linkedMath = MarkdownInlineRun(
        kind: .link,
        text: "x + y",
        destination: "https://example.com/math",
        presentation: .math
    )

    let prepared = PreparedInlineContent(runs: [linkedCode, .init(kind: .text, text: " "), linkedMath])

    #expect(prepared.segments.count == 3)
    #expect(prepared.segments[0].text == "let value = 1")
    #expect(prepared.segments[0].presentation.contains(.code))
    #expect(prepared.segments[0].isBreakOpportunity == false)
    #expect(prepared.segments[2].text == "x + y")
    #expect(prepared.segments[2].presentation.contains(.math))
    #expect(prepared.segments[2].isBreakOpportunity == false)
}

@Test
private func overwideFallbackPreservesAtomicPresentationDuringUnitMeasurement() {
    let run = MarkdownInlineRun(
        kind: .link,
        text: "x + y",
        destination: "https://example.com/math",
        presentation: .math
    )
    let prepared = PreparedInlineContent(runs: [run])
    let measurer = SegmentPresentationRecordingMeasurer()
    let walker = VariableWidthLineWalker(measurer: measurer)
    let measured = walker.prepare(prepared, fontSize: 1)

    _ = walker.layout(
        measured,
        options: InlineLayoutOptions(containerWidth: 1, fontSize: 1, lineHeight: 2)
    )

    let unitMeasurements = measurer.segments.filter { $0.text.utf8.count == 1 }
    #expect(unitMeasurements.count >= 5)
    #expect(unitMeasurements.allSatisfy { $0.presentation.contains(.math) })
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
private func inlineSourceRangesRemainByteAccurateAfterMultibytePrefixes() throws {
    let markdown = "😀 [link](https://example.com) and \\(x^2\\)"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let link = try #require(block.inlines.first { $0.kind == .link })
    let linkRange = try #require(link.sourceRange)
    #expect(stream.markdown(in: linkRange) == "link")

    let math = try #require(block.inlines.first { $0.kind == .math })
    let mathRange = try #require(math.sourceRange)
    #expect(stream.markdown(in: mathRange) == "\\(x^2\\)")
}

@Test
private func bareHTTPSURLsBecomeLinkRunsWithByteAccurateSourceRanges() throws {
    let bareURL = "https://www.google.com/travel/flights?q=DTW%20to%20ORF%20one%20way%20Jun%2012%202026"
    let markdown = "Friday morning DTW -> Norfolk link:\n\(bareURL)\n\n"
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let link = try #require(block.inlines.first { $0.kind == .link })
    let linkRange = try #require(link.sourceRange)

    #expect(link.text == bareURL)
    #expect(link.destination == bareURL)
    #expect(stream.markdown(in: linkRange) == bareURL)
    #expect(block.inlines.contains { $0.kind == .softBreak })
}

@Test
private func bareURLLinkificationTrimsSentencePunctuationAndSkipsCode() throws {
    var stream = MarkdownStream()
    stream.append("Open https://example.com/path?q=1). Code `https://example.com/code` stays literal.")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first)
    let links = block.inlines.filter { $0.kind == .link }
    let code = try #require(block.inlines.first { $0.kind == .code })

    #expect(links.map(\.destination) == ["https://example.com/path?q=1"])
    #expect(links.map(\.text) == ["https://example.com/path?q=1"])
    #expect(code.text == "https://example.com/code")
}

@Test
private func tailInlineSourceRangesRemainByteAccurateAfterSealedReferencePrefix() throws {
    let definition = "[ref]: https://example.com/reference\n\n"
    let tail = "😀 Uses [linked text][ref] and \\(x^2\\).\n\n"

    var stream = MarkdownStream()
    stream.append(definition)
    #expect(stream.diagnosticsCounters.sealedRegionParseCount == 1)
    stream.append(tail)
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.text.contains("Uses") })
    let link = try #require(block.inlines.first { $0.kind == .link })
    let linkRange = try #require(link.sourceRange)
    #expect(link.destination == "https://example.com/reference")
    #expect(stream.markdown(in: linkRange) == "linked text")
    #expect(linkRange.byteRange.lowerBound >= definition.utf8.count)

    let math = try #require(block.inlines.first { $0.kind == .math })
    let mathRange = try #require(math.sourceRange)
    #expect(stream.markdown(in: mathRange) == "\\(x^2\\)")
    #expect(mathRange.byteRange.lowerBound >= definition.utf8.count)
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

private func utf8Range(of needle: String, in haystack: String) throws -> Range<Int> {
    let range = try #require(haystack.range(of: needle))
    let lower = haystack.utf8.distance(
        from: haystack.utf8.startIndex,
        to: range.lowerBound.samePosition(in: haystack.utf8) ?? haystack.utf8.startIndex
    )
    let upper = haystack.utf8.distance(
        from: haystack.utf8.startIndex,
        to: range.upperBound.samePosition(in: haystack.utf8) ?? haystack.utf8.endIndex
    )
    return lower..<upper
}
