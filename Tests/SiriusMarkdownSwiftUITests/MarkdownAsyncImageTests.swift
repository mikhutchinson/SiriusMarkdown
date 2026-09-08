import Foundation
import Testing
import SiriusMarkdownCore
#if os(macOS)
import AppKit
import SwiftUI
#endif
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownAsyncImageTests {
    @Test func imageCompletionRefreshesOnlyOwnersAndPreservesSourceIdentity() async throws {
        #if os(macOS)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<80 { for x in 0..<160 {
            bitmap.setColor(x < 80 ? NSColor(deviceRed: 1, green: 0.2, blue: 0.5, alpha: 1) : NSColor(deviceRed: 0, green: 0.7, blue: 0.7, alpha: 1), atX: x, y: y)
        } }
        let resolver = AsyncImageFixtureResolver(cacheEnabled: false, imageData: try #require(bitmap.representation(using: .png, properties: [:])))
        #else
        let resolver = AsyncImageFixtureResolver(cacheEnabled: false)
        #endif
        let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil, imagePolicy: AsyncImageFixturePolicy(), imageResolver: resolver)
        let session = MarkdownRenderSession(configuration: configuration)
        session.append("Stable paragraph.\n\n![picture](https://example.com/image.png)\n\n<div><img src=\"https://example.com/image.png\"></div>")
        await session.waitUntilIdle()
        #if os(macOS)
        let host = NSHostingView(rootView: AnyView(AsyncImageMountedFixture(session: session, configuration: configuration)))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        defer {
            host.rootView = AnyView(EmptyView())
            host.layoutSubtreeIfNeeded()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        #endif
        let before = session.preparedSnapshot
        let ids = before.snapshot.blocks.map(\.id)
        let parses = session.streamCounters.parseCount
        await session.waitUntilImagesIdle()
        #expect(session.preparedSnapshot.snapshot.blocks.map(\.id) == ids)
        #expect(session.streamCounters.parseCount == parses)
        #expect(resolver.requestCount == 1)
        #if os(macOS)
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
        let rendered = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rendered)
        var coloredPixels = 0
        for y in 0..<rendered.pixelsHigh { for x in 0..<rendered.pixelsWide {
            if let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               color.redComponent > 0.7, color.greenComponent < 0.5, color.blueComponent > 0.15 {
                coloredPixels += 1
            }
        } }
        #expect(coloredPixels > 10, "Completed image bytes must reach the mounted native renderer")
        if let path = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_ASYNC_IMAGE_PROBE_OUTPUT"] {
            try rendered.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        #endif
        let imageBlock = ids[1]
        let images = try #require(session.preparedSnapshot.preparedContentByBlockID[imageBlock]?.inlineLayout?.images)
        #expect(images.contains { if case .data = $0.preparedSource { true } else { false } })
        let htmlBlock = try #require(ids.last)
        let rich = try #require(session.preparedSnapshot.preparedContentByBlockID[htmlBlock]?.richContent)
        #expect(rich.blocks.contains { child in child.preparedContent.inlineLayout?.images.contains { if case .data = $0.preparedSource { true } else { false } } == true })
        #expect(!session.snapshotDiff.changedItemIDs.contains("block:\(ids[0].rawValue)"))
        session.append("\n\nAnother paragraph.")
        session.finish()
        await session.waitUntilImagesIdle()
        #expect(resolver.requestCount == 1)
    }

    @Test func defaultAndDeniedImagesNeverStartAsyncResolution() async {
        let resolver = AsyncImageFixtureResolver()
        let session = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(linkMetadataResolver: nil, imageResolver: resolver))
        session.append("![picture](https://example.com/image.png)\n\n<div><img src=\"https://example.com/html.png\"></div>")
        session.finish()
        await session.waitUntilImagesIdle()
        #expect(resolver.requestCount == 0)
        let remote = RemoteMarkdownImageResolver()
        let denied = await remote.resolveImage(for: "https://127.0.0.1/private.png")
        #expect(denied.cacheIdentity == "unavailable")
        #expect(remote.cachedImageResolution(for: "https://127.0.0.1/private.png")?.cacheIdentity == "unavailable")
    }

    @Test func imageRequestsAreBoundedAndResetDiscardsLateCompletion() async {
        let resolver = AsyncImageFixtureResolver()
        let session = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(linkMetadataResolver: nil, imagePolicy: AsyncImageFixturePolicy(), imageResolver: resolver))
        session.updateImageLoadingViewport(blockIDs: [])
        session.append((0..<12).map { "![image](https://example.com/\($0).png)\n\n" }.joined())
        await session.waitUntilImagesIdle()
        #expect(resolver.requestCount == 0)
        session.updateImageLoadingViewport(blockIDs: Set(session.snapshot.blocks.prefix(4).map(\.id)))
        for _ in 0..<20 where resolver.requestCount == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(resolver.requestCount > 0 && resolver.requestCount <= 4)
        session.reset()
        session.append("Replacement document")
        session.finish()
        await session.waitUntilImagesIdle()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(session.snapshot.blocks.count == 1)
        #expect(session.snapshot.blocks.first?.text == "Replacement document")
        #expect(resolver.maximumConcurrent <= 4)
        let initialCount = resolver.requestCount
        session.reset()
        session.updateImageLoadingViewport(blockIDs: nil)
        session.append((0..<9).map { "![new](https://example.com/new-\($0).png)\n\n" }.joined())
        session.finish()
        await session.waitUntilImagesIdle()
        #expect(resolver.requestCount == initialCount + 9)
        #expect(resolver.maximumConcurrent <= 4)
        var temporary: MarkdownRenderSession? = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(linkMetadataResolver: nil, imagePolicy: AsyncImageFixturePolicy(), imageResolver: resolver))
        temporary?.append("![temporary](https://example.com/temporary.png)")
        await temporary?.waitUntilIdle()
        let cancellations = resolver.cancellationCount
        for _ in 0..<20 where resolver.requestCount == initialCount + 9 { try? await Task.sleep(for: .milliseconds(5)) }
        temporary = nil
        for _ in 0..<20 where resolver.cancellationCount == cancellations { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(resolver.cancellationCount > cancellations)
    }
}

