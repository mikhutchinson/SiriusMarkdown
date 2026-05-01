import SiriusMarkdown
import SwiftUI

@main
struct MarkdownDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoDocumentView()
                .frame(minWidth: 720, minHeight: 560)
        }
    }
}

private struct DemoDocumentView: View {
    private let configuration = MarkdownRendererConfiguration.document
    private let preparedSnapshot: MarkdownPreparedSnapshot

    init() {
        self.preparedSnapshot = configuration.prepare(snapshot: DemoDocument.makeSnapshot())
    }

    var body: some View {
        MarkdownDocumentView(preparedSnapshot: preparedSnapshot, configuration: configuration)
    }
}

private enum DemoDocument {
    static func makeSnapshot() -> MarkdownSnapshot {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        return stream.snapshot()
    }

    private static let markdown = """
    # SiriusMarkdown Demo

    SiriusMarkdown renders a native SwiftUI document from an append-only stream.

    ## Structured Blocks

    - Native paragraphs, headings, lists, quotes, code, and tables.
    - Safe policies for links, images, HTML, code, and math.
    - Stable block identities for long streaming transcripts.

    > Block quotes keep their own structured render path.

    ```swift
    import SiriusMarkdown

    var stream = MarkdownStream()
    stream.append("# Hello")
    stream.finish()

    let configuration = MarkdownRendererConfiguration.document
    MarkdownDocumentView(
        preparedSnapshot: configuration.prepare(snapshot: stream.snapshot()),
        configuration: configuration
    )
    ```

    | Area | Contract |
    | --- | --- |
    | Parser | swift-markdown owns semantics |
    | Stream | sealed regions plus one mutable tail |
    | SwiftUI | renders prepared snapshots |

    [Swift Markdown](https://github.com/swiftlang/swift-markdown)
    """
}
