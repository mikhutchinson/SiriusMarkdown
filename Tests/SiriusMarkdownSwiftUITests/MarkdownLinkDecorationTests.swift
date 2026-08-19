import Foundation
import SwiftUI
import Testing
@testable import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
#endif

@Test
func linksReceiveImmediateNativeGlyphWithoutChangingSourceModel() throws {
    let block = try firstLinkDecorationBlock("Read [Example](https://example.com/docs).")
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)

    #expect(block.inlines.map(\.text).joined() == "Read Example.")
    #expect(String(prepared.attributed.characters) == "Read \(automaticLinkDecorationPrefix)Example.")
    #expect(prepared.prepared.runs.contains { $0.presentation.contains(.linkDecoration) })
    let attachment = try #require(prepared.attachments.values.first)
    #expect(prepared.attachments.count == 1)
    #expect(attachment.image.source == markdownLinkSystemSymbolSourcePrefix + "globe")
    #expect(attachment.image.preparedSource == .placeholder(reason: "Native link symbol"))
    #expect(attachment.pointWidth == 16)
    #expect(attachment.isDecorative)
    if case let .systemSymbol(name) = MarkdownAttachmentHostDisplay(record: attachment) {
        #expect(name == "globe")
    } else {
        Issue.record("Expected the automatic link fallback to mount a template system symbol.")
    }
    let layout = try #require(prepared.initialLayoutResult)
    let linePlan = MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout)
    #expect(linePlan.accessibilityLabel == "Read Example.")
    #expect(linePlan.underlinesLinks == false)
    #expect(prepared.allSemanticLinksHaveDecorations)
}

@Test
func allowedNonHTTPSLinksReceiveImmediateNativeGlyphs() throws {
    let block = try firstLinkDecorationBlock(
        "[Relative](/docs), [scheme-less](example.com/profile), and [email](mailto:hello@example.com)."
    )
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let layout = try #require(prepared.initialLayoutResult)

    #expect(
        String(prepared.attributed.characters) ==
            "\(automaticLinkDecorationPrefix)Relative, \(automaticLinkDecorationPrefix)scheme-less, and \(automaticLinkDecorationPrefix)email."
    )
    #expect(
        prepared.prepared.runs.filter {
            $0.presentation.contains(.linkDecoration) && $0.attachmentMetrics != nil
        }.map(\.destination) == ["/docs", "example.com/profile", "mailto:hello@example.com"]
    )
    #expect(prepared.allSemanticLinksHaveDecorations)
    #expect(MarkdownCoreTextPaintedLinePlan.make(prepared: prepared, layout: layout).underlinesLinks == false)
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
    let website = URL(string: "https://example.com")!
    let block = try firstLinkDecorationBlock(
        "[Website](https://example.com) and [email](mailto:hello@example.com)"
    )
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: SelectiveCachedLinkMetadataResolver(
            destination: website,
            resolution: .metadata(
                MarkdownLinkMetadata(
                    destination: website,
                    decoration: .glyph("◆")
                )
            )
        ),
        linkDecoration: MarkdownLinkDecorationConfiguration(fallbackGlyph: "")
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let layout = try #require(prepared.initialLayoutResult)

    #expect(String(prepared.attributed.characters) == "◆\u{00A0}Website and email")
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
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: resolver,
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let block = try firstLinkDecorationBlock("[Example](https://example.com)")
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let afterFirst = recorder.snapshot()
    _ = configuration.prepare(block: block)
    let afterCached = recorder.snapshot()
    let attachment = try #require(prepared.attachments.values.first)
    let decorationRun = try #require(prepared.prepared.runs.first(where: {
        $0.presentation.contains(MarkdownInlinePresentation.linkDecoration) && $0.attachmentMetrics != nil
    }))
    let largerConfiguration = MarkdownRendererConfiguration(
        linkMetadataResolver: resolver,
        linkDecoration: MarkdownLinkDecorationConfiguration(iconPointSize: 22),
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    let largerPrepared = try #require(largerConfiguration.prepare(block: block).inlineLayout)
    let largerAttachment = try #require(largerPrepared.attachments.values.first)
    let afterSizeChange = recorder.snapshot()

    #expect(prepared.attachments.count == 1)
    #expect(attachment.pointWidth == 16)
    #expect(attachment.pointHeight == 16)
    #expect(attachment.ascent + attachment.descent == 16)
    #expect(attachment.isDecorative)
    #expect(attachment.image.preparedSource == .data(onePixelLinkDecorationPNG, mimeType: "image/png"))
    #expect(decorationRun.destination == "https://example.com")
    #expect(decorationRun.attachmentMetrics?.id == attachment.id)
    #expect(afterCached.prepareCount == afterFirst.prepareCount)
    #expect(afterCached.cacheHitCount == afterFirst.cacheHitCount + 1)
    #expect(largerAttachment.pointWidth == 22)
    #expect(largerAttachment.pointHeight == 22)
    #expect(largerAttachment.ascent + largerAttachment.descent == 22)
    #expect(afterSizeChange.prepareCount == afterFirst.prepareCount + 1)
}

