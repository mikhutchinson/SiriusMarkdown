import SiriusMarkdownCore
import Foundation
import SwiftUI

@MainActor
public final class MarkdownRenderSession: ObservableObject {
    @Published public private(set) var preparedSnapshot: MarkdownPreparedSnapshot
    @Published public private(set) var snapshot: MarkdownSnapshot
    @Published public private(set) var snapshotDiff: MarkdownPreparedSnapshotDiff

    public private(set) var configuration: MarkdownRendererConfiguration
    public let streamDiagnosticsRecorder: MarkdownDiagnosticsRecorder
    public let renderDiagnosticsRecorder: MarkdownDiagnosticsRecorder

    private let pipeline: MarkdownRenderSessionPipeline
    private let sourceCopyStore: MarkdownMutableSourceCopyStore
    private let parserCacheCapacity: Int
    private var renderTask: Task<Void, Never>?
    private var pendingOperations: [MarkdownRenderSessionOperation] = []
    private var presentationRevision: Int = 0
    private var linkMetadataTasks: [URL: Task<Void, Never>] = [:]
    private var scheduledLinkMetadataOrigins: Set<URL> = []
    private var linkMetadataRefreshTask: Task<Void, Never>?

    public init(
        configuration: MarkdownRendererConfiguration = .compactChat,
        parserCacheCapacity: Int = 256,
        streamDiagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder(),
        renderDiagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.streamDiagnosticsRecorder = streamDiagnosticsRecorder
        self.renderDiagnosticsRecorder = renderDiagnosticsRecorder
        self.parserCacheCapacity = parserCacheCapacity
        let sourceCopyStore = MarkdownMutableSourceCopyStore()
        var sessionConfiguration = configuration
        sessionConfiguration.diagnosticsRecorder = renderDiagnosticsRecorder
        sessionConfiguration.copyProvider = MarkdownCopyProvider(
            markdown: { [sourceCopyStore] range in
                sourceCopyStore.markdown(in: range)
            },
            documentMarkdown: { [sourceCopyStore] in
                sourceCopyStore.markdown
            }
        )
        self.sourceCopyStore = sourceCopyStore
        self.pipeline = MarkdownRenderSessionPipeline(
            configuration: sessionConfiguration,
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: streamDiagnosticsRecorder
        )
        self.configuration = sessionConfiguration

        let stream = MarkdownStream(
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: streamDiagnosticsRecorder
        )
        let snapshot = stream.snapshot()
        self.snapshot = snapshot
        let preparedSnapshot = sessionConfiguration.prepare(snapshot: snapshot)
        self.preparedSnapshot = preparedSnapshot
        self.snapshotDiff = preparedSnapshot.diff
    }

    public var streamCounters: MarkdownDiagnosticsCounters {
        streamDiagnosticsRecorder.snapshot()
    }

    public var renderCounters: MarkdownDiagnosticsCounters {
        renderDiagnosticsRecorder.snapshot()
    }

    public var sourceLength: Int {
        sourceCopyStore.byteCount
    }

    public func append(_ markdown: String) {
        guard !markdown.isEmpty else {
            return
        }

        sourceCopyStore.append(markdown)
        schedule(.append(markdown))
    }

    public func appendHostBoundary(id: MarkdownHostBoundaryID? = nil) {
        schedule(.appendHostBoundary(id))
    }

    public func finish() {
        schedule(.finish)
    }

    public func markdown(in sourceRange: MarkdownSourceRange) -> String {
        sourceCopyStore.markdown(in: sourceRange) ?? ""
    }

    public func reset() {
        sourceCopyStore.removeAll()
        configuration.preparationCache.removeAll()
        cancelLinkMetadataResolution()
        schedule(.reset)
    }

    public func waitUntilIdle() async {
        let task = renderTask
        await task?.value
    }

    /// Waits for package-owned favicon discovery and the resulting prepared
    /// snapshot refresh. Ordinary `waitUntilIdle()` intentionally remains a
    /// source/render-pipeline barrier and does not wait on the network.
    public func waitUntilLinkMetadataIdle() async {
        while true {
            let tasks = Array(linkMetadataTasks.values)
            let refreshTask = linkMetadataRefreshTask
            if tasks.isEmpty, refreshTask == nil {
                await waitUntilIdle()
                if linkMetadataTasks.isEmpty, linkMetadataRefreshTask == nil, renderTask == nil {
                    return
                }
                continue
            }
            for task in tasks {
                await task.value
            }
            await refreshTask?.value
            await waitUntilIdle()
        }
    }

