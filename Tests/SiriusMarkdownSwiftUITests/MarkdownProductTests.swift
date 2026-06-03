import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

@Test
@MainActor
func MarkdownRenderSessionPreparesSnapshotsAndSourceBackedCopy() async throws {
    let session = MarkdownRenderSession(configuration: .compactChat)
    session.append("# Title\n\n")
    session.append("Body with $x^2$ and ![diagram](local-diagram.png).\n\n")
    session.finish()
    await session.waitUntilIdle()

    let paragraph = try #require(session.snapshot.blocks.last)
    let prepared = try #require(session.preparedSnapshot.preparedContentByBlockID[paragraph.id])

    #expect(session.snapshot.isFinished)
    #expect(prepared.inlineLayout?.prepared.runs.contains { $0.kind == .math } == true)
    #expect(prepared.inlineLayout?.images.first?.source == "local-diagram.png")
    #expect(session.markdown(in: paragraph.sourceRange).contains("Body with"))
    #expect(session.configuration.copyProvider?.markdown(paragraph.sourceRange)?.contains("local-diagram.png") == true)
}

@Test
@MainActor
func MarkdownRenderSessionAppendReturnsBeforeParseAndPrepare() async throws {
    let markdown = "# Title\n\nBody that should be processed by the render-session worker.\n"
    let streamRecorder = MarkdownDiagnosticsRecorder()
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let session = MarkdownRenderSession(
        configuration: .document,
        streamDiagnosticsRecorder: streamRecorder,
        renderDiagnosticsRecorder: renderRecorder
    )

    session.append(markdown)

    #expect(session.sourceLength == markdown.utf8.count)
    #expect(session.snapshot.sourceLength == 0)
    #expect(streamRecorder.snapshot().parseCount == 0)
    #expect(renderRecorder.snapshot().prepareCount == 0)
    #expect(session.configuration.copyProvider?.markdownForDocument() == markdown)

    await session.waitUntilIdle()

    #expect(session.snapshot.sourceLength == markdown.utf8.count)
    #expect(streamRecorder.snapshot().parseCount > 0)
    #expect(renderRecorder.snapshot().prepareCount > 0)
}

@Test
@MainActor
func MarkdownSelectionControllerCopiesBoundedSourceBackedSelection() async throws {
    let source = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let controller = MarkdownSelectionController(maximumSelectedBlockCount: 2)
    controller.updateSnapshot(session.snapshot)
    let first = try #require(session.snapshot.blocks.first?.id)
    let last = try #require(session.snapshot.blocks.last?.id)

    controller.selectRange(from: first, to: last)
    let selectedMarkdown = controller.selectedMarkdown(
        in: session.preparedSnapshot,
        copyProvider: session.configuration.copyProvider
    )
    let selectedText = controller.selectedPlainText(in: session.preparedSnapshot)

    #expect(controller.selectedBlockIDs.count == 2)
    #expect(controller.selectedSourceRanges.count == 1)
    #expect(selectedMarkdown == "# Title\n\nFirst paragraph.")
    #expect(selectedText.contains("Title"))
}

@Test
@MainActor
func MarkdownSelectionControllerCopiesExactPartialAndNonContiguousSourceRanges() async throws {
    let source = "Alpha beta gamma.\n\nSecond paragraph.\n\nThird paragraph.\n"
    let session = MarkdownRenderSession(configuration: .document)
    session.append(source)
    session.finish()
    await session.waitUntilIdle()

    let first = try #require(session.snapshot.blocks.first)
    let last = try #require(session.snapshot.blocks.last)
    let controller = MarkdownSelectionController()
    controller.updateSnapshot(session.snapshot)

    controller.selectSourceRanges(
        [sourceRange(of: "beta gamma", in: source)],
        selectedBlockIDs: [first.id]
    )
    #expect(controller.selectedMarkdown(in: session.preparedSnapshot, copyProvider: session.configuration.copyProvider) == "beta gamma")

    controller.selectSourceRanges(
        [
            sourceRange(of: "Third paragraph.", in: source),
            sourceRange(of: "Alpha", in: source),
        ],
        selectedBlockIDs: [last.id, first.id]
    )
    #expect(controller.selectedSourceRanges.map(\.byteRange.lowerBound) == controller.selectedSourceRanges.map(\.byteRange.lowerBound).sorted())
    #expect(controller.selectedMarkdown(in: session.preparedSnapshot, copyProvider: session.configuration.copyProvider) == "Alpha\nThird paragraph.")
}

