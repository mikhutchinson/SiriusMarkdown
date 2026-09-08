import SwiftUI
import SiriusMarkdownCore

struct MarkdownDocumentIndexRevision: Hashable {
    let identity: UUID
    let generation: Int
    let preparedGeneration: Int
    let sourceLength: Int
    let firstBlockID: MarkdownBlockID?

    init(_ snapshot: MarkdownPreparedSnapshot) {
        identity = snapshot.documentIndexIdentity
        generation = snapshot.snapshot.generation
        preparedGeneration = snapshot.diff.generation
        sourceLength = snapshot.snapshot.sourceLength
        firstBlockID = snapshot.snapshot.blocks.first?.id
    }
}

struct MarkdownDocumentRevealRequest: Equatable {
    let id = UUID()
    let blockID: MarkdownBlockID
    let sourceRange: MarkdownSourceRange
    var anchorID: String { "markdown-document-reveal:\(id.uuidString)" }

    func highlight(in fragments: [MarkdownDocumentSelectionFragment]) -> MarkdownDocumentSelectionHighlight? {
        for fragment in fragments where fragment.blockID == blockID && fragment.sourceRange.byteRange.overlaps(sourceRange.byteRange) {
            if let highlight = fragment.highlightRects(for: [sourceRange]).first { return highlight }
        }
        return nil
    }
}

private struct MarkdownDocumentRevealRequestKey: EnvironmentKey {
    static let defaultValue: MarkdownDocumentRevealRequest? = nil
}

private struct MarkdownHostScrollRevealKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var markdownHostScrollReveal: Bool {
        get { self[MarkdownHostScrollRevealKey.self] }
        set { self[MarkdownHostScrollRevealKey.self] = newValue }
    }

    var markdownDocumentRevealRequest: MarkdownDocumentRevealRequest? {
        get { self[MarkdownDocumentRevealRequestKey.self] }
        set { self[MarkdownDocumentRevealRequestKey.self] = newValue }
    }
}

struct MarkdownDocumentRevealAnchorKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

@MainActor
final class MarkdownDocumentNavigationState: ObservableObject {
    @Published private(set) var revealRequest: MarkdownDocumentRevealRequest?
    private(set) var indexBuildCount = 0
    private var indexedRevision: MarkdownDocumentIndexRevision?
    private var pendingBuild: (id: UUID, revision: MarkdownDocumentIndexRevision, task: Task<MarkdownPreparedDocumentIndex, Never>)?
    private var snapshot: MarkdownPreparedSnapshot
    private var externalLinkAction: MarkdownLinkAction?
    let findController: MarkdownDocumentFindController

    lazy var linkAction = MarkdownLinkAction { [weak self] destination in
        Task { @MainActor [weak self] in await self?.open(destination) }
    }

    init(snapshot: MarkdownPreparedSnapshot, findController: MarkdownDocumentFindController, externalLinkAction: MarkdownLinkAction?) {
        self.snapshot = snapshot
        self.findController = findController
        self.externalLinkAction = externalLinkAction
    }

    func update(snapshot: MarkdownPreparedSnapshot, externalLinkAction: MarkdownLinkAction?) {
        self.snapshot = snapshot
        self.externalLinkAction = externalLinkAction
    }

    func prepareIndex() async {
        let revision = MarkdownDocumentIndexRevision(snapshot)
        guard indexedRevision != revision else { return }
        let request: (id: UUID, revision: MarkdownDocumentIndexRevision, task: Task<MarkdownPreparedDocumentIndex, Never>)
        if let pendingBuild, pendingBuild.revision == revision {
            request = pendingBuild
        } else {
            pendingBuild?.task.cancel()
            let snapshot = snapshot
            request = (UUID(), revision, Task.detached(priority: .userInitiated) {
                MarkdownPreparedDocumentIndex(preparedSnapshot: snapshot)
            })
            pendingBuild = request
            indexBuildCount += 1
        }
        let index = await request.task.value
        guard pendingBuild?.id == request.id,
              MarkdownDocumentIndexRevision(snapshot) == revision else { return }
        pendingBuild = nil
        indexedRevision = revision
        findController.update(index: index)
    }

