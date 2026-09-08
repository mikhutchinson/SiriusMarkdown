import Foundation
import CoreGraphics
import ImageIO
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath
#if canImport(SwiftMath)
import SwiftMath
#if canImport(AppKit)
import AppKit
import PDFKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite
struct MarkdownMathRasterizationTests {
    @Test(arguments: [1.0, 2.0, 2.5, 3.0])
    func inlineMathPointBoundsMatchActualRasterPixels(scale: Double) throws {
        let renderer = NativeMarkdownMathRenderer(rasterizationScaleForTesting: scale)
        let prepared = renderer.preparedMath("x^2 + \\frac{a}{b}", isBlock: false, fontSize: 16)
        guard case let .image(image) = prepared else {
            Issue.record("Expected a native raster.")
            return
        }
        let bitmap = try decode(image.imageData)
        #expect(abs(image.pointWidth * scale - Double(bitmap.width)) < 0.0001)
        #expect(abs(image.pointHeight * scale - Double(bitmap.height)) < 0.0001)
        #expect(abs(image.ascent + image.descent - image.pointHeight) < 0.0001)
        let coverage = try alpha(bitmap)
        #expect(coverage.contains { $0 > 200 })
        #expect(coverage.contains { $0 == 0 })
        #expect(coverage.contains { $0 > 0 && $0 < 255 })
    }

    @Test
    func preparedPNGPreservesDirectVectorRasterCoverageWithoutResampling() throws {
        let source = "\\frac{x_i^2}{\\sqrt{1+y}}"
        let scale = 2.5
        let prepared = NativeMarkdownMathRenderer(rasterizationScaleForTesting: scale)
            .preparedMath(source, isBlock: false, fontSize: 16)
        guard case let .image(image) = prepared else {
            Issue.record("Expected a native raster.")
            return
        }
        let direct = MTMathImage(
            latex: source, fontSize: 16, textColor: MTColor.black,
            labelMode: .text, textAlignment: .left
        )
        let (error, optionalRendered, _) = direct.asImage(rasterizationScale: scale)
        #expect(error == nil)
        let rendered = try #require(optionalRendered)
        #if canImport(AppKit)
        let representation = try #require(rendered.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        let reference = try #require(representation.cgImage)
        #elseif canImport(UIKit)
        let reference = try #require(rendered.cgImage)
        #endif
        let actual = try decode(image.imageData)
        #expect(actual.width == reference.width)
        #expect(actual.height == reference.height)
        #expect(try alpha(actual) == alpha(reference))
        if let directory = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_MATH_RASTER_OUTPUT"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try image.imageData.write(to: output.appendingPathComponent("inline-math-direct-2.5x.png"))
        }
    }

    #if os(macOS)
    @Test @MainActor
    func nativeFormulaPDFExportsPreparedInlineAndBlockRasters() throws {
        var stream = MarkdownStream()
        stream.append("# Native formula export\n\nInline $x^2 + \\frac{a}{b}$ stays with its sentence.\n\n$$\n\\frac{x_i^2}{\\sqrt{1+y}}\n$$\n\nSelectable text follows the display formula.\n\n> $$\n> \\sqrt{a+b}\n> $$\n\n| Formula | Meaning |\n| --- | --- |\n| $x^2$ | squared |")
        stream.finish()
        let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil,
            mathRenderer: NativeMarkdownMathRenderer(rasterizationScaleForTesting: 2))
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let quoted = try #require(prepared.snapshot.blocks.first { $0.kind == .blockQuote })
        #expect(quoted.childBlocks.first?.inlines.first?.text == "\\sqrt{a+b}")
        let document = try MarkdownDocumentPrintExporter.prepare(prepared)
        #expect(!document.limitations.contains(.mathAsSourceText))
        #expect(document.pages.map(\.text).joined() == document.text)
        let pdf = try #require(PDFDocument(data: document.pdfData))
        #expect(pdf.string?.contains("Selectable text follows") == true)
        #expect(pdf.string?.contains("\\frac") == false)
        if let path = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_FORMULA_PDF_PROBE_OUTPUT"] {
            try document.writePDF(to: URL(fileURLWithPath: path))
            let page = try #require(pdf.page(at: 0))
            let tiff = try #require(page.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox).tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path + ".png"))
        }
    }
    #endif

    private func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func alpha(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).map { bytes[$0] }
    }
}
#endif
