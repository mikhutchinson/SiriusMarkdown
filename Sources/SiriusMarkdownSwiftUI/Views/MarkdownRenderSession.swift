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
        schedule(.reset)
    }

    public func waitUntilIdle() async {
        let task = renderTask
        await task?.value
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
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            while true {
                let batch = await MainActor.run { () -> MarkdownRenderSessionBatch? in
                    guard let self else {
                        return nil
                    }

                    guard !self.pendingOperations.isEmpty else {
                        self.renderTask = nil
                        return nil
                    }

                    let operations = self.drainPendingOperations()
                    return MarkdownRenderSessionBatch(
                        operations: operations,
                        revision: self.presentationRevision
                    )
                }

                guard let batch else {
                    return
                }

                let state = await pipeline.apply(batch.operations)
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    guard batch.revision == self.presentationRevision else {
                        return
                    }
                    self.snapshot = state.snapshot
                    self.preparedSnapshot = state.preparedSnapshot
                    self.snapshotDiff = state.preparedSnapshot.diff
                }
            }
        }
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
            case .appendHostBoundary, .finish, .reset:
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
