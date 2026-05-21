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
    public var mermaidRenderCount: Int
    public var mermaidFallbackCount: Int
    public var mathRenderCount: Int
    public var widthRelayoutCount: Int
    public var boundaryScanCount: Int
    public var boundaryScannedByteCount: Int
    public var boundaryScannedLineCount: Int
    public var nonFiniteInlineProposalFallbackCount: Int
    public var overwideUnitFallbackCount: Int
    public var nativeLineClippingCount: Int
    public var selectionPreferenceBodyEvaluationCount: Int
    public var selectionFrameQueryCount: Int
    public var inlineLineFragmentBuildCount: Int
    public var selectionTextGeometryInitializationCount: Int
    public var selectionFingerprintBuildCount: Int
    public var selectionSourceRunMappingCount: Int
    public var selectionPreferenceChangeCount: Int
    public var selectionCoreTextLineBuildCount: Int
    public var selectionLineFragmentCacheHitCount: Int
    public var selectionLineFragmentCacheMissCount: Int
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
        mermaidRenderCount: Int = 0,
        mermaidFallbackCount: Int = 0,
        mathRenderCount: Int = 0,
        widthRelayoutCount: Int = 0,
        boundaryScanCount: Int = 0,
        boundaryScannedByteCount: Int = 0,
        boundaryScannedLineCount: Int = 0,
        nonFiniteInlineProposalFallbackCount: Int = 0,
        overwideUnitFallbackCount: Int = 0,
        nativeLineClippingCount: Int = 0,
        selectionPreferenceBodyEvaluationCount: Int = 0,
        selectionFrameQueryCount: Int = 0,
        inlineLineFragmentBuildCount: Int = 0,
        selectionTextGeometryInitializationCount: Int = 0,
        selectionFingerprintBuildCount: Int = 0,
        selectionSourceRunMappingCount: Int = 0,
        selectionPreferenceChangeCount: Int = 0,
        selectionCoreTextLineBuildCount: Int = 0,
        selectionLineFragmentCacheHitCount: Int = 0,
        selectionLineFragmentCacheMissCount: Int = 0,
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
        self.mermaidRenderCount = mermaidRenderCount
        self.mermaidFallbackCount = mermaidFallbackCount
        self.mathRenderCount = mathRenderCount
        self.widthRelayoutCount = widthRelayoutCount
        self.boundaryScanCount = boundaryScanCount
        self.boundaryScannedByteCount = boundaryScannedByteCount
        self.boundaryScannedLineCount = boundaryScannedLineCount
        self.nonFiniteInlineProposalFallbackCount = nonFiniteInlineProposalFallbackCount
        self.overwideUnitFallbackCount = overwideUnitFallbackCount
        self.nativeLineClippingCount = nativeLineClippingCount
        self.selectionPreferenceBodyEvaluationCount = selectionPreferenceBodyEvaluationCount
        self.selectionFrameQueryCount = selectionFrameQueryCount
        self.inlineLineFragmentBuildCount = inlineLineFragmentBuildCount
        self.selectionTextGeometryInitializationCount = selectionTextGeometryInitializationCount
        self.selectionFingerprintBuildCount = selectionFingerprintBuildCount
        self.selectionSourceRunMappingCount = selectionSourceRunMappingCount
        self.selectionPreferenceChangeCount = selectionPreferenceChangeCount
        self.selectionCoreTextLineBuildCount = selectionCoreTextLineBuildCount
        self.selectionLineFragmentCacheHitCount = selectionLineFragmentCacheHitCount
        self.selectionLineFragmentCacheMissCount = selectionLineFragmentCacheMissCount
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

    public func recordMermaidRender() {
        lock.withLock {
            counters.mermaidRenderCount += 1
        }
    }

    public func recordMermaidFallback() {
        lock.withLock {
            counters.mermaidFallbackCount += 1
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

    public func recordSelectionPreferenceBodyEvaluation() {
        lock.withLock {
            counters.selectionPreferenceBodyEvaluationCount += 1
        }
    }

    public func recordSelectionFrameQuery() {
        lock.withLock {
            counters.selectionFrameQueryCount += 1
        }
    }

    public func recordInlineLineFragmentBuild(count: Int = 1) {
        lock.withLock {
            counters.inlineLineFragmentBuildCount += count
        }
    }

    public func recordSelectionTextGeometryInitialization() {
        lock.withLock {
            counters.selectionTextGeometryInitializationCount += 1
        }
    }

    public func recordSelectionFingerprintBuild() {
        lock.withLock {
            counters.selectionFingerprintBuildCount += 1
        }
    }

    public func recordSelectionSourceRunMapping(count: Int = 1) {
        lock.withLock {
            counters.selectionSourceRunMappingCount += count
        }
    }

    public func recordSelectionPreferenceChange() {
        lock.withLock {
            counters.selectionPreferenceChangeCount += 1
        }
    }

    public func recordSelectionCoreTextLineBuild() {
        lock.withLock {
            counters.selectionCoreTextLineBuildCount += 1
        }
    }

    public func recordSelectionLineFragmentCacheHit() {
        lock.withLock {
            counters.selectionLineFragmentCacheHitCount += 1
        }
    }

    public func recordSelectionLineFragmentCacheMiss() {
        lock.withLock {
            counters.selectionLineFragmentCacheMissCount += 1
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
