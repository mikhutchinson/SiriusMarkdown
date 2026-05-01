import Foundation
import os

public struct MarkdownDiagnosticsCounters: Sendable, Hashable {
    public var parseCount: Int
    public var sealedRegionParseCount: Int
    public var tailReparseCount: Int
    public var prepareCount: Int
    public var layoutCount: Int
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

    public func debugDump(_ snapshot: MarkdownSnapshot) -> String {
        snapshot.blocks
            .map { "\($0.id.rawValue) \($0.kind.rawValue) \($0.sourceRange.byteRange)" }
            .joined(separator: "\n")
    }
}
