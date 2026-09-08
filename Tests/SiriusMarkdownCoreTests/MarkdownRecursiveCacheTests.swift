import Testing
@testable import SiriusMarkdownCore

@Test
func parserCacheUpdatesSealedStateThroughoutRecursiveContainers() throws {
    let range = MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2)
    let leaf = MarkdownBlock(
        id: MarkdownBlockID("leaf"), kind: .paragraph,
        sourceRange: range, text: "x", isSealed: false
    )
    let item = MarkdownListItem(
        sourceRange: range, text: "x",
        childItems: [MarkdownListItem(sourceRange: range, text: "x", childBlocks: [leaf])],
        childBlocks: [leaf]
    )
    let container = MarkdownBlock(
        id: MarkdownBlockID("container"), kind: .blockQuote,
        sourceRange: range, text: "x", listItems: [item], isSealed: false,
        richContent: MarkdownRichContent(blocks: [leaf]), childBlocks: [leaf]
    )
    let cache = MarkdownParserCache()
    let key = MarkdownCacheKey(sourceRange: range, contentHash: 1, namespace: "recursive")
    cache.insert([container], forKey: key)
    let sealed = try #require(cache.blocks(forKey: key, isSealed: true)?.first)
    #expect(sealed.isSealed)
    #expect(sealed.childBlocks.first?.isSealed == true)
    #expect(sealed.richContent?.blocks.first?.isSealed == true)
    #expect(sealed.listItems.first?.childBlocks.first?.isSealed == true)
    #expect(sealed.listItems.first?.childItems.first?.childBlocks.first?.isSealed == true)

    cache.insert([sealed], forKey: key)
    #expect(cache.blocks(forKey: key, isSealed: false) == [container])
}

@Test
func finishingCachedTailSealsNestedQuoteAndListBlocks() {
    var stream = MarkdownStream()
    stream.append("> - first\n>   - nested")
    let active = stream.snapshot()
    #expect(active.blocks.first?.isSealed == false)
    stream.finish()
    let finished = stream.snapshot()
    let nested = finished.blocks.first?.childBlocks.first?.listItems.first?.childBlocks
    #expect(nested?.isEmpty == false)
    #expect(nested?.allSatisfy(\.isSealed) == true)
}
