import Foundation
import SiriusMarkdownCore
import SwiftUI

#if canImport(CoreText)
import CoreText
#endif

let markdownDocumentSelectionCoordinateSpaceName = "SiriusMarkdownDocumentSelectionSpace"

struct MarkdownDocumentSelectionContext: Equatable {
    var blockID: MarkdownBlockID
}

private struct MarkdownDocumentSelectionContextKey: EnvironmentKey {
    static let defaultValue: MarkdownDocumentSelectionContext? = nil
}

extension EnvironmentValues {
    var markdownDocumentSelectionContext: MarkdownDocumentSelectionContext? {
        get { self[MarkdownDocumentSelectionContextKey.self] }
        set { self[MarkdownDocumentSelectionContextKey.self] = newValue }
    }

    var markdownSelectionController: MarkdownSelectionController? {
        get { self[MarkdownSelectionControllerKey.self] }
        set { self[MarkdownSelectionControllerKey.self] = newValue }
    }
}

private struct MarkdownSelectionControllerKey: EnvironmentKey {
    static let defaultValue: MarkdownSelectionController? = nil
}

struct MarkdownDocumentSelectionEndpoint: Equatable {
    var blockID: MarkdownBlockID
    var sourceByteOffset: Int
    var line: Int
}

struct MarkdownDocumentSelectionHighlight: Identifiable {
    var id: String
    var rect: CGRect
}

struct MarkdownDocumentSelectionDragActivation: Equatable, Sendable {
    static let defaultMinimumDistance: CGFloat = 4

    var minimumDistance: CGFloat = Self.defaultMinimumDistance

    func hasActivated(start: CGPoint, current: CGPoint) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return dx * dx + dy * dy >= minimumDistance * minimumDistance
    }
}

struct MarkdownDocumentSelectionFragment: Identifiable, Equatable {
    var id: String
    var blockID: MarkdownBlockID
    var sourceRange: MarkdownSourceRange
    var rect: CGRect
    var textGeometry: MarkdownDocumentSelectionTextGeometry? = nil

    static func == (
        lhs: MarkdownDocumentSelectionFragment,
        rhs: MarkdownDocumentSelectionFragment
    ) -> Bool {
        lhs.id == rhs.id &&
            lhs.blockID == rhs.blockID &&
            lhs.sourceRange == rhs.sourceRange &&
            lhs.rect == rhs.rect &&
            lhs.textGeometry == rhs.textGeometry
    }

    static func selection(
        from lower: MarkdownDocumentSelectionEndpoint,
        to upper: MarkdownDocumentSelectionEndpoint,
        in fragments: [MarkdownDocumentSelectionFragment]
    ) -> (ranges: [MarkdownSourceRange], blockIDs: [MarkdownBlockID]) {
        let lowerBound = min(lower.sourceByteOffset, upper.sourceByteOffset)
        let upperBound = max(lower.sourceByteOffset, upper.sourceByteOffset)
        guard lowerBound < upperBound else {
            return ([], [])
        }

        let selectedFragments = fragments.filter {
            $0.sourceRange.byteRange.lowerBound < upperBound &&
                lowerBound < $0.sourceRange.byteRange.upperBound
        }
        let lineLower = selectedFragments.map(\.sourceRange.lineRange.lowerBound).min() ??
            min(lower.line, upper.line)
        let lineUpper = selectedFragments.map(\.sourceRange.lineRange.upperBound).max() ??
            max(lower.line + 1, upper.line + 1)
        let blockIDs = selectedFragments.map(\.blockID).orderedUnique()
        let range = MarkdownSourceRange(
            byteRange: lowerBound..<upperBound,
            lineRange: lineLower..<lineUpper
        )
        return ([range], blockIDs)
    }

    static func selection(
        from lower: MarkdownDocumentSelectionFragment,
        to upper: MarkdownDocumentSelectionFragment,
        in fragments: [MarkdownDocumentSelectionFragment]
    ) -> (ranges: [MarkdownSourceRange], blockIDs: [MarkdownBlockID]) {
        let selectsForward = lower.sourceRange.byteRange.lowerBound <= upper.sourceRange.byteRange.lowerBound
        let lowerEndpoint = MarkdownDocumentSelectionEndpoint(
            blockID: lower.blockID,
            sourceByteOffset: selectsForward
                ? lower.sourceRange.byteRange.lowerBound
                : lower.sourceRange.byteRange.upperBound,
            line: selectsForward ? lower.sourceRange.lineRange.lowerBound : lower.sourceRange.lineRange.upperBound
        )
        let upperEndpoint = MarkdownDocumentSelectionEndpoint(
            blockID: upper.blockID,
            sourceByteOffset: selectsForward
                ? upper.sourceRange.byteRange.upperBound
                : upper.sourceRange.byteRange.lowerBound,
            line: selectsForward ? upper.sourceRange.lineRange.upperBound : upper.sourceRange.lineRange.lowerBound
        )
        return selection(from: lowerEndpoint, to: upperEndpoint, in: fragments)
    }

    static func fragments(
        for block: MarkdownBlock,
        preparedContent: MarkdownPreparedBlockContent,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return [blockFragment(for: block, rect: rect)]
        }

        if !preparedContent.listItems.isEmpty {
            let itemFragments = listFragments(
                block: block,
                items: preparedContent.listItems,
                rect: rect
            )
            if !itemFragments.isEmpty {
                return itemFragments
            }
        }