@Test
@MainActor
func MarkdownSelectionControllerFallsBackToPlainTextWhenSourceIsUnavailable() async throws {
    let session = MarkdownRenderSession(configuration: .document)
    session.append("Plain fallback paragraph.\n")
    session.finish()
    await session.waitUntilIdle()

    let block = try #require(session.snapshot.blocks.first)
    let controller = MarkdownSelectionController()
    controller.updateSnapshot(session.snapshot)
    controller.select(block.id)

    #expect(controller.selectedMarkdown(in: session.preparedSnapshot, copyProvider: nil) == "Plain fallback paragraph.")
}

@Test
@MainActor
func MarkdownSelectionSurvivesStreamingAppendAndWidthRelayoutWithoutExpensiveWork() async throws {
    let renderRecorder = MarkdownDiagnosticsRecorder()
    let session = MarkdownRenderSession(
        configuration: .document,
        renderDiagnosticsRecorder: renderRecorder
    )
    session.append("# Title\n\nSelected paragraph wraps across visual lines for geometry.\n\n")
    await session.waitUntilIdle()

    let controller = MarkdownSelectionController()
    controller.updateSnapshot(session.snapshot)
    let selectedBlock = try #require(session.snapshot.blocks.first)
    controller.select(selectedBlock.id)
    let selectedIDs = controller.selectedBlockIDs
    let selectedRanges = controller.selectedSourceRanges

    session.append("Active tail keeps streaming.\n")
    await session.waitUntilIdle()
    controller.updateSnapshot(session.snapshot)

    #expect(controller.selectedBlockIDs == selectedIDs)
    #expect(controller.selectedSourceRanges == selectedRanges)

    let preparedBlock = try #require(session.preparedSnapshot.preparedContentByBlockID[selectedBlock.id])
    let inline = try #require(preparedBlock.inlineLayout)
    let before = renderRecorder.snapshot()
    for width in [120.0, 180.0, 240.0] {
        _ = InlineRunsView.lineLayout(for: inline, containerWidth: width)
    }
    let after = renderRecorder.snapshot()

    #expect(after.parseCount == before.parseCount)
    #expect(after.prepareCount == before.prepareCount)
    #expect(after.codeHighlightCount == before.codeHighlightCount)
    #expect(after.mathRenderCount == before.mathRenderCount)
    #expect(after.layoutCount >= before.layoutCount)
}

@Suite(.serialized)
struct MarkdownProductPerformanceTests {
    @Test
    func ProductLongTranscriptResizeUsesPreparedLayoutOnly() throws {
        guard ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_PRODUCT_CHECK"] == "1" else {
            return
        }

        var stream = MarkdownStream()
        for index in 0..<10_000 {
            stream.append("Paragraph \(index) with **strong text** and [link](https://example.com/\(index)).\n\n")
        }
        stream.append("Active mutable tail with `code` and $x^2$")

        let snapshot = stream.snapshot()
        let recorder = MarkdownDiagnosticsRecorder()
        let configuration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
        let prepared = configuration.prepare(snapshot: snapshot)
        let tail = try #require(snapshot.blocks.last)
        let inline = try #require(prepared.preparedContentByBlockID[tail.id]?.inlineLayout)
        let afterPrepare = recorder.snapshot()

        for width in stride(from: 160.0, through: 520.0, by: 40.0) {
            _ = InlineRunsView.lineLayout(for: inline, containerWidth: width)
        }
        let afterResize = recorder.snapshot()

