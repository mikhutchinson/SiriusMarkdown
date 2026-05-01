import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

@Test
@MainActor
func documentViewCanBeConstructedFromSnapshot() {
    let block = MarkdownBlock(
        id: MarkdownBlockID("block-1"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        isSealed: true
    )
    let snapshot = MarkdownSnapshot(blocks: [block], sourceLength: 5, generation: 1, isFinished: true)

    _ = MarkdownDocumentView(snapshot: snapshot)
    _ = StreamingMarkdownView(snapshot: snapshot)
}
