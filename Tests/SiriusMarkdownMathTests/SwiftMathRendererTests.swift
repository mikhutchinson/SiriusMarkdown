import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath

@Test
func nativeMathRendererProducesTypesetImageForValidLatex() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2 + \\alpha", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image for valid LaTeX, got \(prepared).")
        return
    }

    #expect(!image.imageData.isEmpty)
    #expect(image.pointWidth > 0)
    #expect(image.pointHeight > 0)
    #expect(image.scale == NativeMarkdownMathRenderer.renderScale)
    #expect(image.latex == "x^2 + \\alpha")
}

@Test
func nativeMathRendererTypesetsDisplayAndInlineStyles() {
    let renderer = NativeMarkdownMathRenderer()
    let block = renderer.preparedMath("\\sum_{i=1}^{n} i", isBlock: true, fontSize: 22)
    let inline = renderer.preparedMath("\\sum_{i=1}^{n} i", isBlock: false, fontSize: 14)

    if case let .image(blockImage) = block, case let .image(inlineImage) = inline {
        #expect(blockImage.pointHeight > 0)
        #expect(inlineImage.pointHeight > 0)
    } else {
        Issue.record("Expected typeset images for both display and inline math.")
    }
}

@Test
func nativeMathRendererFallsBackToTextForInvalidLatex() {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("\\unknowncommandxyz", isBlock: false, fontSize: 16)

    guard case .text = prepared else {
        Issue.record("Expected a plain-text fallback for invalid LaTeX, got \(prepared).")
        return
    }
}

@Test
func nativeMathRendererExposesStableCacheIdentity() {
    let renderer = NativeMarkdownMathRenderer()
    #expect(!renderer.mathRendererCacheIdentity.isEmpty)
    #expect(renderer.mathRendererCacheIdentity == NativeMarkdownMathRenderer().mathRendererCacheIdentity)
}

@Test
func mathBlockPreparesTypesetImageAndReusesCache() throws {
    var stream = MarkdownStream()
    stream.append("""
    $$
    \\frac{a}{b}
    $$
    """)
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    configuration.diagnosticsRecorder = recorder

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })

    let first = configuration.prepare(block: block)
    guard case .image = first.mathRender else {
        Issue.record("Expected a typeset image for the math block.")
        return
    }

    let afterFirst = recorder.snapshot()
    #expect(afterFirst.mathRenderCount == 1)

    let second = configuration.prepare(block: block)
    guard case .image = second.mathRender else {
        Issue.record("Expected the cached math block to remain a typeset image.")
        return
    }

    let afterSecond = recorder.snapshot()
    #expect(afterSecond.mathRenderCount == 1)
    #expect(afterSecond.cacheHitCount > afterFirst.cacheHitCount)
}

@Test
func inlineMathProducesNativeTextPiecesWithTypesetRenderer() throws {
    var stream = MarkdownStream()
    stream.append("The limit \\(\\frac{f(x)}{g(x)}\\) is evaluated here.")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)
    let pieces = try #require(inline.mathTextPieces)

    let hasMath = pieces.contains { piece in
        if case .math = piece { return true }
        return false
    }
    let hasText = pieces.contains { piece in
        if case .text = piece { return true }
        return false
    }
    #expect(hasMath)
    #expect(hasText)
}

@Test
func inlineMathWithPlainRendererDoesNotProduceTypesetPieces() throws {
    var stream = MarkdownStream()
    stream.append("The limit $x^2$ is evaluated here.")
    stream.finish()

    // `.document` keeps the default PlainMarkdownMathRenderer, so inline math stays
    // on the prepared CoreText line path with no native Text pieces.
    let configuration = MarkdownRendererConfiguration.document

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)

    #expect(inline.mathTextPieces == nil)
}

@Test
func streamingDisplayMathShowsFallbackUntilClosedThenTypesets() throws {
    var stream = MarkdownStream()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    // Unclosed display math stays in the mutable tail and must not typeset yet.
    stream.append("\\[\n\\lim_{x \\to a} \\frac{f(x)}{g(x)}\n")
    let partial = stream.snapshot()
    #expect(partial.blocks.allSatisfy { $0.kind != .mathBlock })

    // Closing the delimiter seals the region into a real math block that typesets.
    stream.append("\\]\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    guard case .image = configuration.prepare(block: block).mathRender else {
        Issue.record("Expected the completed display math to typeset to an image.")
        return
    }
}

@Test
func mathBlockRenderPlanReportsMathRenderedWithTypesetRenderer() throws {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n$$")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)
    let plan = MarkdownBlockView.renderPlan(
        for: block,
        configuration: configuration,
        preparedContent: prepared
    )

    #expect(plan.mathAllowed == true)
    #expect(plan.mathRendered == true)
}

@Test
func latexDisplayBracketBlockPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    \\[
    \\lim_{x \\to a} \\frac{f(x)}{g(x)}
    \\]
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected a typeset image for the \\[...\\] display block.")
        return
    }
    #expect(image.latex == "\\lim_{x \\to a} \\frac{f(x)}{g(x)}")
}

@Test
func paragraphEmbeddedDisplayMathPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    Then:
    \\[
    \\frac{f'(x)}{g'(x)}
    \\]
    if the derivative limit exists.
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let blocks = stream.snapshot().blocks
    #expect(blocks.map(\.kind) == [.paragraph, .mathBlock, .paragraph])
    let block = try #require(blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected embedded display math to prepare a typeset image.")
        return
    }
    #expect(image.latex == "\\frac{f'(x)}{g'(x)}")
}

@Test
func degradedBareDisplayBracketMathPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    [
    \\frac{f'(x)}{g'(x)}
    ]
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected degraded bare-bracket display math to prepare a typeset image.")
        return
    }
    #expect(image.latex == "\\frac{f'(x)}{g'(x)}")
}
