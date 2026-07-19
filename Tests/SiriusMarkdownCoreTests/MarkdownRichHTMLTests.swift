import Testing
@testable import SiriusMarkdownCore

@Test
func blockHTMLIsConvertedIntoNativeSemanticBlocks() throws {
    let markdown = """
    <div>
      <h2>Welcome <em>friend</em></h2>
      <p>Visit <a href="https://example.com"><strong>Example</strong></a><br>Now H<sub>2</sub>O</p>
      <ul><li>First</li><li>Second</li></ul>
      <script>alert("unsafe")</script>
    </div>
    """

    let outer = try #require(parse(markdown).first)
    #expect(outer.kind == .htmlBlock)
    let rich = try #require(outer.richContent)
    #expect(rich.blocks.map(\.kind) == [.heading, .paragraph, .unorderedList])
    #expect(rich.blocks.map(\.text).joined(separator: " ").contains("unsafe") == false)
    #expect(rich.diagnostics.droppedNodeCount == 1)

    let heading = try #require(rich.blocks.first)
    #expect(heading.headingLevel == 2)
    #expect(heading.inlines.first { $0.text == "friend" }?.presentation.contains(.emphasis) == true)

    let paragraph = try #require(rich.blocks.dropFirst().first)
    let link = try #require(paragraph.inlines.first { $0.text == "Example" })
    #expect(link.kind == .link)
    #expect(link.destination == "https://example.com")
    #expect(link.presentation.contains(.strong))
    #expect(paragraph.inlines.contains { $0.kind == .hardBreak })
    #expect(paragraph.inlines.first { $0.text == "2" }?.presentation.contains(.subscriptText) == true)

    let list = try #require(rich.blocks.last)
    #expect(list.listItems.map(\.text) == ["First", "Second"])
}

@Test
func inlineHTMLAnchorsShareNativeMarkdownLinkRuns() throws {
    let block = try #require(parse(
        "Before <a href=\"https://example.com/docs\"><strong>Example docs</strong></a> after"
    ).first)

    #expect(block.inlines.map(\.text).joined() == "Before Example docs after")
    #expect(block.inlines.contains { $0.presentation.contains(.html) } == false)
    let link = try #require(block.inlines.first { $0.text == "Example docs" })
    #expect(link.kind == .link)
    #expect(link.destination == "https://example.com/docs")
    #expect(link.presentation.contains(.strong))
}

@Test
func malformedInlineHTMLUsesHTML5RecoveryWithoutLeakingTags() throws {
    let block = try #require(parse(
        "<a href=\"https://example.com\"><strong>one</a> two</strong>"
    ).first)

    #expect(block.inlines.contains { $0.presentation.contains(.html) } == false)
    #expect(block.inlines.map(\.text).joined() == "one two")
    let one = try #require(block.inlines.first { $0.text == "one" })
    #expect(one.kind == .link)
    #expect(one.destination == "https://example.com")
    #expect(one.presentation.contains(.strong))
}

@Test
func activeInlineHTMLSubtreesAreDropped() throws {
    let block = try #require(parse(
        "Safe <script>alert('unsafe')</script> content <iframe src=\"https://example.com\">hidden</iframe> end"
    ).first)

    let visibleText = block.inlines.map(\.text).joined()
    #expect(visibleText.contains("unsafe") == false)
    #expect(visibleText.contains("hidden") == false)
    #expect(visibleText == "Safe  content  end")
}

@Test
func emptyCommentsAndActiveOnlyHTMLRenderNoRawMarkup() throws {
    for source in [
        "<!-- private implementation note -->",
        "<div></div>",
        "<script>alert('unsafe')</script>"
    ] {
        let block = try #require(parse(source).first)
        #expect(block.richContent?.blocks.isEmpty == true)
    }
}

@Test
func unsafeHTMLDestinationsRemainGovernedByNormalLinkPolicy() throws {
    let outer = try #require(parse(
        "<p><a href=\"javascript:alert(1)\">Unsafe</a> <a href=\"https://example.com\">Safe</a></p>"
    ).first)
    let runs = try #require(outer.richContent?.blocks.first?.inlines)
    let unsafe = try #require(runs.first { $0.text == "Unsafe" })
    let safe = try #require(runs.first { $0.text == "Safe" })
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: try #require(unsafe.destination)) != .allow)
    #expect(policy.evaluateLink(destination: try #require(safe.destination)) == .allow)
}

@Test
func HTMLImagesBecomePolicyGovernedNativeImageRuns() throws {
    let outer = try #require(parse(
        "<div><img src=\"https://example.com/image.png\" alt=\"Example\" onerror=\"alert(1)\"></div>"
    ).first)
    let image = try #require(outer.richContent?.blocks.first?.inlines.first)

    #expect(image.kind == .image)
    #expect(image.imageSource == "https://example.com/image.png")
    #expect(image.text == "Example")
    #expect(image.presentation.contains(.image))
}

