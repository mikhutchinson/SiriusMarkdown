import SiriusMarkdownCore
import SwiftUI

public struct MarkdownDocumentView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .preparedNativeLines)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
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
        .onAppear {
            selectionController?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .onChange(of: preparedSnapshot.snapshot.generation) { _ in
            selectionController?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    @ViewBuilder
    private func preparedItemView(_ item: MarkdownPreparedSnapshotItem) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectableBlockContainer(
                    block: block,
                    preparedSnapshot: preparedSnapshot,
                    configuration: configuration,
                    selectionController: selectionController
                ) {
                    blockView
                }
            } else {
                blockView
            }
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}

public struct StreamingMarkdownView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .preparedNativeLines)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { boundary in AnyView(hostBoundaryContent(boundary)) }
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(preparedSnapshot.items) { item in
                preparedItemView(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            selectionController?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .onChange(of: preparedSnapshot.snapshot.generation) { _ in
            selectionController?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    @ViewBuilder
    private func preparedItemView(_ item: MarkdownPreparedSnapshotItem) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectableBlockContainer(
                    block: block,
                    preparedSnapshot: preparedSnapshot,
                    configuration: configuration,
                    selectionController: selectionController
                ) {
                    blockView
                }
            } else {
                blockView
            }
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}

private struct MarkdownSelectableBlockContainer<Content: View>: View {
    var block: MarkdownBlock
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    @ObservedObject var selectionController: MarkdownSelectionController
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, isSelected ? 2 : 0)
            .padding(.horizontal, isSelected ? 4 : 0)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectionController.select(block.id)
            }
            .contextMenu {
                Button("Select Block") {
                    selectionController.select(block.id)
                }
                Button("Copy Selected Markdown") {
                    selectionController.copySelectedMarkdown(
                        in: preparedSnapshot,
                        copyProvider: configuration.copyProvider
                    )
                }
                Button("Copy Selected Text") {
                    selectionController.copySelectedPlainText(in: preparedSnapshot)
                }
                Button("Clear Selection") {
                    selectionController.clearSelection()
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isSelected: Bool {
        selectionController.isSelected(block.id)
    }
}