@Test
func automaticLinkDecorationSizeTracksCompactTextMetrics() throws {
    let block = try firstLinkDecorationBlock("[Example](https://example.com)")
    let theme = MarkdownTheme(
        paragraphFont: .system(size: 14),
        paragraphFontSize: 14,
        paragraphLineHeight: 17
    )
    let configuration = MarkdownRendererConfiguration(
        theme: theme,
        linkMetadataResolver: nil
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let attachment = try #require(prepared.attachments.values.first)

    #expect(attachment.pointWidth == 14)
    #expect(attachment.pointHeight == 14)
    #expect(attachment.ascent + attachment.descent == 14)
}

@Test
func coreTextPlanCacheRejectsDifferentPreparedContentWithEqualGeometry() throws {
    let firstBlock = try firstLinkDecorationBlock("[Same](https://one.example)")
    let secondBlock = try firstLinkDecorationBlock("[Same](https://two.example)")
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: nil,
        linkDecoration: .disabled
    )
    let first = try #require(configuration.prepare(block: firstBlock).inlineLayout)
    let second = try #require(configuration.prepare(block: secondBlock).inlineLayout)
    let firstLayout = try #require(first.initialLayoutResult)
    let secondLayout = try #require(second.initialLayoutResult)
    let key = CTPlanCacheKey(
        preparedFingerprint: first.cacheFingerprint,
        preparedNaturalWidth: first.measured.naturalWidth,
        layout: firstLayout
    )

    #expect(first.measured.naturalWidth == second.measured.naturalWidth)
    #expect(firstLayout == secondLayout)
    #expect(first.cacheFingerprint != second.cacheFingerprint)
    #expect(
        key.matches(
            preparedFingerprint: second.cacheFingerprint,
            naturalWidth: second.measured.naturalWidth,
            layout: secondLayout
        ) == false
    )
}

@Test
func automaticFallbackAndFaviconHaveDistinctPresentationFingerprintsAtEqualGeometry() throws {
    let destination = URL(string: "https://example.com/")!
    let icon = MarkdownLinkIcon(
        sourceURL: URL(string: "https://example.com/favicon.png")!,
        data: onePixelLinkDecorationPNG,
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1
    )
    let block = try firstLinkDecorationBlock("[Example](https://example.com/)")
    let fallback = try #require(
        MarkdownRendererConfiguration(linkMetadataResolver: nil)
            .prepare(block: block).inlineLayout
    )
    let resolved = try #require(
        MarkdownRendererConfiguration(linkMetadataResolver: CachedLinkMetadataResolver(
            resolution: .metadata(MarkdownLinkMetadata(
                destination: destination,
                decoration: .favicon(icon)
            ))
        )).prepare(block: block).inlineLayout
    )

    #expect(fallback.measured.naturalWidth == resolved.measured.naturalWidth)
    #expect(fallback.initialLayoutResult == resolved.initialLayoutResult)
    #expect(fallback.cacheFingerprint != resolved.cacheFingerprint)
}

