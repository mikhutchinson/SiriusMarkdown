import Testing
@testable import SiriusMarkdownCore

@Test
func scannerDoesNotSealOpenCodeFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```swift\nlet x = 1\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenBlockQuoteCodeFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("> ```swift\n> let x = 1\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenListCodeFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("- ```swift\n  let x = 1\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsClosedContainerCodeFences() {
    let scanner = MarkdownBoundaryScanner()

    var quote = MarkdownSourceBuffer()
    quote.append("> ```swift\n> let x = 1\n> ```\n\n")
    #expect(scanner.safeSealUpperBound(in: quote, after: 0) == quote.byteCount)

    var list = MarkdownSourceBuffer()
    list.append("- ```swift\n  let x = 1\n  ```\n\n")
    #expect(scanner.safeSealUpperBound(in: list, after: 0) == nil)
    list.append("\n")
    #expect(scanner.safeSealUpperBound(in: list, after: 0) == list.byteCount)
}

@Test
func scannerDoesNotCloseContainerCodeFenceWithNestedContainerLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "> ```text\n> > ```\n\n",
        "> ```text\n> - ```\n\n",
        "- ```text\n  - ```\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerDoesNotCloseTopLevelCodeFenceWithContainerLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "```text\n> ```\n\n",
        "```text\n- ```\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerSealsAfterClosedFenceAndBlankLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```swift\nlet x = 1\n```\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsBacktickFenceLineWithBacktickInfoAsParagraph() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("``` swift `\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerTreatsCRLFBlankLinesLikeLF() {
    let scanner = MarkdownBoundaryScanner()

    var paragraph = MarkdownSourceBuffer()
    paragraph.append("alpha\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: paragraph, after: 0) == paragraph.byteCount)

    var looseList = MarkdownSourceBuffer()
    looseList.append("1. item\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == nil)
    looseList.append("\r\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == looseList.byteCount)
}

@Test
func scannerTreatsParenOrderedListsAsListLike() {
    let scanner = MarkdownBoundaryScanner()

    var looseList = MarkdownSourceBuffer()
    looseList.append("1) item\n\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == nil)
    looseList.append("\n")
    #expect(scanner.safeSealUpperBound(in: looseList, after: 0) == looseList.byteCount)
}

@Test
func scannerTreatsCRLFFencesMathAndHTMLLikeLF() {
    let scanner = MarkdownBoundaryScanner()

    var code = MarkdownSourceBuffer()
    code.append("```swift\r\nlet x = 1\r\n```\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: code, after: 0) == code.byteCount)

    var math = MarkdownSourceBuffer()
    math.append("$$\r\nx^2\r\n$$\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: math, after: 0) == math.byteCount)

    var html = MarkdownSourceBuffer()
    html.append("<div>\r\nraw\r\n</div>\r\n\r\n")
    #expect(scanner.safeSealUpperBound(in: html, after: 0) == html.byteCount)
}

@Test
func scannerKeepsNonTagHTMLBlocksOpenAcrossBlankLines() {
    let scanner = MarkdownBoundaryScanner()

    var processingInstruction = MarkdownSourceBuffer()
    processingInstruction.append("<?instruction\n\n")
    #expect(scanner.safeSealUpperBound(in: processingInstruction, after: 0) == nil)
    processingInstruction.append("?>\n\n")
    #expect(scanner.safeSealUpperBound(in: processingInstruction, after: 0) == processingInstruction.byteCount)

    var declaration = MarkdownSourceBuffer()
    declaration.append("<!DOCTYPE html\n\n")
    #expect(scanner.safeSealUpperBound(in: declaration, after: 0) == nil)
    declaration.append(">\n\n")
    #expect(scanner.safeSealUpperBound(in: declaration, after: 0) == declaration.byteCount)

    var cdata = MarkdownSourceBuffer()
    cdata.append("<![CDATA[\nraw\n\n")
    #expect(scanner.safeSealUpperBound(in: cdata, after: 0) == nil)
    cdata.append("]]>\n\n")
    #expect(scanner.safeSealUpperBound(in: cdata, after: 0) == cdata.byteCount)
}

@Test
func scannerDoesNotCloseListProjectedHTMLBlockWithNestedListLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "- <script>\n  - </script>\n\n",
        "- <!--\n  - -->\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerKeepsReferenceLinkCandidatesMutableUntilFinish() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][ref].\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsShortcutReferenceLabelNamedXMutableUntilDefinition() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [x].\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsCheckedTaskListMarkerAfterSecondBlankLine() {
    let cases = [
        "- [x] done\n\n\n",
        "- [X] done\n\n\n",
        "1. [x] done\n\n\n",
        "> - [x] done\n\n\n",
        "- > - [x] done\n\n\n"
    ]

    for markdown in cases {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)

        let scanner = MarkdownBoundaryScanner()
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerKeepsProjectedNonTaskXReferenceMutableUntilDefinition() {
    let cases = [
        "- [x][ref]\n\n\n",
        "> [x] quote reference\n\n\n",
        "- > [x] quote reference\n\n\n"
    ]

    for markdown in cases {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)

        let scanner = MarkdownBoundaryScanner()
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerSealsEscapedReferenceLabelInProse() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Escaped reference syntax \\[ref] is plain prose.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsReferenceLikeTextInsideInlineCodeSpan() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal code `[ref]` is not a reference.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsReferenceLikeTextInsideMultilineInlineCodeSpan() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal code `\n[ref]\n` is still not a reference.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotCarryOpenInlineCodeSpanAcrossBlankLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal code starts `\n\n[ref]\n`\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsReferenceAfterUnclosedInlineCodeOpenerMutableUntilDefinition() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal code starts `[ref]\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsReferenceAfterEscapedBacktickMutableUntilDefinition() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Escaped backticks \\`[ref]\\` still leave a reference candidate.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsLiteralUnmatchedBracketAfterParagraphBoundary() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal [ bracket in normal prose.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerRecoversLiteralUnmatchedBracketAcrossIncrementalScans() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal [ bracket in normal prose.\n")

    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("\nNext paragraph can seal too.\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerStillSealsInlineLinksAndReferenceDefinitions() {
    let scanner = MarkdownBoundaryScanner()

    var inline = MarkdownSourceBuffer()
    inline.append("See [now](https://example.com).\n\n")
    #expect(scanner.safeSealUpperBound(in: inline, after: 0) == inline.byteCount)

    var definition = MarkdownSourceBuffer()
    definition.append("[ref]: https://example.com\n\n")
    #expect(scanner.safeSealUpperBound(in: definition, after: 0) == definition.byteCount)
}

@Test
func scannerSealsReferenceLikeTextInsideInlineLinkDestinationAndTitle() {
    let scanner = MarkdownBoundaryScanner()

    var destination = MarkdownSourceBuffer()
    destination.append("See [now](https://example.com/[ref]).\n\n")
    #expect(scanner.safeSealUpperBound(in: destination, after: 0) == destination.byteCount)

    var title = MarkdownSourceBuffer()
    title.append("See [now](https://example.com \"title [ref]\").\n\n")
    #expect(scanner.safeSealUpperBound(in: title, after: 0) == title.byteCount)

    var parentheticalTitle = MarkdownSourceBuffer()
    parentheticalTitle.append("See [now](https://example.com (title [ref])).\n\n")
    #expect(scanner.safeSealUpperBound(in: parentheticalTitle, after: 0) == parentheticalTitle.byteCount)
}

@Test
func scannerKeepsNestedBracketInlineLinkLabelMutableUntilReferencesAreKnown() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [[ref]](https://example.com).\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsReferenceLikeTextInsideInlineAngleConstructs() {
    let scanner = MarkdownBoundaryScanner()

    var autolink = MarkdownSourceBuffer()
    autolink.append("See <https://example.com/[ref]>.\n\n")
    #expect(scanner.safeSealUpperBound(in: autolink, after: 0) == autolink.byteCount)

    var inlineHTML = MarkdownSourceBuffer()
    inlineHTML.append("<span data-label=\"[ref]\">text</span>\n\n")
    #expect(scanner.safeSealUpperBound(in: inlineHTML, after: 0) == inlineHTML.byteCount)
}

@Test
func scannerSealsReferenceLikeTextInsideInlineHTMLSpecialForms() {
    let scanner = MarkdownBoundaryScanner()
    let forms = [
        "See <?pi [ref]?>.\n\n",
        "See <!DECLARATION [ref]>.\n\n"
    ]

    for form in forms {
        var buffer = MarkdownSourceBuffer()
        buffer.append(form)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerKeepsReferenceLikeTextInsideInlineCDATAConstructMutable() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See <![CDATA[[ref]]]>.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsReferenceLikeTextInsideMalformedInlineAngleConstructMutable() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See <https://example.com/[ref].\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsReferenceLikeTextInsidePlainAngleProseMutable() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See < value [ref] >.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsReferenceLikeTextInsideInvalidAutolinkSchemeMutable() {
    let scanner = MarkdownBoundaryScanner()

    var tooShortScheme = MarkdownSourceBuffer()
    tooShortScheme.append("See <x:[ref]>.\n\n")
    #expect(scanner.safeSealUpperBound(in: tooShortScheme, after: 0) == nil)

    var tooLongScheme = MarkdownSourceBuffer()
    tooLongScheme.append("See <abcdefghijklmnopqrstuvwxyzabcdefg:[ref]>.\n\n")
    #expect(scanner.safeSealUpperBound(in: tooLongScheme, after: 0) == nil)
}

@Test
func scannerKeepsReferenceLikeTextInsideMalformedInlineLinkMutable() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [now](broken [ref]).\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerKeepsMultilineShortcutAndCollapsedReferenceLabelsMutable() {
    let cases = [
        "See [multi\nline].\n\n",
        "See [multi\nline][].\n\n",
        "See [text][multi\nline].\n\n"
    ]

    for markdown in cases {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)

        let scanner = MarkdownBoundaryScanner()
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil, "Unsafe seal for \(markdown)")
    }
}

@Test
func scannerSealsReferenceCandidateAfterMatchingDefinitionArrives() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][ref].\n\n")
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("[ref]: https://example.com\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerKeepsReferenceDefinitionOpenUntilContinuationBlank() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][ref].\n\n")
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("[ref]:\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("  https://example.com/reference\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerAcceptsTabIndentedReferenceDefinitionContinuation() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][ref].\n\n")
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("[ref]:\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("\thttps://example.com/reference\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerAcceptsContainerReferenceDefinitions() {
    let cases = [
        "> [ref]: https://example.com/quote\n\n",
        "> [ref]:\n>   https://example.com/quote-continuation\n\n",
        "- [ref]: https://example.com/list\n\n",
        "- [ref]:\n  https://example.com/list-continuation\n\n",
        "1. [ref]: https://example.com/ordered-list\n\n",
        "> - [ref]: https://example.com/quote-list\n\n",
        "- > [ref]: https://example.com/list-quote\n\n",
        "  - [ref]: https://example.com/indented-list\n\n",
        "- [ref]:\n    https://example.com/list-four-space-continuation\n\n",
        "1. [ref]:\n   https://example.com/ordered-list-continuation\n\n",
        "> - [ref]:\n>   https://example.com/quote-list-continuation\n\n",
        "- > [ref]:\n  >   https://example.com/list-quote-continuation\n\n"
    ]

    for definition in cases {
        let scanner = MarkdownBoundaryScanner()
        var state = MarkdownBoundaryScanState()
        var buffer = MarkdownSourceBuffer()
        buffer.append("See [later][ref].\n\n")
        var result = scanner.scan(in: buffer, state: &state)
        #expect(result.safeUpperBound == nil)

        buffer.append(definition)
        result = scanner.scan(in: buffer, state: &state)
        if referenceDefinitionMayHaveListContinuation(definition) {
            #expect(result.safeUpperBound != buffer.byteCount, "List-contained definition sealed too early: \(definition)")
            buffer.append("\n")
            result = scanner.scan(in: buffer, state: &state)
            #expect(result.safeUpperBound == buffer.byteCount, "Did not seal after extra blank for list definition: \(definition)")
        } else {
            #expect(result.safeUpperBound == buffer.byteCount, "Did not seal after container definition: \(definition)")
        }
    }
}

@Test
func scannerAcceptsMultilineReferenceDefinitionLabels() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][multi line].\n\n")
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("[multi\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("line]: https://example.com/reference\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerDoesNotTreatFourSpaceIndentedReferenceLikeDefinition() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()
    buffer.append("See [later][ref].\n\n")
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("    [ref]: https://code.example\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)
}

@Test
func scannerDoesNotSealOpenMathFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\nx^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenDisplayMathBracketFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\[\nx^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenBlockQuoteDisplayMathBracketFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("> \\[\n> x^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenListDisplayMathBracketFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("- \\[\n  x^2\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealOpenContainerDollarMathFence() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "> $$\n> x^2\n\n",
        "- $$\n  x^2\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerSealsFourSpaceIndentedMathOpenersAsCodeBlocks() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "    $$\n\n",
        "    \\[\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerSealsClosedContainerDisplayMathFences() {
    let scanner = MarkdownBoundaryScanner()

    for markdown in ["> \\[\n> x^2\n> \\]\n\n", "> $$\n> x^2\n> $$\n\n"] {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }

    for markdown in ["- \\[\n  x^2\n  \\]\n\n", "- $$\n  x^2\n  $$\n\n"] {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
        buffer.append("\n")
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerDoesNotCloseBracketDisplayMathFenceWithContainerLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "\\[\n> \\]\n\n",
        "\\[\n- \\]\n\n",
        "> \\[\n> > \\]\n\n",
        "> \\[\n> - \\]\n\n",
        "- \\[\n  - \\]\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerDoesNotCloseContainerDollarMathFenceWithNestedContainerLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "> $$\n> > $$\n\n",
        "> $$\n> - $$\n\n",
        "- $$\n  - $$\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerDoesNotCloseTopLevelDollarMathFenceWithContainerLookingContent() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "$$\n> $$\n\n",
        "$$\n- $$\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
    }
}

@Test
func scannerSealsEscapedDisplayMathDelimiterInProse() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("Literal array syntax a\\[i is not display math.\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsLineStartingWithNonDelimiterBracketDisplayMathText() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("\\[not a standalone display math opener\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerPreservesOpenFenceAcrossIncrementalScansUntilCloseLine() {
    let scanner = MarkdownBoundaryScanner()

    var buffer = MarkdownSourceBuffer()
    buffer.append("```\npartial\n")

    var state = MarkdownBoundaryScanState()
    var result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer.append("\n````\n\n")
    result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
}

@Test
func scannerTreatsInsufficientClosingBackticksAsInsideFenceStill() {
    var buffer = MarkdownSourceBuffer()
    buffer.append(String(repeating: "`", count: 5))
    buffer.append("\nhi\n")
    buffer.append(String(repeating: "`", count: 4))
    buffer.append("\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotCloseFenceWhenClosingMarkerHasTrailingText() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```\n")
    buffer.append("code before fake closer\n")
    buffer.append("``` not a closer\n")
    buffer.append("\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)

    buffer.append("```\n\n")
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotCloseFenceWithIndentedMarkerContent() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("```\n")
    buffer.append("code before indented marker\n")
    buffer.append("    ```\n")
    buffer.append("\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)

    buffer.append("```\n\n")
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerDoesNotCloseTildeFenceWithBacktickCloser() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("~~~\nbody\n")
    buffer.append(String(repeating: "`", count: 4))
    buffer.append("\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerDoesNotSealMathFenceUntilClosingLineEqualsDollarFence() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\n$x $y$\nstill")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsSmallMathFenceWhenCloserIsOwnLine() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("$$\n$$\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerKeepsCommentOpenAcrossInnerBlankLines() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("<!-- intro\n\nbody\nstill open\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == nil)
}

@Test
func scannerSealsAfterScriptBlockCloserEvenWithIndentedContent() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("<script>\n  console.log(1);\n</script>\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsBlankLineTerminatedHTMLBlocksOnBlankLine() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "<div>\n\n",
        "<div>\ninside\n\n",
        "<section>\n\n",
        "<table>\n<tr>\n\n",
        "> <section>\n>\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerDoesNotCloseBlankLineTerminatedHTMLBlocksOnClosingTag() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("<div>\n</div>\n[ref]: https://html.example\n\n")

    let scanner = MarkdownBoundaryScanner()
    #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
}

@Test
func scannerSealsFourSpaceIndentedHTMLOpenersAsCodeBlocks() {
    let scanner = MarkdownBoundaryScanner()
    let markdowns = [
        "    <script>\n\n",
        "    <div>\n\n",
        "    <!-- comment\n\n"
    ]

    for markdown in markdowns {
        var buffer = MarkdownSourceBuffer()
        buffer.append(markdown)
        #expect(scanner.safeSealUpperBound(in: buffer, after: 0) == buffer.byteCount)
    }
}

@Test
func scannerDeferSealAfterSingleBlankFollowingOrderedListMarker() {
    let scanner = MarkdownBoundaryScanner()

    var state = MarkdownBoundaryScanState()
    var buffer2 = MarkdownSourceBuffer()
    buffer2.append("1. outer\n\n")
    var result = scanner.scan(in: buffer2, state: &state)
    #expect(result.safeUpperBound == nil)

    buffer2.append("\n")
    result = scanner.scan(in: buffer2, state: &state)
    #expect(result.safeUpperBound == buffer2.byteCount)
}

@Test
func scannerUpdatesSealCandidateAcrossMultipleParagraphSeparatorsInOneScan() {
    var buffer = MarkdownSourceBuffer()
    buffer.append("alpha\n\nbeta\n\n")

    let scanner = MarkdownBoundaryScanner()
    let seal = scanner.safeSealUpperBound(in: buffer, after: 0)
    #expect(seal == buffer.byteCount)
}

@Test
func scannerDoesNotRescanIncompleteLongLineBeforeNewline() {
    let scanner = MarkdownBoundaryScanner()
    var state = MarkdownBoundaryScanState()
    var buffer = MarkdownSourceBuffer()

    for _ in 0..<1_000 {
        buffer.append("a")
        let result = scanner.scan(in: buffer, state: &state)
        #expect(result.safeUpperBound == nil)
        #expect(result.scannedByteCount == 0)
        #expect(result.scannedLineCount == 0)
    }

    buffer.append("\n\n")
    let result = scanner.scan(in: buffer, state: &state)
    #expect(result.safeUpperBound == buffer.byteCount)
    #expect(result.scannedLineCount == 2)
    #expect(result.scannedByteCount == buffer.byteCount)
}

private func referenceDefinitionMayHaveListContinuation(_ definition: String) -> Bool {
    var line = definition.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""

    while true {
        line = String(line.drop { $0 == " " })
        if line.hasPrefix(">") {
            line = String(line.dropFirst())
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                line = String(line.dropFirst())
            }
            continue
        }

        return startsListMarker(line)
    }
}

private func startsListMarker(_ line: String) -> Bool {
    guard let first = line.first else {
        return false
    }

    if first == "-" || first == "+" || first == "*" {
        let afterMarker = line.index(after: line.startIndex)
        return afterMarker < line.endIndex &&
            (line[afterMarker] == " " || line[afterMarker] == "\t")
    }

    var cursor = line.startIndex
    var sawDigit = false
    while cursor < line.endIndex, line[cursor].isNumber {
        sawDigit = true
        cursor = line.index(after: cursor)
    }

    guard sawDigit,
          cursor < line.endIndex,
          line[cursor] == "." || line[cursor] == ")"
    else {
        return false
    }

    let afterMarker = line.index(after: cursor)
    return afterMarker < line.endIndex &&
        (line[afterMarker] == " " || line[afterMarker] == "\t")
}
