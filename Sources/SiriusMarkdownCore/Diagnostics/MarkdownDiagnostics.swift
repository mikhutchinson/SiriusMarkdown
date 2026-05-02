import Foundation
import os

public struct MarkdownDiagnosticsCounters: Sendable, Hashable {
    public var parseCount: Int
    public var sealedRegionParseCount: Int
    public var tailReparseCount: Int
    public var prepareCount: Int
    public var layoutCount: Int
    public var renderPreparationCount: Int
    public var codeHighlightCount: Int
    public var mathRenderCount: Int
    public var widthRelayoutCount: Int
    public var boundaryScanCount: Int
    public var boundaryScannedByteCount: Int
    public var boundaryScannedLineCount: Int
    public var nonFiniteInlineProposalFallbackCount: Int
    public var overwideUnitFallbackCount: Int
    public var nativeLineClippingCount: Int
    public var cacheHitCount: Int
    public var cacheMissCount: Int
    public var sealedRegionCacheHitCount: Int
    public var sealedRegionCacheMissCount: Int

    public init(
        parseCount: Int = 0,
        sealedRegionParseCount: Int = 0,
        tailReparseCount: Int = 0,
        prepareCount: Int = 0,
        layoutCount: Int = 0,
        renderPreparationCount: Int = 0,
        codeHighlightCount: Int = 0,
        mathRenderCount: Int = 0,
        widthRelayoutCount: Int = 0,
        boundaryScanCount: Int = 0,
        boundaryScannedByteCount: Int = 0,
        boundaryScannedLineCount: Int = 0,
        nonFiniteInlineProposalFallbackCount: Int = 0,
        overwideUnitFallbackCount: Int = 0,
        nativeLineClippingCount: Int = 0,
        cacheHitCount: Int = 0,
        cacheMissCount: Int = 0,
        sealedRegionCacheHitCount: Int = 0,
        sealedRegionCacheMissCount: Int = 0
    ) {
        self.parseCount = parseCount
        self.sealedRegionParseCount = sealedRegionParseCount
        self.tailReparseCount = tailReparseCount
        self.prepareCount = prepareCount
        self.layoutCount = layoutCount
        self.renderPreparationCount = renderPreparationCount
        self.codeHighlightCount = codeHighlightCount
        self.mathRenderCount = mathRenderCount
        self.widthRelayoutCount = widthRelayoutCount
        self.boundaryScanCount = boundaryScanCount
        self.boundaryScannedByteCount = boundaryScannedByteCount
        self.boundaryScannedLineCount = boundaryScannedLineCount
        self.nonFiniteInlineProposalFallbackCount = nonFiniteInlineProposalFallbackCount
        self.overwideUnitFallbackCount = overwideUnitFallbackCount
        self.nativeLineClippingCount = nativeLineClippingCount
        self.cacheHitCount = cacheHitCount
        self.cacheMissCount = cacheMissCount
        self.sealedRegionCacheHitCount = sealedRegionCacheHitCount
        self.sealedRegionCacheMissCount = sealedRegionCacheMissCount
    }
}

public final class MarkdownDiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counters = MarkdownDiagnosticsCounters()

    public init() {}

    public func snapshot() -> MarkdownDiagnosticsCounters {
        lock.withLock {
            counters
        }
    }

    public func recordParse(isSealedRegion: Bool) {
        lock.withLock {
            counters.parseCount += 1
            if isSealedRegion {
                counters.sealedRegionParseCount += 1
            } else {
                counters.tailReparseCount += 1
            }
        }
    }

    public func recordPrepare() {
        lock.withLock {
            counters.prepareCount += 1
        }
    }

    public func recordLayout() {
        lock.withLock {
            counters.layoutCount += 1
        }
    }

    public func recordRenderPreparation() {
        lock.withLock {
            counters.renderPreparationCount += 1
        }
    }

    public func recordCodeHighlight() {
        lock.withLock {
            counters.codeHighlightCount += 1
        }
    }

    public func recordMathRender() {
        lock.withLock {
            counters.mathRenderCount += 1
        }
    }

    public func recordWidthRelayout() {
        lock.withLock {
            counters.widthRelayoutCount += 1
        }
    }

    public func recordBoundaryScan(bytes: Int, lines: Int) {
        lock.withLock {
            counters.boundaryScanCount += 1
            counters.boundaryScannedByteCount += bytes
            counters.boundaryScannedLineCount += lines
        }
    }

    public func recordOverwideUnitFallback() {
        lock.withLock {
            counters.overwideUnitFallbackCount += 1
        }
    }

    public func recordNonFiniteInlineProposalFallback() {
        lock.withLock {
            counters.nonFiniteInlineProposalFallbackCount += 1
        }
    }

    public func recordNativeLineClipping() {
        lock.withLock {
            counters.nativeLineClippingCount += 1
        }
    }

    public func recordCacheHit(isSealedRegion: Bool = false) {
        lock.withLock {
            counters.cacheHitCount += 1
            if isSealedRegion {
                counters.sealedRegionCacheHitCount += 1
            }
        }
    }

    public func recordCacheMiss(isSealedRegion: Bool = false) {
        lock.withLock {
            counters.cacheMissCount += 1
            if isSealedRegion {
                counters.sealedRegionCacheMissCount += 1
            }
        }
    }
}

public struct MarkdownDiagnostics: Sendable {
    public static let subsystem = "SiriusMarkdown"

    public init() {}

    public func makeLog(category: String) -> OSLog {
        OSLog(subsystem: Self.subsystem, category: category)
    }

    public func signpost<T>(
        _ name: StaticString,
        category: String,
        _ body: () throws -> T
    ) rethrows -> T {
        let log = makeLog(category: category)
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return try body()
    }

    public func signpostEvent(_ name: StaticString, category: String) {
        os_signpost(.event, log: makeLog(category: category), name: name)
    }

    public func debugDump(_ snapshot: MarkdownSnapshot) -> String {
        snapshot.blocks
            .map { "\($0.id.rawValue) \($0.kind.rawValue) \($0.sourceRange.byteRange)" }
            .joined(separator: "\n")
    }
}
