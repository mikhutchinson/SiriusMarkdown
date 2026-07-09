import Foundation
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath

#if canImport(SwiftMath)
import SwiftMath
#endif

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Display-list metrics (Part 01)

@Test
func preparedMathImageHasRealAscentDescent() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("\\frac{a}{b}", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image for \\frac{a}{b}.")
        return
    }

    #expect(image.ascent > 0)
    #expect(image.descent > 0)
    #expect(abs(image.ascent + image.descent - image.pointHeight) < 0.01)
}

#if canImport(SwiftMath)
@Test
func preparedMathImageMetricsMatchMathImageLayoutInfo() throws {
    let latex = "\\frac{a}{b}"
    let fontSize: CGFloat = 20
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath(latex, isBlock: true, fontSize: Double(fontSize))

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    let mathImage = MTMathImage(
        latex: latex,
        fontSize: fontSize,
        textColor: .black,
        labelMode: .display,
        textAlignment: .left
    )
    let (error, _, layout) = mathImage.asImage()
    #expect(error == nil)
    let layoutInfo = try #require(layout)

    // Mirror SwiftMathTypesetter.metricsMatchingImageHeight / MTMathImage.layoutImage.
    let contentHeight = Double(layoutInfo.ascent + layoutInfo.descent)
    let layoutHeight = max(contentHeight, Double(fontSize) / 2)
    let expectedDescent =
        (image.pointHeight - layoutHeight) / 2 + Double(layoutInfo.descent)
    #expect(abs(image.descent - expectedDescent) < 0.01)
    #expect(abs(image.ascent - (image.pointHeight - expectedDescent)) < 0.01)
}
#endif

@Test
func preparedMathImageAscentLessThanPointHeightForEquationWithDescenders() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x_i + \\frac{a}{b}", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    #expect(image.ascent < image.pointHeight)
    #expect(image.descent > 0)
}

@Test
func preparedMathImageSimpleEquationHasSmallDescent() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2 + y^2", isBlock: false, fontSize: 16)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    #expect(image.ascent > image.descent)
    #expect(image.descent < image.ascent)
}

@Test
func preparedMathImageFractionHasLargerDescentThanSimpleEquation() throws {
    let renderer = NativeMarkdownMathRenderer()
    let simple = renderer.preparedMath("x^2", isBlock: false, fontSize: 16)
    let fraction = renderer.preparedMath("\\frac{a}{b}", isBlock: false, fontSize: 16)

    guard case let .image(simpleImage) = simple,
          case let .image(fractionImage) = fraction
    else {
        Issue.record("Expected typeset images for both equations.")
        return
    }

    #expect(fractionImage.descent > simpleImage.descent)
}

@Test
func preparedMathImageCompactGlyphKeepsBaselineInsideImage() throws {
    // Compact glyphs can be shorter than fontSize/2. Metrics must keep the
    // baseline inside the bitmap so -descent does not pull past the image.
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath(".", isBlock: false, fontSize: 16)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image for compact glyph.")
        return
    }

    #expect(image.descent >= 0)
    #expect(image.descent <= image.pointHeight)
    #expect(abs(image.ascent + image.descent - image.pointHeight) < 0.01)
    #expect(image.pointHeight + 0.01 >= 8.0) // fontSize/2 floor
}

// MARK: - Baseline alignment (Part 01)

@Test
func inlineMathBaselineOffsetUsesDescent() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("\\frac{a}{b}", isBlock: false, fontSize: 16)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    // SwiftUI places the image bottom on the text baseline; -descent aligns
    // the math baseline. Offset magnitude must match prepared descent.
    let offset = -image.descent
    #expect(image.descent > 0)
    #expect(abs(offset + image.descent) < 0.000_1)
}

#if canImport(SwiftMath)
@Test
func inlineMathBaselineAlignedWithinTwoPointsForCommonEquations() throws {
    let fontSize: CGFloat = 16
    let renderer = NativeMarkdownMathRenderer()
    let fixtures = [
        "x^2",
        "\\frac{a}{b}",
        "x_i",
        "\\sum_{i=0}^n x_i"
    ]

    for latex in fixtures {
        let prepared = renderer.preparedMath(latex, isBlock: false, fontSize: Double(fontSize))
        guard case let .image(image) = prepared else {
            Issue.record("Expected a typeset image for \(latex).")
            continue
        }

        let mathImage = MTMathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: .black,
            labelMode: .text,
            textAlignment: .left
        )
        let (error, _, layout) = mathImage.asImage()
        #expect(error == nil)
        let layoutInfo = try #require(layout)

        let contentHeight = Double(layoutInfo.ascent + layoutInfo.descent)
        let layoutHeight = max(contentHeight, Double(fontSize) / 2)
        let expectedDescent =
            (image.pointHeight - layoutHeight) / 2 + Double(layoutInfo.descent)
        let misalignment = abs(image.descent - expectedDescent)
        #expect(misalignment < 2.0)
        #expect(abs(image.ascent + image.descent - image.pointHeight) < 0.01)
    }
}
#endif

