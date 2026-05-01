import SiriusMarkdownCore
import SwiftUI

public struct MarkdownDocumentView: View {
    private var snapshot: MarkdownSnapshot
    private var configuration: MarkdownRendererConfiguration
    private var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.snapshot = snapshot
        self.configuration = MarkdownRendererConfiguration(theme: theme)
        self.preparedContentByBlockID = self.configuration.prepare(snapshot: snapshot)
    }

    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.preparedContentByBlockID = configuration.prepare(snapshot: snapshot)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(snapshot.blocks) { block in
                    MarkdownBlockView(
                        block: block,
                        configuration: configuration,
                        preparedContent: preparedContentByBlockID[block.id]
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct StreamingMarkdownView: View {
    private var snapshot: MarkdownSnapshot
    private var configuration: MarkdownRendererConfiguration
    private var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.snapshot = snapshot
        self.configuration = MarkdownRendererConfiguration(theme: theme)
        self.preparedContentByBlockID = self.configuration.prepare(snapshot: snapshot)
    }

    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.preparedContentByBlockID = configuration.prepare(snapshot: snapshot)
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(snapshot.blocks) { block in
                MarkdownBlockView(
                    block: block,
                    configuration: configuration,
                    preparedContent: preparedContentByBlockID[block.id]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