        #expect(snapshot.blocks.count == 10_001)
        #expect(tail.isSealed == false)
        #expect(afterResize.parseCount == afterPrepare.parseCount)
        #expect(afterResize.prepareCount == afterPrepare.prepareCount)
        #expect(afterResize.codeHighlightCount == afterPrepare.codeHighlightCount)
        #expect(afterResize.mathRenderCount == afterPrepare.mathRenderCount)
        #expect(afterResize.layoutCount > afterPrepare.layoutCount)
    }
}

private func sourceRange(of substring: String, in source: String) -> MarkdownSourceRange {
    guard let range = source.range(of: substring) else {
        Issue.record("Missing substring \(substring)")
        return MarkdownSourceRange(byteRange: 0..<0, lineRange: 1..<2)
    }

    let lower = source[..<range.lowerBound].utf8.count
    let upper = source[..<range.upperBound].utf8.count
    let line = source[..<range.lowerBound].filter { $0 == "\n" }.count + 1
    let lineEnd = source[..<range.upperBound].filter { $0 == "\n" }.count + 2
    return MarkdownSourceRange(byteRange: lower..<upper, lineRange: line..<lineEnd)
}

@Test
func ProductDefaultCodeHighlighterAddsThemeAwareAttributes() {
    let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(
        """
        let value = {"name":"sirius","count":2}
        // comment
        """,
        infoString: "swift"
    )

    #expect(highlighted.runs.contains { $0.foregroundColor != nil })
}

@Test
func ProductDefaultCodeHighlighterUsesLanguageAwareFixtures() {
    let fixtures: [(language: String, code: String)] = [
        ("swift", "struct Example { let value = 42 }\n"),
        ("json", "{ \"name\": \"sirius\", \"count\": 2 }\n"),
        ("bash", "if [ -f Package.swift ]; then swift test; fi\n"),
        ("yaml", "name: SiriusMarkdown\nplatforms:\n  - macOS\n"),
        ("diff", "-old\n+new\n"),
        ("markdown", "# Title\n\n`code`\n")
    ]

    for fixture in fixtures {
        let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(
            fixture.code,
            infoString: fixture.language
        )

        #expect(String(highlighted.characters) == fixture.code)
        #expect(highlighted.runs.contains { $0.foregroundColor != nil })
    }
}

@Test
func ProductDefaultCodeHighlighterHandlesLongSwiftStringLiteralsWithoutCrashing() {
    let code = """
    let veryLongIdentifierName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
    """

    let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(
        code,
        infoString: "swift"
    )

    #expect(String(highlighted.characters) == code)
    #expect(highlighted.runs.contains { $0.foregroundColor != nil })
}

@Test
func ProductDefaultSwiftCodeHighlighterKeepsNestedInterpolationStringsColored() throws {
    let palette = MarkdownSyntaxHighlightingPalette.default
    let code = #"let value = "\(String("inner"))""#
    let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(
        code,
        infoString: "swift",
        palette: palette
    )

    #expect(String(highlighted.characters) == code)
    let colors = foregroundColors(for: "inner", in: highlighted)
    #expect(colors.isEmpty == false)
    #expect(colors.allSatisfy { $0 == palette.string.swiftUIColor })
}

@Test
func ProductDefaultSwiftCodeHighlighterRecognizesModernSwiftKeywords() throws {
    let palette = MarkdownSyntaxHighlightingPalette.default
    let code = "actor Worker { func run() throws { throw Failure() } }\n"
    let highlighted = DefaultMarkdownCodeHighlighter().highlightedCode(
        code,
        infoString: "swift",
        palette: palette
    )

    #expect(String(highlighted.characters) == code)
    for keyword in ["actor", "throw"] {
        let colors = foregroundColors(for: keyword, in: highlighted)
        #expect(colors.isEmpty == false)
        #expect(colors.allSatisfy { $0 == palette.keyword.swiftUIColor })
    }
}