private struct AsyncImageFixturePolicy: MarkdownImagePolicy, MarkdownImagePolicyCacheIdentifying {
    var imagePolicyCacheIdentity: String { "async-fixture-allow" }
    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision { .allow }
}

private final class AsyncImageFixtureResolver: MarkdownAsyncImageResolver, MarkdownImageResolverCacheIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private let cacheEnabled: Bool
    private let imageData: Data
    init(cacheEnabled: Bool = true, imageData: Data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!) {
        self.cacheEnabled = cacheEnabled
        self.imageData = imageData
    }
    private var cache: [String: MarkdownAsyncImageResolution] = [:]
    private var count = 0
    private var active = 0
    private var peak = 0
    private var cancelled = 0
    var cancellationCount: Int { lock.withLock { cancelled } }
    var requestCount: Int { lock.withLock { count } }
    var maximumConcurrent: Int { lock.withLock { peak } }
    var imageResolverCacheIdentity: String { "async-fixture" }
    func cachedImageResolution(for source: String) -> MarkdownAsyncImageResolution? { lock.withLock { cacheEnabled ? cache[source] : nil } }
    func resolveImage(for source: String) async -> MarkdownAsyncImageResolution {
        lock.withLock { count += 1; active += 1; peak = max(peak, active) }
        try? await Task.sleep(for: .milliseconds(100))
        let resolution = MarkdownAsyncImageResolution(preparedSource: .data(imageData, mimeType: "image/png"), cacheIdentity: source + ":loaded")
        let wasCancelled = Task.isCancelled
        lock.withLock { active -= 1; cache[source] = resolution; if wasCancelled { cancelled += 1 } }
        return resolution
    }
    func preparedImage(source: String, altText: String?, sourceRange: MarkdownSourceRange?, policyDecision: MarkdownPolicyDecision) -> MarkdownPreparedImage {
        .init(source: source, altText: altText, sourceRange: sourceRange,
              preparedSource: cachedImageResolution(for: source)?.preparedSource ?? .placeholder(reason: "Loading image"))
    }
}

#if os(macOS)
private struct AsyncImageMountedFixture: View {
    @ObservedObject var session: MarkdownRenderSession
    let configuration: MarkdownRendererConfiguration
    var body: some View {
        MarkdownDocumentView(preparedSnapshot: session.preparedSnapshot, configuration: configuration)
            .preferredColorScheme(.light).background(Color.white)
            .frame(width: 640, height: 300)
    }
}
#endif
