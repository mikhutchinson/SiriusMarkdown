import AppKit
import Darwin
import SiriusMarkdown
import SwiftUI

@main
struct SiriusMarkdownRenderProbe {
    @MainActor
    static func main() {
        let result = renderRepresentativeDocument()
        let nativeResult = renderRepresentativeNativeDocument()
        let chatResult = renderCompactChatTranscript()
        let transcriptWrapResult = renderTranscriptWrappingProbe()
        let multilingualResult = renderMultilingualNativeDocument()
        let attributeResult = renderInlineAttributeCrossingProbe()
        let overflowResult = renderOverflowContainmentProbe()
        let codeHighlightResult = renderCodeHighlightingProbe()
        let breakResult = renderBreakAndLongWordProbe()
        let widthResult = renderInlineWidthProbe()
        let nativeSpacingResult = renderNativeInlineSpacingProbe()
        let containmentResult = renderPreparedNativeContainmentProbe()
        let resizeResult = renderPreparedNativeResizeProbe()
        let documentAffordanceResult = renderDocumentAffordanceProbe(collapsed: false)
        let collapsedDocumentAffordanceResult = renderDocumentAffordanceProbe(collapsed: true)
        let mermaidResult = renderMermaidDiagramProbe()
        let selectionStressResult = renderNativeTextSelectionStressProbe()
        assertRenderable("MarkdownDocumentView", result)
        assertRenderable("prepared native MarkdownDocumentView", nativeResult)
        assertRenderable("compact chat prepared native transcript", chatResult, minimumNonWhitePixels: 1_400)
        assertRenderable("compact transcript wrapping prepared native transcript", transcriptWrapResult, minimumNonWhitePixels: 1_600)
        assertRenderable("multilingual prepared native document", multilingualResult, minimumNonWhitePixels: 1_200)
        assertRenderable("inline attribute crossing prepared native document", attributeResult)
        assertRenderable("code and table overflow prepared native document", overflowResult)
        assertRenderable(
            "code highlighting prepared native document",
            codeHighlightResult,
            minimumNonWhitePixels: 9_000,
            minimumDistinctColorBuckets: 12
        )
        assertRenderable("hard-break and long-word prepared native document", breakResult, minimumNonWhitePixels: 1_200)
        assertRenderable("prepared native containment document", containmentResult, minimumNonWhitePixels: 1_400)
        assertRenderable("prepared native resize document", resizeResult, minimumNonWhitePixels: 1_200)
        assertRenderable("document affordance surface", documentAffordanceResult, minimumNonWhitePixels: 2_600)
        assertRenderable("collapsed document affordance surface", collapsedDocumentAffordanceResult, minimumNonWhitePixels: 1_000)
        assertRenderable(
            "Mermaid diagram pan and zoom surface",
            mermaidResult,
            minimumNonWhitePixels: 4_000,
            minimumDistinctColorBuckets: 6
        )
        assertRenderable(
            "enabled native text selection stress surface",
            selectionStressResult,
            minimumNonWhitePixels: 2_400
        )

        if widthResult.darkRightmostX < widthResult.minimumDarkRightmostX {
            fputs(
                "error: prepared inline text only reached x=\(widthResult.darkRightmostX); expected at least \(widthResult.minimumDarkRightmostX). This usually means the view measured its wrapped intrinsic width instead of the offered document width.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if nativeSpacingResult.wideDarkColumnGaps < nativeSpacingResult.minimumWideDarkColumnGaps {
            fputs(
                "error: native prepared inline rendering produced only \(nativeSpacingResult.wideDarkColumnGaps) wide word gaps; expected at least \(nativeSpacingResult.minimumWideDarkColumnGaps). This usually means word spacing collapsed while rendering prepared lines.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if overflowResult.darkRightmostX < 300 {
            fputs(
                "error: code/table overflow probe only reached x=\(overflowResult.darkRightmostX); expected wide block content to render inside its containment surface.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if overflowResult.fittingWidth > overflowResult.maximumFittingWidth {
            fputs(
                "error: code/table overflow probe fitting width was \(overflowResult.fittingWidth); expected <= \(overflowResult.maximumFittingWidth) so wide code scrolls inside the host column instead of stretching the transcript.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if containmentResult.darkRightmostX > containmentResult.maximumDarkRightmostX {
            fputs(
                "error: prepared native containment probe leaked dark text to x=\(containmentResult.darkRightmostX); expected no normal inline text beyond x=\(containmentResult.maximumDarkRightmostX).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if transcriptWrapResult.darkRightmostX > transcriptWrapResult.maximumDarkRightmostX {
            fputs(
                "error: compact transcript wrapping probe leaked dark text to x=\(transcriptWrapResult.darkRightmostX); expected no normal inline text beyond x=\(transcriptWrapResult.maximumDarkRightmostX).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if transcriptWrapResult.fittingWidth > transcriptWrapResult.maximumFittingWidth {
            fputs(
                "error: compact transcript wrapping fitting width was \(transcriptWrapResult.fittingWidth); expected <= \(transcriptWrapResult.maximumFittingWidth).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if containmentResult.fittingWidth > containmentResult.maximumFittingWidth {
            fputs(
                "error: prepared native containment fitting width was \(containmentResult.fittingWidth); expected <= \(containmentResult.maximumFittingWidth).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if resizeResult.darkRightmostX > resizeResult.maximumDarkRightmostX {
            fputs(
                "error: prepared native resize probe leaked dark text to x=\(resizeResult.darkRightmostX); expected no normal inline text beyond x=\(resizeResult.maximumDarkRightmostX) after narrowing the host column.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if resizeResult.fittingWidth > resizeResult.maximumFittingWidth {
            fputs(
                "error: prepared native resize fitting width was \(resizeResult.fittingWidth); expected <= \(resizeResult.maximumFittingWidth) after shrinking the host column.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if documentAffordanceResult.nonWhiteRightmostX < Int(520 * documentAffordanceResult.pixelScale) {
            fputs(
                "error: document affordance surface did not render non-white pixels in the top-right action region; rightmost x was \(documentAffordanceResult.nonWhiteRightmostX).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if collapsedDocumentAffordanceResult.nonWhiteRightmostX < Int(520 * collapsedDocumentAffordanceResult.pixelScale) {
            fputs(
                "error: collapsed document affordance surface did not keep visible header chrome; rightmost x was \(collapsedDocumentAffordanceResult.nonWhiteRightmostX).\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if mermaidResult.rightBandNonWhitePixels < 80 {
            fputs(
                "error: Mermaid diagram probe did not render visible toolbar/action pixels in the diagram surface; sampled \(mermaidResult.rightBandNonWhitePixels) non-white pixels in the right band.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if mermaidResult.fittingWidth > mermaidResult.maximumFittingWidth {
            fputs(
                "error: Mermaid diagram probe fitting width was \(mermaidResult.fittingWidth); expected <= \(mermaidResult.maximumFittingWidth) so diagrams stay contained instead of stretching the document.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        let minimumSelectionStressTextViewCount = 8
        if selectionStressResult.selectableTextViewCount < minimumSelectionStressTextViewCount {
            fputs(
                "error: enabled native text selection stress probe mounted \(selectionStressResult.selectableTextViewCount) selectable AppKit text leaves; expected at least \(minimumSelectionStressTextViewCount) so list, quote, code, and table text leaves are covered.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        print("MarkdownDocumentView render probe: \(result.nonWhitePixels) non-white pixels, \(result.distinctColorBuckets) color buckets")
        print("Prepared native document render probe: \(nativeResult.nonWhitePixels) non-white pixels, \(nativeResult.distinctColorBuckets) color buckets")
        print("Compact chat render probe: \(chatResult.nonWhitePixels) non-white pixels, \(chatResult.distinctColorBuckets) color buckets")
        print("Compact transcript wrapping probe: dark text reached x=\(transcriptWrapResult.darkRightmostX), fitting width \(transcriptWrapResult.fittingWidth)")
        print("Multilingual render probe: \(multilingualResult.nonWhitePixels) non-white pixels, \(multilingualResult.distinctColorBuckets) color buckets")
        print("Inline attribute crossing probe: \(attributeResult.nonWhitePixels) non-white pixels, \(attributeResult.distinctColorBuckets) color buckets")
        print("Overflow containment probe: \(overflowResult.nonWhitePixels) non-white pixels, \(overflowResult.distinctColorBuckets) color buckets, fitting width \(overflowResult.fittingWidth)")
        print("Code highlighting probe: \(codeHighlightResult.nonWhitePixels) non-white pixels, \(codeHighlightResult.distinctColorBuckets) color buckets")
        print("Break and long-word probe: \(breakResult.nonWhitePixels) non-white pixels, \(breakResult.distinctColorBuckets) color buckets")
        print("Prepared inline width probe: dark text reached x=\(widthResult.darkRightmostX)")
        print("Native inline spacing probe: \(nativeSpacingResult.wideDarkColumnGaps) wide word gaps")
        print("Prepared native containment probe: dark text reached x=\(containmentResult.darkRightmostX), fitting width \(containmentResult.fittingWidth)")
        print("Prepared native resize probe: dark text reached x=\(resizeResult.darkRightmostX), fitting width \(resizeResult.fittingWidth)")
        print("Document affordance surface probe: \(documentAffordanceResult.nonWhitePixels) non-white pixels, rightmost x=\(documentAffordanceResult.nonWhiteRightmostX)")
        print("Collapsed document affordance surface probe: \(collapsedDocumentAffordanceResult.nonWhitePixels) non-white pixels, rightmost x=\(collapsedDocumentAffordanceResult.nonWhiteRightmostX)")
        print("Mermaid diagram probe: \(mermaidResult.nonWhitePixels) non-white pixels, \(mermaidResult.distinctColorBuckets) color buckets, right-band pixels=\(mermaidResult.rightBandNonWhitePixels), fitting width \(mermaidResult.fittingWidth)")
        print("Enabled native text selection stress probe: \(selectionStressResult.nonWhitePixels) non-white pixels, \(selectionStressResult.distinctColorBuckets) color buckets, selectable AppKit text leaves=\(selectionStressResult.selectableTextViewCount)")
    }

    private static func assertRenderable(
        _ label: String,
        _ result: RenderResult,
        minimumNonWhitePixels: Int = 2_000,
        minimumDistinctColorBuckets: Int = 3
    ) {
        if result.nonWhitePixels < minimumNonWhitePixels {
            fputs(
                "error: \(label) rendered only \(result.nonWhitePixels) non-white pixels; expected at least \(minimumNonWhitePixels)\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if result.distinctColorBuckets < minimumDistinctColorBuckets {
            fputs(
                "error: \(label) rendered only \(result.distinctColorBuckets) color buckets; expected at least \(minimumDistinctColorBuckets)\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func renderRepresentativeDocument() -> RenderResult {
        renderDocument(
            markdown:
                """
                # Render Check

                Paragraph with **strong** text, `code`, and [link](https://example.com).

                > Block quote with stable native layout.

                - [ ] task
                - [x] done

                | A | B |
                | - | - |
                | 1 | 2 |

                ```swift
                print("native")
                ```
                """,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_RENDER_PROBE_OUTPUT"]
        )
    }

    @MainActor
    private static func renderRepresentativeNativeDocument() -> RenderResult {
        renderDocument(
            markdown:
                """
                # Native Render Check

                Paragraph with **strong** text, `code`, and [link](https://example.com).

                > Block quote with stable native layout.

                - [ ] task
                - [x] done

                | A | B |
                | - | - |
                | 1 | 2 |

                ```swift
                print("native")
                ```
                """,
            configuration: MarkdownRendererConfiguration(
                theme: .document,
                inlineRenderingMode: .preparedNativeLines
            ),
            outputPath: nil
        )
    }

    @MainActor
    private static func renderCompactChatTranscript() -> RenderResult {
        renderDocument(
            markdown:
                """
                Assistant response with **strong text**, `inline code`, [safe link](https://example.com), and image alt ![diagram](diagram.png).

                - [ ] streamed task
                - [x] completed task
                """,
            configuration: .compactChat,
            size: NSSize(width: 520, height: 260),
            outputPath: nil
        )
    }

    @MainActor
    private static func renderTranscriptWrappingProbe() -> RenderResult {
        let markdown =
            """
            - File changed:
              - `/opt/example/workspaces/sample-project/build-artifacts/transcript_renderer_wrap_probe.log`
            - Verification command:
              - `./.venv/bin/python experiment_honest_ensemble.py | tee /tmp/example_render_pipeline/transcript_renderer_wrap_probe_20260503_211600.log`
            - Evidence URL:
              - `https://example.com/results/transcript-renderer-wrap-probe/2026/05/03/long_identifier_value`
            > Quote with `/var/tmp/example_render_pipeline/transcript_renderer_wrap_probe_20260503_211600.log`
            """
        let configuration = MarkdownRendererConfiguration.compactChat
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let columnWidth = CGFloat(260)
        let leadingInset = CGFloat(32)
        let size = NSSize(width: 640, height: 420)
        let document = StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
            .frame(width: columnWidth, alignment: .leading)
        let fittingView = NSHostingView(rootView: document)
        fittingView.frame = NSRect(origin: .zero, size: NSSize(width: columnWidth, height: 1_000))
        fittingView.layoutSubtreeIfNeeded()
        let fittingWidth = fittingView.fittingSize.width

        let root = HStack(spacing: 0) {
            Color.white.frame(width: leadingInset)
            StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
            Color.white
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        var result = renderHosted(
            root,
            size: size,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_TRANSCRIPT_WRAP_PROBE_OUTPUT"]
        )
        result.maximumDarkRightmostX = Int(Double(leadingInset + columnWidth + 8) * result.pixelScale)
        result.fittingWidth = fittingWidth
        result.maximumFittingWidth = Double(columnWidth + 1)
        return result
    }

    @MainActor
    private static func renderMultilingualNativeDocument() -> RenderResult {
        renderDocument(
            markdown:
                """
                # Multilingual

                English 日本語 العربية emoji 😀 café wraps in the prepared native line path without corrupting byte ranges.
                """,
            configuration: .document,
            size: NSSize(width: 560, height: 260),
            outputPath: nil
        )
    }

    @MainActor
    private static func renderInlineAttributeCrossingProbe() -> RenderResult {
        renderDocument(
            markdown:
                """
                A paragraph with [linked text crossing a prepared line boundary](https://example.com) and `code value crossing another boundary` so attributes survive line slicing.
                """,
            configuration: .document,
            size: NSSize(width: 420, height: 240),
            outputPath: nil
        )
    }

    @MainActor
    private static func renderOverflowContainmentProbe() -> RenderResult {
        let markdown =
            """
            | Region | Very Wide Evidence |
            | - | - |
            | Code | `abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz` |

            ```swift
            let veryLongIdentifierName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
            ```
            """
        let configuration = MarkdownRendererConfiguration.document
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let columnWidth = CGFloat(320)
        let leadingInset = CGFloat(32)
        let size = NSSize(width: 640, height: 320)

        let fittingView = NSHostingView(
            rootView: MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
                .frame(width: columnWidth, alignment: .leading)
        )
        fittingView.frame = NSRect(origin: .zero, size: NSSize(width: columnWidth, height: 1_000))
        fittingView.layoutSubtreeIfNeeded()
        let fittingWidth = fittingView.fittingSize.width

        let root = HStack(spacing: 0) {
            Color.white.frame(width: leadingInset)
            MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
            Color.white
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        var result = renderHosted(
            root,
            size: size,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_OVERFLOW_PROBE_OUTPUT"]
        )
        result.maximumDarkRightmostX = Int(Double(leadingInset + columnWidth + 8) * result.pixelScale)
        result.fittingWidth = fittingWidth
        result.maximumFittingWidth = Double(columnWidth + 1)
        return result
    }

    @MainActor
    private static func renderCodeHighlightingProbe() -> RenderResult {
        renderDocument(
            markdown:
                """
                # Code Highlighting

                ```swift
                struct Message {
                    let id: UUID
                    let body: String
                }
                ```

                ```json
                { "role": "assistant", "tokens": 128, "ok": true }
                ```

                ```bash
                set -euo pipefail
                swift test --filter Product
                ```

                ```yaml
                renderer:
                  code:
                    languageAware: true
                    autodetect: false
                ```

                ```diff
                - lexical fallback colored every number
                + language grammar colors meaningful tokens
                ```

                ```markdown
                ## Heading
                Paragraph with **strong** text and `inline code`.
                ```

                ```plaintext
                2026-05-02 12:00:00 memory trace 7a0f-3b2d "not semantic code"
                ```

                ```memory-diagnostics
                2026-05-02T12:00:00Z object=7a0f-3b2d quoted="plain diagnostic text"
                ```
                """,
            configuration: .document,
            size: NSSize(width: 760, height: 980),
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_CODE_HIGHLIGHT_PROBE_OUTPUT"]
        )
    }

    @MainActor
    private static func renderBreakAndLongWordProbe() -> RenderResult {
        renderDocument(
            markdown: "first  \n"
                + "second  \n"
                + "third\n\n"
                + "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
            configuration: .document,
            size: NSSize(width: 420, height: 260),
            outputPath: nil
        )
    }

    @MainActor
    private static func renderInlineWidthProbe() -> RenderResult {
        renderDocument(
            markdown:
                """
                # Width Probe

                This paragraph is intentionally long enough to reach deep into a 640 point document surface when prepared inline content measures the offered parent width instead of repeatedly measuring the intrinsic width of already wrapped text.
                """,
            outputPath: nil
        )
    }

    @MainActor
    private static func renderNativeInlineSpacingProbe() -> RenderResult {
        renderDocument(
            markdown: "MMMM MMMM MMMM MMMM",
            configuration: MarkdownRendererConfiguration(
                theme: MarkdownTheme(
                    blockSpacing: 0,
                    paragraphFontSize: 32,
                    paragraphLineHeight: 44
                ),
                inlineRenderingMode: .preparedNativeLines
            ),
            size: NSSize(width: 640, height: 120),
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_SPACING_PROBE_OUTPUT"]
        )
    }

    @MainActor
    private static func renderPreparedNativeContainmentProbe() -> RenderResult {
        let markdown =
            """
            # Contained Prepared Native Heading With Long Text

            Paragraph with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content that must stay in the proposed column.

            > Quote with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content that must respect quote indentation.

            1. Ordered list item with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content.
               - Nested list item with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content.
            - [x] Task list item with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content.

            | Region | Evidence |
            | - | - |
            | Cell | abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz |
            """
        let configuration = MarkdownRendererConfiguration.document
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let columnWidth = CGFloat(300)
        let leadingInset = CGFloat(32)
        let size = NSSize(width: 720, height: 560)
        let document = MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            .frame(width: columnWidth, alignment: .leading)
        let fittingView = NSHostingView(rootView: document)
        fittingView.frame = NSRect(origin: .zero, size: NSSize(width: columnWidth, height: 1_000))
        fittingView.layoutSubtreeIfNeeded()
        let fittingWidth = fittingView.fittingSize.width

        let root = HStack(spacing: 0) {
            Color.white.frame(width: leadingInset)
            MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
            Color.white
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        var result = renderHosted(
            root,
            size: size,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_CONTAINMENT_PROBE_OUTPUT"]
        )
        result.maximumDarkRightmostX = Int(Double(leadingInset + columnWidth + 8) * result.pixelScale)
        result.fittingWidth = fittingWidth
        result.maximumFittingWidth = Double(columnWidth + 1)
        return result
    }

    @MainActor
    private static func renderPreparedNativeResizeProbe() -> RenderResult {
        let markdown =
            """
            Resize probe paragraph with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content that must rewrap when the host column shrinks.

            - Resize list item with abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz content.
            - Another item with [linked prepared native text](https://example.com) and `inline code` that should stay inside the narrowed column.
            """
        let configuration = MarkdownRendererConfiguration.document
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let leadingInset = CGFloat(32)
        let initialColumnWidth = CGFloat(560)
        let finalColumnWidth = CGFloat(220)
        let canvasSize = NSSize(width: 720, height: 420)
        let model = PreparedNativeResizeProbeModel(columnWidth: initialColumnWidth)

        let fittingView = NSHostingView(
            rootView: StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
                .frame(width: finalColumnWidth, alignment: .leading)
        )
        fittingView.frame = NSRect(origin: .zero, size: NSSize(width: finalColumnWidth, height: 1_000))
        fittingView.layoutSubtreeIfNeeded()
        let fittingWidth = fittingView.fittingSize.width

        let root = PreparedNativeResizeProbeHarness(
            model: model,
            preparedSnapshot: prepared,
            configuration: configuration,
            leadingInset: leadingInset
        )
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        var result = renderHosted(
            root,
            size: canvasSize,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_RESIZE_PROBE_OUTPUT"]
        ) {
            model.columnWidth = finalColumnWidth
        }
        result.maximumDarkRightmostX = Int(Double(leadingInset + finalColumnWidth - 4) * result.pixelScale)
        result.fittingWidth = fittingWidth
        result.maximumFittingWidth = Double(finalColumnWidth + 1)
        return result
    }

    @MainActor
    private static func renderDocumentAffordanceProbe(collapsed: Bool) -> RenderResult {
        let markdown =
            """
            # Affordance Probe

            Document-level affordances should be visible without requiring host-private chrome.

            ```swift
            let surface = MarkdownDocumentSurface(preparedSnapshot: prepared, configuration: configuration)
            ```

            | Action | Source |
            | :--- | :--- |
            | Copy | source-backed Markdown |
            | Export | host-replaceable action handler |
            """
        var configuration = MarkdownRendererConfiguration.document
        configuration.copyProvider = MarkdownCopyProvider(markdownSource: markdown)
        var affordances = MarkdownDocumentAffordances.default
        affordances.startsCollapsed = collapsed

        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let size = NSSize(width: 680, height: collapsed ? 180 : 520)
        let root = MarkdownDocumentSurface(
            title: "Affordance Probe",
            subtitle: "Copy, export, and collapse are package-level document chrome.",
            suggestedFilename: "AffordanceProbe.md",
            preparedSnapshot: prepared,
            configuration: configuration,
            affordances: affordances
        )
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        return renderHosted(
            root,
            size: size,
            outputPath: collapsed
                ? ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_AFFORDANCE_COLLAPSED_PROBE_OUTPUT"]
                : ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_AFFORDANCE_PROBE_OUTPUT"]
        )
    }

    @MainActor
    private static func renderMermaidDiagramProbe() -> RenderResult {
        var configuration = MarkdownRendererConfiguration.document
        configuration.theme.mermaidAffordances.maximumViewportHeight = 220
        let markdown =
            """
            # Mermaid Probe

            ```mermaid
            graph LR
              A[Start] --> B[Validate]
              B --> C[Render]
              C --> D[Done]
            ```

            ```mermaid
            graph LR
              Source[Session transcript] --> Parser[Markdown stream]
              Parser --> Mermaid[Prepared Mermaid SVG]
              Mermaid --> Viewport[Bounded pan and zoom viewport]
              Viewport --> Transcript[SiriusAgent transcript]
              Source --> Memory[Session recap]
              Memory --> Mermaid
            ```

            ```mermaid
            sequenceDiagram
              participant User
              participant Sirius
              participant Renderer
              User->>Sirius: ask for plan
              Sirius->>Renderer: prepare markdown
              Renderer-->>Sirius: diagram with controls
              Sirius-->>User: inline transcript result
            ```
            """
        let size = NSSize(width: 640, height: 560)
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let document = MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)

        let fittingView = NSHostingView(rootView: document)
        fittingView.frame = NSRect(origin: .zero, size: size)
        fittingView.layoutSubtreeIfNeeded()
        let fittingWidth = fittingView.fittingSize.width

        var result = renderHosted(
            document,
            size: size,
            outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_MERMAID_PROBE_OUTPUT"]
        )
        result.fittingWidth = fittingWidth
        result.maximumFittingWidth = 680
        return result
    }

    @MainActor
    private static func renderNativeTextSelectionStressProbe() -> RenderResult {
        withWatchdog("enabled native text selection stress probe", timeout: 18) {
            var configuration = MarkdownRendererConfiguration.compactChat
            configuration.nativeTextSelection = .enabled
            let initialColumnWidth = CGFloat(520)
            let finalColumnWidth = CGFloat(300)
            let size = NSSize(width: 720, height: 620)
            let model = NativeTextSelectionStressProbeModel(
                configuration: configuration,
                columnWidth: initialColumnWidth
            )

            model.append(
                """
                Assistant stream with [a link](https://example.com), **strong text**, `inline code`, and a long path `/tmp/markdown/selection-overlay/stress/probe/transcript-renderer.log`.

                - Streaming list item with enough text to wrap across prepared native lines while selection is enabled.
                  - Nested child item with `inline code` and a URL https://example.com/native-selection/probe.

                """
            )

            let root = NativeTextSelectionStressProbeHarness(model: model)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color.white)
                .environment(\.colorScheme, .light)

            return renderHosted(
                root,
                size: size,
                outputPath: ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_SELECTION_STRESS_PROBE_OUTPUT"]
            ) {
                model.columnWidth = CGFloat(560)
                model.append(
                    """

                    | Surface | Evidence |
                    | - | - |
                    | Transcript | Native selection is mounted on bounded AppKit text leaves. |
                    | Path | `/private/tmp/markdown-selection-overlay-stress/abcdefghijklmnopqrstuvwxyz` |

                    """
                )
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))

                model.columnWidth = finalColumnWidth
                model.append(
                    """

                    ```swift
                    let selectionMode = MarkdownRendererConfiguration(nativeTextSelection: .enabled)
                    print(selectionMode)
                    ```

                    > Quote text wraps after the width change while the selectable surface avoids SwiftUI SelectionOverlay.

                    """
                )
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))

                model.appendHostBoundary(id: "selection-stress-native-boundary")
                model.append(
                    """

                    Final streamed tail after a host boundary with `code`, [link](https://example.com/final), and enough words to trigger another prepared-line layout pass.
                    """
                )
                model.finish()
            }
        }
    }

    @MainActor
    private static func renderDocument(
        markdown: String,
        configuration: MarkdownRendererConfiguration = .document,
        size: NSSize = NSSize(width: 640, height: 520),
        outputPath: String?
    ) -> RenderResult {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()

        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let root = MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)

        return renderHosted(root, size: size, outputPath: outputPath)
    }

    @MainActor
    private static func renderHosted<V: View>(
        _ root: V,
        size: NSSize,
        outputPath: String?,
        afterInitialLayout: (() -> Void)? = nil
    ) -> RenderResult {
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = hostingView

        for _ in 0..<4 {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        if let afterInitialLayout {
            afterInitialLayout()
            for _ in 0..<6 {
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            fputs("error: could not allocate render bitmap\n", stderr)
            exit(EXIT_FAILURE)
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        writeBitmapIfRequested(bitmap, outputPath: outputPath)

        let pixelScale = Double(bitmap.pixelsWide) / Double(size.width)
        let sample = sampleRenderedPixels(bitmap, pixelScale: pixelScale)
        let result = RenderResult(
            nonWhitePixels: sample.nonWhitePixels,
            distinctColorBuckets: sample.distinctColorBuckets,
            nonWhiteRightmostX: sample.nonWhiteRightmostX,
            darkRightmostX: sample.darkRightmostX,
            wideDarkColumnGaps: sample.wideDarkColumnGaps,
            rightBandNonWhitePixels: sample.rightBandNonWhitePixels,
            pixelScale: pixelScale,
            selectableTextViewCount: selectableTextViewCount(in: hostingView)
        )
        window.orderOut(nil)
        window.contentView = nil
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return result
    }

    @MainActor
    private static func selectableTextViewCount(in view: NSView) -> Int {
        let localCount: Int
        if let textView = view as? NSTextView,
           textView.isSelectable,
           !textView.isEditable {
            localCount = 1
        } else {
            localCount = 0
        }

        return view.subviews.reduce(localCount) { count, subview in
            count + selectableTextViewCount(in: subview)
        }
    }

    @MainActor
    private static func withWatchdog<T>(
        _ label: String,
        timeout: TimeInterval,
        _ work: () -> T
    ) -> T {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            fputs("error: \(label) exceeded \(timeout)s; treating this as a main-thread stall\n", stderr)
            exit(EXIT_FAILURE)
        }
        timer.resume()
        let result = work()
        timer.cancel()
        return result
    }

    private static func sampleRenderedPixels(_ bitmap: NSBitmapImageRep, pixelScale: Double) -> PixelSample {
        if let rawSample = sampleRenderedPixelsFromRGBA8(bitmap, pixelScale: pixelScale) {
            return rawSample
        }

        var nonWhitePixels = 0
        var colorBuckets = Set<Int>()
        var nonWhiteRightmostX = 0
        var darkRightmostX = 0
        var rightBandNonWhitePixels = 0
        var darkColumnCounts = Array(repeating: 0, count: bitmap.pixelsWide)
        let rightBandStart = Int(Double(bitmap.pixelsWide) * 0.72)

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                if red < 0.96 || green < 0.96 || blue < 0.96 {
                    nonWhitePixels += 1
                    nonWhiteRightmostX = max(nonWhiteRightmostX, x)
                    if x >= rightBandStart {
                        rightBandNonWhitePixels += 1
                    }
                    let bucket =
                        (Int(red * 15) << 8) |
                        (Int(green * 15) << 4) |
                        Int(blue * 15)
                    colorBuckets.insert(bucket)

                    if red < 0.35, green < 0.35, blue < 0.35 {
                        darkRightmostX = max(darkRightmostX, x)
                        darkColumnCounts[x] += 1
                    }
                }
            }
        }

        // Gap detection ignores isolated antialiasing specks; darkRightmostX remains a per-pixel edge check above.
        let columnDarkThreshold = max(2, bitmap.pixelsHigh / 200)
        let darkColumns = darkColumnCounts.map { $0 >= columnDarkThreshold }
        let minimumGapWidth = max(5, Int(round(4.5 * pixelScale)))

        return PixelSample(
            nonWhitePixels: nonWhitePixels,
            distinctColorBuckets: colorBuckets.count,
            nonWhiteRightmostX: nonWhiteRightmostX,
            darkRightmostX: darkRightmostX,
            wideDarkColumnGaps: wideBlankRunCount(darkColumns, minimumWidth: minimumGapWidth),
            rightBandNonWhitePixels: rightBandNonWhitePixels
        )
    }

    private static func sampleRenderedPixelsFromRGBA8(
        _ bitmap: NSBitmapImageRep,
        pixelScale: Double
    ) -> PixelSample? {
        guard bitmap.bitsPerSample == 8,
              bitmap.samplesPerPixel >= 3,
              bitmap.bitsPerPixel == 32,
              !bitmap.isPlanar,
              bitmap.bitmapFormat.isEmpty,
              let bitmapData = bitmap.bitmapData
        else {
            return nil
        }

        var nonWhitePixels = 0
        var colorBuckets = Set<Int>()
        var nonWhiteRightmostX = 0
        var darkRightmostX = 0
        var rightBandNonWhitePixels = 0
        var darkColumnCounts = Array(repeating: 0, count: bitmap.pixelsWide)
        let rightBandStart = Int(Double(bitmap.pixelsWide) * 0.72)
        let nonWhiteThreshold = UInt8(244)
        let darkThreshold = UInt8(89)

        for y in 0..<bitmap.pixelsHigh {
            let rowStart = y * bitmap.bytesPerRow
            for x in 0..<bitmap.pixelsWide {
                let offset = rowStart + x * 4
                let red = bitmapData[offset]
                let green = bitmapData[offset + 1]
                let blue = bitmapData[offset + 2]

                if red <= nonWhiteThreshold || green <= nonWhiteThreshold || blue <= nonWhiteThreshold {
                    nonWhitePixels += 1
                    nonWhiteRightmostX = max(nonWhiteRightmostX, x)
                    if x >= rightBandStart {
                        rightBandNonWhitePixels += 1
                    }

                    let bucket =
                        (Int(red) * 15 / 255 << 8) |
                        (Int(green) * 15 / 255 << 4) |
                        (Int(blue) * 15 / 255)
                    colorBuckets.insert(bucket)

                    if red <= darkThreshold, green <= darkThreshold, blue <= darkThreshold {
                        darkRightmostX = max(darkRightmostX, x)
                        darkColumnCounts[x] += 1
                    }
                }
            }
        }

        let columnDarkThreshold = max(2, bitmap.pixelsHigh / 200)
        let darkColumns = darkColumnCounts.map { $0 >= columnDarkThreshold }
        let minimumGapWidth = max(5, Int(round(4.5 * pixelScale)))

        return PixelSample(
            nonWhitePixels: nonWhitePixels,
            distinctColorBuckets: colorBuckets.count,
            nonWhiteRightmostX: nonWhiteRightmostX,
            darkRightmostX: darkRightmostX,
            wideDarkColumnGaps: wideBlankRunCount(darkColumns, minimumWidth: minimumGapWidth),
            rightBandNonWhitePixels: rightBandNonWhitePixels
        )
    }

    private static func wideBlankRunCount(_ darkColumns: [Bool], minimumWidth: Int) -> Int {
        guard let firstDark = darkColumns.firstIndex(of: true),
              let lastDark = darkColumns.lastIndex(of: true),
              firstDark < lastDark
        else {
            return 0
        }

        var count = 0
        var blankRun = 0

        for isDark in darkColumns[firstDark...lastDark] {
            if isDark {
                if blankRun >= minimumWidth {
                    count += 1
                }
                blankRun = 0
            } else {
                blankRun += 1
            }
        }

        return count
    }

    private static func writeBitmapIfRequested(_ bitmap: NSBitmapImageRep, outputPath: String?) {
        guard
            let outputPath,
            !outputPath.isEmpty,
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            fputs("warning: could not write render probe image to \(outputPath): \(error)\n", stderr)
        }
    }
}

@MainActor
private final class PreparedNativeResizeProbeModel: ObservableObject {
    @Published var columnWidth: CGFloat

    init(columnWidth: CGFloat) {
        self.columnWidth = columnWidth
    }
}

private struct PreparedNativeResizeProbeHarness: View {
    @ObservedObject var model: PreparedNativeResizeProbeModel
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    var leadingInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.white
                .frame(width: leadingInset)
            StreamingMarkdownView(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration
            )
            .frame(width: model.columnWidth, alignment: .leading)
            Color.white
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
private final class NativeTextSelectionStressProbeModel: ObservableObject {
    @Published var preparedSnapshot: MarkdownPreparedSnapshot
    @Published var columnWidth: CGFloat
    let configuration: MarkdownRendererConfiguration
    private var stream = MarkdownStream()

    init(configuration: MarkdownRendererConfiguration, columnWidth: CGFloat) {
        self.configuration = configuration
        self.columnWidth = columnWidth
        self.preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
    }

    func append(_ markdown: String) {
        stream.append(markdown)
        refresh()
    }

    func appendHostBoundary(id: String) {
        stream.appendHostBoundary(id: MarkdownHostBoundaryID(id))
        refresh()
    }

    func finish() {
        stream.finish()
        refresh()
    }

    private func refresh() {
        preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
    }
}

private struct NativeTextSelectionStressProbeHarness: View {
    @ObservedObject var model: NativeTextSelectionStressProbeModel

    var body: some View {
        HStack(spacing: 0) {
            Color.white.frame(width: 28)
            StreamingMarkdownView(
                preparedSnapshot: model.preparedSnapshot,
                configuration: model.configuration
            )
            .frame(width: model.columnWidth, alignment: .leading)
            .clipped()
            Color.white
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RenderResult {
    var nonWhitePixels: Int
    var distinctColorBuckets: Int
    var nonWhiteRightmostX: Int
    var darkRightmostX: Int
    var wideDarkColumnGaps: Int
    var rightBandNonWhitePixels: Int
    var pixelScale = 1.0
    var selectableTextViewCount = 0
    var maximumDarkRightmostX = Int.max
    var fittingWidth = 0.0
    var maximumFittingWidth = Double.infinity

    let minimumNonWhitePixels = 2_000
    let minimumDistinctColorBuckets = 3
    let minimumDarkRightmostX = 360
    let minimumWideDarkColumnGaps = 3
}

private struct PixelSample {
    var nonWhitePixels: Int
    var distinctColorBuckets: Int
    var nonWhiteRightmostX: Int
    var darkRightmostX: Int
    var wideDarkColumnGaps: Int
    var rightBandNonWhitePixels: Int
}
