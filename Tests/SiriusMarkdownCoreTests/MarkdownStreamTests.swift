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
func activeTailKeepsStableBlockIDWhileAppending() {
    var stream = MarkdownStream()
    stream.append("A paragraph")
    let before = stream.snapshot().blocks.first?.id

    stream.append(" still active")
    let after = stream.snapshot().blocks.first?.id

    #expect(before == after)
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
