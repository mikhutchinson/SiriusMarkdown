import SiriusMarkdown
import SwiftUI
import Testing

@Test func umbrellaModuleReExportsCoreAndSwiftUIAPIs() {
    var stream = MarkdownStream()
    stream.append("# Hello\n\nStreaming Markdown.")
    stream.finish()

    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(theme: .document)
    let preparedSnapshot = configuration.prepare(snapshot: snapshot)
    let inlineEngine = InlineLayoutEngine(measurer: CoreTextInlineMeasurer())
    let policy = DefaultMarkdownPolicy()
    let outlineRange = snapshot.blocks.first?.sourceRange ?? MarkdownSourceRange(byteRange: 0..<1, lineRange: 1..<2)

    #expect(snapshot.blocks.count == 2)
    #expect(preparedSnapshot.preparedContentByBlockID.count == snapshot.blocks.count)
    #expect(snapshot.blockID(containingSourceLine: 1) == snapshot.blocks.first?.id)
    #expect(preparedSnapshot.firstBlockID(overlappingSourceRange: outlineRange) == snapshot.blocks.first?.id)
    #expect(MarkdownSourceRevealPolicy.nearestRenderedBlock == .nearestRenderedBlock)
    #expect(policy.evaluateLink(destination: "https://example.com") == .allow)
    _ = inlineEngine
}
