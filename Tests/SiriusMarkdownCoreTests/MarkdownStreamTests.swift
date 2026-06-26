import Testing
@testable import SiriusMarkdownCore

@Test
func streamedParseMatchesStaticBlockText() {
    let markdown = "# Title\n\nParagraph one.\n\n- Item\n- Item two\n"

    var streamed = MarkdownStream()
    for chunk in ["# Title\n", "\nParagraph ", "one.\n\n", "- Item\n- Item two\n"] {
        streamed.append(chunk)
    }
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedSnapshot = streamed.snapshot()
    let oneShotSnapshot = oneShot.snapshot()
    let allBlocksSealed = streamedSnapshot.blocks.allSatisfy { $0.isSealed }

    #expect(streamedSnapshot.blocks.map(\.text) == oneShotSnapshot.blocks.map(\.text))
    #expect(allBlocksSealed)
}

@Test
func crlfStreamedParseMatchesStaticParse() {
    let markdown = [
        "# Title",
        "",
        "Paragraph one.",
        "",
        "1. Item",
        "",
        "",
        "```swift",
        "let x = 1",
        "```",
        "",
        "$$",
        "x^2",
        "$$",
        "",
        "<div>",
        "raw",
        "</div>",
        "",
    ].joined(separator: "\r\n")

    var streamed = MarkdownStream()
    for chunk in markdown.split(separator: "\r\n", omittingEmptySubsequences: false).map({ String($0) + "\r\n" }) {
        streamed.append(chunk)
    }
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedSnapshot = streamed.snapshot()
    let oneShotSnapshot = oneShot.snapshot()

    #expect(streamedSnapshot.blocks.map(\.kind) == oneShotSnapshot.blocks.map(\.kind))
    #expect(streamedSnapshot.blocks.map(\.text) == oneShotSnapshot.blocks.map(\.text))
    #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
}

