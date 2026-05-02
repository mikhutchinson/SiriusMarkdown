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
        let multilingualResult = renderMultilingualNativeDocument()
        let attributeResult = renderInlineAttributeCrossingProbe()
        let overflowResult = renderOverflowContainmentProbe()
        let breakResult = renderBreakAndLongWordProbe()
        let widthResult = renderInlineWidthProbe()
        let nativeSpacingResult = renderNativeInlineSpacingProbe()
        let containmentResult = renderPreparedNativeContainmentProbe()
        assertRenderable("MarkdownDocumentView", result)
        assertRenderable("prepared native MarkdownDocumentView", nativeResult)
        assertRenderable("compact chat prepared native transcript", chatResult, minimumNonWhitePixels: 1_400)
        assertRenderable("multilingual prepared native document", multilingualResult, minimumNonWhitePixels: 1_200)
        assertRenderable("inline attribute crossing prepared native document", attributeResult)
        assertRenderable("code and table overflow prepared native document", overflowResult)
        assertRenderable("hard-break and long-word prepared native document", breakResult, minimumNonWhitePixels: 1_200)
        assertRenderable("prepared native containment document", containmentResult, minimumNonWhitePixels: 1_400)

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

        if containmentResult.darkRightmostX > containmentResult.maximumDarkRightmostX {
            fputs(
                "error: prepared native containment probe leaked dark text to x=\(containmentResult.darkRightmostX); expected no normal inline text beyond x=\(containmentResult.maximumDarkRightmostX).\n",
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

        print("MarkdownDocumentView render probe: \(result.nonWhitePixels) non-white pixels, \(result.distinctColorBuckets) color buckets")
        print("Prepared native document render probe: \(nativeResult.nonWhitePixels) non-white pixels, \(nativeResult.distinctColorBuckets) color buckets")
        print("Compact chat render probe: \(chatResult.nonWhitePixels) non-white pixels, \(chatResult.distinctColorBuckets) color buckets")
        print("Multilingual render probe: \(multilingualResult.nonWhitePixels) non-white pixels, \(multilingualResult.distinctColorBuckets) color buckets")
        print("Inline attribute crossing probe: \(attributeResult.nonWhitePixels) non-white pixels, \(attributeResult.distinctColorBuckets) color buckets")
        print("Overflow containment probe: \(overflowResult.nonWhitePixels) non-white pixels, \(overflowResult.distinctColorBuckets) color buckets")
        print("Break and long-word probe: \(breakResult.nonWhitePixels) non-white pixels, \(breakResult.distinctColorBuckets) color buckets")
        print("Prepared inline width probe: dark text reached x=\(widthResult.darkRightmostX)")
        print("Native inline spacing probe: \(nativeSpacingResult.wideDarkColumnGaps) wide word gaps")
        print("Prepared native containment probe: dark text reached x=\(containmentResult.darkRightmostX), fitting width \(containmentResult.fittingWidth)")
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
        renderDocument(
            markdown:
                """
                | Region | Very Wide Evidence |
                | - | - |
                | Code | `abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz` |

                ```swift
                let veryLongIdentifierName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
                ```
                """,
            configuration: .document,
            size: NSSize(width: 560, height: 300),
            outputPath: nil
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
        outputPath: String?
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
        window.contentView = hostingView
        window.orderFrontRegardless()

        for _ in 0..<4 {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            fputs("error: could not allocate render bitmap\n", stderr)
            exit(EXIT_FAILURE)
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        writeBitmapIfRequested(bitmap, outputPath: outputPath)

        let pixelScale = Double(bitmap.pixelsWide) / Double(size.width)
        let sample = sampleRenderedPixels(bitmap, pixelScale: pixelScale)
        return RenderResult(
            nonWhitePixels: sample.nonWhitePixels,
            distinctColorBuckets: sample.distinctColorBuckets,
            darkRightmostX: sample.darkRightmostX,
            wideDarkColumnGaps: sample.wideDarkColumnGaps,
            pixelScale: pixelScale
        )
    }

    private static func sampleRenderedPixels(_ bitmap: NSBitmapImageRep, pixelScale: Double) -> PixelSample {
        var nonWhitePixels = 0
        var colorBuckets = Set<Int>()
        var darkRightmostX = 0
        var darkColumnCounts = Array(repeating: 0, count: bitmap.pixelsWide)

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
            darkRightmostX: darkRightmostX,
            wideDarkColumnGaps: wideBlankRunCount(darkColumns, minimumWidth: minimumGapWidth)
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

private struct RenderResult {
    var nonWhitePixels: Int
    var distinctColorBuckets: Int
    var darkRightmostX: Int
    var wideDarkColumnGaps: Int
    var pixelScale = 1.0
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
    var darkRightmostX: Int
    var wideDarkColumnGaps: Int
}