    private func schedule(_ operation: MarkdownRenderSessionOperation) {
        presentationRevision += 1
        pendingOperations.append(operation)

        guard renderTask == nil else {
            return
        }

        let pipeline = pipeline
        // This session is MainActor-isolated because it publishes ObservableObject
        // state to SwiftUI. A child `Task`, however, inherits that actor. Merely
        // awaiting the pipeline actor is not a sufficient thread-hop guarantee:
        // when the pipeline is uncontended, Swift's cooperative executor may run
        // its parse/prepare job immediately on the calling main thread. Large
        // documents can then starve AppKit for an entire parse + highlight +
        // preparation pass even though none of that work requires the MainActor.
        //
        // Start the pump detached so every pipeline batch originates on the
        // global executor. The only MainActor hops are the small operation drain
        // and prepared-value publication boundaries below.
        renderTask = Task.detached(priority: .userInitiated) { [self, pipeline] in
            while let batch = await nextRenderBatch() {
                let state = await pipeline.apply(batch.operations)
                await publish(state, for: batch)
            }
        }
    }

    /// MainActor boundary for the detached render pump. Capturing the
    /// globally-isolated session strongly for the bounded lifetime of one
    /// drain avoids moving a task-isolated weak reference between executors,
    /// which older Swift 6 compilers correctly reject under strict
    /// concurrency. The task clears its stored handle before returning, so
    /// the temporary self/task retain cycle is broken deterministically.
    private func nextRenderBatch() -> MarkdownRenderSessionBatch? {
        guard !pendingOperations.isEmpty else {
            renderTask = nil
            return nil
        }

        return MarkdownRenderSessionBatch(
            operations: drainPendingOperations(),
            revision: presentationRevision
        )
    }

    /// MainActor publication boundary for prepared render state.
    private func publish(
        _ state: MarkdownRenderSessionState,
        for batch: MarkdownRenderSessionBatch
    ) {
        guard batch.revision == presentationRevision else {
            return
        }
        snapshot = state.snapshot
        preparedSnapshot = state.preparedSnapshot
        snapshotDiff = state.preparedSnapshot.diff
        scheduleLinkMetadataResolution(in: state.snapshot)
    }

    private func scheduleLinkMetadataResolution(in snapshot: MarkdownSnapshot) {
        guard let resolver = configuration.linkMetadataResolver,
              configuration.linkDecoration.isEnabled
        else {
            return
        }

        for destination in Self.externalHTTPSLinkDestinations(in: snapshot, policy: configuration.linkPolicy) {
            let origin = Self.linkOrigin(for: destination) ?? destination
            guard !scheduledLinkMetadataOrigins.contains(origin) else { continue }
            scheduledLinkMetadataOrigins.insert(origin)
            if resolver.cachedResolution(for: destination) == .unavailable {
                continue
            }

            // Even a positive cache hit crosses an asynchronous boundary once.
            // The cache may have filled after the just-published preparation
            // read it; resolving (immediately) and scheduling one debounced
            // refresh closes that race without network work.
            linkMetadataTasks[origin] = Task { [weak self, resolver] in
                let resolution = await resolver.resolveMetadata(for: destination)
                guard !Task.isCancelled else { return }
                self?.linkMetadataResolutionFinished(resolution, origin: origin)
            }
        }
    }

    private func linkMetadataResolutionFinished(
        _ resolution: MarkdownLinkMetadataResolution,
        origin: URL
    ) {
        linkMetadataTasks.removeValue(forKey: origin)
        guard case .metadata = resolution else { return }

        // A page of citations often completes several favicon requests in
        // one network burst. Debounce them into one preparation publication.
        linkMetadataRefreshTask?.cancel()
        linkMetadataRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.linkMetadataRefreshTask = nil
            self?.schedule(.refreshLinkMetadata)
        }
    }

    private func cancelLinkMetadataResolution() {
        linkMetadataTasks.values.forEach { $0.cancel() }
        linkMetadataTasks.removeAll()
        scheduledLinkMetadataOrigins.removeAll()
        linkMetadataRefreshTask?.cancel()
        linkMetadataRefreshTask = nil
    }

    private nonisolated static func externalHTTPSLinkDestinations(
        in snapshot: MarkdownSnapshot,
        policy: any MarkdownLinkPolicy
    ) -> Set<URL> {
        var destinations: Set<URL> = []

        func add(_ runs: [MarkdownInlineRun]) {
            for run in runs {
                guard let destination = run.destination,
                      let url = markdownLinkURL(for: destination, policy: policy),
                      url.scheme?.lowercased() == "https",
                      url.host != nil
                else {
                    continue
                }
                destinations.insert(url)
            }
        }

        func addListItems(_ items: [MarkdownListItem]) {
            for item in items {
                add(item.inlines)
                addListItems(item.childItems)
            }
        }

        func addBlocks(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                add(block.inlines)
                addListItems(block.listItems)
                if let table = block.table {
                    table.header.forEach { add($0.inlines) }
                    table.rows.flatMap { $0 }.forEach { add($0.inlines) }
                }
                if let richContent = block.richContent {
                    addBlocks(richContent.blocks)
                }
            }
        }

        addBlocks(snapshot.blocks)
        return destinations
    }

    private nonisolated static func linkOrigin(for destination: URL) -> URL? {
        guard let host = destination.host else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.lowercased()
        components.port = destination.port == 443 ? nil : destination.port
        components.path = "/"
        return components.url
    }

    private func drainPendingOperations() -> [MarkdownRenderSessionOperation] {
        let operations = pendingOperations
        pendingOperations.removeAll(keepingCapacity: true)
        return Self.coalescedOperations(operations)
    }

    private static func coalescedOperations(
        _ operations: [MarkdownRenderSessionOperation]
    ) -> [MarkdownRenderSessionOperation] {
        let effectiveOperations: ArraySlice<MarkdownRenderSessionOperation>
        if let lastResetIndex = operations.lastIndex(where: { operation in
            if case .reset = operation {
                return true
            }
            return false
        }) {
            effectiveOperations = operations[lastResetIndex...]
        } else {
            effectiveOperations = operations[...]
        }

        var coalesced: [MarkdownRenderSessionOperation] = []
        var pendingAppendChunks: [String] = []

        func flushPendingAppend() {
            guard !pendingAppendChunks.isEmpty else {
                return
            }
            coalesced.append(.append(pendingAppendChunks.joined()))
            pendingAppendChunks.removeAll(keepingCapacity: true)
        }

        for operation in effectiveOperations {
            switch operation {
            case let .append(markdown):
                pendingAppendChunks.append(markdown)
            case .appendHostBoundary, .finish, .reset, .refreshLinkMetadata:
                flushPendingAppend()
                coalesced.append(operation)
            }
        }

        flushPendingAppend()
        return coalesced
    }
}

