import SiriusMarkdownCore
import SwiftUI

public struct MarkdownDocumentView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.configuration = MarkdownRendererConfiguration(theme: theme)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.hostBoundaryView = { boundary in AnyView(hostBoundaryContent(boundary)) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(preparedSnapshot.items) { item in
                    preparedItemView(item)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func preparedItemView(_ item: MarkdownPreparedSnapshotItem) -> some View {
        switch item {
        case let .block(block, preparedContent):
            MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}

public struct StreamingMarkdownView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.configuration = MarkdownRendererConfiguration(theme: theme)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.hostBoundaryView = { boundary in AnyView(hostBoundaryContent(boundary)) }
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(preparedSnapshot.items) { item in
                preparedItemView(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func preparedItemView(_ item: MarkdownPreparedSnapshotItem) -> some View {
        switch item {
        case let .block(block, preparedContent):
            MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}