@Test
func linkDecorationKeepsTheFirstLabelTokenOnItsLine() throws {
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
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: resolver,
        linkDecoration: MarkdownLinkDecorationConfiguration(iconPointSize: 14)
    )
    let block = try firstLinkDecorationBlock(
        "A deliberately long recommendation prefix [Consensus guidance](https://example.com/)"
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let decorationStart = try #require(
        prepared.measured.segments.firstIndex {
            $0.segment.presentation.contains(.linkDecoration)
        }
    )
    let labelStart = try #require(
        prepared.measured.segments[decorationStart...].firstIndex {
            !$0.segment.presentation.contains(.linkDecoration) && !$0.segment.isBreakOpportunity
        }
    )
    let decorationWidth = prepared.measured.segments[decorationStart..<labelStart]
        .reduce(0) { $0 + $1.width }
    let labelWidth = prepared.measured.segments[labelStart].width
    let prefixWidth = prepared.measured.segments[..<decorationStart]
        .reduce(0) { $0 + $1.width }
    let containerWidth = max(
        decorationWidth + labelWidth + 0.5,
        prefixWidth + decorationWidth + 0.5
    )
    let layout = InlineRunsView.lineLayout(
        for: prepared,
        containerWidth: containerWidth
    )
    let decorationByte = prepared.measured.segments[decorationStart].segment.byteRange.lowerBound
    let labelRange = prepared.measured.segments[labelStart].segment.byteRange
    let decoratedLine = try #require(
        layout.lines.first { $0.byteRange.contains(decorationByte) }
    )

    #expect(containerWidth < prefixWidth + decorationWidth + labelWidth)
    #expect(decoratedLine.byteRange.upperBound >= labelRange.upperBound)
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
    #expect(String(html.attributed.characters) == "\(automaticLinkDecorationPrefix)Example")
}

@Test
func relativeMarkdownAndHTMLAnchorsUseTheSameFallbackDecoration() throws {
    let markdownBlock = try firstLinkDecorationBlock("[Documentation](/docs)")
    let htmlOuter = try firstLinkDecorationBlock("<p><a href=\"/docs\">Documentation</a></p>")
    let htmlBlock = try #require(htmlOuter.richContent?.blocks.first)
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)

    let markdown = try #require(configuration.prepare(block: markdownBlock).inlineLayout)
    let html = try #require(configuration.prepare(block: htmlBlock).inlineLayout)
    #expect(String(markdown.attributed.characters) == String(html.attributed.characters))
    #expect(String(html.attributed.characters) == "\(automaticLinkDecorationPrefix)Documentation")
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

@Test
@MainActor
func renderSessionDoesNotResolveRemoteMetadataForNonHTTPSFallbackLinks() async throws {
    let resolver = DelayedLinkMetadataResolver(resolution: .unavailable)
    let configuration = MarkdownRendererConfiguration(linkMetadataResolver: resolver)
    let session = MarkdownRenderSession(configuration: configuration)

    session.append("[Relative](/docs) and [email](mailto:hello@example.com)")
    session.finish()
    await session.waitUntilIdle()
    await session.waitUntilLinkMetadataIdle()

    let block = try #require(session.snapshot.blocks.first)
    let inline = try #require(session.preparedSnapshot.preparedContentByBlockID[block.id]?.inlineLayout)
    #expect(
        String(inline.attributed.characters) ==
            "\(automaticLinkDecorationPrefix)Relative and \(automaticLinkDecorationPrefix)email"
    )
    #expect(resolver.resolveCount == 0)
}

@Test
@MainActor
func customDestinationScopedResolverVisitsEveryURLOnTheSameOrigin() async {
    let first = URL(string: "https://example.com/first")!
    let second = URL(string: "https://example.com/second")!
    let resolver = DestinationScopedLinkMetadataResolver()
    let session = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(
        linkMetadataResolver: resolver
    ))

    session.append("[First](\(first.absoluteString)) [Second](\(second.absoluteString))")
    session.finish()
    await session.waitUntilLinkMetadataIdle()

    #expect(resolver.resolvedDestinations == Set([first, second]))
}

@Test
@MainActor
func renderSessionRetriesMetadataAfterResolverCacheIsCleared() async {
    let destination = URL(string: "https://retry.example/first")!
    let resolver = RetryableLinkMetadataResolver()
    let session = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(
        linkMetadataResolver: resolver
    ))

    session.append("[First](\(destination.absoluteString))")
    await session.waitUntilLinkMetadataIdle()
    #expect(resolver.resolveCount == 1)

    resolver.clearNegativeCacheAndAllowSuccess()
    session.append(" trailing text")
    session.finish()
    await session.waitUntilLinkMetadataIdle()

    #expect(resolver.resolveCount == 2)
}

