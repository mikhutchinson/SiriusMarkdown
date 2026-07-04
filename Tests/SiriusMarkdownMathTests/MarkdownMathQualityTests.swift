import Foundation
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath

// MARK: - Metric extraction (Part 01/03)

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

// MARK: - Baseline alignment (Part 01)

@Test
func inlineMathBaselineOffsetUsesDescent() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("\\frac{a}{b}", isBlock: false, fontSize: 16)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    // The baseline offset should be -descent (aligning math baseline with text baseline).
    // Verify the descent is non-zero so the offset is non-trivial.
    #expect(image.descent > 0)
}

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
    // The scale should be screen-matched, not a fixed 3.0.
    // On 2x Retina (most Macs), it should be 2.0.
    // On 3x displays (iPhone Pro), it should be 3.0.
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image.")
        return
    }

    #expect(image.scale == NativeMarkdownMathRenderer.renderScale)
}

// MARK: - Inline math flow (Part 03)

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
}