        if let table = preparedContent.table {
            let cellFragments = tableCellFragments(block: block, table: table, rect: rect)
            if !cellFragments.isEmpty {
                return cellFragments
            }
        }

        if let inlineLayout = preparedContent.inlineLayout {
            let lines = inlineLineFragments(
                blockID: block.id,
                prepared: inlineLayout,
                layout: inlineLayout.layout(
                    containerWidth: InlineRunsView.nativeLineLayoutWidth(
                        for: inlineLayout,
                        containerWidth: Double(rect.width)
                    ),
                    allowsOverwideFallback: true
                ),
                rect: rect,
                idPrefix: "block"
            )
            if !lines.isEmpty {
                return lines
            }
        }

        if let selectionInlineLayout = preparedContent.selectionInlineLayout {
            let lines = inlineLineFragments(
                blockID: block.id,
                prepared: selectionInlineLayout,
                layout: selectionInlineLayout.layout(
                    containerWidth: InlineRunsView.nativeLineLayoutWidth(
                        for: selectionInlineLayout,
                        containerWidth: Double(rect.width)
                    ),
                    allowsOverwideFallback: true
                ),
                rect: rect,
                idPrefix: "block-selection"
            )
            if !lines.isEmpty {
                return lines
            }
        }

        return [blockFragment(for: block, rect: rect)]
    }

    static func inlineLineFragments(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        rect: CGRect,
        idPrefix: String
    ) -> [MarkdownDocumentSelectionFragment] {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return []
        }
        guard !layout.lines.isEmpty else {
            return []
        }

        let lineHeight = CGFloat(prepared.lineHeight)
        let spacing = InlineRunsView.nativeLineSpacing(for: prepared)
        return prepared.layoutCache.selectionLineFragmentTemplates(
            blockID: blockID,
            prepared: prepared,
            layout: layout,
            idPrefix: idPrefix
        ).map { template in
            template.fragment(in: rect, lineHeight: lineHeight, spacing: spacing)
        }
    }

    static func makeInlineLineFragmentTemplates(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        idPrefix: String,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder
    ) -> [MarkdownDocumentSelectionLineFragmentTemplate] {
        diagnosticsRecorder.recordInlineLineFragmentBuild(count: layout.lines.count)
        return layout.lines.enumerated().compactMap { index, line in
            guard let sourceRange = sourceRange(
                for: line.consumedByteRange,
                in: prepared,
                diagnosticsRecorder: diagnosticsRecorder
            ) else {
                return nil
            }
            let textGeometry = MarkdownDocumentSelectionTextGeometry(
                prepared: prepared,
                line: line,
                diagnosticsRecorder: diagnosticsRecorder
            )
            let lineWidth = max(
                1,
                CGFloat(max(line.width, 1)) + InlineRunsView.nativeLinePaintGuard(for: prepared)
            )
            return MarkdownDocumentSelectionLineFragmentTemplate(
                id: "\(idPrefix):\(blockID.rawValue):line:\(index):\(sourceRange.byteRange.lowerBound)",
                blockID: blockID,
                sourceRange: sourceRange,
                lineIndex: index,
                lineWidth: lineWidth,
                textGeometry: textGeometry
            )
        }
    }

    static func fallbackTextFragment(
        blockID: MarkdownBlockID,
        sourceRange: MarkdownSourceRange,
        rect: CGRect,
        idPrefix: String
    ) -> MarkdownDocumentSelectionFragment {
        MarkdownDocumentSelectionFragment(
            id: "\(idPrefix):\(blockID.rawValue):\(sourceRange.byteRange.lowerBound)",
            blockID: blockID,
            sourceRange: sourceRange,
            rect: rect
        )
    }

    static func hitFragment(
        at location: CGPoint,
        in fragments: [MarkdownDocumentSelectionFragment],
        hitSlop: CGFloat
    ) -> MarkdownDocumentSelectionFragment? {
        if let direct = fragments.first(where: { $0.rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(location) }) {
            return direct
        }

        return fragments
            .filter { fragment in
                location.y >= fragment.rect.minY - hitSlop &&
                    location.y <= fragment.rect.maxY + hitSlop
            }
            .min { lhs, rhs in
                lhs.horizontalDistanceSquared(to: location) < rhs.horizontalDistanceSquared(to: location)
            }
    }

    func intersectsAny(_ ranges: [MarkdownSourceRange]) -> Bool {
        ranges.contains { range in
            sourceRange.byteRange.lowerBound < range.byteRange.upperBound &&
                range.byteRange.lowerBound < sourceRange.byteRange.upperBound
        }
    }

    func highlightRects(for ranges: [MarkdownSourceRange]) -> [MarkdownDocumentSelectionHighlight] {
        ranges.compactMap { range in
            let lowerBound = max(sourceRange.byteRange.lowerBound, range.byteRange.lowerBound)
            let upperBound = min(sourceRange.byteRange.upperBound, range.byteRange.upperBound)
            guard lowerBound < upperBound else {
                return nil
            }

            if let textGeometry {
                let lowerX = textGeometry.xOffset(forSourceByteOffset: lowerBound)
                let upperX = textGeometry.xOffset(forSourceByteOffset: upperBound)
                let minX = min(lowerX, upperX)
                let maxX = max(lowerX, upperX)
                let clippedMinX = max(0, min(rect.width, minX))
                let clippedMaxX = max(0, min(rect.width, maxX))
                let width = clippedMaxX - clippedMinX
                guard width.isFinite, width > 0 else {
                    return nil
                }
                let highlightRect = CGRect(
                    x: rect.minX + clippedMinX,
                    y: rect.minY,
                    width: max(1, width),
                    height: rect.height
                )
                return MarkdownDocumentSelectionHighlight(
                    id: "\(id):\(lowerBound)-\(upperBound)",
                    rect: highlightRect
                )
            }

            return MarkdownDocumentSelectionHighlight(
                id: "\(id):\(lowerBound)-\(upperBound)",
                rect: rect
            )
        }
    }

    func endpoint(at location: CGPoint) -> MarkdownDocumentSelectionEndpoint {
        if let textGeometry {
            let localX = location.x - rect.minX
            let visibleMaxX = max(0, min(textGeometry.lineWidth, rect.width))
            let queryX = min(max(localX, 0), visibleMaxX)
            return MarkdownDocumentSelectionEndpoint(
                blockID: blockID,
                sourceByteOffset: textGeometry.sourceByteOffset(atX: queryX),
                line: sourceRange.lineRange.lowerBound
            )
        }

        let sourceByteOffset = location.x <= rect.midX
            ? sourceRange.byteRange.lowerBound
            : sourceRange.byteRange.upperBound
        return MarkdownDocumentSelectionEndpoint(
            blockID: blockID,
            sourceByteOffset: sourceByteOffset,
            line: location.x <= rect.midX ? sourceRange.lineRange.lowerBound : sourceRange.lineRange.upperBound
        )
    }

    private func horizontalDistanceSquared(to point: CGPoint) -> CGFloat {
        if point.x < rect.minX {
            let dx = rect.minX - point.x
            return dx * dx
        }
        if point.x > rect.maxX {
            let dx = point.x - rect.maxX
            return dx * dx
        }
        return 0
    }

    private static func blockFragment(for block: MarkdownBlock, rect: CGRect) -> MarkdownDocumentSelectionFragment {
        MarkdownDocumentSelectionFragment(
            id: "block:\(block.id.rawValue)",
            blockID: block.id,
            sourceRange: block.sourceRange,
            rect: rect
        )
    }

    private static let listItemIndentationPerLevel: CGFloat = 36

    private static func listFragments(
        block: MarkdownBlock,
        items: [MarkdownPreparedListItem],
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        guard !items.isEmpty else { return [] }
        var yCursor = rect.minY
        return listItemFragmentsInternal(
            block: block,
            items: items,
            rect: rect,
            yCursor: &yCursor,
            indentation: 0
        )
    }

    private static func listItemFragmentsInternal(
        block: MarkdownBlock,
        items: [MarkdownPreparedListItem],
        rect: CGRect,
        yCursor: inout CGFloat,
        indentation: CGFloat
    ) -> [MarkdownDocumentSelectionFragment] {
        let itemRectX = rect.minX + indentation
        let itemRectWidth = max(rect.width - indentation, 0)
        var fragments: [MarkdownDocumentSelectionFragment] = []
        for item in items {
            if let prepared = item.inlineLayout ?? item.selectionInlineLayout {
                let lineHeight = CGFloat(prepared.lineHeight)
                let spacing = InlineRunsView.nativeLineSpacing(for: prepared)
                let containerWidth = InlineRunsView.nativeLineLayoutWidth(
                    for: prepared,
                    containerWidth: Double(itemRectWidth)
                )
                let layoutResult = prepared.layout(
                    containerWidth: containerWidth,
                    allowsOverwideFallback: true
                )
                let itemHeight = CGFloat(max(1, layoutResult.lines.count)) * (lineHeight + spacing)
                let itemRect = CGRect(x: itemRectX, y: yCursor, width: itemRectWidth, height: itemHeight)
                yCursor += itemHeight
                fragments.append(contentsOf: inlineLineFragments(
                    blockID: block.id,
                    prepared: prepared,
                    layout: layoutResult,
                    rect: itemRect,
                    idPrefix: "list:\(item.id)"
                ))
            } else {
                let itemRect = CGRect(x: itemRectX, y: yCursor, width: itemRectWidth, height: rect.height)
                yCursor += rect.height
                fragments.append(MarkdownDocumentSelectionFragment(
                    id: "\(item.id):\(item.sourceRange.byteRange.lowerBound)",
                    blockID: block.id,
                    sourceRange: item.sourceRange,
                    rect: itemRect
                ))
            }

            fragments.append(contentsOf: listItemFragmentsInternal(
                block: block,
                items: item.childItems,
                rect: rect,
                yCursor: &yCursor,
                indentation: indentation + listItemIndentationPerLevel
            ))
        }
        return fragments
    }

    private static func tableCellFragments(
        block: MarkdownBlock,
        table: MarkdownPreparedTableBlock,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        let columnCount = max(
            table.columnAlignments.count,
            table.header.count,
            table.rows.map(\.cells.count).max() ?? 0
        )
        guard columnCount > 0 else { return [] }
        let rowCount = 1 + table.rows.count
        let cellWidth = rect.width / CGFloat(columnCount)
        let cellHeight = rect.height / CGFloat(rowCount)

        var fragments: [MarkdownDocumentSelectionFragment] = []

        for (column, cell) in table.header.enumerated() {
            let cellRect = CGRect(
                x: rect.minX + CGFloat(column) * cellWidth,
                y: rect.minY,
                width: cellWidth,
                height: cellHeight
            )
            fragments.append(contentsOf: tableCellFragment(
                block: block,
                cell: cell,
                rect: cellRect,
                index: column
            ))
        }

        for (rowIndex, row) in table.rows.enumerated() {
            for (column, cell) in row.cells.enumerated() {
                let cellRect = CGRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.minY + CGFloat(rowIndex + 1) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                fragments.append(contentsOf: tableCellFragment(
                    block: block,
                    cell: cell,
                    rect: cellRect,
                    index: table.header.count + rowIndex * columnCount + column
                ))
            }
        }

        return fragments
    }

    private static func tableCellFragment(
        block: MarkdownBlock,
        cell: MarkdownPreparedTableCell,
        rect: CGRect,
        index: Int
    ) -> [MarkdownDocumentSelectionFragment] {
        if let layout = cell.inlineLayout ?? cell.selectionInlineLayout {
            let lines = inlineLineFragments(
                blockID: block.id,
                prepared: layout,
                layout: layout.layout(
                    containerWidth: InlineRunsView.nativeLineLayoutWidth(
                        for: layout,
                        containerWidth: Double(rect.width)
                    ),
                    allowsOverwideFallback: true
                ),
                rect: rect,
                idPrefix: "table-cell:\(block.id.rawValue):\(index)"
            )
            if !lines.isEmpty {
                return lines
            }
        }
        return [MarkdownDocumentSelectionFragment(
            id: "table-cell:\(block.id.rawValue):\(index):\(cell.sourceRange.byteRange.lowerBound)",
            blockID: block.id,
            sourceRange: cell.sourceRange,
            rect: rect
        )]
    }

    private static func sourceRange(
        for relativeByteRange: Range<Int>,
        in inlineLayout: MarkdownPreparedInlineContent,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder? = nil
    ) -> MarkdownSourceRange? {
        if relativeByteRange == 0..<inlineLayout.prepared.naturalText.utf8.count,
           let sourceRange = inlineLayout.prepared.sourceRange {
            return sourceRange
        }

        guard !relativeByteRange.isEmpty else {
            return inlineLayout.prepared.sourceRange
        }

        var cursor = 0
        var lower: Int?
        var upper: Int?
        var lineLower: Int?
        var lineUpper: Int?

        for run in inlineLayout.prepared.runs {
            let runLength = run.text.utf8.count
            let runRange = cursor..<(cursor + runLength)
            let overlapLower = max(relativeByteRange.lowerBound, runRange.lowerBound)
            let overlapUpper = min(relativeByteRange.upperBound, runRange.upperBound)
            if overlapLower < overlapUpper, let sourceRange = run.sourceRange {
                let mapper = MarkdownDocumentSelectionSourceRun(
                    visibleByteRange: runRange,
                    sourceRange: sourceRange
                )
                diagnosticsRecorder?.recordSelectionSourceRunMapping(count: 2)
                let absoluteLower: Int
                let absoluteUpper: Int
                if mapper.mapsOneToOne {
                    absoluteLower = mapper.sourceByteOffset(forVisibleByteOffset: overlapLower)
                    absoluteUpper = mapper.sourceByteOffset(forVisibleByteOffset: overlapUpper)
                } else {
                    absoluteLower = sourceRange.byteRange.lowerBound
                    absoluteUpper = sourceRange.byteRange.upperBound
                }
                lower = min(lower ?? absoluteLower, absoluteLower)
                upper = max(upper ?? absoluteUpper, absoluteUpper)
                lineLower = min(lineLower ?? sourceRange.lineRange.lowerBound, sourceRange.lineRange.lowerBound)
                lineUpper = max(lineUpper ?? sourceRange.lineRange.upperBound, sourceRange.lineRange.upperBound)
            }
            cursor += runLength
        }

        if let lower, let upper, lower < upper {
            return MarkdownSourceRange(
                byteRange: lower..<upper,
                lineRange: (lineLower ?? 1)..<(lineUpper ?? ((lineLower ?? 1) + 1))
            )
        }

        guard let sourceRange = inlineLayout.prepared.sourceRange else {
            return nil
        }
        let lowerBound = min(sourceRange.byteRange.upperBound, sourceRange.byteRange.lowerBound + relativeByteRange.lowerBound)
        let upperBound = min(sourceRange.byteRange.upperBound, sourceRange.byteRange.lowerBound + relativeByteRange.upperBound)
        guard lowerBound < upperBound else {
            return sourceRange
        }
        return MarkdownSourceRange(byteRange: lowerBound..<upperBound, lineRange: sourceRange.lineRange)
    }
}