public extension MarkdownRenderSession {
    func blockID(
        containingSourceLine line: Int,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        snapshot.blockID(containingSourceLine: line, policy: policy)
    }

    func firstBlockID(
        overlappingSourceRange sourceRange: MarkdownSourceRange,
        policy: MarkdownSourceRevealPolicy = .nearestRenderedBlock
    ) -> MarkdownBlockID? {
        snapshot.firstBlockID(overlappingSourceRange: sourceRange, policy: policy)
    }
}

private enum MarkdownRenderSessionOperation: Sendable {
    case append(String)
    case appendHostBoundary(MarkdownHostBoundaryID?)
    case finish
    case reset
    case refreshLinkMetadata
}

private struct MarkdownRenderSessionState: Sendable {
    var snapshot: MarkdownSnapshot
    var preparedSnapshot: MarkdownPreparedSnapshot
}

private struct MarkdownRenderSessionBatch: Sendable {
    var operations: [MarkdownRenderSessionOperation]
    var revision: Int
}

private actor MarkdownRenderSessionPipeline {
    private var stream: MarkdownStream
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot?
    private let parserCacheCapacity: Int
    private let diagnosticsRecorder: MarkdownDiagnosticsRecorder

    init(
        configuration: MarkdownRendererConfiguration,
        parserCacheCapacity: Int,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder
    ) {
        self.configuration = configuration
        self.parserCacheCapacity = parserCacheCapacity
        self.diagnosticsRecorder = diagnosticsRecorder
        self.preparedSnapshot = nil
        self.stream = MarkdownStream(
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    func apply(_ operations: [MarkdownRenderSessionOperation]) -> MarkdownRenderSessionState {
        for operation in operations {
            switch operation {
            case let .append(markdown):
                stream.append(markdown)
            case let .appendHostBoundary(id):
                stream.appendHostBoundary(id: id)
            case .finish:
                stream.finish()
            case .reset:
                stream = MarkdownStream(
                    parserCacheCapacity: parserCacheCapacity,
                    diagnosticsRecorder: diagnosticsRecorder
                )
                configuration.preparationCache.removeAll()
                preparedSnapshot = nil
            case .refreshLinkMetadata:
                // Metadata changes presentation, not source semantics.
                preparedSnapshot = nil
            }
        }

        let snapshot = stream.snapshot()
        let preparedSnapshot = configuration.prepare(
            snapshot: snapshot,
            reusing: preparedSnapshot
        )
        self.preparedSnapshot = preparedSnapshot
        return MarkdownRenderSessionState(
            snapshot: snapshot,
            preparedSnapshot: preparedSnapshot
        )
    }
}

private final class MarkdownMutableSourceCopyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var source = MarkdownSourceBuffer()

    var byteCount: Int {
        lock.withLock {
            source.byteCount
        }
    }

    func append(_ markdown: String) {
        lock.withLock {
            _ = source.append(markdown)
        }
    }

    func removeAll() {
        lock.withLock {
            source = MarkdownSourceBuffer()
        }
    }

    var markdown: String {
        lock.withLock {
            source.slice(0..<source.byteCount).text
        }
    }

    func markdown(in sourceRange: MarkdownSourceRange) -> String? {
        lock.withLock {
            let byteRange = sourceRange.byteRange
            guard byteRange.lowerBound >= 0,
                  byteRange.lowerBound <= byteRange.upperBound,
                  byteRange.upperBound <= source.byteCount
            else {
                return nil
            }

            return source.slice(byteRange).text
        }
    }
}