@Test
@MainActor
func metadataRefreshDiffInvalidatesOnlyBlocksContainingChangedLinks() async throws {
    let resolver = SlowLinkMetadataResolver(
        delay: .milliseconds(350),
        resolution: .metadata(MarkdownLinkMetadata(
            destination: URL(string: "https://diff.example/page")!,
            decoration: .glyph("!")
        ))
    )
    let session = MarkdownRenderSession(configuration: MarkdownRendererConfiguration(
        linkMetadataResolver: resolver,
        linkDecoration: MarkdownLinkDecorationConfiguration(fallbackGlyph: "~")
    ))

    session.append("[Linked](https://diff.example/page)\n\nPlain unaffected paragraph.\n")
    session.finish()
    await session.waitUntilIdle()
    let linkedBlock = try #require(session.snapshot.blocks.first { $0.inlines.contains { $0.destination != nil } })
    let plainBlock = try #require(session.snapshot.blocks.first { $0.text.contains("unaffected") })

    await session.waitUntilLinkMetadataIdle()

    let linkedID = "block:\(linkedBlock.id.rawValue)"
    let plainID = "block:\(plainBlock.id.rawValue)"
    #expect(session.snapshotDiff.changedItemIDs == [linkedID])
    #expect(!session.snapshotDiff.contains(plainID))
    #expect(session.snapshotDiff.newItemIDs.isEmpty)
}

@Test
func multilineSemanticLinkReceivesOneDecoration() throws {
    let block = try firstLinkDecorationBlock(
        "[first line\nsecond line](https://example.com/page)"
    )
    let configuration = MarkdownRendererConfiguration(
        linkMetadataResolver: nil,
        linkDecoration: MarkdownLinkDecorationConfiguration(fallbackGlyph: "~")
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)

    #expect(
        prepared.prepared.runs.filter {
            $0.presentation.contains(.linkDecoration)
        }.count == 1
    )
}

#if canImport(AppKit)
@Test
@MainActor
func mountedFixedWidthTableRefreshesAllLinkTextWhenFaviconArrives() async throws {
    let destination = URL(string: "https://example.com/")!
    let icon = MarkdownLinkIcon(
        sourceURL: URL(string: "https://example.com/favicon.png")!,
        data: onePixelLinkDecorationPNG,
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1
    )
    let resolver = SlowLinkMetadataResolver(
        delay: .milliseconds(500),
        resolution: .metadata(
            MarkdownLinkMetadata(destination: destination, decoration: .favicon(icon))
        )
    )
    let configuration = MarkdownRendererConfiguration(
        theme: .compactChat,
        inlineRenderingMode: .coreTextPaintedLines,
        nativeTextSelection: .disabled,
        documentSelection: .disabled,
        linkMetadataResolver: resolver
    )
    let session = MarkdownRenderSession(configuration: configuration)
    session.append(mountedLinkDecorationTableMarkdown)
    session.finish()
    await session.waitUntilIdle()

    let root = MountedLinkDecorationSessionView(session: session)
        .frame(width: 980, height: 720, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
    let window = mountedLinkDecorationWindow(hostingView)
    defer {
        window.orderOut(nil)
        window.contentView = nil
    }
    pumpMountedLinkDecorationLayout(hostingView, iterations: 5)

    let fallbackHost = try #require(mountedLinkDecorationAttachmentHosts(in: hostingView).first)
    let fallbackFrameSize = fallbackHost.frame.size
    if case let .systemSymbol(name) = MarkdownAttachmentHostDisplay(record: fallbackHost.record) {
        #expect(name == "globe")
    } else {
        Issue.record("Expected the mounted table to start with the automatic globe symbol.")
    }

    await session.waitUntilLinkMetadataIdle()
    pumpMountedLinkDecorationLayout(hostingView, iterations: 10)

    let resolvedSurface = try #require(
        mountedLinkDecorationPaintedViews(in: hostingView).first {
            $0.plan.accessibilityLabel.contains("Offer definitive duct-decompressing surgery")
        }
    )
    let renderedText = resolvedSurface.plan.lines.map(\.text).joined(separator: " ")
    let resolvedHost = try #require(mountedLinkDecorationAttachmentHosts(in: hostingView).first)

    #expect(renderedText.contains("Consensus"))
    #expect(renderedText.contains("guidance"))
    #expect(resolvedSurface.plan.lines.allSatisfy { $0.text != " " })
    #expect(resolvedSurface.plan.attachmentGaps.count == 1)
    #expect(resolvedSurface.attachmentHostsByID.count == 1)
    #expect(resolvedHost.frame.size == fallbackFrameSize)
    if case let .data(data) = MarkdownAttachmentHostDisplay(record: resolvedHost.record) {
        #expect(data == onePixelLinkDecorationPNG)
    } else {
        Issue.record("Expected the mounted table globe to refresh to favicon bytes.")
    }
}