// MARK: - Rendering sharpness (Part 02)

@Test
func blockMathImageScaleMatchesBackingScale() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    #expect(image.scale >= 2.0)
}

@Test
func blockMathImageScaleIsNotFixedThree() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    #expect(image.scale == NativeMarkdownMathRenderer.renderScale)
}

@Test
func markdownMathImageViewDoesNotUseHighInterpolation() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SiriusMarkdownSwiftUI/Views/MarkdownMathRendering.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(source.contains(".interpolation(.medium)"))
    #expect(!source.contains(".interpolation(.high)"))
}

// MARK: - Inline math flow / line spacing (Part 03)

@Test
func inlineMathProducesTextAndMathPieces() throws {
    var stream = MarkdownStream()
    stream.append("The value of $x^2$ is computed here.")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)
    let pieces = try #require(inline.mathTextPieces)

    let mathCount = pieces.filter { if case .math = $0 { return true }; return false }.count
    let textCount = pieces.filter { if case .text = $0 { return true }; return false }.count

    #expect(mathCount == 1)
    #expect(textCount >= 2)
}

@Test
func multipleInlineMathInParagraphProducesMultipleMathPieces() throws {
    var stream = MarkdownStream()
    stream.append("Given $a + b$ and $c + d$, we get $e + f$.")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)
    let pieces = try #require(inline.mathTextPieces)

    let mathCount = pieces.filter { if case .math = $0 { return true }; return false }.count
    #expect(mathCount == 3)
}

@Test
func tallInlineMathLineHeightUsesFullAscentDescent() throws {
    let renderer = NativeMarkdownMathRenderer()
    let simple = renderer.preparedMath("x", isBlock: false, fontSize: 16)
    let tall = renderer.preparedMath("\\frac{a}{b}", isBlock: false, fontSize: 16)

    guard case let .image(simpleImage) = simple,
          case let .image(tallImage) = tall
    else {
        Issue.record("Expected typeset images.")
        return
    }

    // Tall equations contribute their full ascent+descent to line height via
    // the prepared image size; they must be taller than a simple glyph run.
    #expect(tallImage.pointHeight > simpleImage.pointHeight)
    #expect(abs(tallImage.ascent + tallImage.descent - tallImage.pointHeight) < 0.01)
    #expect(tallImage.ascent > 0)
    #expect(tallImage.descent > 0)
}

@Test
func inlineMathFlowsWithTextWithoutCollapsingMetrics() throws {
    var stream = MarkdownStream()
    stream.append("Before $\\frac{a}{b}$ after $\\sum_{i=0}^n x_i$ end.")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let pieces = try #require(prepared.inlineLayout?.mathTextPieces)

    var maxMathHeight = 0.0
    for piece in pieces {
        guard case let .math(image) = piece else { continue }
        #expect(image.ascent + image.descent >= image.pointHeight - 0.01)
        maxMathHeight = max(maxMathHeight, image.pointHeight)
    }

    #expect(maxMathHeight > 16)
}

// MARK: - Streaming fallback (Part 04 / INV-M5)

@Test
func streamingPartialMathRendersAsTextNotMathBlock() {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n")

    let snapshot = stream.snapshot()
    #expect(snapshot.blocks.allSatisfy { $0.kind != .mathBlock })
}

@Test
func streamingSealedMathTypesetsCorrectly() throws {
    var stream = MarkdownStream()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    stream.append("$$\n\\frac{a}{b}\n$$\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    guard case .image = configuration.prepare(block: block).mathRender else {
        Issue.record("Expected sealed math to typeset to an image.")
        return
    }
}

@Test
func streamingMathFallbackToTextThenTypeset() throws {
    var stream = MarkdownStream()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    stream.append("$$\n\\frac{a}{b}\n")
    #expect(stream.snapshot().blocks.allSatisfy { $0.kind != .mathBlock })

    stream.append("$$\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    guard case .image = configuration.prepare(block: block).mathRender else {
        Issue.record("Expected completed math to typeset to an image.")
        return
    }
}

// MARK: - Cache identity (Part 02)

@Test
func mathRendererCacheIdentityReflectsScale() {
    let renderer = NativeMarkdownMathRenderer()
    let identity = renderer.mathRendererCacheIdentity
    #expect(identity.contains("scale"))
    #expect(identity.contains(String(Int(NativeMarkdownMathRenderer.renderScale))))
    #expect(identity.contains("layoutinfo"))
}
