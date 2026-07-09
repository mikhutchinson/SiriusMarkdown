import SiriusMarkdownCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct MarkdownDocumentView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    @StateObject private var internalSelectionController = MarkdownSelectionController()

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .coreTextPaintedLines)
        self.preparedSnapshot = self.configuration.unpreparedSnapshot(for: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.unpreparedSnapshot(for: snapshot)
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
        let controller = activeSelectionController
        ScrollView {
            selectionDocumentContent(selectionController: controller)
        }
        .onAppear {
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .markdownOnChange(of: preparedSnapshot.snapshot.generation) { _ in
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    private var activeSelectionController: MarkdownSelectionController? {
        guard configuration.documentSelection == .enabled else {
            return nil
        }
        return selectionController ?? internalSelectionController
    }

    @ViewBuilder
    private func selectionDocumentContent(selectionController: MarkdownSelectionController?) -> some View {
        let content = LazyVStack(alignment: .leading, spacing: theme.renderBlockSpacing) {
            ForEach(preparedSnapshot.renderItems) { item in
                preparedRenderItemView(item, selectionController: selectionController)
                    .id(itemViewID(for: item, in: preparedSnapshot))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)

        if let selectionController {
            MarkdownDocumentSelectionLayer(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            ) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func preparedRenderItemView(
        _ renderItem: MarkdownPreparedSnapshotRenderItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        if let item = preparedSnapshot.item(at: renderItem.itemIndex) {
            preparedItemView(item, selectionController: selectionController)
        }
    }

    @ViewBuilder
    private func preparedItemView(
        _ item: MarkdownPreparedSnapshotItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectionFragmentContainer(
                    block: block,
                    preparedContent: preparedContent,
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

    /// Returns a stable view identity for `item` that only changes when the diff marks the
    /// item as changed or new (INV-P3).  Unchanged sealed items receive the ":0" suffix so
    /// SwiftUI recognises them across snapshot publishes and skips expensive re-evaluation.
    private func itemViewID(
        for item: MarkdownPreparedSnapshotRenderItem,
        in snapshot: MarkdownPreparedSnapshot
    ) -> String {
        let baseID = snapshot.item(at: item.itemIndex)?.id ?? item.id
        // Only items whose content actually changed need a new view identity. New items start at
        // ":0" so when they seal on the next render they keep the same identity without a flip.
        if snapshot.diff.changedItemIDs.contains(baseID) {
            return item.id + ":\(snapshot.diff.generation)"
        }
        return item.id + ":0"
    }
}

public struct StreamingMarkdownView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    @StateObject private var internalSelectionController = MarkdownSelectionController()

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .coreTextPaintedLines)
        self.preparedSnapshot = self.configuration.unpreparedSnapshot(for: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.unpreparedSnapshot(for: snapshot)
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
        let controller = activeSelectionController
        selectionDocumentContent(selectionController: controller)
        .onAppear {
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .markdownOnChange(of: preparedSnapshot.snapshot.generation) { _ in
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    private var activeSelectionController: MarkdownSelectionController? {
        guard configuration.documentSelection == .enabled else {
            return nil
        }
        return selectionController ?? internalSelectionController
    }

    @ViewBuilder
    private func selectionDocumentContent(selectionController: MarkdownSelectionController?) -> some View {
        let content = LazyVStack(alignment: .leading, spacing: theme.renderBlockSpacing) {
            ForEach(preparedSnapshot.renderItems) { item in
                preparedRenderItemView(item, selectionController: selectionController)
                    .id(itemViewID(for: item, in: preparedSnapshot))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let selectionController {
            MarkdownDocumentSelectionLayer(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            ) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func preparedRenderItemView(
        _ renderItem: MarkdownPreparedSnapshotRenderItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        if let item = preparedSnapshot.item(at: renderItem.itemIndex) {
            preparedItemView(item, selectionController: selectionController)
        }
    }

    @ViewBuilder
    private func preparedItemView(
        _ item: MarkdownPreparedSnapshotItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectionFragmentContainer(
                    block: block,
                    preparedContent: preparedContent,
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

    private func itemViewID(
        for item: MarkdownPreparedSnapshotRenderItem,
        in snapshot: MarkdownPreparedSnapshot
    ) -> String {
        let baseID = snapshot.item(at: item.itemIndex)?.id ?? item.id
        if snapshot.diff.changedItemIDs.contains(baseID) {
            return item.id + ":\(snapshot.diff.generation)"
        }
        return item.id + ":0"
    }
}

private struct MarkdownSelectionFragmentContainer<Content: View>: View {
    var block: MarkdownBlock
    var preparedContent: MarkdownPreparedBlockContent
    @ObservedObject var selectionController: MarkdownSelectionController
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.markdownDocumentSelectionContext, MarkdownDocumentSelectionContext(blockID: block.id))
            .background(fragmentPreference)
            .markdownContextMenu {
                Button("Select Block") {
                    selectionController.select(block.id)
                }
                Button("Clear Selection") {
                    selectionController.clearSelection()
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fragmentPreference: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: fallbackFragments(rect: proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName)))
            )
        }
    }

    private var isSelected: Bool {
        selectionController.isSelected(block.id)
    }

    private func fallbackFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard !preparedContent.emitsTextLeafSelectionFragments else {
            return []
        }
        return MarkdownDocumentSelectionFragment.fragments(
            for: block,
            preparedContent: preparedContent,
            rect: rect
        )
    }
}

private struct MarkdownDocumentSelectionLayer<Content: View>: View {
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    @ObservedObject var selectionController: MarkdownSelectionController
    @ViewBuilder var content: () -> Content

    @State private var fragments: [MarkdownDocumentSelectionFragment] = []
    @State private var dragAnchor: MarkdownDocumentSelectionEndpoint?
    @State private var focusToken = 0
    private let dragActivation = MarkdownDocumentSelectionDragActivation()

    var body: some View {
        content()
            .environment(\.markdownSelectionController, selectionController)
            .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                selectionHighlights
            }
            .background {
                MarkdownDocumentSelectionKeyHandler(
                    focusToken: focusToken,
                    copyContext: copyContext
                )
                .frame(width: 0, height: 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(selectionGesture)
            .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { value in
                // Measures whether this closure runs (and thus sorts) on
                // layout passes where nothing actually changed, separately
                // from whether it ends up updating `fragments` (INV-P8).
                configuration.diagnosticsRecorder.recordSelectionPreferenceEvaluation()
                let sorted = value.sortedForSelection()
                guard sorted != fragments else { return }
                configuration.diagnosticsRecorder.recordSelectionPreferenceChange()
                fragments = sorted
            }
            .markdownContextMenu {
                Button("Select All") {
                    selectAll()
                }
                Button("Copy Selection") {
                    copySelection()
                }
                Button("Clear Selection") {
                    selectionController.clearSelection()
                }
            }
    }

    private var selectionGesture: some Gesture {
        #if os(tvOS)
        TapGesture()
            .onEnded {
                takeFocus()
            }
        #else
        DragGesture(minimumDistance: dragActivation.minimumDistance)
            .onChanged { value in
                guard dragActivation.hasActivated(start: value.startLocation, current: value.location) else {
                    return
                }
                takeFocus()
                let anchor = dragAnchor ?? hitEndpoint(at: value.startLocation, affinityHint: nil)
                dragAnchor = anchor
                guard let anchor else { return }
                // Affinity: downward drag → prefer next-fragment start; upward → prefer current-fragment end.
                let affinityHint: MarkdownDocumentSelectionAffinity =
                    value.location.y >= value.startLocation.y ? .downstream : .upstream
                guard let current = hitEndpoint(at: value.location, affinityHint: affinityHint) else {
                    return
                }
                activateContextForDrag(startBlockID: anchor.blockID, currentBlockID: current.blockID)
                selectRange(from: anchor, to: current)
            }
            .onEnded { _ in
                dragAnchor = nil
            }
        #endif
    }

    @ViewBuilder
    private var selectionHighlights: some View {
        let selectedRanges = selectionController.selectedSourceRanges
        let highlights = fragments.flatMap { $0.highlightRects(for: selectedRanges) }
        ForEach(highlights) { highlight in
            Rectangle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: max(1, highlight.rect.width), height: max(1, highlight.rect.height))
                .position(x: highlight.rect.midX, y: highlight.rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func hitEndpoint(
        at location: CGPoint,
        affinityHint: MarkdownDocumentSelectionAffinity? = nil
    ) -> MarkdownDocumentSelectionEndpoint? {
        hitFragment(at: location, affinityHint: affinityHint)?.endpoint(at: location)
    }

    private func hitFragment(
        at location: CGPoint,
        affinityHint: MarkdownDocumentSelectionAffinity? = nil
    ) -> MarkdownDocumentSelectionFragment? {
        MarkdownDocumentSelectionFragment.hitFragment(
            at: location,
            in: fragments,
            hitSlop: 4,
            affinityHint: affinityHint
        )
    }

    /// Activates the appropriate selection context using already-resolved endpoint blockIDs.
    ///
    /// Single-block code/table drags activate that block's scrollable context.
    /// Cross-block drags (or drags where either endpoint is outside a scrollable block) activate `.document`.
    /// Uses blockIDs from already-computed endpoints to avoid redundant `hitFragment` calls.
    private func activateContextForDrag(
        startBlockID: MarkdownBlockID,
        currentBlockID: MarkdownBlockID
    ) {
        guard startBlockID == currentBlockID,
              let block = preparedSnapshot.snapshot.blocks.first(where: { $0.id == startBlockID }),
              block.kind == .codeBlock || block.kind == .table
        else {
            selectionController.activateContext(.document)
            return
        }
        let role: MarkdownScrollableSelectionRegionID.Role = block.kind == .table ? .table : .codeBlock
        selectionController.activateContext(
            .scrollableRegion(MarkdownScrollableSelectionRegionID(blockID: startBlockID, role: role))
        )
    }

    private func selectRange(
        from lower: MarkdownDocumentSelectionEndpoint,
        to upper: MarkdownDocumentSelectionEndpoint
    ) {
        let selection = MarkdownDocumentSelectionFragment.selection(
            from: lower,
            to: upper,
            in: fragments
        )
        selectionController.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    }

    private func copySelection() {
        copyContext.copySelection()
    }

    private func selectAll() {
        copyContext.selectAll()
    }

    private func takeFocus() {
        focusToken &+= 1
    }

    private var copyContext: MarkdownDocumentSelectionCopyContext {
        MarkdownDocumentSelectionCopyContext(
            selectionController: selectionController,
            preparedSnapshot: preparedSnapshot,
            copyProvider: configuration.copyProvider,
            affordanceActionHandler: configuration.affordanceActionHandler
        )
    }
}

struct MarkdownDocumentSelectionCopyContext {
    var selectionController: MarkdownSelectionController
    var preparedSnapshot: MarkdownPreparedSnapshot
    var copyProvider: MarkdownCopyProvider?
    var affordanceActionHandler: MarkdownAffordanceActionHandler

    @MainActor
    func copySelection() {
        let markdown = selectionController.selectedMarkdown(
            in: preparedSnapshot,
            copyProvider: copyProvider
        )
        guard !markdown.isEmpty else {
            return
        }
        let plainText = selectionController.selectedPlainText(in: preparedSnapshot)
        let payload = MarkdownPasteboardPayload(
            plainText: plainText.isEmpty ? markdown : plainText,
            markdown: markdown
        )
        affordanceActionHandler.copyPayload(payload)
    }

    @MainActor
    func selectAll() {
        selectionController.selectAll(in: preparedSnapshot)
    }
}

#if os(macOS)
struct MarkdownDocumentSelectionKeyHandler: NSViewRepresentable {
    var focusToken: Int
    var copyContext: MarkdownDocumentSelectionCopyContext

    func makeNSView(context: Context) -> CopyKeyView {
        let view = CopyKeyView()
        view.coordinator = context.coordinator
        context.coordinator.copyContext = copyContext
        context.coordinator.focusToken = focusToken
        return view
    }

    func updateNSView(_ nsView: CopyKeyView, context: Context) {
        context.coordinator.copyContext = copyContext
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else {
                    return
                }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    static func dismantleNSView(_ nsView: CopyKeyView, coordinator _: Coordinator) {
        nsView.coordinator = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(copyContext: copyContext)
    }

    final class Coordinator {
        var copyContext: MarkdownDocumentSelectionCopyContext
        var focusToken = 0

        init(copyContext: MarkdownDocumentSelectionCopyContext) {
            self.copyContext = copyContext
        }

        @MainActor
        func copySelection() {
            copyContext.copySelection()
        }

        @MainActor
        func selectAll() {
            copyContext.selectAll()
        }
    }

    final class CopyKeyView: NSView {
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.command),
                  let character = event.charactersIgnoringModifiers?.lowercased()
            else {
                super.keyDown(with: event)
                return
            }

            if character == "c" {
                coordinator?.copySelection()
            } else if character == "a" {
                coordinator?.selectAll()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
#else
struct MarkdownDocumentSelectionKeyHandler: View {
    var focusToken: Int
    var copyContext: MarkdownDocumentSelectionCopyContext

    var body: some View {
        EmptyView()
    }
}
#endif