struct MarkdownDocumentSelectionLineFragmentTemplate: Sendable {
    var id: String
    var blockID: MarkdownBlockID
    var sourceRange: MarkdownSourceRange
    var lineIndex: Int
    var lineWidth: CGFloat
    var textGeometry: MarkdownDocumentSelectionTextGeometry?

    func fragment(
        in rect: CGRect,
        lineHeight: CGFloat,
        spacing: CGFloat
    ) -> MarkdownDocumentSelectionFragment {
        let y = rect.minY + CGFloat(lineIndex) * (lineHeight + spacing)
        return MarkdownDocumentSelectionFragment(
            id: id,
            blockID: blockID,
            sourceRange: sourceRange,
            rect: CGRect(
                x: rect.minX,
                y: y,
                width: min(rect.width, lineWidth),
                height: lineHeight
            ),
            textGeometry: textGeometry
        )
    }
}

struct MarkdownDocumentSelectionTextGeometry: Equatable, Sendable {
    var visibleByteRange: Range<Int>
    var lineText: String
    var sourceRuns: [MarkdownDocumentSelectionSourceRun]
    var fontRuns: [MarkdownDocumentSelectionFontRun]
    var fontProfiles: MarkdownInlineFontProfiles
    var fontSize: Double
    var lineWidth: CGFloat
    private var equalityFingerprint: Int
    #if canImport(CoreText)
    private var coreTextMetrics: MarkdownDocumentSelectionCoreTextMetrics?
    #endif

