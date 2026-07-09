import Foundation
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath

private struct MathCorpus: Decodable {
    var schemaVersion: Int
    var requiredGroups: [String]
    var minimumNativeImageCases: Int
    var cases: [MathCorpusCase]
}

private struct MathCorpusCase: Decodable {
    var id: String
    var group: String
    var latex: String
    var display: Bool
    var nativeExpected: NativeExpectation
    var webExpected: WebExpectation
    var visual: MathVisualGolden?
}

private struct MathVisualGolden: Decodable {
    var minWidth: Double
    var maxWidth: Double
    var minHeight: Double
    var maxHeight: Double
    var maxDescent: Double
}

private enum NativeExpectation: String, Decodable {
    case image
    case text
}

private enum WebExpectation: String, Decodable {
    case success
    case skip
}

private let requiredMathCorpusGroups = [
    "basic",
    "fractions",
    "operators",
    "generated-ai",
    "matrices",
    "environments",
    "relations",
    "arrows",
    "accents",
    "typography",
    "sirius-compatibility",
    "diagnostics"
]

@Test
func mathCorpusCoversRequiredBestInClassGroups() throws {
    let corpus = try loadMathCorpus()
    #expect(corpus.schemaVersion == 1)
    #expect(corpus.requiredGroups == requiredMathCorpusGroups)
    #expect(corpus.cases.count >= 50)

    var ids = Set<String>()
    var groups = Set<String>()
    var nativeImageCount = 0
    var webParityCount = 0
    var diagnosticCount = 0

    for testCase in corpus.cases {
        #expect(ids.insert(testCase.id).inserted, "Duplicate math corpus id: \(testCase.id)")
        #expect(!testCase.latex.isEmpty, "Empty LaTeX for \(testCase.id)")
        groups.insert(testCase.group)

        if testCase.nativeExpected == .image {
            nativeImageCount += 1
            #expect(testCase.visual != nil, "Native image case has no visual golden: \(testCase.id)")
        }
        if testCase.webExpected == .success {
            webParityCount += 1
        }
        if testCase.group == "diagnostics" {
            diagnosticCount += 1
        }
    }

    for requiredGroup in requiredMathCorpusGroups {
        #expect(groups.contains(requiredGroup), "Missing math corpus group: \(requiredGroup)")
    }
    #expect(nativeImageCount >= corpus.minimumNativeImageCases)
    #expect(webParityCount >= 35)
    #expect(diagnosticCount >= 2)
}

@Test
func nativeMathRendererTypesetsSharedCorpus() throws {
    let corpus = try loadMathCorpus()
    let renderer = NativeMarkdownMathRenderer()

    for testCase in corpus.cases where testCase.nativeExpected == .image {
        let prepared = renderer.preparedMath(
            testCase.latex,
            isBlock: testCase.display,
            fontSize: testCase.display ? 20 : 16
        )

        guard case let .image(image) = prepared else {
            Issue.record("Expected native image for \(testCase.id): \(testCase.latex)")
            continue
        }

        #expect(image.latex == testCase.latex, "Original LaTeX was not preserved for \(testCase.id)")
        #expect(image.accessibilityLabel == testCase.latex, "Accessibility label drifted for \(testCase.id)")
        #expect(image.scale == NativeMarkdownMathRenderer.renderScale)
        #expect(isPNG(image.imageData), "Expected PNG image data for \(testCase.id)")
        #expect(image.pointWidth.isFinite && image.pointWidth > 0, "Invalid width for \(testCase.id)")
        #expect(image.pointHeight.isFinite && image.pointHeight > 0, "Invalid height for \(testCase.id)")
        #expect(image.ascent.isFinite && image.ascent > 0, "Invalid ascent for \(testCase.id)")
        #expect(image.descent.isFinite && image.descent >= 0, "Invalid descent for \(testCase.id)")
        #expect(abs(image.ascent + image.descent - image.pointHeight) < 0.01, "Ascent/descent mismatch for \(testCase.id)")
    }
}

@Test
func sharedMathCorpusMatchesVisualMetricGoldens() throws {
    let corpus = try loadMathCorpus()
    let renderer = NativeMarkdownMathRenderer()

    for testCase in corpus.cases where testCase.nativeExpected == .image {
        let visual = try #require(testCase.visual, "Missing visual golden for \(testCase.id)")
        let prepared = renderer.preparedMath(
            testCase.latex,
            isBlock: testCase.display,
            fontSize: testCase.display ? 20 : 16
        )
        guard case let .image(image) = prepared else {
            Issue.record("Expected native image for visual golden \(testCase.id)")
            continue
        }

        #expect(
            image.pointWidth >= visual.minWidth && image.pointWidth <= visual.maxWidth,
            "\(testCase.id) width \(image.pointWidth) outside \(visual.minWidth)...\(visual.maxWidth)"
        )
        #expect(
            image.pointHeight >= visual.minHeight && image.pointHeight <= visual.maxHeight,
            "\(testCase.id) height \(image.pointHeight) outside \(visual.minHeight)...\(visual.maxHeight)"
        )
        #expect(
            image.descent <= visual.maxDescent,
            "\(testCase.id) descent \(image.descent) exceeds \(visual.maxDescent)"
        )
        #expect(image.ascent > image.descent || image.pointHeight > 24, "Suspicious baseline split for \(testCase.id)")
    }
}

