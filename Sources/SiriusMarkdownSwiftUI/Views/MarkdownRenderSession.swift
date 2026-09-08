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
    private var preparedLinkMetadataResolutions: [URL: MarkdownLinkMetadataResolution] = [:]
    private var pendingLinkMetadataRefreshes: [URL: MarkdownLinkMetadataResolution] = [:]
    private var linkMetadataRefreshTask: Task<Void, Never>?
    private var imageTasks: [String: Task<Void, Never>] = [:]
    private var imageTaskIDs: [String: UUID] = [:]
    private var imageOwners: [String: Set<MarkdownBlockID>] = [:]
    private var imageLoadingViewport: Set<MarkdownBlockID>?
    private var imageResolutionIDs: [String: String] = [:]
    private var authorizedImageSources: Set<String> = []
    private var pendingImageRefreshes: [String: MarkdownAsyncImageResolution] = [:]
    private var imageRefreshTask: Task<Void, Never>?
    private var imageEpoch = UUID()


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

    deinit {
        imageTasks.values.forEach { $0.cancel() }
        imageRefreshTask?.cancel()
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
        cancelImageResolution()
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

    /// Waits for opted-in image loads and their prepared snapshot publication.
    /// Ordinary waitUntilIdle remains independent of network completion.
    public func waitUntilImagesIdle() async {
        while true {
            await waitUntilIdle()
            let tasks = Array(imageTasks.values)
            let refresh = imageRefreshTask
            if tasks.isEmpty, refresh == nil, renderTask == nil { return }
            for task in tasks { await task.value }
            await refresh?.value
        }
    }

    /// Restricts new image loads to visible top-level block IDs supplied by the
    /// host's viewport tracking. An empty set pauses loads; nil permits all
    /// document images. Already prepared images remain available when scrolled
    /// away. A reset retains viewport gating but clears its old block IDs.
    public func updateImageLoadingViewport(blockIDs: Set<MarkdownBlockID>?) {
        guard imageLoadingViewport != blockIDs else { return }
        imageLoadingViewport = blockIDs
        scheduleImageResolution(owners: imageOwners)
    }

    private func scheduleImageResolution(owners: [String: Set<MarkdownBlockID>]) {
        imageOwners = owners
        authorizedImageSources = Set(owners.compactMap { source, blocks in
            imageLoadingViewport.map { $0.isDisjoint(with: blocks) } == true ? nil : source
        })
        for source in Array(imageTasks.keys) where !authorizedImageSources.contains(source) {
            imageTaskIDs.removeValue(forKey: source)
            imageTasks.removeValue(forKey: source)?.cancel()
        }
        imageResolutionIDs = imageResolutionIDs.filter { owners[$0.key] != nil }
        startImageRequests()
    }

    private func startImageRequests() {
        guard let resolver = configuration.imageResolver as? any MarkdownAsyncImageResolver else { return }
        let epoch = imageEpoch
        for source in authorizedImageSources.sorted() {
            guard imageTasks.count < 4 else { break }
            guard imageTasks[source] == nil, imageResolutionIDs[source] == nil else { continue }
            let requestID = UUID()
            imageTaskIDs[source] = requestID
            imageTasks[source] = Task.detached(priority: .utility) { [weak self, resolver] in
                let resolution = await resolver.resolveImage(for: source)
                guard !Task.isCancelled else { return }
                await self?.imageResolutionFinished(resolution, source: source, epoch: epoch, requestID: requestID)
            }
        }
    }

    private func imageResolutionFinished(_ resolution: MarkdownAsyncImageResolution, source: String, epoch: UUID, requestID: UUID) {
        guard epoch == imageEpoch, authorizedImageSources.contains(source), imageTaskIDs[source] == requestID else { return }
        imageTaskIDs.removeValue(forKey: source)
        imageTasks.removeValue(forKey: source)
        imageResolutionIDs[source] = resolution.cacheIdentity
        pendingImageRefreshes[source] = resolution
        startImageRequests()
        // Coalesce completion bursts, but keep a fixed deadline so a sustained
        // download stream cannot indefinitely postpone the first visible image.
        guard imageRefreshTask == nil else { return }
        imageRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.imageRefreshTask = nil
            let sources = self.pendingImageRefreshes
            self.pendingImageRefreshes.removeAll(keepingCapacity: true)
            if !sources.isEmpty { self.schedule(.refreshImages(sources)) }
        }
    }

    private func cancelImageResolution() {
        imageEpoch = UUID()
        imageTasks.values.forEach { $0.cancel() }
        imageTasks.removeAll()
        imageTaskIDs.removeAll()
        imageOwners.removeAll()
        if imageLoadingViewport != nil { imageLoadingViewport = [] }
        imageResolutionIDs.removeAll()
        authorizedImageSources.removeAll()
        pendingImageRefreshes.removeAll()
        imageRefreshTask?.cancel()
        imageRefreshTask = nil
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
        for operation in batch.operations {
            guard case let .refreshLinkMetadata(resolutions) = operation else { continue }
            preparedLinkMetadataResolutions.merge(resolutions) { _, latest in latest }
        }
        scheduleLinkMetadataResolution(in: state.snapshot)
        scheduleImageResolution(owners: state.imageOwners)
    }

    private func scheduleLinkMetadataResolution(in snapshot: MarkdownSnapshot) {
        guard let resolver = configuration.linkMetadataResolver,
              configuration.linkDecoration.isEnabled
        else {
            return
        }

        for destination in Self.externalHTTPSLinkDestinations(in: snapshot, policy: configuration.linkPolicy) {
            guard linkMetadataTasks[destination] == nil else { continue }
            let cachedResolution = resolver.cachedResolution(for: destination)
            if cachedResolution == .unavailable {
                linkMetadataResolutionFinished(.unavailable, destination: destination)
                continue
            }
            if let cachedResolution,
               preparedLinkMetadataResolutions[destination] == cachedResolution
            {
                continue
            }
            // Even a positive cache hit crosses an asynchronous boundary once.
            // The cache may have filled after the just-published preparation
            // read it; resolving (immediately) and scheduling one debounced
            // refresh closes that race without network work.
            linkMetadataTasks[destination] = Task { [weak self, resolver] in
                let resolution = await resolver.resolveMetadata(for: destination)
                guard !Task.isCancelled else { return }
                self?.linkMetadataResolutionFinished(resolution, destination: destination)
            }
        }
    }

    private func linkMetadataResolutionFinished(
        _ resolution: MarkdownLinkMetadataResolution,
        destination: URL
    ) {
        linkMetadataTasks.removeValue(forKey: destination)
        if resolution == .unavailable {
            if case .metadata? = preparedLinkMetadataResolutions[destination] {
                // A cleared or expired positive cache can legitimately fall
                // back to unavailable. Reprepare the affected link so a stale
                // branded icon does not survive the resolver's new state.
            } else {
                preparedLinkMetadataResolutions[destination] = .unavailable
                return
            }
        }
        guard preparedLinkMetadataResolutions[destination] != resolution else { return }
        pendingLinkMetadataRefreshes[destination] = resolution

        // A page of citations often completes several favicon requests in
        // one network burst. Debounce them into one preparation publication.
        linkMetadataRefreshTask?.cancel()
        linkMetadataRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.linkMetadataRefreshTask = nil
            guard let self else { return }
            let resolutions = self.pendingLinkMetadataRefreshes
            self.pendingLinkMetadataRefreshes.removeAll(keepingCapacity: true)
            guard !resolutions.isEmpty else { return }
            self.schedule(.refreshLinkMetadata(resolutions))
        }
    }

    private func cancelLinkMetadataResolution() {
        linkMetadataTasks.values.forEach { $0.cancel() }
        linkMetadataTasks.removeAll()
        preparedLinkMetadataResolutions.removeAll()
        pendingLinkMetadataRefreshes.removeAll()
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
                addBlocks(item.childBlocks)
                addListItems(item.childItems)
            }
        }

        func addBlocks(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                add(block.inlines)
                addBlocks(block.childBlocks)
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
            case .appendHostBoundary, .finish, .reset, .refreshLinkMetadata, .refreshImages:
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
    case refreshLinkMetadata([URL: MarkdownLinkMetadataResolution])
    case refreshImages([String: MarkdownAsyncImageResolution])
}