@Test
func streamedTabDelimitedLooseListsMatchOneShotParse() {
    let cases = [
        ["-\tFirst\n\n", "-\tSecond\n\n"],
        ["1.\tFirst\n\n", "2.\tSecond\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        for chunk in chunks {
            streamed.append(chunk)
        }
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()

        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedLooseListsWithContinuationLinesMatchOneShotParse() {
    let cases = [
        ["- First\ncontinued\n\n", "- Second\n\n", "After.\n\n"],
        ["-\tFirst\n\tcontinued\n\n", "-\tSecond\n\n", "After.\n\n"],
        ["1. First\ncontinued\n\n", "2. Second\n\n", "After.\n\n"],
        ["1.\tFirst\n\tcontinued\n\n", "2.\tSecond\n\n", "After.\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        for chunk in chunks {
            streamed.append(chunk)
        }
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()

        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedListContainedBlocksWaitForIndentedContinuationAfterBlankLine() {
    let cases = [
        ["- ```swift\n  let x = 1\n  ```\n\n", "  After.\n\n"],
        ["- ~~~swift\n  let x = 1\n  ~~~\n\n", "  After.\n\n"],
        ["- $$\n  x^2\n  $$\n\n", "  After.\n\n"],
        ["- \\[\n  x^2\n  \\]\n\n", "  After.\n\n"],
        ["- <style>\n  body {}\n  </style>\n\n", "  After.\n\n"],
        [
            "- A | B\n  --- | ---\n  value | [ref]\n\n",
            "  [ref]: https://example.com/ref\n\n",
            "  After.\n\n"
        ],
        ["> - ~~~swift\n>   let x = 1\n>   ~~~\n>\n", ">   After.\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        for chunk in chunks {
            streamed.append(chunk)
        }
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()

        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedContainerDisplayMathWaitsForClosingFenceAfterBlankLine() throws {
    let cases = [
        ["> \\[\n> x^2\n\n", "> \\]\n\n"],
        ["- \\[\n  x^2\n\n", "  \\]\n\n"],
        ["> $$\n> x^2\n\n", "> $$\n\n"],
        ["- $$\n  x^2\n\n", "  $$\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        #expect(streamed.snapshot().blocks.contains { !$0.isSealed })

        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedContainerCodeFenceWaitsForClosingFenceAfterBlankLine() throws {
    let cases = [
        ["> ```swift\n> let x = 1\n\n", "> ```\n\n"],
        ["- ```swift\n  let x = 1\n\n", "  ```\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        #expect(streamed.snapshot().blocks.contains { !$0.isSealed })

        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func backtickFenceLineWithBacktickInfoSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("``` swift `\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.isSealed)
}

@Test
func streamedTopLevelFencesIgnoreContainerLookingContentClosers() throws {
    let cases = [
        ["```text\n> ```\n\n", "```\n\n"],
        ["```text\n- ```\n\n", "```\n\n"],
        ["$$\n> $$\n\n", "$$\n\n"],
        ["$$\n- $$\n\n", "$$\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        #expect(streamed.snapshot().blocks.contains { !$0.isSealed })

        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedContainerFencesIgnoreNestedContainerLookingContentClosers() throws {
    let cases = [
        ["> ```text\n> > ```\n\n", "> ```\n\n"],
        ["> ```text\n> - ```\n\n", "> ```\n\n"],
        ["- ```text\n  - ```\n\n", "  ```\n\n"],
        ["> $$\n> > $$\n\n", "> $$\n\n"],
        ["> $$\n> - $$\n\n", "> $$\n\n"],
        ["- $$\n  - $$\n\n", "  $$\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        #expect(streamed.snapshot().blocks.contains { !$0.isSealed })

        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedBracketDisplayMathFencesIgnoreContainerLookingContentClosers() throws {
    let cases = [
        ["\\[\n> \\]\n\n", "\\]\n\n"],
        ["\\[\n- \\]\n\n", "\\]\n\n"],
        ["> \\[\n> > \\]\n\n", "> \\]\n\n"],
        ["> \\[\n> - \\]\n\n", "> \\]\n\n"],
        ["- \\[\n  - \\]\n\n", "  \\]\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        #expect(streamed.snapshot().blocks.contains { !$0.isSealed })

        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func streamedContainerHTMLBlocksMatchOneShotWithNestedContainerLookingClosers() throws {
    let cases = [
        ["> <script>\n> > </script>\n\n", "> </script>\n\n"],
        ["> <script>\n> - </script>\n\n", "> </script>\n\n"],
        ["- <script>\n  - </script>\n\n", "  </script>\n\n"],
        ["> <!--\n> > -->\n\n", "> -->\n\n"],
        ["> <!--\n> - -->\n\n", "> -->\n\n"],
        ["- <!--\n  - -->\n\n", "  -->\n\n"]
    ]

    for chunks in cases {
        var streamed = MarkdownStream()
        streamed.append(chunks[0])
        streamed.append(chunks[1])
        streamed.finish()

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        let streamedSnapshot = streamed.snapshot()
        let oneShotSnapshot = oneShot.snapshot()
        #expect(blockSignature(streamedSnapshot.blocks) == blockSignature(oneShotSnapshot.blocks))
        #expect(streamedSnapshot.blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func activeTailKeepsStableBlockIDWhileAppending() {
    var stream = MarkdownStream()
    stream.append("A paragraph")
    let before = stream.snapshot().blocks.first?.id

    stream.append(" still active")
    let after = stream.snapshot().blocks.first?.id

    #expect(before == after)
}

@Test
func copiedStreamsDoNotShareBoundaryScanState() throws {
    var original = MarkdownStream()
    original.append("See [later][ref].\n\n")

    var copy = original
    copy.append("[ref]: https://example.com/copy\n\n")

    original.append("[ref]: https://example.com/original\n\n")

    let originalLink = try #require(original.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let copyLink = try #require(copy.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(originalLink.destination == "https://example.com/original")
    #expect(copyLink.destination == "https://example.com/copy")
}

@Test
func escapedDisplayMathDelimiterInProseSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("Literal array syntax a\\[i is not display math.\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.isSealed)
}

@Test
func lineStartingWithNonDelimiterBracketDisplayMathTextSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("\\[not a standalone display math opener\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.isSealed)
}

@Test
func fourSpaceIndentedMathOpenersSealAsCodeBlocks() throws {
    for markdown in ["    $$\n\n", "    \\[\n\n"] {
        var stream = MarkdownStream()
        stream.append(markdown)

        let block = try #require(stream.snapshot().blocks.first)
        #expect(block.kind == .codeBlock)
        #expect(block.isSealed)
    }
}

@Test
func fourSpaceIndentedHTMLOpenersSealAsCodeBlocks() throws {
    for markdown in ["    <script>\n\n", "    <div>\n\n", "    <!-- comment\n\n"] {
        var stream = MarkdownStream()
        stream.append(markdown)

        let block = try #require(stream.snapshot().blocks.first)
        #expect(block.kind == .codeBlock)
        #expect(block.isSealed)
    }
}

@Test
func blankLineTerminatedHTMLBlocksSealLikeOneShot() throws {
    let markdowns = [
        "<div>\n\n",
        "<div>\ninside\n\n",
        "<section>\n\n",
        "<table>\n<tr>\n\n"
    ]

    for markdown in markdowns {
        var stream = MarkdownStream()
        stream.append(markdown)

        var oneShot = MarkdownStream()
        oneShot.append(markdown)
        oneShot.finish()

        #expect(blockSignature(stream.snapshot().blocks) == blockSignature(oneShot.snapshot().blocks))
        #expect(stream.snapshot().blocks.allSatisfy { $0.isSealed })
    }
}

@Test
func blankLineTerminatedHTMLBlocksDoNotLeakDefinitionsAfterClosingTags() throws {
    let markdown = """
    <div>
    </div>
    [ref]: https://html.example

    Later [ref].
    """

    var stream = MarkdownStream()
    stream.append("<div>\n</div>\n[ref]: https://html.example\n\n")
    stream.append("Later [ref].\n\n")

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    #expect(blockSignature(stream.snapshot().blocks) == blockSignature(oneShot.snapshot().blocks))
}

@Test
func containerHTMLBlocksDoNotLeakDefinitionsIntoReferencePrefix() throws {
    let cases = [
        [
            "> <div>\n",
            "> [ref]: https://quote-html.example\n",
            ">\n\n",
            "Later [ref].\n\n"
        ],
        [
            "- <div>\n",
            "  [ref]: https://list-html.example\n",
            "\n",
            "Later [ref].\n\n"
        ]
    ]

    for chunks in cases {
        var stream = MarkdownStream()
        for chunk in chunks {
            stream.append(chunk)
        }

        var oneShot = MarkdownStream()
        oneShot.append(chunks.joined())
        oneShot.finish()

        #expect(blockSignature(stream.snapshot().blocks) == blockSignature(oneShot.snapshot().blocks))
        #expect(stream.snapshot().blocks.flatMap(\.inlines).compactMap(\.destination).isEmpty)
    }
}

@Test
func escapedReferenceLabelInProseSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("Escaped reference syntax \\[ref] is plain prose.\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.isSealed)
}

@Test
func inlineCodeReferenceSyntaxSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("Literal code `[ref]` is not a reference.\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.inlines.contains { $0.kind == .code && $0.text == "[ref]" })
    #expect(block.inlines.allSatisfy { $0.kind != .link })
    #expect(block.isSealed)
}

@Test
func multilineInlineCodeReferenceSyntaxSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("Literal code `\n[ref]\n` is still not a reference.\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .paragraph)
    #expect(block.inlines.contains { $0.kind == .code && $0.text.contains("[ref]") })
    #expect(block.inlines.allSatisfy { $0.kind != .link })
    #expect(block.isSealed)
}

@Test
func inlineLinkDestinationReferenceSyntaxSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("See [now](https://example.com/[ref]).\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    let link = try #require(block.inlines.first { $0.kind == .link })
    #expect(link.text == "now")
    #expect(link.destination == "https://example.com/[ref]")
    #expect(block.isSealed)
}

@Test
func nestedBracketInlineLinkLabelStaysMutableUntilReferencesAreKnown() throws {
    var stream = MarkdownStream()
    stream.append("See [[ref]](https://example.com).\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    let link = try #require(block.inlines.first { $0.kind == .link })
    #expect(link.text == "[ref]")
    #expect(link.destination == "https://example.com")
    #expect(!block.isSealed)
}

@Test
func checkedTaskListItemSealsAfterSecondBlankLineWithoutReferenceDefinition() throws {
    var stream = MarkdownStream()
    stream.append("- [x] done\n\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    #expect(block.kind == .taskList)
    #expect(block.listItems.first?.taskState == .checked)
    #expect(block.isSealed)
}

@Test
func inlineAngleReferenceSyntaxSealsAsNormalParagraph() throws {
    var stream = MarkdownStream()
    stream.append("See <https://example.com/[ref]>.\n\n")

    let block = try #require(stream.snapshot().blocks.first)
    let link = try #require(block.inlines.first { $0.kind == .link })
    #expect(link.destination == "https://example.com/[ref]")
    #expect(block.isSealed)
}

@Test
func inlineHTMLSpecialFormReferenceSyntaxSealsAsNormalParagraph() throws {
    let forms = [
        "See <?pi [ref]?>.\n\n",
        "See <!DECLARATION [ref]>.\n\n"
    ]

    for form in forms {
        var stream = MarkdownStream()
        stream.append(form)

        let block = try #require(stream.snapshot().blocks.first)
        #expect(block.kind == .paragraph)
        #expect(block.inlines.allSatisfy { $0.kind != .link })
        #expect(block.isSealed)
    }
}

@Test
func inlineCDATAReferenceSyntaxResolvesLikeWholeDocument() throws {
    let markdown = "See <![CDATA[[ref]]]>.\n\n[ref]: https://example.com/reference\n\n"

    var streamed = MarkdownStream()
    streamed.append("See <![CDATA[[ref]]]>.\n\n")
    #expect(streamed.snapshot().blocks.first?.isSealed == false)
    streamed.append("[ref]: https://example.com/reference\n\n")
    streamed.finish()

    var oneShot = MarkdownStream()
    oneShot.append(markdown)
    oneShot.finish()

    let streamedLink = try #require(streamed.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    let oneShotLink = try #require(oneShot.snapshot().blocks.first?.inlines.first { $0.kind == .link })
    #expect(streamedLink.destination == "https://example.com/reference")
    #expect(streamedLink == oneShotLink)
}

@Test
func hostBoundarySealsCurrentTail() {
    var stream = MarkdownStream()
    stream.append("Native insertion boundary")
    stream.appendHostBoundary(id: MarkdownHostBoundaryID("native-card-1"))

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.count == 1)
    #expect(snapshot.blocks[0].isSealed)
    #expect(snapshot.items.count == 2)
    #expect(snapshot.items.last == .hostBoundary(MarkdownHostBoundary(id: MarkdownHostBoundaryID("native-card-1"), sourceOffset: stream.sourceLength)))
}

@Test
func hostBoundariesAtSameOffsetPreserveAppendOrder() {
    var stream = MarkdownStream()
    stream.append("Before native insertions\n\n")
    stream.appendHostBoundary(id: MarkdownHostBoundaryID("first-native-card"))
    stream.appendHostBoundary(id: MarkdownHostBoundaryID("second-native-card"))

    let boundaries = stream.snapshot().items.compactMap { item -> MarkdownHostBoundaryID? in
        guard case let .hostBoundary(boundary) = item else {
            return nil
        }
        return boundary.id
    }

    #expect(boundaries == [
        MarkdownHostBoundaryID("first-native-card"),
        MarkdownHostBoundaryID("second-native-card")
    ])
}

@Test
func manyHostBoundariesRemainOrderedInSnapshotItems() {
    var stream = MarkdownStream()
    let expectedIDs = (0..<512).map { MarkdownHostBoundaryID("native-card-\($0)") }

    for (index, id) in expectedIDs.enumerated() {
        stream.append("Paragraph \(index)\n\n")
        stream.appendHostBoundary(id: id)
    }

    let snapshot = stream.snapshot()
    let actualIDs = snapshot.items.compactMap { item -> MarkdownHostBoundaryID? in
        guard case let .hostBoundary(boundary) = item else {
            return nil
        }
        return boundary.id
    }

    #expect(snapshot.items.count == snapshot.blocks.count + expectedIDs.count)
    #expect(actualIDs == expectedIDs)
}

@Test
func hostBoundaryPreservesSealedReferenceDefinitionsForLaterTail() {
    let definitions = [
        "[ref]: https://example.com/reference\n\n",
        "[ref]: <https://example.com/reference>\n\n",
        "[ref]: <https://example.com/with space>\n\n",
        "[ref]: <https://example.com/with\ttab>\n\n",
        "[ref]: <https://example.com/escaped\\>angle>\n\n",
        "[ref]: <>\n\n",
        "[ref]: https://example.com/escaped\\ space\n\n",
        "[ref]: https://example.com/escaped\\\ttab\n\n",
        "[ref]: https://example.com/escaped\\(paren\\)\n\n",
        "[ref]: https://example.com/reference \"title\"\n\n",
        "[ref]: https://example.com/reference\n \"title\"\n\n",
        "[ref]: https://example.com/reference\n  not a title\n\n"
    ]

    for definition in definitions {
        let laterReference = "Later [ref]."

        var oneShot = MarkdownStream()
        oneShot.append(definition + laterReference)
        oneShot.finish()

        var streamed = MarkdownStream()
        streamed.append(definition)
        streamed.appendHostBoundary(id: MarkdownHostBoundaryID("native-card"))
        streamed.append(laterReference)
        streamed.finish()

        let oneShotDestinations = oneShot.snapshot().blocks.flatMap(\.inlines).compactMap(\.destination)
        let streamedSnapshot = streamed.snapshot()
        let streamedDestinations = streamedSnapshot.blocks.flatMap(\.inlines).compactMap(\.destination)

        #expect(streamedDestinations == oneShotDestinations, "Definition did not survive host boundary: \(definition)")
        #expect(
            blockSignature(streamedSnapshot.blocks) == blockSignature(oneShot.snapshot().blocks),
            "Streamed host-boundary blocks diverged from one-shot parse: \(definition)"
        )
    }
}

private func blockSignature(_ blocks: [MarkdownBlock]) -> [String] {
    blocks.map { block in
        let inlineSignature = block.inlines
            .map { "\($0.kind.rawValue):\($0.text):\($0.destination ?? "")" }
            .joined(separator: "|")
        return "\(block.kind.rawValue):\(block.text):\(inlineSignature)"
    }
}