@Test
@MainActor
func automaticSystemLinkFallbackMountsInSelectionModesAndColorSchemes() throws {
    var stream = MarkdownStream()
    stream.append("Read [PubMed guidance](https://pubmed.ncbi.nlm.nih.gov/).")
    stream.finish()
    let snapshot = stream.snapshot()

    for nativeSelection in [MarkdownNativeTextSelection.enabled, .disabled] {
        for colorScheme in [ColorScheme.light, .dark] {
            let theme = MarkdownTheme(
                paragraphFont: .system(size: 14),
                paragraphFontSize: 14,
                paragraphLineHeight: 17
            )
            let configuration = MarkdownRendererConfiguration(
                theme: theme,
                inlineRenderingMode: .coreTextPaintedLines,
                nativeTextSelection: nativeSelection,
                documentSelection: .disabled,
                linkMetadataResolver: nil
            )
            let prepared = configuration.prepare(snapshot: snapshot)
            let root = AnyView(
                MarkdownDocumentView(
                    preparedSnapshot: prepared,
                    configuration: configuration
                )
                .environment(\.colorScheme, colorScheme)
                .frame(width: 360, height: 140, alignment: .topLeading)
            )
            let hostingView = NSHostingView(rootView: root)
            hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 140)
            let window = mountedLinkDecorationWindow(hostingView)
            pumpMountedLinkDecorationLayout(hostingView, iterations: 8)
            let symbolHost = try #require(
                mountedLinkDecorationAttachmentHosts(in: hostingView).first
            )
            let imageView = try #require(symbolHost.subviews.compactMap { $0 as? NSImageView }.first)

            #expect(imageView.image != nil)
            #expect(symbolHost.frame.width == 14)
            #expect(symbolHost.frame.height == 14)
            #expect(symbolHost.isAccessibilityElement() == false)

            window.orderOut(nil)
            window.contentView = nil
        }
    }
}

@Test
@MainActor
func automaticSystemFallbackSwapsToUntintedFaviconInTheSameHost() throws {
    let block = try firstLinkDecorationBlock("[Example](https://example.com)")
    let theme = MarkdownTheme(
        paragraphFont: .system(size: 14),
        paragraphFontSize: 14,
        paragraphLineHeight: 17
    )
    let configuration = MarkdownRendererConfiguration(
        theme: theme,
        linkMetadataResolver: nil
    )
    let prepared = try #require(configuration.prepare(block: block).inlineLayout)
    let fallback = try #require(prepared.attachments.values.first)
    let host = MarkdownAttachmentHostNSView(
        frame: NSRect(x: 0, y: 0, width: fallback.pointWidth, height: fallback.pointHeight)
    )
    host.record = fallback
    let fallbackImageView = try #require(host.subviews.compactMap { $0 as? NSImageView }.first)
    #expect(fallbackImageView.contentTintColor == .linkColor)

    var resolved = fallback
    resolved.image.source = "resolved-favicon"
    resolved.image.preparedSource = .data(onePixelLinkDecorationPNG, mimeType: "image/png")
    host.record = resolved
    let resolvedImageView = try #require(host.subviews.compactMap { $0 as? NSImageView }.first)

    #expect(resolvedImageView === fallbackImageView)
    #expect(resolvedImageView.contentTintColor == nil)
    #expect(resolvedImageView.image?.isTemplate == false)
}
#endif

private struct CachedLinkMetadataResolver: MarkdownLinkMetadataResolver {
    var resolution: MarkdownLinkMetadataResolution

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        resolution
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        resolution
    }
}

