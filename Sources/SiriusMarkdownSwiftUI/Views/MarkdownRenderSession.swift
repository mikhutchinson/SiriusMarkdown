import SiriusMarkdownCore
import SwiftUI

@MainActor
public final class MarkdownRenderSession: ObservableObject {
    @Published public private(set) var preparedSnapshot: MarkdownPreparedSnapshot
    @Published public private(set) var snapshot: MarkdownSnapshot

    public private(set) var configuration: MarkdownRendererConfiguration
    public let streamDiagnosticsRecorder: MarkdownDiagnosticsRecorder
    public let renderDiagnosticsRecorder: MarkdownDiagnosticsRecorder

    private var stream: MarkdownStream
    private let sourceCopyStore: MarkdownMutableSourceCopyStore
    private let parserCacheCapacity: Int

    public init(
        configuration: MarkdownRendererConfiguration = .compactChat,
        parserCacheCapacity: Int = 256,
        streamDiagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder(),
        renderDiagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.streamDiagnosticsRecorder = streamDiagnosticsRecorder
        self.renderDiagnosticsRecorder = renderDiagnosticsRecorder
        self.parserCacheCapacity = parserCacheCapacity
        self.stream = MarkdownStream(
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: streamDiagnosticsRecorder
        )
        self.sourceCopyStore = MarkdownMutableSourceCopyStore()

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
        self.configuration = sessionConfiguration

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
        stream.sourceLength
    }

    public func append(_ markdown: String) {
        guard !markdown.isEmpty else {
            return
        }

        sourceCopyStore.append(markdown)
        stream.append(markdown)
        refreshPreparedSnapshot()
    }

    public func appendHostBoundary(id: MarkdownHostBoundaryID? = nil) {
        stream.appendHostBoundary(id: id)
        refreshPreparedSnapshot()
    }

    public func finish() {
        stream.finish()
        refreshPreparedSnapshot()
    }

    public func markdown(in sourceRange: MarkdownSourceRange) -> String {
        stream.markdown(in: sourceRange)
    }

    public func reset() {
        stream = MarkdownStream(
            parserCacheCapacity: parserCacheCapacity,
            diagnosticsRecorder: streamDiagnosticsRecorder
        )
        sourceCopyStore.removeAll()
        configuration.preparationCache.removeAll()
        refreshPreparedSnapshot()
    }

    private func refreshPreparedSnapshot() {
        let latestSnapshot = stream.snapshot()
        snapshot = latestSnapshot
        preparedSnapshot = configuration.prepare(snapshot: latestSnapshot)
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

private final class MarkdownMutableSourceCopyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var source = ""

    func append(_ markdown: String) {
        lock.withLock {
            source.append(markdown)
        }
    }

    func removeAll() {
        lock.withLock {
            source.removeAll(keepingCapacity: true)
        }
    }

    var markdown: String {
        lock.withLock {
            source
        }
    }

    func markdown(in sourceRange: MarkdownSourceRange) -> String? {
        lock.withLock {
            let byteRange = sourceRange.byteRange
            guard byteRange.lowerBound >= 0,
                  byteRange.lowerBound <= byteRange.upperBound,
                  byteRange.upperBound <= source.utf8.count,
                  let lowerUTF8 = source.utf8.index(
                      source.utf8.startIndex,
                      offsetBy: byteRange.lowerBound,
                      limitedBy: source.utf8.endIndex
                  ),
                  let upperUTF8 = source.utf8.index(
                      source.utf8.startIndex,
                      offsetBy: byteRange.upperBound,
                      limitedBy: source.utf8.endIndex
                  ),
                  let lower = String.Index(lowerUTF8, within: source),
                  let upper = String.Index(upperUTF8, within: source)
            else {
                return nil
            }

            return String(source[lower..<upper])
        }
    }
}