@Test
func ProductDefaultCodeHighlighterKeepsUnknownAndPlainFencesPlain() {
    let diagnosticFence = """
    id: 019de2e4-0571-7bf3-94f0-3cd35b8fa0d3
    timestamp: 2026-05-02T10:15:00Z
    message: "not source code"
    """

    let unknown = DefaultMarkdownCodeHighlighter().highlightedCode(
        diagnosticFence,
        infoString: "memory-diagnostic"
    )
    let plaintext = DefaultMarkdownCodeHighlighter().highlightedCode(
        "let fake = \"text\"\n",
        infoString: "plaintext"
    )
    let unlabeled = DefaultMarkdownCodeHighlighter().highlightedCode(
        "let fake = \"text\"\n",
        infoString: nil
    )

    #expect(String(unknown.characters) == diagnosticFence)
    #expect(unknown.runs.contains { $0.foregroundColor != nil } == false)
    #expect(plaintext.runs.contains { $0.foregroundColor != nil } == false)
    #expect(unlabeled.runs.contains { $0.foregroundColor != nil } == false)
}

private func foregroundColors(
    for target: String,
    in highlighted: AttributedString
) -> [Color?] {
    let rendered = String(highlighted.characters)
    guard let range = rendered.range(of: target) else {
        return []
    }

    let targetStart = rendered.distance(from: rendered.startIndex, to: range.lowerBound)
    let targetEnd = rendered.distance(from: rendered.startIndex, to: range.upperBound)
    var runStart = 0
    var colors: [Color?] = []

    for run in highlighted.runs {
        let runText = String(highlighted[run.range].characters)
        let runEnd = runStart + runText.count
        if runStart < targetEnd, targetStart < runEnd {
            colors.append(run.foregroundColor)
        }
        runStart = runEnd
    }

    return colors
}

@Test
func ProductPreparedImageDecisionsKeepRemoteLoadingOptIn() throws {
    var stream = MarkdownStream()
    stream.append("Remote ![diagram](https://example.com/diagram.png)")
    stream.finish()

    let configuration = MarkdownRendererConfiguration()
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let block = try #require(stream.snapshot().blocks.first)
    let image = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout?.images.first)

    #expect(image.source == "https://example.com/diagram.png")
    if case let .placeholder(reason) = image.preparedSource {
        #expect(reason.contains("disabled"))
    } else {
        Issue.record("Default image handling must stay placeholder-only.")
    }
}

