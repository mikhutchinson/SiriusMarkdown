import SiriusMarkdownCore
import Foundation
import SwiftUI

@MainActor
public final class MarkdownRenderSession: ObservableObject {
    @Published public private(set) var preparedSnapshot: MarkdownPreparedSnapshot
    @Published public private(set) var snapshot: MarkdownSnapshot

    public private(set) var configuration: MarkdownRendererConfiguration
    public let streamDiagnosticsRecorder: MarkdownDiagnosticsRecorder
    public let renderDiagnosticsRecorder: MarkdownDiagnosticsRecorder

    private let pipeline: MarkdownRenderSessionPipeline
    private let sourceCopyStore: MarkdownMutableSourceCopyStore
    private let parserCacheCapacity: Int
    private var renderTask: Task<Void, Never>?
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
        self.preparedSnapshot = sessionConfiguration.prepare(snapshot: snapshot)
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
        let revision = presentationRevision
        let previousTask = renderTask
        let pipeline = pipeline
        renderTask = Task(priority: .userInitiated) { [weak self] in
            await previousTask?.value
            let state = await pipeline.apply(operation)
            await MainActor.run {
                guard let self else {
                    return
                }
                guard revision == self.presentationRevision else {
                    return
                }
                self.snapshot = state.snapshot
                self.preparedSnapshot = state.preparedSnapshot
            }
        }
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

private actor MarkdownRenderSessionPipeline {
    private var stream: MarkdownStream
    private var configuration: MarkdownRendererConfiguration
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
        self.stream = MarkdownStream(
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    func apply(_ operation: MarkdownRenderSessionOperation) -> MarkdownRenderSessionState {
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
        }

        let snapshot = stream.snapshot()
        return MarkdownRenderSessionState(
            snapshot: snapshot,
            preparedSnapshot: configuration.prepare(snapshot: snapshot)
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
