#if os(macOS)
import AppKit
import Foundation
import PDFKit
import SiriusMarkdownCore
import Testing
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized)
@MainActor
struct MarkdownDocumentPrintExporterTests {
    @Test
    func paginationIsDeterministicAndEveryCharacterBelongsToOnePage() throws {
        let source = "# Print document\n\n" + (1...90).map { "Paragraph \($0): Native selectable text with café and emoji 😀.\n\n" }.joined()
        let snapshot = prepare(source)
        let options = MarkdownDocumentPrintOptions(pageSize: CGSize(width: 300, height: 240), margins: .init(top: 24, bottom: 24, leading: 24, trailing: 24))
        let first = try MarkdownDocumentPrintExporter.prepare(snapshot, options: options)
        let second = try MarkdownDocumentPrintExporter.prepare(snapshot, options: options)
        #expect(first.pages.count > 3)
        #expect(first.pages == second.pages)
        #expect(first.pages.map(\.text).joined() == first.text)
        var end = 0
        for page in first.pages {
            #expect(page.textRange.location == end)
            #expect(page.textRange.length > 0)
            end = NSMaxRange(page.textRange)
        }
        #expect(end == (first.text as NSString).length)
        let pdf = try #require(PDFDocument(data: first.pdfData))
        #expect(pdf.pageCount == first.pages.count)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == options.pageSize)
        let extracted = pdf.string ?? ""
        #expect(extracted.contains("Native selectable text"))
        #expect(extracted.contains("Paragraph 90"))
        #expect(!first.pdfData.isEmpty)
        if let path = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_PDF_PROBE_OUTPUT"] {
            try first.writePDF(to: URL(fileURLWithPath: path))
            if let page = pdf.page(at: 0),
               let tiff = page.thumbnail(of: CGSize(width: 1200, height: 960), for: .mediaBox).tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: path + ".png"))
            }
        }
    }

    @Test
    func longCodeAndTallTablesPaginateWithoutLosingTheirLastContent() throws {
        let code = String(repeating: "LongIdentifierWithoutWhitespace", count: 80)
        let rows = (1...100).map { "| Row \($0) | value \($0) |" }.joined(separator: "\n")
        let source = "```swift\n\(code)\nEND_CODE\n```\n\n| Name | Value |\n| --- | --- |\n\(rows)\n"
        let document = try MarkdownDocumentPrintExporter.prepare(prepare(source), options: .init(pageSize: CGSize(width: 260, height: 280), margins: .init(top: 20, bottom: 20, leading: 20, trailing: 20)))
        #expect(document.pages.count > 3)
        #expect(document.pages.map(\.text).joined() == document.text)
        #expect(document.text.contains(code))
        #expect(document.text.contains("END_CODE"))
        #expect(document.text.contains("Row 100"))
        #expect(document.limitations.contains(.codeLinesWrapToPage))
        #expect(!document.limitations.contains(.tablesAsTabSeparatedText))
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.string?.contains("END_CODE") == true)
        #expect(pdf.string?.contains("Row 100") == true)
    }

    @Test
    func invalidGeometryAndUnfittableContentFailExplicitly() throws {
        let snapshot = prepare("# Heading")
        #expect(throws: MarkdownDocumentPrintError.invalidPageGeometry) {
            try MarkdownDocumentPrintExporter.prepare(snapshot, options: .init(pageSize: CGSize(width: 40, height: 40)))
        }
        #expect(throws: MarkdownDocumentPrintError.invalidFontSize) {
            try MarkdownDocumentPrintExporter.prepare(snapshot, options: .init(bodyFontSize: .nan))
        }
        #expect(throws: (any Error).self) {
            try MarkdownDocumentPrintExporter.prepare(snapshot, options: .init(pageSize: CGSize(width: 1, height: 1), margins: .init(top: 0, bottom: 0, leading: 0, trailing: 0)))
        }
    }

    @Test
    func emptySnapshotProducesOneBlankPrintablePage() throws {
        let document = try MarkdownDocumentPrintExporter.prepare(prepare(""))
        #expect(document.pages.count == 1)
        #expect(document.pages[0].text.isEmpty)
        #expect(document.pages[0].textRange == NSRange(location: 0, length: 0))
        #expect(PDFDocument(data: document.pdfData)?.pageCount == 1)
    }

    @Test
    func printOperationCreationDoesNotRunAndPDFRetainsLinkAnnotations() throws {
        let document = try MarkdownDocumentPrintExporter.prepare(prepare("[Example](https://example.com/path)"))
        let operation = try document.makePrintOperation()
        #expect(operation.printInfo.paperSize == document.options.pageSize)
        let pdf = try #require(PDFDocument(data: document.pdfData))
        let annotations = pdf.page(at: 0)?.annotations ?? []
        #expect(annotations.contains { $0.url?.absoluteString == "https://example.com/path" })
    }

    @Test
    func imageAndMathFallbackLimitationsAreReturnedWithSemanticText() throws {
        let document = try MarkdownDocumentPrintExporter.prepare(prepare("![Example image](https://example.com/image.png) and $x^2$"))
        #expect(document.limitations.contains(.imagesAsAlternativeText))
        #expect(document.limitations.contains(.mathAsSourceText))
        #expect(document.text.contains("Example image"))
        #expect(document.text.contains("x^2"))
        #expect(!document.text.contains("https://example.com/image.png"))
    }

    @Test
    func nativeTablePDFKeepsCellTextAndLinkRectanglesInsidePageMargins() throws {
        let document = try MarkdownDocumentPrintExporter.prepare(prepare("| Name | Site |\n| --- | --- |\n| Alpha | [Visit](https://example.com) |\n"),
            options: .init(pageSize: CGSize(width: 300, height: 240), margins: .init(top: 30, bottom: 30, leading: 30, trailing: 30)))
        let pdf = try #require(PDFDocument(data: document.pdfData))
        let page = try #require(pdf.page(at: 0))
        #expect(pdf.string?.contains("Alpha") == true)
        #expect(pdf.string?.contains("Visit") == true)
        #expect(!document.limitations.contains(.tablesAsTabSeparatedText))
        #expect(document.pages.map(\.text).joined() == document.text)
        let link = try #require(page.annotations.first { $0.url?.host == "example.com" })
        #expect(link.bounds.minX >= 30 && link.bounds.maxX <= 270)
        #expect(link.bounds.minY >= 30 && link.bounds.maxY <= 210)
        let textRange = ((page.string ?? "") as NSString).range(of: "Visit")
        let glyphBounds = try #require(page.selection(for: textRange)).bounds(for: page)
        #expect(abs(link.bounds.minX - glyphBounds.minX) < 1)
        #expect(abs(link.bounds.minY - glyphBounds.minY) < 1)
        let tiff = try #require(page.thumbnail(of: CGSize(width: 600, height: 480), for: .mediaBox).tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        if let prefix = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_VISUAL_PDF_PROBE_OUTPUT"] {
            try document.writePDF(to: URL(fileURLWithPath: prefix + "-table.pdf"))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: prefix + "-table.png"))
        }
        // Native row fills/borders produce a broad band beyond glyph-sized ink.
        var grayPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.85 && color.redComponent < 0.96 && abs(color.redComponent - color.greenComponent) < 0.02 { grayPixels += 1 }
            }
        }
        #expect(grayPixels > 1000)
    }

    @Test(arguments: [false, true])
    func preparedInlineImageExportsPixelsAndKeepsSemanticPageText(nestedInQuote: Bool) throws {
        let source = "[Link](https://example.com) Before ![red sample](https://example.com/sample.png) after."
        var snapshot = prepare(nestedInQuote ? "> " + source : source)
        let rootBlock = try #require(snapshot.snapshot.blocks.first)
        var rootContent = try #require(snapshot[rootBlock.id])
        let block = nestedInQuote ? try #require(rootBlock.childBlocks.first) : rootBlock
        var content = nestedInQuote ? try #require(rootContent.childBlocks.first?.preparedContent) : rootContent
        var inline = try #require(content.inlineLayout)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 20,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<20 { for x in 0..<32 { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y) } }
        let iconPNG = try #require(bitmap.representation(using: .png, properties: [:]))
        for y in 0..<20 { for x in 0..<32 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let imageRange = try #require(block.inlines.first { $0.presentation.contains(.image) }?.sourceRange)
        let image = MarkdownPreparedImage(source: "https://example.com/sample.png", altText: "red sample",
            sourceRange: imageRange, preparedSource: .data(png, mimeType: "image/png"))
        let icon = MarkdownPreparedImage(source: "https://example.com/favicon.png", altText: nil,
            sourceRange: block.sourceRange, preparedSource: .data(iconPNG, mimeType: "image/png"))
        inline.images = [icon, image]
        let attachmentID = MarkdownAttachmentID(rawValue: "print-image")
        inline.attachments[attachmentID] = MarkdownPreparedAttachment(id: attachmentID, image: image,
            pointWidth: 32, pointHeight: 20, ascent: 20, descent: 0, sizingSource: .decoded, policyDecision: .allow)
        content.inlineLayout = inline
        if nestedInQuote { rootContent.childBlocks[0].preparedContent = content }
        else { rootContent = content }
        snapshot.preparedContentByBlockID[rootBlock.id] = rootContent
        let document = try MarkdownDocumentPrintExporter.prepare(snapshot)
        #expect(!document.limitations.contains(.imagesAsAlternativeText))
        #expect(document.text.contains("red sample"))
        #expect(document.pages.map(\.text).joined() == document.text)
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.string?.contains("Before") == true)
        #expect(pdf.string?.contains("after.") == true)
        let page = try #require(pdf.page(at: 0))
        let tiff = try #require(page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox).tiffRepresentation)
        let rendered = try #require(NSBitmapImageRep(data: tiff))
        if let prefix = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_VISUAL_PDF_PROBE_OUTPUT"] {
            let path = prefix + (nestedInQuote ? "-quoted" : "-inline")
            try document.writePDF(to: URL(fileURLWithPath: path + ".pdf"))
            let png = try #require(rendered.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path + ".png"))
        }
        let cgImage = try #require(rendered.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let redPixels = try rgba.withUnsafeMutableBytes { bytes -> Int in
            let context = try #require(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).filter {
                pixels[$0] > 204 && pixels[$0 + 1] < 51 && pixels[$0 + 2] < 51 && pixels[$0 + 3] > 204
            }.count
        }
        #expect(redPixels >= 400)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SiriusMarkdown-print-\(UUID().uuidString).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var localInline = inline
        for key in localInline.attachments.keys where !localInline.attachments[key]!.isDecorative {
            localInline.attachments[key]!.image.preparedSource = .localFile(path: file.path)
        }
        content.inlineLayout = localInline
        if nestedInQuote { rootContent.childBlocks[0].preparedContent = content } else { rootContent = content }
        snapshot.preparedContentByBlockID[rootBlock.id] = rootContent
        let localDocument = try MarkdownDocumentPrintExporter.prepare(snapshot)
        #expect(!localDocument.limitations.contains(.imagesAsAlternativeText))
    }

    @Test
    func preparedBlockMathUsesItsRasterWhileRetainingSemanticText() throws {
        var snapshot = prepare("Before.\n\n$$\nx^2\n$$\n\nAfter.")
        let block = try #require(snapshot.snapshot.blocks.first { $0.kind == .mathBlock })
        var content = try #require(snapshot[block.id])
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 30,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<30 { for x in 0..<60 { bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        content.mathRender = .image(.init(imageData: try #require(bitmap.representation(using: .png, properties: [:])),
            scale: 2, pointWidth: 30, pointHeight: 15, ascent: 15, descent: 0, latex: "x^2"))
        snapshot.preparedContentByBlockID[block.id] = content
        let document = try MarkdownDocumentPrintExporter.prepare(snapshot)
        #expect(document.text.contains("x^2"))
        #expect(document.pages.map(\.text).joined() == document.text)
        #expect(!document.limitations.contains(.mathAsSourceText))
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.string?.contains("Before.") == true)
        #expect(pdf.string?.contains("After.") == true)
        #expect(pdf.string?.contains("x^2") == false)
    }

    @Test(arguments: [false, true])
    func nestedSpanningMultilineTablesRetainNativeGridAndEmptyCells(inQuote: Bool) throws {
        let html = "<table><tr><th colspan=\"2\">Merged header</th></tr><tr><td rowspan=\"2\">Left<br>second line</td><td>Right</td></tr><tr><td></td></tr></table>"
        let source = inQuote ? "> " + html : html
        let snapshot = prepare(source)
        let document = try MarkdownDocumentPrintExporter.prepare(snapshot)
        #expect(!document.limitations.contains(.tablesAsTabSeparatedText))
        #expect(document.pages.map(\.text).joined() == document.text)
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.string?.contains("Merged header") == true)
        #expect(pdf.string?.contains("second line") == true)
        #expect(pdf.string?.contains("Right") == true)
        if let prefix = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_VISUAL_PDF_PROBE_OUTPUT"] {
            let suffix = inQuote ? "-nested-spans" : "-spans"
            try document.writePDF(to: URL(fileURLWithPath: prefix + suffix + ".pdf"))
            let page = try #require(pdf.page(at: 0))
            let tiff = try #require(page.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox).tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: prefix + suffix + ".png"))
        }
        let markdown = "| Empty | Value |\n| --- | --- |\n| | visible |\n"
        let empty = try MarkdownDocumentPrintExporter.prepare(prepare(markdown))
        #expect(!empty.limitations.contains(.tablesAsTabSeparatedText))
        #expect(empty.text.contains("\tvisible"))
    }

    @Test
    func continuingTablePagesRepeatHeadersWithoutDuplicatingSemanticRanges() throws {
        let source = "| Name | Value |\n| --- | --- |\n" + (1...30).map { "| Row \($0) | Data \($0) |\n" }.joined()
        let document = try MarkdownDocumentPrintExporter.prepare(prepare(source), options: .init(pageSize: CGSize(width: 300, height: 240)))
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.pageCount > 2)
        #expect(document.pages.map(\.text).joined() == document.text)
        for index in 0..<pdf.pageCount {
            #expect(pdf.page(at: index)?.string?.contains("Name") == true)
            #expect(pdf.page(at: index)?.string?.contains("Value") == true)
            let page = try #require(pdf.page(at: index))
            let headerRange = ((page.string ?? "") as NSString).range(of: "Name")
            let headerBounds = try #require(page.selection(for: headerRange)).bounds(for: page)
            #expect(headerBounds.minY > 170)
        }
        #expect(pdf.string?.contains("Row 30") == true)
    }

    private func prepare(_ source: String) -> MarkdownPreparedSnapshot {
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        return MarkdownRendererConfiguration(linkMetadataResolver: nil).prepare(snapshot: stream.snapshot())
    }
}
#endif
