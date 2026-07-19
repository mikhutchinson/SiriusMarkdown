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
    /// UTF-8 source bytes submitted to syntax highlighters. This distinguishes
    /// bounded suffix work from repeatedly highlighting a complete growing
    /// code tail even when invocation counts are identical.
    public var codeHighlightByteCount: Int
    public var mermaidRenderCount: Int
    public var mermaidFallbackCount: Int
    public var mathRenderCount: Int
    public var mathFallbackCount: Int
    public var widthRelayoutCount: Int
    /// Table cells whose attributed/prepared inline payload was rebuilt.
    public var tableCellPreparationCount: Int
    /// Historical table cells copied from the preceding prepared snapshot.
    public var tableCellReuseCount: Int
    /// Cells visited by incremental table comparison. Historical prefix rows
    /// retained as prepared values do not increment this counter.
    public var tableCellIncrementalComparisonCount: Int
    /// Prepared cell widths inspected while updating incremental column maxima.
    public var tableColumnWidthScanCount: Int
    /// Publications that changed the bounded effective table column widths.
    public var tableColumnWidthChangeCount: Int
    /// Table rows whose SwiftUI subtree was asked for a fresh natural size.
    public var tableRowLayoutMeasurementCount: Int
    /// Table row natural sizes reused across SwiftUI layout passes/publications.
    public var tableRowLayoutCacheHitCount: Int
    public var boundaryScanCount: Int
    public var boundaryScannedByteCount: Int
    public var boundaryScannedLineCount: Int
    public var nonFiniteInlineProposalFallbackCount: Int
    public var overwideUnitFallbackCount: Int
    public var nativeLineClippingCount: Int
    /// Count of `MarkdownCoreTextPaintedLinePlan.make()` calls that ran
    /// inside `updateNSView`/`updateUIView` because the actual container
    /// width differed from the width used to pre-build the plan during
    /// `prepare(snapshot:)` (INV-P1). Should trend toward zero after the
    /// first block in a session, once `defaultLayoutWidth` tracks the real
    /// rendering width (Streaming Performance Part 01/02).
    public var coreTextLinePlanRebuiltInBodyCount: Int
    public var selectionPreferenceBodyEvaluationCount: Int
    public var selectionFrameQueryCount: Int
    public var inlineLineFragmentBuildCount: Int
    public var selectionTextGeometryInitializationCount: Int
    public var selectionFingerprintBuildCount: Int
    public var selectionSourceRunMappingCount: Int
    public var selectionPreferenceChangeCount: Int
    /// Count of times the `onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self)`
    /// closure body ran (i.e. `sortedForSelection()` was called), regardless
    /// of whether the sorted result actually differed from the previously
    /// stored fragments. Compared against `selectionPreferenceChangeCount`
    /// (which only increments when the result differs) to measure whether
    /// SwiftUI's own preference-equality gate already suppresses no-op
    /// re-sorts, or whether the sort genuinely runs on every layout pass
    /// regardless of content change (Streaming Performance Part 04, INV-P8).
    public var selectionPreferenceEvaluationCount: Int
    public var selectionCoreTextLineBuildCount: Int
    public var selectionLineFragmentCacheHitCount: Int
    public var selectionLineFragmentCacheMissCount: Int
    /// Cache hit/miss counts for the final, rect-mapped selection fragment
    /// array (as opposed to `selectionLineFragmentCache*`, which caches the
    /// rect-independent templates). Distinct from the template cache because
    /// a cache hit here skips the templates' `.map` into absolute rects too,
    /// which repeats identically across multiple layout-settle passes for
    /// the same (content, layout, rect) — Streaming Performance Part 04.
    public var selectionFragmentArrayCacheHitCount: Int
    public var selectionFragmentArrayCacheMissCount: Int
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
        codeHighlightByteCount: Int = 0,
        mermaidRenderCount: Int = 0,
        mermaidFallbackCount: Int = 0,
        mathRenderCount: Int = 0,
        mathFallbackCount: Int = 0,
        widthRelayoutCount: Int = 0,
        tableCellPreparationCount: Int = 0,
        tableCellReuseCount: Int = 0,
        tableCellIncrementalComparisonCount: Int = 0,
        tableColumnWidthScanCount: Int = 0,
        tableColumnWidthChangeCount: Int = 0,
        tableRowLayoutMeasurementCount: Int = 0,
        tableRowLayoutCacheHitCount: Int = 0,
        boundaryScanCount: Int = 0,
        boundaryScannedByteCount: Int = 0,
        boundaryScannedLineCount: Int = 0,
        nonFiniteInlineProposalFallbackCount: Int = 0,
        overwideUnitFallbackCount: Int = 0,
        nativeLineClippingCount: Int = 0,
        coreTextLinePlanRebuiltInBodyCount: Int = 0,
        selectionPreferenceBodyEvaluationCount: Int = 0,
        selectionFrameQueryCount: Int = 0,
        inlineLineFragmentBuildCount: Int = 0,
        selectionTextGeometryInitializationCount: Int = 0,
        selectionFingerprintBuildCount: Int = 0,
        selectionSourceRunMappingCount: Int = 0,
        selectionPreferenceChangeCount: Int = 0,
        selectionPreferenceEvaluationCount: Int = 0,
        selectionCoreTextLineBuildCount: Int = 0,
        selectionLineFragmentCacheHitCount: Int = 0,
        selectionLineFragmentCacheMissCount: Int = 0,
        selectionFragmentArrayCacheHitCount: Int = 0,
        selectionFragmentArrayCacheMissCount: Int = 0,
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
        self.codeHighlightByteCount = codeHighlightByteCount
        self.mermaidRenderCount = mermaidRenderCount
        self.mermaidFallbackCount = mermaidFallbackCount
        self.mathRenderCount = mathRenderCount
        self.mathFallbackCount = mathFallbackCount
        self.widthRelayoutCount = widthRelayoutCount
        self.tableCellPreparationCount = tableCellPreparationCount
        self.tableCellReuseCount = tableCellReuseCount
        self.tableCellIncrementalComparisonCount = tableCellIncrementalComparisonCount
        self.tableColumnWidthScanCount = tableColumnWidthScanCount
        self.tableColumnWidthChangeCount = tableColumnWidthChangeCount
        self.tableRowLayoutMeasurementCount = tableRowLayoutMeasurementCount
        self.tableRowLayoutCacheHitCount = tableRowLayoutCacheHitCount
        self.boundaryScanCount = boundaryScanCount
        self.boundaryScannedByteCount = boundaryScannedByteCount
        self.boundaryScannedLineCount = boundaryScannedLineCount
        self.nonFiniteInlineProposalFallbackCount = nonFiniteInlineProposalFallbackCount
        self.overwideUnitFallbackCount = overwideUnitFallbackCount
        self.nativeLineClippingCount = nativeLineClippingCount
        self.coreTextLinePlanRebuiltInBodyCount = coreTextLinePlanRebuiltInBodyCount
        self.selectionPreferenceBodyEvaluationCount = selectionPreferenceBodyEvaluationCount
        self.selectionFrameQueryCount = selectionFrameQueryCount
        self.inlineLineFragmentBuildCount = inlineLineFragmentBuildCount
        self.selectionTextGeometryInitializationCount = selectionTextGeometryInitializationCount
        self.selectionFingerprintBuildCount = selectionFingerprintBuildCount
        self.selectionSourceRunMappingCount = selectionSourceRunMappingCount
        self.selectionPreferenceChangeCount = selectionPreferenceChangeCount
        self.selectionPreferenceEvaluationCount = selectionPreferenceEvaluationCount
        self.selectionCoreTextLineBuildCount = selectionCoreTextLineBuildCount
        self.selectionLineFragmentCacheHitCount = selectionLineFragmentCacheHitCount
        self.selectionLineFragmentCacheMissCount = selectionLineFragmentCacheMissCount
        self.selectionFragmentArrayCacheHitCount = selectionFragmentArrayCacheHitCount
        self.selectionFragmentArrayCacheMissCount = selectionFragmentArrayCacheMissCount
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

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func snapshot() -> MarkdownDiagnosticsCounters {
        withLock {
            counters
        }
    }

    public func recordParse(isSealedRegion: Bool) {
        withLock {
            counters.parseCount += 1
            if isSealedRegion {
                counters.sealedRegionParseCount += 1
            } else {
                counters.tailReparseCount += 1
            }
        }
    }

    public func recordPrepare() {
        withLock {
            counters.prepareCount += 1
        }
    }

    public func recordLayout() {
        withLock {
            counters.layoutCount += 1
        }
    }

    public func recordRenderPreparation() {
        withLock {
            counters.renderPreparationCount += 1
        }
    }

    public func recordCodeHighlight() {
        recordCodeHighlight(bytes: 0)
    }

    public func recordCodeHighlight(bytes: Int) {
        withLock {
            counters.codeHighlightCount += 1
            counters.codeHighlightByteCount += max(0, bytes)
        }
    }

    public func recordMermaidRender() {
        withLock {
            counters.mermaidRenderCount += 1
        }
    }

    public func recordMermaidFallback() {
        withLock {
            counters.mermaidFallbackCount += 1
        }
    }

    public func recordMathRender() {
        withLock {
            counters.mathRenderCount += 1
        }
    }

    public func recordMathFallback() {
        withLock {
            counters.mathFallbackCount += 1
        }
    }

    public func recordWidthRelayout() {
        withLock {
            counters.widthRelayoutCount += 1
        }
    }

    public func recordTableCellPreparation() {
        withLock {
            counters.tableCellPreparationCount += 1
        }
    }

    public func recordTableCellReuse(count: Int = 1) {
        guard count > 0 else { return }
        withLock {
            counters.tableCellReuseCount += count
        }
    }

    public func recordTableCellIncrementalComparison() {
        withLock {
            counters.tableCellIncrementalComparisonCount += 1
        }
    }

    public func recordTableColumnWidthScan(count: Int = 1) {
        guard count > 0 else { return }
        withLock {
            counters.tableColumnWidthScanCount += count
        }
    }

    public func recordTableColumnWidthChange() {
        withLock {
            counters.tableColumnWidthChangeCount += 1
        }
    }

    public func recordTableRowLayoutMeasurement() {
        withLock {
            counters.tableRowLayoutMeasurementCount += 1
        }
    }

    public func recordTableRowLayoutCacheHit() {
        withLock {
            counters.tableRowLayoutCacheHitCount += 1
        }
    }

    public func recordBoundaryScan(bytes: Int, lines: Int) {
        withLock {
            counters.boundaryScanCount += 1
            counters.boundaryScannedByteCount += bytes
            counters.boundaryScannedLineCount += lines
        }
    }

    public func recordOverwideUnitFallback() {
        withLock {
            counters.overwideUnitFallbackCount += 1
        }
    }

    public func recordNonFiniteInlineProposalFallback() {
        withLock {
            counters.nonFiniteInlineProposalFallbackCount += 1
        }
    }

    public func recordNativeLineClipping() {
        withLock {
            counters.nativeLineClippingCount += 1
        }
    }

    public func recordCoreTextLinePlanRebuiltInBody() {
        withLock {
            counters.coreTextLinePlanRebuiltInBodyCount += 1
        }
    }

    public func recordSelectionPreferenceBodyEvaluation() {
        withLock {
            counters.selectionPreferenceBodyEvaluationCount += 1
        }
    }

    public func recordSelectionFrameQuery() {
        withLock {
            counters.selectionFrameQueryCount += 1
        }
    }

    public func recordInlineLineFragmentBuild(count: Int = 1) {
        withLock {
            counters.inlineLineFragmentBuildCount += count
        }
    }

    public func recordSelectionTextGeometryInitialization() {
        withLock {
            counters.selectionTextGeometryInitializationCount += 1
        }
    }

    public func recordSelectionFingerprintBuild() {
        withLock {
            counters.selectionFingerprintBuildCount += 1
        }
    }

    public func recordSelectionSourceRunMapping(count: Int = 1) {
        withLock {
            counters.selectionSourceRunMappingCount += count
        }
    }

    public func recordSelectionPreferenceChange() {
        withLock {
            counters.selectionPreferenceChangeCount += 1
        }
    }

    public func recordSelectionPreferenceEvaluation() {
        withLock {
            counters.selectionPreferenceEvaluationCount += 1
        }
    }

    public func recordSelectionCoreTextLineBuild() {
        withLock {
            counters.selectionCoreTextLineBuildCount += 1
        }
    }

    public func recordSelectionLineFragmentCacheHit() {
        withLock {
            counters.selectionLineFragmentCacheHitCount += 1
        }
    }

    public func recordSelectionLineFragmentCacheMiss() {
        withLock {
            counters.selectionLineFragmentCacheMissCount += 1
        }
    }

    public func recordSelectionFragmentArrayCacheHit() {
        withLock {
            counters.selectionFragmentArrayCacheHitCount += 1
        }
    }

    public func recordSelectionFragmentArrayCacheMiss() {
        withLock {
            counters.selectionFragmentArrayCacheMissCount += 1
        }
    }

    public func recordCacheHit(isSealedRegion: Bool = false) {
        withLock {
            counters.cacheHitCount += 1
            if isSealedRegion {
                counters.sealedRegionCacheHitCount += 1
            }
        }
    }

    public func recordCacheMiss(isSealedRegion: Bool = false) {
        withLock {
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