private struct SelectiveCachedLinkMetadataResolver: MarkdownLinkMetadataResolver {
    var destination: URL
    var resolution: MarkdownLinkMetadataResolution

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        destination == self.destination ? resolution : nil
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        destination == self.destination ? resolution : .unavailable
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

private final class SlowLinkMetadataResolver: MarkdownLinkMetadataResolver, @unchecked Sendable {
    private let lock = NSLock()
    private let delay: Duration
    private let resolution: MarkdownLinkMetadataResolution
    private var cached: MarkdownLinkMetadataResolution?

    init(delay: Duration, resolution: MarkdownLinkMetadataResolution) {
        self.delay = delay
        self.resolution = resolution
    }

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        lock.withLock { cached }
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        try? await Task.sleep(for: delay)
        return lock.withLock {
            cached = resolution
            return resolution
        }
    }
}

private final class DestinationScopedLinkMetadataResolver: MarkdownLinkMetadataResolver, @unchecked Sendable {
    private let lock = NSLock()
    private var resolutions: [URL: MarkdownLinkMetadataResolution] = [:]

    var resolvedDestinations: Set<URL> {
        lock.withLock { Set(resolutions.keys) }
    }

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        lock.withLock { resolutions[destination] }
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        let resolution = MarkdownLinkMetadataResolution.metadata(MarkdownLinkMetadata(
            destination: destination,
            title: destination.lastPathComponent,
            decoration: .glyph("#")
        ))
        lock.withLock { resolutions[destination] = resolution }
        return resolution
    }
}

private final class RetryableLinkMetadataResolver: MarkdownLinkMetadataResolver, @unchecked Sendable {
    private let lock = NSLock()
    private var cached: MarkdownLinkMetadataResolution?
    private var shouldSucceed = false
    private var count = 0

    var resolveCount: Int { lock.withLock { count } }

    func clearNegativeCacheAndAllowSuccess() {
        lock.withLock {
            cached = nil
            shouldSucceed = true
        }
    }

    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        lock.withLock { cached }
    }

    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        lock.withLock {
            count += 1
            let resolution: MarkdownLinkMetadataResolution = shouldSucceed
                ? .metadata(MarkdownLinkMetadata(destination: destination, decoration: .glyph("!")))
                : .unavailable
            cached = resolution
            return resolution
        }
    }
}

private let onePixelLinkDecorationPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!

private let automaticLinkDecorationPrefix = markdownAttachmentPlaceholderCharacter + "\u{00A0}"

private func firstLinkDecorationBlock(_ markdown: String) throws -> MarkdownBlock {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return try #require(stream.snapshot().blocks.first)
}

#if canImport(AppKit)
@MainActor
private struct MountedLinkDecorationSessionView: View {
    @ObservedObject var session: MarkdownRenderSession

    var body: some View {
        MarkdownDocumentView(
            preparedSnapshot: session.preparedSnapshot,
            configuration: session.configuration
        )
    }
}

private let mountedLinkDecorationTableMarkdown = """
| Time | Likely recommendation | Key decision-driving facts | The attending's question |
| --- | --- | --- | --- |
| 7:05 — P2 | Offer definitive duct-decompressing surgery after multidisciplinary review—Puestow if uniformly dilated duct; Frey if head-dominant disease. Advanced endoscopic/ESWL attempt is an alternative. TP/TPIAT is not the only operation. [Consensus guidance](https://example.com/) | Very young, disabling recurrent attacks, obstructing head stone, failed ERCP. | What is the duct diameter and is there an inflammatory head mass? |
"""

@MainActor
private func mountedLinkDecorationWindow<V: View>(_ hostingView: NSHostingView<V>) -> NSWindow {
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    return window
}

@MainActor
private func pumpMountedLinkDecorationLayout<V: View>(
    _ hostingView: NSHostingView<V>,
    iterations: Int
) {
    for _ in 0..<iterations {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func mountedLinkDecorationPaintedViews(in view: NSView) -> [MarkdownCoreTextPaintedNSView] {
    var result = (view as? MarkdownCoreTextPaintedNSView).map { [$0] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: mountedLinkDecorationPaintedViews(in: subview))
    }
    return result
}

@MainActor
private func mountedLinkDecorationAttachmentHosts(in view: NSView) -> [MarkdownAttachmentHostNSView] {
    var result = (view as? MarkdownAttachmentHostNSView).map { [$0] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: mountedLinkDecorationAttachmentHosts(in: subview))
    }
    return result
}
#endif