@Test
func nativeMathRendererFallsBackForOnlyDiagnosticCorpusCases() throws {
    let corpus = try loadMathCorpus()
    let renderer = NativeMarkdownMathRenderer()

    for testCase in corpus.cases where testCase.nativeExpected == .text {
        let prepared = renderer.preparedMath(
            testCase.latex,
            isBlock: testCase.display,
            fontSize: testCase.display ? 20 : 16
        )
        guard case let .text(fallback) = prepared else {
            Issue.record("Expected text fallback for \(testCase.id)")
            continue
        }
        #expect(String(fallback.characters) == testCase.latex)
    }
}

@Test
func nativeMathFallbackDiagnosticsCountTextFallbacksOnlyOncePerCachedFormula() throws {
    var stream = MarkdownStream()
    stream.append("Valid $x^2$ invalid $\\unknowncommandxyz$ valid again $\\frac{a}{b}$.")
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    configuration.diagnosticsRecorder = recorder

    let block = try #require(stream.snapshot().blocks.first)
    _ = configuration.prepare(block: block)
    let afterFirst = recorder.snapshot()
    #expect(afterFirst.mathRenderCount == 3)
    #expect(afterFirst.mathFallbackCount == 1)

    _ = configuration.prepare(block: block)
    let afterSecond = recorder.snapshot()
    #expect(afterSecond.mathRenderCount == afterFirst.mathRenderCount)
    #expect(afterSecond.mathFallbackCount == afterFirst.mathFallbackCount)
    #expect(afterSecond.cacheHitCount > afterFirst.cacheHitCount)
}

@Test
func imageBackedInlineMathCorpusCopyUsesOriginalMarkdownSource() throws {
    let formula = try #require(
        loadMathCorpus().cases.first { $0.id == "simple-fraction-inline" }?.latex
    )
    let source = "Copy this $\(formula)$ exactly."
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)

    let block = try #require(stream.snapshot().blocks.first)
    let mathRun = try #require(block.inlines.first {
        $0.kind == .math || $0.presentation.contains(.math)
    })
    let prepared = configuration.prepare(block: block)
    let pieces = try #require(prepared.inlineLayout?.mathTextPieces)
    let image = try #require(pieces.compactMap { piece -> MarkdownPreparedMathImage? in
        if case let .math(image) = piece {
            return image
        }
        return nil
    }.first)

    let sourceRange = try #require(mathRun.sourceRange)
    #expect(image.latex == formula)
    #expect(configuration.copyProvider?.markdown(sourceRange) == "$\(formula)$")
}

@Test
func sharedMathCorpusRenderPreparationStaysWithinCacheBudget() throws {
    let corpus = try loadMathCorpus()
    let formulas = corpus.cases
        .filter { $0.nativeExpected == .image }
        .prefix(18)

    var stream = MarkdownStream()
    stream.append(
        formulas
            .map { "$$\n\($0.latex)\n$$" }
            .joined(separator: "\n\n")
    )
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    configuration.diagnosticsRecorder = recorder

    let mathBlocks = stream.snapshot().blocks.filter { $0.kind == .mathBlock }
    #expect(mathBlocks.count == formulas.count)

    for block in mathBlocks {
        let prepared = configuration.prepare(block: block)
        guard case .image = prepared.mathRender else {
            Issue.record("Expected cached corpus math block to render as image: \(block.text)")
            continue
        }
    }

    let afterFirst = recorder.snapshot()
    #expect(afterFirst.mathRenderCount == mathBlocks.count)
    #expect(afterFirst.mathFallbackCount == 0)

    for block in mathBlocks {
        _ = configuration.prepare(block: block)
    }

    let afterSecond = recorder.snapshot()
    #expect(afterSecond.mathRenderCount == afterFirst.mathRenderCount)
    #expect(afterSecond.mathFallbackCount == afterFirst.mathFallbackCount)
    #expect(afterSecond.cacheHitCount >= afterFirst.cacheHitCount + mathBlocks.count)
}

private func loadMathCorpus() throws -> MathCorpus {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot = testDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repositoryRoot.appendingPathComponent("Tools/math-corpus/corpus.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(MathCorpus.self, from: data)
}

private func isPNG(_ data: Data) -> Bool {
    let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    return data.starts(with: pngSignature)
}