private struct MarkdownRenderSessionState: Sendable {
    var snapshot: MarkdownSnapshot
    var preparedSnapshot: MarkdownPreparedSnapshot
    var imageOwners: [String: Set<MarkdownBlockID>]
}

private struct MarkdownRenderSessionBatch: Sendable {
    var operations: [MarkdownRenderSessionOperation]
    var revision: Int
}

private actor MarkdownRenderSessionPipeline {
    private var stream: MarkdownStream
    private var imageIndex = MarkdownPreparedImageResourceIndex()
    // These values are part of the current document, shared with its prepared
    // attachments. Global cache eviction must not discard an in-flight result.
    private var resolvedImages: [String: MarkdownAsyncImageResolution] = [:]
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
        var invalidatingLinkDestinations: Set<URL> = []
        var invalidatingImageSources: Set<String> = []
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
                imageIndex = MarkdownPreparedImageResourceIndex()
                resolvedImages.removeAll()
            case let .refreshImages(resolutions):
                resolvedImages.merge(resolutions) { _, newest in newest }
                invalidatingImageSources.formUnion(resolutions.keys)
            case let .refreshLinkMetadata(resolutions):
                // Metadata changes presentation, not source semantics. Retain
                // the previous prepared snapshot and invalidate only top-level
                // blocks that actually contain one of the changed links.
                invalidatingLinkDestinations.formUnion(resolutions.keys)
            }
        }

        let snapshot = stream.snapshot()
        var invalidatingBlockIDs = Self.blockIDs(
            containingAny: invalidatingLinkDestinations,
            in: snapshot,
            policy: configuration.linkPolicy
        )
        for source in invalidatingImageSources { invalidatingBlockIDs.formUnion(imageIndex.owners[source] ?? []) }
        var preparationConfiguration = configuration
        if !resolvedImages.isEmpty {
            preparationConfiguration.imageResolver = MarkdownImageCompletionResolver(base: configuration.imageResolver, resolutions: resolvedImages)
        }
        let preparedSnapshot = preparationConfiguration.prepare(
            snapshot: snapshot,
            reusing: preparedSnapshot,
            invalidatingBlockIDs: invalidatingBlockIDs
        )
        self.preparedSnapshot = preparedSnapshot
        if configuration.imageResolver is any MarkdownAsyncImageResolver {
            imageIndex.update(preparedSnapshot)
            resolvedImages = resolvedImages.filter { imageIndex.owners[$0.key] != nil }
        }
        return MarkdownRenderSessionState(
            snapshot: snapshot,
            preparedSnapshot: preparedSnapshot,
            imageOwners: imageIndex.owners
        )
    }

    private nonisolated static func blockIDs(
        containingAny destinations: Set<URL>,
        in snapshot: MarkdownSnapshot,
        policy: any MarkdownLinkPolicy
    ) -> Set<MarkdownBlockID> {
        guard !destinations.isEmpty else { return [] }

        func runsContainDestination(_ runs: [MarkdownInlineRun]) -> Bool {
            runs.contains { run in
                guard let destination = run.destination,
                      let url = markdownLinkURL(for: destination, policy: policy)
                else {
                    return false
                }
                return destinations.contains(url)
            }
        }

        func listItemsContainDestination(_ items: [MarkdownListItem]) -> Bool {
            items.contains { item in
                runsContainDestination(item.inlines) ||
                    item.childBlocks.contains(where: blockContainsDestination) ||
                    listItemsContainDestination(item.childItems)
            }
        }

        func blockContainsDestination(_ block: MarkdownBlock) -> Bool {
            if runsContainDestination(block.inlines) ||
                block.childBlocks.contains(where: blockContainsDestination) ||
                listItemsContainDestination(block.listItems)
            {
                return true
            }
            if let table = block.table,
               (table.header + table.rows.flatMap { $0 }).contains(where: {
                   runsContainDestination($0.inlines)
               })
            {
                return true
            }
            return block.richContent?.blocks.contains(where: blockContainsDestination) == true
        }

        return Set(snapshot.blocks.compactMap { block in
            blockContainsDestination(block) ? block.id : nil
        })
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
