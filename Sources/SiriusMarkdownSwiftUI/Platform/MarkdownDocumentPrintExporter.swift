#if os(macOS)
import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import SiriusMarkdownCore

public struct MarkdownPrintMargins: Sendable, Hashable {
    public var top: Double
    public var bottom: Double
    public var leading: Double
    public var trailing: Double

    public init(top: Double = 36, bottom: Double = 36, leading: Double = 36, trailing: Double = 36) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }
}

/// Dimensions are PDF points (72 points per inch). The default paper is US Letter.
public struct MarkdownDocumentPrintOptions: Sendable {
    public var pageSize: CGSize
    public var margins: MarkdownPrintMargins
    public var title: String
    public var bodyFontSize: Double

    public init(pageSize: CGSize = CGSize(width: 612, height: 792), margins: MarkdownPrintMargins = .init(), title: String = "Document", bodyFontSize: Double = 12) {
        self.pageSize = pageSize
        self.margins = margins
        self.title = title
        self.bodyFontSize = bodyFontSize
    }
}

/// Explicit differences from the on-screen renderer, reported only when present.
public enum MarkdownDocumentPrintLimitation: String, Sendable, Hashable {
    case tablesAsTabSeparatedText
    case imagesAsAlternativeText
    case mathAsSourceText
    case diagramsAsSourceText
    case codeLinesWrapToPage
}

public enum MarkdownDocumentPrintError: Error, Equatable {
    case invalidPageGeometry
    case invalidFontSize
    case contentDoesNotFit(utf16Offset: Int)
    case pdfCreationFailed
    case printOperationUnavailable
}

public struct MarkdownPrintedPage: Sendable, Equatable {
    /// One-based page number.
    public let number: Int
    /// Contiguous UTF-16 range in `MarkdownPreparedPrintDocument.text`.
    public let textRange: NSRange
    public let text: String
}

/// A fixed native pagination result. PDF export and printing share these exact
/// pages; resizing the application window does not change the print document.
@MainActor
public final class MarkdownPreparedPrintDocument {
    public let options: MarkdownDocumentPrintOptions
    public let pages: [MarkdownPrintedPage]
    public let text: String
    public let limitations: [MarkdownDocumentPrintLimitation]
    public let pdfData: Data

    fileprivate init(options: MarkdownDocumentPrintOptions, pages: [MarkdownPrintedPage], text: String, limitations: [MarkdownDocumentPrintLimitation], pdfData: Data) {
        self.options = options
        self.pages = pages
        self.text = text
        self.limitations = limitations
        self.pdfData = pdfData
    }

    public func writePDF(to url: URL) throws {
        try pdfData.write(to: url, options: .atomic)
    }

    /// Returns a native print operation without displaying a panel or printing.
    /// The host decides when to call `run()` or its asynchronous equivalent.
    public func makePrintOperation(printInfo: NSPrintInfo? = nil) throws -> NSPrintOperation {
        guard let document = PDFDocument(data: pdfData) else { throw MarkdownDocumentPrintError.pdfCreationFailed }
        let info = (printInfo?.copy() as? NSPrintInfo) ?? NSPrintInfo(dictionary: [:])
        info.paperSize = options.pageSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
            throw MarkdownDocumentPrintError.printOperationUnavailable
        }
        return operation
    }
}