@Test
func structuredHTMLPreservesNativeQuoteCodeTableAndListMetadata() throws {
    let source = """
    <article>
      <blockquote><p>Quoted <code>value</code></p></blockquote>
      <pre><code class="language-swift">let value = 1</code></pre>
      <ol start="4"><li>Fourth</li><li>Fifth</li></ol>
      <table><thead><tr><th align="right">Name</th><th>Value</th></tr></thead>
      <tbody><tr><td colspan="2" rowspan="2">Combined</td></tr></tbody></table>
    </article>
    """
    let outer = try #require(parse(source).first)
    let blocks = try #require(outer.richContent?.blocks)

    #expect(blocks.map(\.kind) == [.blockQuote, .codeBlock, .orderedList, .table])
    #expect(blocks[0].inlines.first { $0.text == "value" }?.presentation.contains(.code) == true)
    #expect(blocks[1].infoString == "swift")
    #expect(blocks[1].text == "let value = 1")
    #expect(blocks[2].orderedListStart == 4)
    #expect(blocks[2].listItems.map(\.text) == ["Fourth", "Fifth"])
    let table = try #require(blocks[3].table)
    #expect(table.columnAlignments.first == .right)
    #expect(table.rows.first?.first?.colspan == 2)
    #expect(table.rows.first?.first?.rowspan == 2)
}

@Test
func HTMLSourceMappingRetainsRawEntityRangesWhileRenderingDecodedText() throws {
    let source = "<p>Fish &amp; Chips &copy; 2026</p>"
    let outer = try #require(parse(source).first)
    let run = try #require(outer.richContent?.blocks.first?.inlines.first)
    let range = try #require(run.sourceRange?.byteRange)
    let lower = source.utf8.index(source.utf8.startIndex, offsetBy: range.lowerBound)
    let upper = source.utf8.index(source.utf8.startIndex, offsetBy: range.upperBound)

    #expect(run.text == "Fish & Chips © 2026")
    #expect(String(decoding: source.utf8[lower..<upper], as: UTF8.self) == "Fish &amp; Chips &copy; 2026")
}

@Test
func HTMLSourceMappingIsMonotonicAcrossRepeatedEntityTextAndQuotedMarkup() throws {
    let source = "<div data-note='1 > 0'><p>Same &copy;</p><!-- hidden --><p>Same &copy;</p></div>"
    let blocks = try #require(parse(source).first?.richContent?.blocks)
    #expect(blocks.count == 2)
    let ranges = try blocks.map { block in
        try #require(block.inlines.first?.sourceRange?.byteRange)
    }
    let bytes = Array(source.utf8)

    #expect(ranges[0].upperBound < ranges[1].lowerBound)
    #expect(String(decoding: bytes[ranges[0]], as: UTF8.self) == "Same &copy;")
    #expect(String(decoding: bytes[ranges[1]], as: UTF8.self) == "Same &copy;")
    #expect(blocks.map(\.text) == ["Same ©", "Same ©"])
}

@Test
func HTMLLeafElementRangesPreserveAuthoredTagBytes() throws {
    let source = "<p>A<BR data-note='1 > 0'/>B<img src='image.png' alt='Icon'>C</p>"
    let runs = try #require(parse(source).first?.richContent?.blocks.first?.inlines)
    let hardBreak = try #require(runs.first { $0.kind == .hardBreak })
    let image = try #require(runs.first { $0.presentation.contains(.image) })
    let bytes = Array(source.utf8)
    let breakRange = try #require(hardBreak.sourceRange?.byteRange)
    let imageRange = try #require(image.sourceRange?.byteRange)

    #expect(String(decoding: bytes[breakRange], as: UTF8.self) == "<BR data-note='1 > 0'/>")
    #expect(String(decoding: bytes[imageRange], as: UTF8.self) == "<img src='image.png' alt='Icon'>")
}

@Test
func streamedRichHTMLMatchesOneShotAcrossManyChunkSizes() throws {
    let source = """
    <section><h3>Title</h3><p>Alpha <strong>bold</strong> and <a href="https://example.com">linked</a>.</p><ul><li>One</li><li>Two</li></ul></section>
    """
    let expected = try #require(parse(source).first?.richContent)

    for chunkSize in 1...31 {
        var stream = MarkdownStream()
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let end = source.index(cursor, offsetBy: chunkSize, limitedBy: source.endIndex)
                ?? source.endIndex
            stream.append(String(source[cursor..<end]))
            cursor = end
        }
        stream.finish()
        let actual = try #require(stream.snapshot().blocks.first?.richContent)
        #expect(actual == expected, "Rich HTML differed at chunk size \(chunkSize)")
    }
}

private func parse(_ markdown: String) -> [MarkdownBlock] {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return stream.snapshot().blocks
}
