import SiriusMarkdown
import SwiftUI

@main
struct DocumentReaderDemo: App {
    var body: some Scene {
        WindowGroup {
            DocumentReaderView()
                .frame(minWidth: 760, minHeight: 620)
        }
    }
}

private struct DocumentReaderView: View {
    private let configuration = MarkdownRendererConfiguration.document
    private let preparedSnapshot: MarkdownPreparedSnapshot

    init() {
        self.preparedSnapshot = configuration.prepare(snapshot: DemoDocument.snapshot())
    }

    var body: some View {
        MarkdownDocumentView(preparedSnapshot: preparedSnapshot, configuration: configuration)
    }
}

private enum DemoDocument {
    static func snapshot() -> MarkdownSnapshot {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        return stream.snapshot()
    }

    private static let markdown = """
    # Document Reader Demo

    This static document stresses wide content, tables, lists, links, and long paragraphs.

    ## Long Paragraph

    SiriusMarkdown is designed for long AI and document workloads where snapshots are rendered repeatedly at changing widths without reparsing Markdown from SwiftUI body evaluation.

    ## Wide Code

    ```swift
    let longLine = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
    print(longLine)
    ```

    ## Table

    | Area | Behavior | Evidence |
    | --- | --- | --- |
    | Streaming | Mutable tail only | Diagnostics counters |
    | Layout | Prepare once, layout cheaply | Pretext fixtures |
    | Safety | Policies gate links/images/HTML | Unit tests |

    [Project README](https://example.com)
    """
}
