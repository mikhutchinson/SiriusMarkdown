import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

@Test
@MainActor
func MarkdownRenderSessionPreparesSnapshotsAndSourceBackedCopy() throws {
    let session = MarkdownRenderSession(configuration: .compactChat)
    session.append("# Title\n\n")
    session.append("Body with $x^2$ and ![diagram](local-diagram.png).\n\n")
    session.finish()

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
func MarkdownSelectionControllerCopiesBoundedSourceBackedSelection() throws {
    let session = MarkdownRenderSession(configuration: .document)
    session.append("# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\n")
    session.finish()

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
    #expect(selectedMarkdown.contains("# Title"))
    #expect(selectedMarkdown.contains("First paragraph"))
    #expect(selectedMarkdown.contains("Second paragraph") == false)
    #expect(selectedText.contains("Title"))
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

    #expect(defaultContent.code == nil)
    #expect(defaultMermaid.ascii.contains("Start"))
    #expect(defaultMermaid.ascii.contains("Done"))
    #expect(lightSVG.contains("Start"))
    #expect(lightSVG.contains("Done"))
    #expect(darkSVG.contains("Start"))
    #expect(darkSVG.contains("Done"))
    #expect(lightSVG.contains("var(") == false)
    #expect(darkSVG.contains("var(") == false)
    #expect(lightSVG.contains("#1F2937"))
    #expect(darkSVG.contains("#F3F4F6"))
    #expect(defaultPlan.mermaidRendered)

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