    func revealCurrentMatch() {
        guard let match = findController.currentMatch else { revealRequest = nil; return }
        revealRequest = MarkdownDocumentRevealRequest(blockID: match.blockID, sourceRange: match.sourceRange)
    }

    func open(_ destination: String) async {
        guard destination.hasPrefix("#") else {
            if let externalLinkAction { externalLinkAction.open(destination) }
            else { MarkdownURLOpener.open(destination) }
            return
        }
        await prepareIndex()
        guard let anchor = findController.index.anchor(forFragment: destination) else { return }
        revealRequest = MarkdownDocumentRevealRequest(blockID: anchor.blockID, sourceRange: anchor.sourceRange)
    }
}

/// Shares navigation between self-scrolled documents and opted-in transcripts.
/// A transcript retains its host scroller and reveals through one native marker.
struct MarkdownDocumentNavigationView<Content: View>: View {
    let snapshot: MarkdownPreparedSnapshot
    let ownsScrollView: Bool
    let showsFindControls: Bool
    let externalLinkAction: MarkdownLinkAction?
    let selectionController: MarkdownSelectionController
    @ObservedObject var findController: MarkdownDocumentFindController
    @StateObject private var navigation: MarkdownDocumentNavigationState
    let content: (MarkdownLinkAction, Bool) -> Content

    init(snapshot: MarkdownPreparedSnapshot, externalLinkAction: MarkdownLinkAction?, selectionController: MarkdownSelectionController,
         findController: MarkdownDocumentFindController, ownsScrollView: Bool = true,
         showsFindControls: Bool = true, @ViewBuilder content: @escaping (MarkdownLinkAction, Bool) -> Content) {
        self.snapshot = snapshot
        self.ownsScrollView = ownsScrollView
        self.showsFindControls = showsFindControls
        self.externalLinkAction = externalLinkAction
        self.selectionController = selectionController
        self.findController = findController
        self.content = content
        _navigation = StateObject(wrappedValue: MarkdownDocumentNavigationState(
            snapshot: snapshot, findController: findController, externalLinkAction: externalLinkAction
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if showsFindControls && findController.isPresented { MarkdownDocumentFindBar(controller: findController) }
                navigationContent
                    .overlay(alignment: .topTrailing) {
                        if showsFindControls && !findController.isPresented {
                            Button { findController.isPresented = true } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel("Find in Document")
                            .accessibilityIdentifier("SiriusMarkdown.Find")
                            .markdownFindShortcut("f", modifiers: .command)
                            .padding(8)
                        }
                    }
            }
            .task(id: MarkdownDocumentIndexRevision(snapshot)) {
                navigation.update(snapshot: snapshot, externalLinkAction: externalLinkAction)
                if findController.isPresented { await navigation.prepareIndex() }
            }
            .markdownOnChange(of: externalLinkAction?.renderIdentity) { _ in
                navigation.update(snapshot: snapshot, externalLinkAction: externalLinkAction)
            }
            .task(id: findController.isPresented) {
                if findController.isPresented {
                    await navigation.prepareIndex()
                    navigation.revealCurrentMatch()
                }
            }
            .markdownOnChange(of: findController.currentMatch) { _ in
                if findController.isPresented {
                    navigation.revealCurrentMatch()
                    if findController.currentMatch == nil { selectionController.clearSelection() }
                }
            }
            .onPreferenceChange(MarkdownDocumentRevealAnchorKey.self) { anchor in
                if ownsScrollView, let anchor { proxy.scrollTo(anchor, anchor: .center) }
            }
            .markdownOnChange(of: navigation.revealRequest) { request in
                guard let request else { return }
                if findController.isPresented {
                    selectionController.selectSourceRanges([request.sourceRange], selectedBlockIDs: [request.blockID])
                }
                if ownsScrollView { proxy.scrollTo("block:\(request.blockID.rawValue)", anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        let rendered = content(navigation.linkAction, findController.isPresented || navigation.revealRequest != nil)
            .environment(\.markdownDocumentRevealRequest, navigation.revealRequest)
            .environment(\.markdownHostScrollReveal, !ownsScrollView)
        if ownsScrollView { ScrollView { rendered } }
        else { rendered }
    }

}