@Test
func ProductInlineMathUsesConfiguredRenderer() throws {
    var stream = MarkdownStream()
    stream.append("Inline math should render through hooks: $x^2 + \\alpha$.")
    stream.finish()

    let configuration = MarkdownRendererConfiguration(
        mathRenderer: ProductInlineMathRenderer()
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let block = try #require(stream.snapshot().blocks.first)
    let inline = try #require(prepared.preparedContentByBlockID[block.id]?.inlineLayout)

    #expect(inline.prepared.runs.contains { $0.kind == .math && $0.text == "math[x^2 + \\alpha]" })
    #expect(String(inline.attributed.characters).contains("math[x^2 + \\alpha]"))
}

@Test
func ProductDefaultMermaidRendererPreparesDiagramsAndSupportsOptOut() throws {
    var stream = MarkdownStream()
    stream.append("```mermaid\ngraph LR\nA[Start] --> B[Done]\n```")
    stream.finish()

    let snapshot = stream.snapshot()
    let block = try #require(snapshot.blocks.first)
    let defaultConfiguration = MarkdownRendererConfiguration()
    let defaultPrepared = defaultConfiguration.prepare(snapshot: snapshot)
    let defaultContent = try #require(defaultPrepared.preparedContentByBlockID[block.id])
    let defaultPlan = MarkdownBlockView.renderPlan(for: block, configuration: defaultConfiguration)

    let defaultMermaid = try #require(defaultContent.mermaid)
    let lightSVG = try #require(defaultMermaid.svg)
    let darkSVG = try #require(defaultMermaid.darkSVG)
    let geometry = try #require(defaultMermaid.geometry)

    #expect(defaultContent.code == nil)
    #expect(defaultMermaid.ascii.contains("Start"))
    #expect(defaultMermaid.ascii.contains("Done"))
    #expect(geometry.width > 0)
    #expect(geometry.height > 0)
    #expect(lightSVG.contains("Start"))
    #expect(lightSVG.contains("Done"))
    #expect(darkSVG.contains("Start"))
    #expect(darkSVG.contains("Done"))
    #expect(lightSVG.contains("fonts.googleapis.com") == false)
    #expect(darkSVG.contains("fonts.googleapis.com") == false)
    #expect(lightSVG.contains("var(") == false)
    #expect(darkSVG.contains("var(") == false)
    #expect(lightSVG.contains("#1F2937"))
    #expect(darkSVG.contains("#F3F4F6"))
    #expect(defaultPlan.mermaidRendered)

    let preparedPlan = MarkdownBlockView.renderPlan(
        for: block,
        configuration: defaultConfiguration,
        preparedContent: defaultContent
    )
    #expect(preparedPlan.mermaidRendered)
    #expect(preparedPlan.mermaidHasGeometry)
    #expect(preparedPlan.mermaidControlsVisible)
    #expect(preparedPlan.mermaidZoomControlsVisible)
    #expect(preparedPlan.mermaidFitButtonVisible)
    #expect(preparedPlan.mermaidResetButtonVisible)
    #expect(MarkdownTheme.compactChat.mermaidAffordances.maximumViewportHeight == 280)
    #expect(MarkdownTheme.document.mermaidAffordances.maximumViewportHeight == 520)

    var hiddenTheme = MarkdownTheme()
    hiddenTheme.mermaidAffordances = .hidden
    let hiddenPlan = MarkdownBlockView.renderPlan(
        for: block,
        configuration: MarkdownRendererConfiguration(theme: hiddenTheme),
        preparedContent: defaultContent
    )
    #expect(hiddenPlan.mermaidRendered)
    #expect(hiddenPlan.mermaidHasGeometry)
    #expect(hiddenPlan.mermaidControlsVisible == false)
    #expect(hiddenPlan.mermaidZoomControlsVisible == false)
    #expect(hiddenPlan.mermaidFitButtonVisible == false)
    #expect(hiddenPlan.mermaidResetButtonVisible == false)

    var asciiOnlyContent = defaultContent
    asciiOnlyContent.mermaid = MarkdownPreparedMermaidDiagram(
        source: "graph LR\nA[Start] --> B[Done]",
        sourceRange: block.sourceRange,
        ascii: "Start -> Done"
    )
    let asciiOnlyPlan = MarkdownBlockView.renderPlan(
        for: block,
        configuration: defaultConfiguration,
        preparedContent: asciiOnlyContent
    )
    #expect(asciiOnlyPlan.mermaidRendered)
    #expect(asciiOnlyPlan.mermaidHasGeometry == false)
    #expect(asciiOnlyPlan.mermaidControlsVisible == false)
    #expect(asciiOnlyPlan.mermaidZoomControlsVisible == false)
    #expect(asciiOnlyPlan.mermaidFitButtonVisible == false)
    #expect(asciiOnlyPlan.mermaidResetButtonVisible == false)

    let disabledConfiguration = MarkdownRendererConfiguration(mermaidRenderer: nil)
    let disabledPrepared = disabledConfiguration.prepare(snapshot: snapshot)
    let disabledContent = try #require(disabledPrepared.preparedContentByBlockID[block.id])
    let disabledPlan = MarkdownBlockView.renderPlan(for: block, configuration: disabledConfiguration)

    #expect(disabledContent.mermaid == nil)
    #expect(disabledContent.code != nil)
    #expect(disabledPlan.mermaidRendered == false)
}

private struct ProductInlineMathRenderer: MarkdownMathRenderer {
    func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        AttributedString("math[\(source)]")
    }
}
