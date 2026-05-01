import AppKit
import Darwin
import SiriusMarkdown
import SwiftUI

@main
struct SiriusMarkdownRenderProbe {
    @MainActor
    static func main() {
        let result = renderRepresentativeDocument()
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

        print("MarkdownDocumentView render probe: \(result.nonWhitePixels) non-white pixels, \(result.distinctColorBuckets) color buckets")
    }

    @MainActor
    private static func renderRepresentativeDocument() -> RenderResult {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var stream = MarkdownStream()
        stream.append(
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
            """
        )
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
        writeBitmapIfRequested(bitmap)

        let sample = sampleRenderedPixels(bitmap)
        return RenderResult(
            nonWhitePixels: sample.nonWhitePixels,
            distinctColorBuckets: sample.distinctColorBuckets
        )
    }

    private static func sampleRenderedPixels(_ bitmap: NSBitmapImageRep) -> PixelSample {
        var nonWhitePixels = 0
        var colorBuckets = Set<Int>()

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
                }
            }
        }

        return PixelSample(
            nonWhitePixels: nonWhitePixels,
            distinctColorBuckets: colorBuckets.count
        )
    }

    private static func writeBitmapIfRequested(_ bitmap: NSBitmapImageRep) {
        guard
            let outputPath = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_RENDER_PROBE_OUTPUT"],
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

    let minimumNonWhitePixels = 2_000
    let minimumDistinctColorBuckets = 3
}

private struct PixelSample {
    var nonWhitePixels: Int
    var distinctColorBuckets: Int
}
