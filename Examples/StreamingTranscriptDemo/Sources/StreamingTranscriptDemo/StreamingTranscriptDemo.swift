import SiriusMarkdown
import SwiftUI

@main
struct StreamingTranscriptDemo: App {
    var body: some Scene {
        WindowGroup {
            StreamingTranscriptView()
                .frame(minWidth: 680, minHeight: 520)
        }
    }
}

@MainActor
private final class StreamingTranscriptModel: ObservableObject {
    @Published var preparedSnapshot: MarkdownPreparedSnapshot

    private var stream = MarkdownStream()
    private let configuration = MarkdownRendererConfiguration.compactChat
    private var chunks: IndexingIterator<[String]>

    init() {
        self.chunks = StreamingTranscriptModel.sampleChunks.makeIterator()
        self.preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
        appendNextChunk()
    }

    func appendNextChunk() {
        if let chunk = chunks.next() {
            stream.append(chunk)
            preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
        } else {
            stream.finish()
            preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
        }
    }

    private static let sampleChunks = [
        "# Streaming Transcript\n\n",
        "This transcript appends Markdown in small chunks while preserving stable block identity.\n\n",
        "- [ ] Parse only the mutable tail\n",
        "- [x] Keep sealed regions immutable\n\n",
        "> Host apps can interleave native UI at stream boundaries.\n\n",
        "```swift\n",
        "var stream = MarkdownStream()\n",
        "stream.append(chunk)\n",
        "let snapshot = stream.snapshot()\n",
        "```\n\n"
    ]
}

private struct StreamingTranscriptView: View {
    @StateObject private var model = StreamingTranscriptModel()
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        StreamingMarkdownView(preparedSnapshot: model.preparedSnapshot, configuration: .compactChat)
            .padding()
            .onReceive(timer) { _ in
                model.appendNextChunk()
            }
    }
}