    init?(
        prepared: MarkdownPreparedInlineContent,
        line: InlineLineRange,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder? = nil
    ) {
        guard !line.byteRange.isEmpty,
              let stringRange = Self.stringRange(
                forUTF8Range: line.byteRange,
                in: prepared.prepared.naturalText
              )
        else {
            return nil
        }

        self.visibleByteRange = line.byteRange
        self.lineText = String(prepared.prepared.naturalText[stringRange])
        self.fontProfiles = prepared.fontProfiles
        self.fontSize = prepared.fontSize
        self.lineWidth = CGFloat(max(line.width, 1))
        diagnosticsRecorder?.recordSelectionTextGeometryInitialization()

        var sourceRuns: [MarkdownDocumentSelectionSourceRun] = []
        var fontRuns: [MarkdownDocumentSelectionFontRun] = []
        var cursor = 0
        for run in prepared.prepared.runs {
            let upper = cursor + run.text.utf8.count
            let visibleRange = cursor..<upper
            let overlapLower = max(line.byteRange.lowerBound, visibleRange.lowerBound)
            let overlapUpper = min(line.byteRange.upperBound, visibleRange.upperBound)
            if overlapLower < overlapUpper {
                if let sourceRange = run.sourceRange {
                    sourceRuns.append(
                        MarkdownDocumentSelectionSourceRun(
                            visibleByteRange: visibleRange,
                            sourceRange: sourceRange,
                            isAtomic: run.isAtomicSelectionRun
                        )
                    )
                }
                fontRuns.append(
                    MarkdownDocumentSelectionFontRun(
                        visibleByteRange: overlapLower..<overlapUpper,
                        kind: run.kind,
                        presentation: run.presentation
                    )
                )
            }
            cursor = upper
        }

        self.sourceRuns = sourceRuns
        self.fontRuns = fontRuns
        diagnosticsRecorder?.recordSelectionFingerprintBuild()
        self.equalityFingerprint = Self.makeEqualityFingerprint(
            visibleByteRange: visibleByteRange,
            lineText: lineText,
            sourceRuns: sourceRuns,
            fontRuns: fontRuns,
            fontProfiles: fontProfiles,
            fontSize: fontSize,
            lineWidth: lineWidth
        )
        #if canImport(CoreText)
        self.coreTextMetrics = Self.makeCoreTextMetrics(
            lineText: lineText,
            visibleByteRange: visibleByteRange,
            fontRuns: fontRuns,
            fontProfiles: fontProfiles,
            fontSize: fontSize,
            lineWidth: lineWidth,
            diagnosticsRecorder: diagnosticsRecorder
        )
        #endif
    }

