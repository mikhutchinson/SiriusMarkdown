import Foundation
import Testing
@testable import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Test
func linksReceiveImmediateNativeGlyphWithoutChangingSourceModel() throws {
    let block = try firstLinkDecorationBlock("Read [Example](https://example.com/docs).")
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)

    #expect(block.inlines.map(\.text).joined() == "Read Example.")
    #expect(String(prepared.attributed.characters) == "Read 🌐\u{00A0}Example.")
    #expect(prepared.prepared.runs.contains { $0.presentation.contains(.linkDecoration) })
    #expect(prepared.attachments.isEmpty)
    let layout = try #require(prepared.initialLayoutResult)
    let linePlan = MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout)
    #expect(linePlan.accessibilityLabel == "Read Example.")
    #expect(linePlan.underlinesLinks == false)
    #expect(prepared.allSemanticLinksHaveDecorations)
}

@Test
func linkDecorationsCanBeDisabledWithoutChangingLinkBehavior() throws {
    let block = try firstLinkDecorationBlock("[Example](https://example.com)")
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: nil,
        linkDecoration: .disabled
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)

    #expect(String(prepared.attributed.characters) == "Example")
    #expect(prepared.prepared.runs.contains { $0.presentation.contains(.linkDecoration) } == false)
    #expect(prepared.attributed.runs.first?.link == URL(string: "https://example.com"))
    let layout = try #require(prepared.initialLayoutResult)
    #expect(MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout).underlinesLinks)
    #expect(prepared.allSemanticLinksHaveDecorations == false)
}

@Test
func mixedDecoratedAndUndecoratedLinksRetainUnderlines() throws {
    let block = try firstLinkDecorationBlock(
        "[Website](https://example.com) and [email](mailto:hello@example.com)"
    )
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let layout = try #require(prepared.initialLayoutResult)

    #expect(prepared.allSemanticLinksHaveDecorations == false)
    #expect(MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout).underlinesLinks)
}

@Test
func cachedFaviconsBecomeBoundedClickableNativeAttachments() throws {
    let destination = URL(string: "https://example.com/")!
    let icon = MarkdownLinkIcon(
        sourceURL: URL(string: "https://example.com/favicon.png")!,
        data: onePixelLinkDecorationPNG,
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1
    )
    let resolver = CachedLinkMetadataResolver(
        resolution: .metadata(
            MarkdownLinkMetadata(destination: destination, decoration: .favicon(icon))
        )
    )
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: resolver)
    let block = try firstLinkDecorationBlock("[Example](https://example.com)")
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let attachment = try #require(prepared.attachments.values.first)
    let decorationRun = try #require(prepared.prepared.runs.first(where: {
        $0.presentation.contains(MarkdownInlinePresentation.linkDecoration) && $0.attachmentMetrics != nil
    }))

    #expect(prepared.attachments.count == 1)
    #expect(attachment.pointWidth == 18)
    #expect(attachment.pointHeight == 18)
    #expect(attachment.isDecorative)
    #expect(attachment.image.preparedSource == .data(onePixelLinkDecorationPNG, mimeType: "image/png"))
    #expect(decorationRun.destination == "https://example.com")
    #expect(decorationRun.attachmentMetrics?.id == attachment.id)
}

@Test
func markdownAndHTMLAnchorsUseTheSameDecorationPipeline() throws {
    let markdownBlock = try firstLinkDecorationBlock("[Example](https://example.com)")
    let htmlOuter = try firstLinkDecorationBlock("<p><a href=\"https://example.com\">Example</a></p>")
    let htmlBlock = try #require(htmlOuter.richContent?.blocks.first)
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)

    let markdown = try #require(configuration.prepare(block: markdownBlock).inlineLayout)
    let html = try #require(configuration.prepare(block: htmlBlock).inlineLayout)
    #expect(String(markdown.attributed.characters) == String(html.attributed.characters))
    #expect(String(html.attributed.characters) == "🌐\u{00A0}Example")
}

@Test
@MainActor
func renderSessionRefreshesPreparedLinksWhenFaviconArrives() async throws {
    let destination = URL(string: "https://example.com/")!
    let icon = MarkdownLinkIcon(
        sourceURL: URL(string: "https://example.com/favicon.png")!,
        data: onePixelLinkDecorationPNG,
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1
    )
    let resolver = DelayedLinkMetadataResolver(
        resolution: .metadata(
            MarkdownLinkMetadata(destination: destination, decoration: .favicon(icon))
        )
    )
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: resolver)
    let session = MarkdownRenderSession(configuration: configuration)

    session.append("[Example](https://example.com)")
    session.finish()
    await session.waitUntilIdle()
    await session.waitUntilLinkMetadataIdle()

    let block = try #require(session.snapshot.blocks.first)
    let inline = try #require(session.preparedSnapshot.preparedContentByBlockID[block.id]?.inlineLayout)
    #expect(inline.attachments.count == 1)
    #expect(resolver.resolveCount == 1)
}

private struct CachedLinkMetadataResolver: MarkdownLinkMetadataResolver {
    var resolution: MarkdownLinkMetadataResolution

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        resolution
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        resolution
    }
}

private final class DelayedLinkMetadataResolver: MarkdownLinkMetadataResolver, @unchecked Sendable {
    private let lock = NSLock()
    private let resolution: MarkdownLinkMetadataResolution
    private var cached: MarkdownLinkMetadataResolution?
    private var count = 0

    init(resolution: MarkdownLinkMetadataResolution) {
        self.resolution = resolution
    }

    var resolveCount: Int {
        lock.withLock { count }
    }

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        lock.withLock { cached }
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        try? await Task.sleep(for: .milliseconds(20))
        return lock.withLock {
            count += 1
            cached = resolution
            return resolution
        }
    }
}

private let onePixelLinkDecorationPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!

private func firstLinkDecorationBlock(_ markdown: String) throws -> MarkdownBlock {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return try #require(stream.snapshot().blocks.first)
}
