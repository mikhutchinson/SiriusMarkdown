import AppKit
import Darwin
import SiriusMarkdown
import SwiftUI

@main
struct SiriusMarkdownRenderProbe {
    @MainActor
    static func main() {
        let result = renderRepresentativeDocument()
        let widthResult = renderInlineWidthProbe()
        if result.nonWhitePixels < result.minimumNonWhitePixels {
            fputs(
                "error: MarkdownDocumentView rendered only \(result.nonWhitePixels) non-white pixels; expected at least \(result.minimumNonWhitePixels)\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if result.distinctColorBuckets < result.minimumDistinctColorBuckets {
            fputs(
                "error: MarkdownDocumentView rendered only \(result.distinctColorBuckets) color buckets; expected at least \(result.minimumDistinctColorBuckets)\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        if widthResult.darkRightmostX < widthResult.minimumDarkRightmostX {
            fputs(
                "error: prepared inline text only reached x=\(widthResult.darkRightmostX); expected at least \(widthResult.minimumDarkRightmostX). This usually means the view measured its wrapped intrinsic width instead of the offered document width.\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }

        print("MarkdownDocumentView render probe: \(result.nonWhitePixels) non-white pixels, \(result.distinctColorBuckets) color buckets")
        print("Prepared inline width probe: dark text reached x=\(widthResult.darkRightmostX)")
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
    private static func renderDocument(markdown: String, outputPath: String?) -> RenderResult {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()

        let configuration = MarkdownRendererConfiguration.document
        let prepared = configuration.prepare(snapshot: stream.snapshot())
        let size = NSSize(width: 640, height: 520)
        let root = MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            .frame(width: size.width, height: size.height)
            .background(Color.white)

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

        let sample = sampleRenderedPixels(bitmap)
        return RenderResult(
            nonWhitePixels: sample.nonWhitePixels,
            distinctColorBuckets: sample.distinctColorBuckets,
            darkRightmostX: sample.darkRightmostX
        )
    }

    private static func sampleRenderedPixels(_ bitmap: NSBitmapImageRep) -> PixelSample {
        var nonWhitePixels = 0
        var colorBuckets = Set<Int>()
        var darkRightmostX = 0

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
                    }
                }
            }
        }

        return PixelSample(
            nonWhitePixels: nonWhitePixels,
            distinctColorBuckets: colorBuckets.count,
            darkRightmostX: darkRightmostX
        )
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

    let minimumNonWhitePixels = 2_000
    let minimumDistinctColorBuckets = 3
    let minimumDarkRightmostX = 360
}

private struct PixelSample {
    var nonWhitePixels: Int
    var distinctColorBuckets: Int
    var darkRightmostX: Int
}