    static func == (
        lhs: MarkdownDocumentSelectionTextGeometry,
        rhs: MarkdownDocumentSelectionTextGeometry
    ) -> Bool {
        lhs.visibleByteRange == rhs.visibleByteRange &&
            lhs.lineText == rhs.lineText &&
            lhs.fontSize == rhs.fontSize &&
            lhs.lineWidth == rhs.lineWidth &&
            lhs.equalityFingerprint == rhs.equalityFingerprint
    }

    func sourceByteOffset(atX x: CGFloat) -> Int {
        let visibleOffset = visibleByteOffset(atX: x)
        return sourceByteOffset(forVisibleByteOffset: visibleOffset)
    }

    func xOffset(forSourceByteOffset sourceByteOffset: Int) -> CGFloat {
        let visibleOffset = visibleByteOffset(forSourceByteOffset: sourceByteOffset)
        return xOffset(forVisibleByteOffset: visibleOffset)
    }

    private func visibleByteOffset(atX x: CGFloat) -> Int {
        guard !lineText.isEmpty else {
            return visibleByteRange.lowerBound
        }

        #if canImport(CoreText)
        if let coreTextMetrics {
            let queryX = max(0, min(lineWidth, x)) / coreTextMetrics.scale
            let index = CTLineGetStringIndexForPosition(coreTextMetrics.line, CGPoint(x: queryX, y: 0))
            if index != kCFNotFound {
                return visibleByteOffset(forLocalUTF16Offset: index)
            }
        }
        #endif

        let progress = lineWidth > 0 ? max(0, min(1, x / lineWidth)) : 0
        let localByteOffset = Int((CGFloat(visibleByteRange.count) * progress).rounded())
        return min(visibleByteRange.upperBound, visibleByteRange.lowerBound + localByteOffset)
    }

