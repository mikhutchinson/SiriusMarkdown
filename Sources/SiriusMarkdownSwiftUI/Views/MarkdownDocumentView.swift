import SiriusMarkdownCore
import SwiftUI

public struct MarkdownDocumentView: View {
    private var snapshot: MarkdownSnapshot
    private var configuration: MarkdownRendererConfiguration

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.snapshot = snapshot
        self.configuration = MarkdownRendererConfiguration(theme: theme)
    }

    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.snapshot = snapshot
        self.configuration = configuration
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(snapshot.blocks) { block in
                    MarkdownBlockView(block: block, configuration: configuration)
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

    private var theme: MarkdownTheme {
        configuration.theme
    }

    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.snapshot = snapshot
        self.configuration = MarkdownRendererConfiguration(theme: theme)
    }

    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.snapshot = snapshot
        self.configuration = configuration
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(snapshot.blocks) { block in
                MarkdownBlockView(block: block, configuration: configuration)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
