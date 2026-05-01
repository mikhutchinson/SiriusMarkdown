import SiriusMarkdown
import SwiftUI
import Testing

@MainActor
@Test func umbrellaModuleReExportsCoreAndSwiftUIAPIs() {
    var stream = MarkdownStream()
    stream.append("# Hello\n\nStreaming Markdown.")
    stream.finish()

    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(theme: .document)
    let preparedSnapshot = configuration.prepare(snapshot: snapshot)
    let documentView = MarkdownDocumentView(preparedSnapshot: preparedSnapshot, configuration: configuration)
    let inlineEngine = InlineLayoutEngine()
    let policy = DefaultMarkdownPolicy()

    #expect(snapshot.blocks.count == 2)
    #expect(preparedSnapshot.preparedContentByBlockID.count == snapshot.blocks.count)
    #expect(policy.evaluateLink(destination: "https://example.com") == .allow)
    _ = documentView
    _ = inlineEngine
}