    private func xOffset(forVisibleByteOffset visibleByteOffset: Int) -> CGFloat {
        guard !lineText.isEmpty else {
            return 0
        }

        let clamped = min(max(visibleByteOffset, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        #if canImport(CoreText)
        if let coreTextMetrics,
           let localUTF16Offset = localUTF16Offset(forVisibleByteOffset: clamped) {
            return CGFloat(CTLineGetOffsetForStringIndex(coreTextMetrics.line, localUTF16Offset, nil)) *
                coreTextMetrics.scale
        }
        #endif

        let progress = visibleByteRange.count > 0
            ? CGFloat(clamped - visibleByteRange.lowerBound) / CGFloat(visibleByteRange.count)
            : 0
        return max(0, min(lineWidth, lineWidth * progress))
    }

    private func sourceByteOffset(forVisibleByteOffset visibleByteOffset: Int) -> Int {
        let clamped = min(max(visibleByteOffset, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        guard !sourceRuns.isEmpty else {
            return clamped
        }

        if let run = sourceRuns.first(where: { $0.visibleByteRange.lowerBound <= clamped && clamped <= $0.visibleByteRange.upperBound }) {
            return run.sourceByteOffset(forVisibleByteOffset: clamped)
        }

        if let first = sourceRuns.first, clamped < first.visibleByteRange.lowerBound {
            return first.sourceRange.byteRange.lowerBound
        }
        return sourceRuns.last?.sourceRange.byteRange.upperBound ?? clamped
    }

    private func visibleByteOffset(forSourceByteOffset sourceByteOffset: Int) -> Int {
        guard !sourceRuns.isEmpty else {
            return sourceByteOffset
        }

        if let run = sourceRuns.first(where: { $0.sourceRange.byteRange.lowerBound <= sourceByteOffset && sourceByteOffset <= $0.sourceRange.byteRange.upperBound }) {
            return min(
                visibleByteRange.upperBound,
                max(visibleByteRange.lowerBound, run.visibleByteOffset(forSourceByteOffset: sourceByteOffset))
            )
        }

        if let first = sourceRuns.first, sourceByteOffset < first.sourceRange.byteRange.lowerBound {
            return visibleByteRange.lowerBound
        }
        return visibleByteRange.upperBound
    }

    private func visibleByteOffset(forLocalUTF16Offset offset: Int) -> Int {
        let clamped = min(max(0, offset), lineText.utf16.count)
        guard let utf16Index = lineText.utf16.index(
            lineText.utf16.startIndex,
            offsetBy: clamped,
            limitedBy: lineText.utf16.endIndex
        ),
            let stringIndex = String.Index(utf16Index, within: lineText),
            let utf8Index = stringIndex.samePosition(in: lineText.utf8)
        else {
            return visibleByteRange.lowerBound
        }

        let localByteOffset = lineText.utf8.distance(from: lineText.utf8.startIndex, to: utf8Index)
        return min(visibleByteRange.upperBound, visibleByteRange.lowerBound + localByteOffset)
    }

    private func localUTF16Offset(forVisibleByteOffset visibleByteOffset: Int) -> Int? {
        let clamped = min(max(visibleByteOffset, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        let localByteOffset = clamped - visibleByteRange.lowerBound
        guard let utf8Index = lineText.utf8.index(
            lineText.utf8.startIndex,
            offsetBy: localByteOffset,
            limitedBy: lineText.utf8.endIndex
        ),
            let stringIndex = String.Index(utf8Index, within: lineText),
            let utf16Index = stringIndex.samePosition(in: lineText.utf16)
        else {
            return nil
        }

        return lineText.utf16.distance(from: lineText.utf16.startIndex, to: utf16Index)
    }

    #if canImport(CoreText)
    private static func makeCoreTextMetrics(
        lineText: String,
        visibleByteRange: Range<Int>,
        fontRuns: [MarkdownDocumentSelectionFontRun],
        fontProfiles: MarkdownInlineFontProfiles,
        fontSize: Double,
        lineWidth: CGFloat,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder?
    ) -> MarkdownDocumentSelectionCoreTextMetrics? {
        guard !lineText.isEmpty else {
            return nil
        }
        let attributed = NSMutableAttributedString(string: lineText)
        if fontRuns.isEmpty {
            attributed.addAttribute(
                NSAttributedString.Key(kCTFontAttributeName as String),
                value: MarkdownDocumentSelectionCTFont.font(
                    profile: fontProfiles.body,
                    kind: .text,
                    size: fontSize
                ),
                range: NSRange(location: 0, length: attributed.length)
            )
        } else {
            for run in fontRuns {
                guard let range = nsRange(
                    forVisibleByteRange: run.visibleByteRange,
                    visibleByteRange: visibleByteRange,
                    lineText: lineText
                ) else {
                    continue
                }
                attributed.addAttribute(
                    NSAttributedString.Key(kCTFontAttributeName as String),
                    value: MarkdownDocumentSelectionCTFont.font(
                        profile: fontProfiles.profile(for: run.presentation, kind: run.kind),
                        kind: run.kind,
                        size: fontSize
                    ),
                    range: range
                )
            }
        }
        let line = CTLineCreateWithAttributedString(attributed)
        diagnosticsRecorder?.recordSelectionCoreTextLineBuild()
        let measuredWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard measuredWidth.isFinite, measuredWidth > 0, lineWidth.isFinite, lineWidth > 0 else {
            return nil
        }
        return MarkdownDocumentSelectionCoreTextMetrics(line: line, scale: lineWidth / measuredWidth)
    }

    private static func nsRange(
        forVisibleByteRange byteRange: Range<Int>,
        visibleByteRange: Range<Int>,
        lineText: String
    ) -> NSRange? {
        let lower = min(max(byteRange.lowerBound, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        let upper = min(max(byteRange.upperBound, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        guard lower < upper,
              let lowerOffset = localUTF16Offset(
                forVisibleByteOffset: lower,
                visibleByteRange: visibleByteRange,
                lineText: lineText
              ),
              let upperOffset = localUTF16Offset(
                forVisibleByteOffset: upper,
                visibleByteRange: visibleByteRange,
                lineText: lineText
              )
        else {
            return nil
        }
        return NSRange(location: lowerOffset, length: max(0, upperOffset - lowerOffset))
    }

    private static func localUTF16Offset(
        forVisibleByteOffset visibleByteOffset: Int,
        visibleByteRange: Range<Int>,
        lineText: String
    ) -> Int? {
        let clamped = min(max(visibleByteOffset, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        let localByteOffset = clamped - visibleByteRange.lowerBound
        guard let utf8Index = lineText.utf8.index(
            lineText.utf8.startIndex,
            offsetBy: localByteOffset,
            limitedBy: lineText.utf8.endIndex
        ),
            let stringIndex = String.Index(utf8Index, within: lineText),
            let utf16Index = stringIndex.samePosition(in: lineText.utf16)
        else {
            return nil
        }

        return lineText.utf16.distance(from: lineText.utf16.startIndex, to: utf16Index)
    }
    #endif

    private static func stringRange(
        forUTF8Range byteRange: Range<Int>,
        in text: String
    ) -> Range<String.Index>? {
        guard byteRange.lowerBound >= 0,
              byteRange.upperBound <= text.utf8.count,
              let lowerUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.lowerBound,
                limitedBy: text.utf8.endIndex
              ),
              let upperUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.upperBound,
                limitedBy: text.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: text),
              let upper = String.Index(upperUTF8, within: text)
        else {
            return nil
        }

        return lower..<upper
    }

    private static func makeEqualityFingerprint(
        visibleByteRange: Range<Int>,
        lineText: String,
        sourceRuns: [MarkdownDocumentSelectionSourceRun],
        fontRuns: [MarkdownDocumentSelectionFontRun],
        fontProfiles: MarkdownInlineFontProfiles,
        fontSize: Double,
        lineWidth: CGFloat
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(visibleByteRange.lowerBound)
        hasher.combine(visibleByteRange.upperBound)
        hasher.combine(lineText)
        hasher.combine(fontProfiles)
        hasher.combine(fontSize)
        hasher.combine(lineWidth)
        hasher.combine(sourceRuns.count)
        for run in sourceRuns {
            hasher.combine(run.visibleByteRange.lowerBound)
            hasher.combine(run.visibleByteRange.upperBound)
            hasher.combine(run.sourceRange)
            hasher.combine(run.isAtomic)
        }
        hasher.combine(fontRuns.count)
        for run in fontRuns {
            hasher.combine(run.visibleByteRange.lowerBound)
            hasher.combine(run.visibleByteRange.upperBound)
            hasher.combine(run.kind)
            hasher.combine(run.presentation)
        }
        return hasher.finalize()
    }
}

struct MarkdownDocumentSelectionSourceRun: Equatable, Sendable {
    var visibleByteRange: Range<Int>
    var sourceRange: MarkdownSourceRange
    var isAtomic: Bool = false

    var mapsOneToOne: Bool {
        visibleByteRange.count == sourceRange.byteRange.count
    }

    private var usesBoundarySnapping: Bool {
        isAtomic || !mapsOneToOne
    }

    func sourceByteOffset(forVisibleByteOffset visibleByteOffset: Int) -> Int {
        let clamped = min(max(visibleByteOffset, visibleByteRange.lowerBound), visibleByteRange.upperBound)
        let visibleLength = max(1, visibleByteRange.count)
        let sourceLength = max(0, sourceRange.byteRange.count)
        if usesBoundarySnapping {
            let midpoint = visibleByteRange.lowerBound + visibleLength / 2
            return clamped <= midpoint ? sourceRange.byteRange.lowerBound : sourceRange.byteRange.upperBound
        }
        if visibleLength == sourceLength {
            return sourceRange.byteRange.lowerBound + (clamped - visibleByteRange.lowerBound)
        }

        let progress = Double(clamped - visibleByteRange.lowerBound) / Double(visibleLength)
        return sourceRange.byteRange.lowerBound + Int((Double(sourceLength) * progress).rounded())
    }

    func visibleByteOffset(forSourceByteOffset sourceByteOffset: Int) -> Int {
        let clamped = min(max(sourceByteOffset, sourceRange.byteRange.lowerBound), sourceRange.byteRange.upperBound)
        let visibleLength = max(0, visibleByteRange.count)
        let sourceLength = max(1, sourceRange.byteRange.count)
        if usesBoundarySnapping {
            if clamped <= sourceRange.byteRange.lowerBound {
                return visibleByteRange.lowerBound
            }
            if clamped >= sourceRange.byteRange.upperBound {
                return visibleByteRange.upperBound
            }
            return visibleByteRange.lowerBound + visibleLength / 2
        }
        if visibleLength == sourceLength {
            return visibleByteRange.lowerBound + (clamped - sourceRange.byteRange.lowerBound)
        }

        let progress = Double(clamped - sourceRange.byteRange.lowerBound) / Double(sourceLength)
        return visibleByteRange.lowerBound + Int((Double(visibleLength) * progress).rounded())
    }
}

struct MarkdownDocumentSelectionFontRun: Equatable, Sendable {
    var visibleByteRange: Range<Int>
    var kind: MarkdownInlineKind
    var presentation: MarkdownInlinePresentation
}

#if canImport(CoreText)
private struct MarkdownDocumentSelectionCoreTextMetrics: @unchecked Sendable {
    var line: CTLine
    var scale: CGFloat
}
#endif

private extension MarkdownInlineRun {
    var isAtomicSelectionRun: Bool {
        kind == .image ||
            kind == .math ||
            presentation.contains(.image) ||
            presentation.contains(.math)
    }
}

extension MarkdownPreparedBlockContent {
    var emitsTextLeafSelectionFragments: Bool {
        if selectionInlineLayout != nil {
            return true
        }
        if inlineLayout != nil {
            return true
        }
        if listItems.contains(where: \.emitsTextLeafSelectionFragments) {
            return true
        }
        if let table {
            let cells = table.header + table.rows.flatMap(\.cells)
            if cells.contains(where: { $0.inlineLayout != nil || $0.selectionInlineLayout != nil }) {
                return true
            }
        }
        return false
    }
}

extension MarkdownPreparedListItem {
    var emitsTextLeafSelectionFragments: Bool {
        inlineLayout != nil ||
            selectionInlineLayout != nil ||
            childItems.contains(where: \.emitsTextLeafSelectionFragments)
    }
}

struct MarkdownDocumentSelectionFragmentsKey: PreferenceKey {
    static let defaultValue: [MarkdownDocumentSelectionFragment] = []

    static func reduce(
        value: inout [MarkdownDocumentSelectionFragment],
        nextValue: () -> [MarkdownDocumentSelectionFragment]
    ) {
        value.append(contentsOf: nextValue())
    }
}

extension Array where Element == MarkdownDocumentSelectionFragment {
    func sortedForSelection() -> [MarkdownDocumentSelectionFragment] {
        sorted {
            if abs($0.rect.minY - $1.rect.minY) > 0.5 {
                return $0.rect.minY < $1.rect.minY
            }
            if abs($0.rect.minX - $1.rect.minX) > 0.5 {
                return $0.rect.minX < $1.rect.minX
            }
            if $0.sourceRange.byteRange.lowerBound == $1.sourceRange.byteRange.lowerBound {
                return $0.sourceRange.byteRange.upperBound < $1.sourceRange.byteRange.upperBound
            }
            return $0.sourceRange.byteRange.lowerBound < $1.sourceRange.byteRange.lowerBound
        }
    }
}

extension Array where Element == MarkdownBlockID {
    func orderedUnique() -> [MarkdownBlockID] {
        var seen: Set<MarkdownBlockID> = []
        var result: [MarkdownBlockID] = []
        for id in self where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }
}

#if canImport(CoreText)
private enum MarkdownDocumentSelectionCTFont {
    static func font(profile: MarkdownFontProfile, kind: MarkdownInlineKind, size: Double) -> CTFont {
        let pointSize = CGFloat(size)
        let base: CTFont
        let symbolicTraits: CTFontSymbolicTraits
        switch profile {
        case let .named(name, weight):
            base = CTFontCreateWithName(name as CFString, pointSize, nil)
            symbolicTraits = kind == .emphasis ? .traitItalic : []
            return apply(weight: weight, symbolicTraits: symbolicTraits, to: base, size: pointSize)
        case let .monospacedSystem(weight):
            base = CTFontCreateUIFontForLanguage(.system, pointSize, nil) ??
                CTFontCreateWithName("Menlo" as CFString, pointSize, nil)
            symbolicTraits = kind == .emphasis ? [.traitMonoSpace, .traitItalic] : .traitMonoSpace
            return apply(weight: weight, symbolicTraits: symbolicTraits, to: base, size: pointSize)
        case let .system(weight, design):
            base = systemFont(design: design, size: pointSize)
            var traits = fontSymbolicTraits(for: design)
            if kind == .emphasis {
                traits.insert(.traitItalic)
            }
            return apply(weight: weight, symbolicTraits: traits, to: base, size: pointSize)
        }
    }

    private static func apply(
        weight: MarkdownFontWeight,
        symbolicTraits: CTFontSymbolicTraits,
        to font: CTFont,
        size: CGFloat
    ) -> CTFont {
        guard weight != .regular || !symbolicTraits.isEmpty else {
            return font
        }
        var traits: [CFString: Any] = [:]
        if let weightValue = fontWeightValue(for: weight) {
            traits[kCTFontWeightTrait] = weightValue
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: traits
        ] as CFDictionary)
        let weighted = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)
        guard !symbolicTraits.isEmpty else {
            return weighted
        }
        return CTFontCreateCopyWithSymbolicTraits(
            weighted,
            size,
            nil,
            symbolicTraits,
            symbolicTraits
        ) ?? weighted
    }

    private static func systemFont(design: MarkdownFontDesign, size: CGFloat) -> CTFont {
        switch design {
        case .serif:
            return CTFontCreateWithName("Times" as CFString, size, nil)
        case .monospaced:
            return CTFontCreateUIFontForLanguage(.system, size, nil) ??
                CTFontCreateWithName("Menlo" as CFString, size, nil)
        case .default, .rounded:
            return CTFontCreateUIFontForLanguage(.system, size, nil) ??
                CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
    }

    private static func fontSymbolicTraits(for design: MarkdownFontDesign) -> CTFontSymbolicTraits {
        switch design {
        case .monospaced:
            return .traitMonoSpace
        case .default, .serif, .rounded:
            return []
        }
    }

    private static func fontWeightValue(for weight: MarkdownFontWeight) -> CGFloat? {
        switch weight {
        case .regular:
            return nil
        case .medium:
            return 0.23
        case .semibold:
            return 0.3
        case .bold:
            return 0.4
        }
    }
}
#endif