/// Event-time native export of an already prepared snapshot. No WebKit, network
/// resources, Markdown parsing, or SwiftUI measurement participates in export.
@MainActor
public enum MarkdownDocumentPrintExporter {
    public static func prepare(_ snapshot: MarkdownPreparedSnapshot, options: MarkdownDocumentPrintOptions = .init()) throws -> MarkdownPreparedPrintDocument {
        let contentRect = try validatedContentRect(options)
        let range = MarkdownSourceRange(byteRange: 0..<snapshot.snapshot.sourceLength, lineRange: 1..<2)
        let semantic = MarkdownRichCopy.semanticFragment(snapshot: snapshot, ranges: [range])
        let attributed = NSMutableAttributedString(attributedString: MarkdownRichCopy.nativeAttributedString(for: semantic))
        configureTypography(attributed, options: options, contentWidth: contentRect.width)
        let semanticText = attributed.string
        let visuals = preparedVisuals(snapshot, semantic: semantic, attributed: attributed, options: options, contentSize: contentRect.size)
        let display = replacingVisuals(in: attributed, visuals: visuals)
        let framesetter = CTFramesetterCreateWithAttributedString(display)
        func semanticOffset(_ displayOffset: Int) -> Int {
            var delta = 0
            for visual in visuals {
                let start = visual.range.location - delta
                if displayOffset <= start { break }
                if displayOffset < start + visual.replacementLength { return NSMaxRange(visual.range) }
                delta += visual.range.length - visual.replacementLength
            }
            return displayOffset + delta
        }
        let tableHeaders = Dictionary(visuals.filter { $0.isHeader && $0.tableID != nil }.map { ($0.tableID!, $0) }, uniquingKeysWith: { first, _ in first })
        var frames: [(body: CTFrame, header: CTFrame?, headerText: NSAttributedString?)] = []
        var pages: [MarkdownPrintedPage] = []
        var offset = 0
        repeat {
            var headerFrame: CTFrame?
            var headerText: NSAttributedString?
            var headerHeight: CGFloat = 0
            if offset > 0, offset < display.length,
               let row = display.attribute(visualKey, at: offset, effectiveRange: nil) as? PrintVisual,
               !row.isHeader, let tableID = row.tableID, let header = tableHeaders[tableID],
               header.size.height + row.size.height + 2 < contentRect.height {
                headerHeight = header.size.height + 0.1
                let clone = PrintVisual(range: NSRange(location: 0, length: 1), size: header.size,
                    cells: header.cells, isHeader: true, limitation: header.limitation, tableID: tableID)
                let seed = NSAttributedString(string: "\n", attributes: display.attributes(at: offset, effectiveRange: nil))
                let text = replacingVisuals(in: seed, visuals: [clone])
                headerText = text
                let headerPath = CGPath(rect: CGRect(x: 0, y: contentRect.height - headerHeight, width: contentRect.width, height: headerHeight), transform: nil)
                headerFrame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: 0), headerPath, nil)
            }
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height - headerHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard display.length == 0 || (visible.location == offset && visible.length > 0) else {
                throw MarkdownDocumentPrintError.contentDoesNotFit(utf16Offset: offset)
            }
            try validateLineWidths(frame, contentWidth: contentRect.width, offset: offset)
            let semanticStart = semanticOffset(offset)
            let textRange = NSRange(location: semanticStart, length: semanticOffset(offset + visible.length) - semanticStart)
            pages.append(MarkdownPrintedPage(number: pages.count + 1, textRange: textRange, text: (semanticText as NSString).substring(with: textRange)))
            frames.append((frame, headerFrame, headerText))
            offset += visible.length
        } while offset < display.length

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw MarkdownDocumentPrintError.pdfCreationFailed }
        var mediaBox = CGRect(origin: .zero, size: options.pageSize)
        let metadata = [kCGPDFContextTitle as String: options.title, kCGPDFContextCreator as String: "SiriusMarkdown"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata) else { throw MarkdownDocumentPrintError.pdfCreationFailed }
        for record in frames {
            let frame = record.body
            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: contentRect.minX, y: contentRect.minY)
            CTFrameDraw(frame, context)
            drawVisuals(frame, contentOrigin: contentRect.origin, context: context)
            if let header = record.header {
                CTFrameDraw(header, context)
                drawVisuals(header, contentOrigin: contentRect.origin, context: context)
            }
            context.restoreGState()
            if let header = record.header, let headerText = record.headerText {
                addLinkAnnotations(header, attributed: headerText, contentOrigin: contentRect.origin, context: context)
            }
            addLinkAnnotations(frame, attributed: display, contentOrigin: contentRect.origin, context: context)
            context.endPDFPage()
        }
        context.closePDF()
        return MarkdownPreparedPrintDocument(options: options, pages: pages, text: semanticText, limitations: limitations(in: snapshot, visuals: visuals), pdfData: data as Data)
    }

    private static let visualKey = NSAttributedString.Key("SiriusMarkdown.printVisual")

    private struct PrintCell {
        let text: NSAttributedString
        let rect: CGRect
        let isHeader: Bool
    }

    private final class PrintVisual {
        let range: NSRange
        let size: CGSize
        let image: CGImage?
        let ascent: CGFloat
        let descent: CGFloat
        let cells: [PrintCell]
        let isHeader: Bool
        let limitation: MarkdownDocumentPrintLimitation
        let tableID: MarkdownBlockID?
        let coveredVisuals: [PrintVisual]
        var replacementLength: Int { tableID == nil ? 1 : 2 }
        init(range: NSRange, size: CGSize, image: CGImage? = nil,
             ascent: CGFloat? = nil, descent: CGFloat = 0,
             cells: [PrintCell] = [], isHeader: Bool = false,
             limitation: MarkdownDocumentPrintLimitation, tableID: MarkdownBlockID? = nil, coveredVisuals: [PrintVisual] = []) {
            self.range = range; self.size = size; self.image = image
            self.ascent = ascent ?? size.height
            self.descent = descent
            self.cells = cells; self.isHeader = isHeader
            self.limitation = limitation; self.tableID = tableID
            self.coveredVisuals = coveredVisuals
        }
    }

    private static func preparedVisuals(_ snapshot: MarkdownPreparedSnapshot, semantic: MarkdownRichCopy.Fragment, attributed: NSAttributedString,
                                        options: MarkdownDocumentPrintOptions, contentSize: CGSize) -> [PrintVisual] {
        var result: [PrintVisual] = []
        var blockOffset = 0
        for block in snapshot.snapshot.blocks {
            var isolated = snapshot
            isolated.snapshot.blocks = [block]
            let fragment = MarkdownRichCopy.semanticFragment(snapshot: isolated, ranges: [block.sourceRange])
            let blockText = fragment.runs.map(\.text).joined()
            defer { blockOffset += (blockText as NSString).length }
            guard let prepared = snapshot[block.id] else { continue }
            let assets = inlineAssets(block, prepared: prepared)
            var imageIndex = 0
            var mathIndex = 0
            var runOffset = blockOffset
            for run in fragment.runs {
                let range = NSRange(location: runOffset, length: (run.text as NSString).length)
                defer { runOffset += range.length }
                guard range.length > 0 else { continue }
                var data: Data?
                var pointSize: CGSize?
                var ascent: CGFloat?
                var descent: CGFloat = 0
                var limitation: MarkdownDocumentPrintLimitation?
                if block.kind == .mathBlock, case let .image(image) = prepared.mathRender, run.text != "\n" {
                    data = image.imageData
                    pointSize = CGSize(width: image.pointWidth, height: image.pointHeight)
                    ascent = image.ascent
                    descent = image.descent
                    limitation = .mathAsSourceText
                } else if run.presentation.contains(.image) {
                    let asset = assets.images.indices.contains(imageIndex) ? assets.images[imageIndex] : nil
                    imageIndex += 1
                    data = asset?.data
                    pointSize = asset?.size
                    limitation = .imagesAsAlternativeText
                } else if run.presentation.contains(.math) {
                    let asset = assets.maths.indices.contains(mathIndex) ? assets.maths[mathIndex] : nil
                    mathIndex += 1
                    data = asset?.data
                    pointSize = asset?.size
                    ascent = asset?.ascent
                    descent = asset?.descent ?? 0
                    if let sourceFontSize = asset?.fontSize, sourceFontSize.isFinite, sourceFontSize > 0,
                       let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                        let typographyScale = font.pointSize / sourceFontSize
                        pointSize = pointSize.map { CGSize(width: $0.width * typographyScale, height: $0.height * typographyScale) }
                        ascent = ascent.map { $0 * typographyScale }
                        descent *= typographyScale
                    }
                    limitation = .mathAsSourceText
                }
                guard let data, let limitation, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                let natural = pointSize ?? CGSize(width: image.width, height: image.height)
                guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0 else { continue }
                let scale = min(1, contentSize.width / natural.width, max(1, contentSize.height - 32) / natural.height)
                result.append(PrintVisual(range: range, size: CGSize(width: natural.width * scale, height: natural.height * scale), image: image,
                    ascent: ascent.map { $0 * scale }, descent: descent * scale, limitation: limitation))
            }
        }
        let tables = preparedTableVisuals(snapshot, semantic: semantic, attributed: attributed, inlineVisuals: result, contentSize: contentSize)
        result.removeAll { asset in tables.contains { $0.range.location <= asset.range.location && NSMaxRange($0.range) >= NSMaxRange(asset.range) } }
        result.append(contentsOf: tables)
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Semantic cell locations survive nesting and authored line breaks. No
    /// delimiter parsing or Markdown reconstruction participates in this layout.
    private static func preparedTableVisuals(_ snapshot: MarkdownPreparedSnapshot,
        semantic: MarkdownRichCopy.Fragment, attributed: NSAttributedString,
        inlineVisuals: [PrintVisual], contentSize: CGSize) -> [PrintVisual] {
        var tables: [MarkdownBlockID: MarkdownPreparedTableBlock] = [:]
        func collectItem(_ item: MarkdownPreparedListItem) {
            item.childBlocks.forEach { collect($0.preparedContent) }
            item.childItems.forEach(collectItem)
        }
        func collect(_ content: MarkdownPreparedBlockContent) {
            if let table = content.table { tables[content.blockID] = table }
            content.childBlocks.forEach { collect($0.preparedContent) }
            content.richContent?.blocks.forEach { collect($0.preparedContent) }
            content.listItems.forEach(collectItem)
        }
        snapshot.preparedContentByBlockID.values.forEach(collect)
        typealias Location = MarkdownRichCopy.TableCellLocation
        var cells: [Location: NSRange] = [:]
        var rowRanges: [MarkdownBlockID: [Int: NSRange]] = [:]
        var offset = 0
        for run in semantic.runs {
            let length = (run.text as NSString).length
            defer { offset += length }
            guard let location = run.tableCell else { continue }
            let range = NSRange(location: offset, length: length)
            cells[location] = cells[location].map { NSUnionRange($0, range) } ?? range
            let old = rowRanges[location.tableID]?[location.rowIndex]
            rowRanges[location.tableID, default: [:]][location.rowIndex] = old.map { NSUnionRange($0, range) } ?? range
        }
        struct CellLayout {
            let row: Int
            let span: Int
            let text: NSAttributedString
            let x: CGFloat
            let width: CGFloat
            let height: CGFloat
            let assets: [PrintVisual]
        }
        var result: [PrintVisual] = []
        for (id, ranges) in rowRanges {
            guard let table = tables[id], !table.columnWidths.isEmpty,
                  let firstRange = ranges.values.min(by: { $0.location < $1.location }) else { continue }
            let rows = [table.header] + table.rows.map(\.cells)
            let indent = (attributed.attribute(.paragraphStyle, at: firstRange.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            let paragraphStart = (attributed.string as NSString).paragraphRange(for: NSRange(location: firstRange.location, length: 0)).location
            let prefix = attributed.attributedSubstring(from: NSRange(location: paragraphStart, length: firstRange.location - paragraphStart))
            let prefixWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(prefix), nil, nil, nil))
            let availableWidth = contentSize.width - max(0, indent) - prefixWidth
            let total = table.columnWidths.reduce(0, +)
            guard total.isFinite, total > 0, availableWidth > 12 else { continue }
            let widths = table.columnWidths.map { CGFloat($0 / total) * availableWidth }
            guard widths.allSatisfy({ $0.isFinite && $0 > 0 }) else { continue }
            var offsets = [CGFloat(0)]
            for width in widths { offsets.append(offsets.last! + width) }
            var heights = rows.map { $0.isEmpty ? CGFloat(0) : CGFloat(12) }
            var layouts: [CellLayout] = []
            var valid = true
            for row in rows.indices {
                for (index, cell) in rows[row].enumerated() {
                    guard var range = cells[Location(tableID: id, rowIndex: row, cellIndex: index)] else { continue }
                    // The semantic serializer owns exactly one separator per
                    // cell; authored tabs/newlines remain inside its text range.
                    if range.length > 0 { range.length -= 1 }
                    let column = max(0, min(widths.count - 1, cell.columnIndex))
                    let colspan = max(1, min(widths.count - column, Int(clamping: cell.colspan)))
                    let width = offsets[column + colspan] - offsets[column]
                    guard width > 12 else { valid = false; break }
                    let original = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: range))
                    let style = NSMutableParagraphStyle()
                    style.lineBreakMode = .byWordWrapping
                    if table.columnAlignments.indices.contains(column) {
                        switch table.columnAlignments[column] {
                        case .center: style.alignment = .center
                        case .right: style.alignment = .right
                        default: break
                        }
                    }
                    original.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: original.length))
                    let assets = inlineVisuals.filter { $0.range.location >= range.location && NSMaxRange($0.range) <= NSMaxRange(range) }
                    let local = assets.map { asset in
                        PrintVisual(range: NSRange(location: asset.range.location - range.location, length: asset.range.length),
                            size: asset.size, image: asset.image, ascent: asset.ascent, descent: asset.descent, limitation: asset.limitation)
                    }
                    let text = replacingVisuals(in: original, visuals: local)
                    let setter = CTFramesetterCreateWithAttributedString(text)
                    let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                        CGSize(width: width - 12, height: .greatestFiniteMagnitude), nil)
                    let height = max(12, ceil(measured.height) + 12)
                    let span = max(1, min(rows.count - row, Int(clamping: cell.rowspan)))
                    if span == 1 { heights[row] = max(heights[row], height) }
                    layouts.append(CellLayout(row: row, span: span, text: text, x: offsets[column], width: width, height: height, assets: assets))
                }
                if !valid { break }
            }
            guard valid else { continue }
            for cell in layouts where cell.span > 1 {
                let current = heights[cell.row..<(cell.row + cell.span)].reduce(0, +)
                if current < cell.height { heights[cell.row + cell.span - 1] += cell.height - current }
            }
            var tableVisuals: [PrintVisual] = []
            var row = 0
            while row < rows.count {
                guard let first = ranges[row] else { row += 1; continue }
                var end = row + 1
                var cursor = row
                while cursor < end {
                    for cell in layouts where cell.row == cursor { end = max(end, cell.row + cell.span) }
                    cursor += 1
                }
                guard let last = ranges[end - 1] else { valid = false; break }
                let height = heights[row..<end].reduce(0, +)
                guard height > 0, height + 1 < contentSize.height else { valid = false; break }
                var entries: [PrintCell] = []
                var covered: [PrintVisual] = []
                for cell in layouts where cell.row >= row && cell.row < end {
                    let top = heights[row..<cell.row].reduce(0, +)
                    let cellHeight = heights[cell.row..<(cell.row + cell.span)].reduce(0, +)
                    let rect = CGRect(x: cell.x, y: height - top - cellHeight, width: cell.width, height: cellHeight)
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width - 12, height: rect.height - 12), transform: nil)
                    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(cell.text), CFRange(location: 0, length: 0), path, nil)
                    guard CTFrameGetVisibleStringRange(frame).length == cell.text.length,
                          (try? validateLineWidths(frame, contentWidth: rect.width - 12, offset: first.location)) != nil else { valid = false; break }
                    entries.append(PrintCell(text: cell.text, rect: rect, isHeader: cell.row == 0))
                    covered.append(contentsOf: cell.assets)
                }
                guard valid else { break }
                tableVisuals.append(PrintVisual(range: NSRange(location: first.location, length: NSMaxRange(last) - first.location),
                    size: CGSize(width: availableWidth, height: height), cells: entries, isHeader: row == 0 && end == 1,
                    limitation: .tablesAsTabSeparatedText, tableID: id, coveredVisuals: covered))
                row = end
            }
            if valid { result.append(contentsOf: tableVisuals) }
        }
        return result
    }

    private struct InlineAsset {
        let data: Data
        let size: CGSize
        var ascent: CGFloat? = nil
        var descent: CGFloat = 0
        var fontSize: CGFloat? = nil
    }

    private static func preparedImageData(_ source: MarkdownPreparedImageSource) -> Data? {
        switch source {
        case let .data(data, _): return data
        case let .localFile(path):
            // Only resolver-authorized prepared attachments reach this helper.
            // Bound local input too; a missing file remains a semantic fallback.
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize,
                  size >= 0, size <= 64 * 1024 * 1024 else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        case .remote, .placeholder: return nil
        }
    }

    /// Parallel optional entries preserve semantic occurrence order even when a
    /// resource is unresolved. Decoration arrays are never treated as images.
    private static func inlineAssets(_ block: MarkdownBlock, prepared: MarkdownPreparedBlockContent) -> (images: [InlineAsset?], maths: [InlineAsset?]) {
        var images: [InlineAsset?] = []
        var maths: [InlineAsset?] = []
        func leaf(_ runs: [MarkdownInlineRun], _ inline: MarkdownPreparedInlineContent?) {
            for run in runs where !run.text.isEmpty && !run.presentation.contains(.linkDecoration) {
                if run.presentation.contains(.image) {
                    let attachment = inline?.attachments.values.first { attachment in
                        guard attachment.policyDecision == .allow, !attachment.isDecorative,
                              attachment.image.source == run.imageSource,
                              let authored = run.sourceRange, let resource = attachment.image.sourceRange else { return false }
                        return authored.byteRange == resource.byteRange
                    }
                    if let attachment, let data = preparedImageData(attachment.image.preparedSource) {
                        images.append(InlineAsset(data: data, size: CGSize(width: attachment.pointWidth, height: attachment.pointHeight)))
                    } else { images.append(nil) }
                }
                if run.presentation.contains(.math) {
                    let image = inline?.mathTextPieces?.compactMap { piece -> MarkdownPreparedMathImage? in
                        if case let .math(image) = piece, image.latex == run.text { return image }; return nil
                    }.first
                    maths.append(image.map { InlineAsset(data: $0.imageData, size: CGSize(width: $0.pointWidth, height: $0.pointHeight), ascent: $0.ascent, descent: $0.descent, fontSize: inline.map { CGFloat($0.fontSize) }) })
                }
            }
        }
        func item(_ value: MarkdownListItem, _ prepared: MarkdownPreparedListItem?) {
            if !value.childBlocks.isEmpty {
                for child in value.childBlocks {
                    visit(child, prepared?.childBlocks.first { $0.block.id == child.id }?.preparedContent)
                }
            } else {
                leaf(value.inlines, prepared?.inlineLayout)
                for (index, child) in value.childItems.enumerated() {
                    item(child, prepared?.childItems.indices.contains(index) == true ? prepared?.childItems[index] : nil)
                }
            }
        }
        func visit(_ block: MarkdownBlock, _ prepared: MarkdownPreparedBlockContent?) {
            if block.kind == .mathBlock {
                if case let .image(image) = prepared?.mathRender {
                    maths.append(InlineAsset(data: image.imageData, size: CGSize(width: image.pointWidth, height: image.pointHeight), ascent: image.ascent, descent: image.descent))
                } else { maths.append(nil) }
            } else if block.kind == .htmlBlock {
                if prepared?.htmlAllowed == true {
                    for child in prepared?.richContent?.blocks ?? [] { visit(child.block, child.preparedContent) }
                }
            } else if block.kind == .blockQuote && !block.childBlocks.isEmpty {
                for child in block.childBlocks { visit(child, prepared?.childBlocks.first { $0.block.id == child.id }?.preparedContent) }
            } else if [.unorderedList, .orderedList, .taskList].contains(block.kind) {
                for (index, value) in block.listItems.enumerated() {
                    item(value, prepared?.listItems.indices.contains(index) == true ? prepared?.listItems[index] : nil)
                }
            } else if let table = block.table {
                for (rowIndex, row) in ([table.header] + table.rows).enumerated() {
                    let preparedCells = rowIndex == 0 ? prepared?.table?.header : prepared?.table?.rows.indices.contains(rowIndex - 1) == true ? prepared?.table?.rows[rowIndex - 1].cells : nil
                    for (column, cell) in row.enumerated() {
                        leaf(cell.inlines, preparedCells?.indices.contains(column) == true ? preparedCells?[column].inlineLayout : nil)
                    }
                }
            } else { leaf(block.inlines, prepared?.inlineLayout) }
        }
        visit(block, prepared)
        return (images, maths)
    }

    private static func replacingVisuals(in attributed: NSAttributedString, visuals: [PrintVisual]) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        for visual in visuals.reversed() {
            var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1,
                dealloc: { pointer in Unmanaged<PrintVisual>.fromOpaque(pointer).release() },
                getAscent: { pointer in Unmanaged<PrintVisual>.fromOpaque(pointer).takeUnretainedValue().ascent },
                getDescent: { pointer in Unmanaged<PrintVisual>.fromOpaque(pointer).takeUnretainedValue().descent },
                getWidth: { pointer in Unmanaged<PrintVisual>.fromOpaque(pointer).takeUnretainedValue().size.width })
            let delegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(visual).toOpaque())!
            var attributes = attributed.attributes(at: visual.range.location, effectiveRange: nil)
            attributes[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = delegate
            attributes[visualKey] = visual
            if visual.tableID != nil {
                attributes[.font] = NSFont.systemFont(ofSize: 0.01)
                let style = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.minimumLineHeight = visual.size.height
                style.maximumLineHeight = visual.size.height
                style.lineSpacing = 0
                style.paragraphSpacing = 0
                style.paragraphSpacingBefore = 0
                attributes[.paragraphStyle] = style
            }
            let replacement = NSMutableAttributedString(string: "\u{fffc}", attributes: attributes)
            if visual.tableID != nil {
                // A text-sized newline adds its descent between otherwise
                // adjacent row rectangles. Only the graphic owns row metrics.
                var separatorAttributes = attributes
                separatorAttributes.removeValue(forKey: NSAttributedString.Key(kCTRunDelegateAttributeName as String))
                separatorAttributes.removeValue(forKey: visualKey)
                replacement.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
            }
            result.replaceCharacters(in: visual.range, with: replacement)
        }
        return result
    }

    private static func drawVisuals(_ frame: CTFrame, contentOrigin: CGPoint, context: CGContext) {
        let frameOrigin = CTFrameGetPath(frame).boundingBoxOfPath.origin
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        if !origins.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
        for (index, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let visual = attributes[visualKey.rawValue] as? PrintVisual else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let rect = CGRect(origin: CGPoint(x: frameOrigin.x + origins[index].x + position.x, y: frameOrigin.y + origins[index].y + position.y - visual.descent), size: visual.size)
                if let image = visual.image { context.draw(image, in: rect); continue }
                context.setFillColor(CGColor(gray: visual.isHeader ? 0.92 : 1, alpha: 1))
                context.fill(rect)
                context.saveGState()
                context.clip(to: rect)
                for entry in visual.cells {
                    let cell = entry.rect.offsetBy(dx: rect.minX, dy: rect.minY)
                    context.setFillColor(CGColor(gray: entry.isHeader ? 0.92 : 1, alpha: 1))
                    context.fill(cell)
                    context.setStrokeColor(CGColor(gray: 0.65, alpha: 1))
                    context.setLineWidth(0.5)
                    context.stroke(cell.insetBy(dx: 0.25, dy: 0.25))
                    let path = CGPath(rect: cell.insetBy(dx: 6, dy: 6), transform: nil)
                    let cellFrame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(entry.text), CFRange(location: 0, length: 0), path, nil)
                    CTFrameDraw(cellFrame, context)
                    drawVisuals(cellFrame, contentOrigin: contentOrigin, context: context)
                    addLinkAnnotations(cellFrame, attributed: entry.text, contentOrigin: contentOrigin, context: context)
                }
                context.restoreGState()
            }
        }
    }

    private static func validatedContentRect(_ options: MarkdownDocumentPrintOptions) throws -> CGRect {
        let size = options.pageSize
        let margins = options.margins
        let values = [Double(size.width), Double(size.height), margins.top, margins.bottom, margins.leading, margins.trailing]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), size.width > 0, size.height > 0,
              size.width <= 14_400, size.height <= 14_400,
              margins.leading + margins.trailing < size.width,
              margins.top + margins.bottom < size.height else { throw MarkdownDocumentPrintError.invalidPageGeometry }
        guard options.bodyFontSize.isFinite, options.bodyFontSize >= 1, options.bodyFontSize <= 512 else {
            throw MarkdownDocumentPrintError.invalidFontSize
        }
        return CGRect(x: margins.leading, y: margins.bottom, width: size.width - margins.leading - margins.trailing, height: size.height - margins.top - margins.bottom)
    }

    private static func configureTypography(_ text: NSMutableAttributedString, options: MarkdownDocumentPrintOptions, contentWidth: CGFloat) {
        let range = NSRange(location: 0, length: text.length)
        var replacements: [(NSRange, NSFont, NSParagraphStyle)] = []
        text.enumerateAttributes(in: range) { attributes, range, _ in
            let original = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            let font = NSFontManager.shared.convert(original, toSize: original.pointSize * options.bodyFontSize / 12)
            let style = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.headIndent = min(style.headIndent, contentWidth * 0.2)
            style.firstLineHeadIndent = min(style.firstLineHeadIndent, contentWidth * 0.2)
            style.lineBreakMode = .byWordWrapping
            style.defaultTabInterval = min(36, contentWidth / 4)
            style.tabStops = []
            replacements.append((range, font, style))
        }
        for (range, font, style) in replacements { text.addAttributes([.font: font, .paragraphStyle: style], range: range) }
    }

    private static func validateLineWidths(_ frame: CTFrame, contentWidth: CGFloat, offset: Int) throws {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        if !origins.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
        for (index, line) in lines.enumerated() {
            let width = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            guard origins[index].x + width <= contentWidth + 0.5 else {
                throw MarkdownDocumentPrintError.contentDoesNotFit(utf16Offset: offset)
            }
        }
    }

    private static func addLinkAnnotations(_ frame: CTFrame, attributed: NSAttributedString, contentOrigin: CGPoint, context: CGContext) {
        let frameOrigin = CTFrameGetPath(frame).boundingBoxOfPath.origin
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        if !origins.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
        for (index, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            attributed.enumerateAttribute(.link, in: NSRange(location: range.location, length: range.length)) { value, linkRange, _ in
                guard let url = value as? URL else { return }
                let start = CTLineGetOffsetForStringIndex(line, linkRange.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(linkRange), nil)
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                let rect = CGRect(x: contentOrigin.x + frameOrigin.x + origins[index].x + min(start, end), y: contentOrigin.y + frameOrigin.y + origins[index].y - descent, width: abs(end - start), height: ascent + descent)
                context.setURL(url as CFURL, for: rect)
            }
        }
    }

    private static func limitations(in snapshot: MarkdownPreparedSnapshot, visuals: [PrintVisual]) -> [MarkdownDocumentPrintLimitation] {
        var result: Set<MarkdownDocumentPrintLimitation> = []
        var tableIDs: Set<MarkdownBlockID> = []
        func visitRuns(_ runs: [MarkdownInlineRun]) {
            if runs.contains(where: { $0.presentation.contains(.math) }) { result.insert(.mathAsSourceText) }
            if runs.contains(where: { $0.presentation.contains(.image) }) { result.insert(.imagesAsAlternativeText) }
        }
        func visitItem(_ item: MarkdownListItem) {
            visitRuns(item.inlines)
            item.childItems.forEach(visitItem)
            item.childBlocks.forEach(visit)
        }
        func visit(_ block: MarkdownBlock) {
            if block.kind == .table { result.insert(.tablesAsTabSeparatedText); tableIDs.insert(block.id) }
            if block.kind == .codeBlock { result.insert(.codeLinesWrapToPage) }
            if block.kind == .mathBlock || block.inlines.contains(where: { $0.presentation.contains(.math) }) { result.insert(.mathAsSourceText) }
            if block.inlines.contains(where: { $0.presentation.contains(.image) }) { result.insert(.imagesAsAlternativeText) }
            if block.kind == .codeBlock && MarkdownCodeLanguage(infoString: block.infoString).isMermaid { result.insert(.diagramsAsSourceText) }
            for child in block.childBlocks { visit(child) }
            for child in block.richContent?.blocks ?? [] { visit(child) }
            block.listItems.forEach(visitItem)
            if let table = block.table {
                for row in [table.header] + table.rows {
                    for cell in row { visitRuns(cell.inlines) }
                }
            }
        }
        snapshot.snapshot.blocks.forEach(visit)
        // Only remove a fallback report when every corresponding semantic
        // occurrence was replaced. Nested/unsupported content stays explicit.
        let all = MarkdownRichCopy.semanticFragment(snapshot: snapshot, ranges: [MarkdownSourceRange(byteRange: 0..<snapshot.snapshot.sourceLength, lineRange: 1..<2)])
        for (flag, limitation) in [(MarkdownInlinePresentation.image, MarkdownDocumentPrintLimitation.imagesAsAlternativeText), (.math, .mathAsSourceText)] {
            let count = all.runs.filter { $0.presentation.contains(flag) }.count
            if count > 0 && (visuals + visuals.flatMap(\.coveredVisuals)).filter({ $0.limitation == limitation }).count == count {
                result.remove(limitation)
            }
        }
        if tableIDs.isSubset(of: Set(visuals.compactMap(\.tableID))) { result.remove(.tablesAsTabSeparatedText) }
        return result.sorted { $0.rawValue < $1.rawValue }
    }
}
#endif
