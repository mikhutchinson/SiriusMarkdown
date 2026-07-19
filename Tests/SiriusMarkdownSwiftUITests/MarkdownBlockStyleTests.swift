import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Test helpers

private func firstBlock(_ markdown: String) throws -> MarkdownBlock {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return try #require(stream.snapshot().blocks.first)
}

#if canImport(AppKit)
@MainActor
private func offscreenTestWindow<V: View>(_ hostingView: NSHostingView<V>) -> NSWindow {
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
private func pumpLayout<V: View>(_ hostingView: NSHostingView<V>) {
    for _ in 0..<6 {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func tearDownWindow(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
    for _ in 0..<3 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private func testBitmap<V: View>(
    for view: V,
    width: CGFloat,
    height: CGFloat
) throws -> NSBitmapImageRep {
    let hostingView = NSHostingView(
        rootView: view
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
    )
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)
    let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    return bitmap
}

private func darkPixelVerticalBounds(
    in bitmap: NSBitmapImageRep,
    xRange: Range<Int>
) -> ClosedRange<Int>? {
    var minimumY: Int?
    var maximumY: Int?
    let safeRange = max(0, xRange.lowerBound)..<min(bitmap.pixelsWide, xRange.upperBound)
    for y in 0..<bitmap.pixelsHigh {
        for x in safeRange {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.redComponent < 0.45,
                  color.greenComponent < 0.45,
                  color.blueComponent < 0.45,
                  color.alphaComponent > 0.5
            else {
                continue
            }
            minimumY = min(minimumY ?? y, y)
            maximumY = max(maximumY ?? y, y)
        }
    }
    guard let minimumY, let maximumY else { return nil }
    return minimumY...maximumY
}

private func hasDarkPixel(
    in bitmap: NSBitmapImageRep,
    xRange: Range<Int>,
    yRange: Range<Int>
) -> Bool {
    let safeX = max(0, xRange.lowerBound)..<min(bitmap.pixelsWide, xRange.upperBound)
    let safeY = max(0, yRange.lowerBound)..<min(bitmap.pixelsHigh, yRange.upperBound)
    for y in safeY {
        for x in safeX {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            if color.redComponent < 0.45,
               color.greenComponent < 0.45,
               color.blueComponent < 0.45,
               color.alphaComponent > 0.5 {
                return true
            }
        }
    }
    return false
}

@MainActor
private func renderOffscreen<V: View>(
    _ view: V,
    width: CGFloat = 360,
    height: CGFloat = 180
) {
    let hostingView = NSHostingView(rootView: view.frame(width: width, alignment: .leading))
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)
}
#endif

// MARK: - Spy styles

/// Records which spy style (by `name`) actually had `makeBody` invoked, and
/// with what per-slot metadata — used to assert INV-BS9 merge order and
/// custom-style invocation without a view-inspection library.
@MainActor
private final class StyleInvocationRecorder {
    var invokedNames: [String] = []
    var headingLevels: [Int] = []
    var languageHints: [String?] = []
    var markerWidthReadCount = 0
    var unorderedMarkerIndentationLevels: [Int] = []
}

private struct SpyParagraphStyle: MarkdownParagraphBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyHeadingStyle: MarkdownHeadingBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        recorder.headingLevels.append(configuration.headingLevel)
        return configuration.label
    }
}

private struct SpyBlockQuoteStyle: MarkdownBlockQuoteStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyThematicBreakStyle: MarkdownThematicBreakStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return Divider()
    }
}

private struct SpyCodeBlockStyle: MarkdownCodeBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        recorder.languageHints.append(configuration.languageHint)
        return configuration.label
    }
}

private struct SpyMermaidBlockStyle: MarkdownMermaidBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyMathBlockStyle: MarkdownMathBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyHTMLBlockStyle: MarkdownHTMLBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyTableBlockStyle: MarkdownTableBlockStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyTableCellStyle: MarkdownTableCellStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return configuration.label
    }
}

private struct SpyListItemStyle: MarkdownListItemStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return MarkdownStyleLeadingContentLayout(spacing: 8) {
            configuration.marker
            configuration.block
        }
    }
}

private struct SpyUnorderedMarkerStyle: MarkdownUnorderedListMarkerStyle {
    let width: CGFloat
    let recorder: StyleInvocationRecorder

    var markerWidth: CGFloat? {
        recorder.markerWidthReadCount += 1
        return width
    }

    func makeBody(configuration: Configuration) -> some View {
        recorder.unorderedMarkerIndentationLevels.append(configuration.indentationLevel)
        return Text("*")
            .frame(width: width, alignment: .trailing)
    }
}

private struct SpyOrderedMarkerStyle: MarkdownOrderedListMarkerStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    var markerWidth: CGFloat? { MarkdownDefaultOrderedListMarkerStyle.width }

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return Text("\(configuration.ordinal).")
            .frame(width: MarkdownDefaultOrderedListMarkerStyle.width, alignment: .trailing)
    }
}

private struct SpyTaskMarkerStyle: MarkdownTaskListMarkerStyle {
    let name: String
    let recorder: StyleInvocationRecorder

    var markerWidth: CGFloat? { MarkdownDefaultTaskListMarkerStyle.width }

    func makeBody(configuration: Configuration) -> some View {
        recorder.invokedNames.append(name)
        return Text(configuration.isChecked ? "[x]" : "[ ]")
            .frame(width: MarkdownDefaultTaskListMarkerStyle.width, alignment: .trailing)
    }
}

private struct AllowAllHTMLPolicy: MarkdownHTMLPolicy {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        .allow
    }
}

private struct AllowAllMathPolicy: MarkdownMathPolicy {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .allow
    }
}

private struct TextMathRenderer: MarkdownMathRenderer {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        AttributedString("math[\(source)]")
    }
}

private struct ASCIIOnlyMermaidRenderer: MarkdownMermaidRenderer {
    func renderedMermaid(
        _ source: String,
        sourceRange: MarkdownSourceRange?,
        theme: MarkdownTheme
    ) -> MarkdownPreparedMermaidDiagram? {
        MarkdownPreparedMermaidDiagram(
            source: source,
            sourceRange: sourceRange,
            ascii: "graph"
        )
    }
}

/// Minimal `MarkdownDocumentStyle` conformance that only overrides
/// `headingStyle`; every other slot falls back to its `MarkdownDefault*Style`
/// via the protocol's own extensions (Part 01), matching the pattern shown
/// in `MarkdownDocumentStyle`'s doc comment.
private struct SpyAggregateDocumentStyle<HeadingStyle: MarkdownHeadingBlockStyle>: MarkdownDocumentStyle {
    let headingStyle: HeadingStyle
}

@MainActor
private func invokeHeadingStyle(_ style: any MarkdownHeadingBlockStyle, headingLevel: Int = 1) {
    let configuration = MarkdownHeadingBlockStyleConfiguration(
        label: MarkdownBlockStyleLabel(Text("test")),
        theme: .compactChat,
        blockID: MarkdownBlockID("test-block"),
        indentationLevel: 0,
        headingLevel: headingLevel
    )
    _ = style.makeBody(configuration: configuration)
}

// MARK: - Merge-order unit tests (INV-BS9, Part 02 §2.6)
//
// These call `resolvedMarkdownStyle` directly with hand-built inputs, so
// they exercise the merge-order contract without rendering a view.

@Test
@MainActor
func resolvedMarkdownStyleOverrideWinsOverAggregateConfigurationAndDefault() {
    let recorder = StyleInvocationRecorder()
    let override = SpyHeadingStyle(name: "override", recorder: recorder)
    let aggregate = SpyAggregateDocumentStyle(headingStyle: SpyHeadingStyle(name: "aggregate", recorder: recorder))
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "configuration", recorder: recorder)
    )

    let resolved = resolvedMarkdownStyle(
        override: override,
        aggregate: aggregate,
        configuration: configuration,
        slot: { $0.headingStyle },
        default: MarkdownDefaultHeadingBlockStyle()
    )

    invokeHeadingStyle(resolved)
    #expect(recorder.invokedNames == ["override"])
}

@Test
@MainActor
func resolvedMarkdownStyleAggregateWinsWhenOverrideAbsent() {
    let recorder = StyleInvocationRecorder()
    let aggregate = SpyAggregateDocumentStyle(headingStyle: SpyHeadingStyle(name: "aggregate", recorder: recorder))
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "configuration", recorder: recorder)
    )

    let resolved = resolvedMarkdownStyle(
        override: nil,
        aggregate: aggregate,
        configuration: configuration,
        slot: { $0.headingStyle },
        default: MarkdownDefaultHeadingBlockStyle()
    )

    invokeHeadingStyle(resolved)
    #expect(recorder.invokedNames == ["aggregate"])
}

@Test
@MainActor
func resolvedMarkdownStyleConfigurationWinsWhenOverrideAndAggregateAbsent() {
    let recorder = StyleInvocationRecorder()
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "configuration", recorder: recorder)
    )

    let resolved = resolvedMarkdownStyle(
        override: nil,
        aggregate: nil,
        configuration: configuration,
        slot: { $0.headingStyle },
        default: MarkdownDefaultHeadingBlockStyle()
    )

    invokeHeadingStyle(resolved)
    #expect(recorder.invokedNames == ["configuration"])
}

@Test
@MainActor
func resolvedMarkdownStyleFallsBackToDefaultWhenNothingSet() {
    let configuration = MarkdownRendererConfiguration.compactChat
    #expect(configuration.documentStyle == nil)

    let resolved = resolvedMarkdownStyle(
        override: Optional<SpyHeadingStyle>.none,
        aggregate: nil,
        configuration: configuration,
        slot: { $0.headingStyle },
        default: MarkdownDefaultHeadingBlockStyle()
    )

    #expect(resolved is MarkdownDefaultHeadingBlockStyle)
}

// MARK: - Configuration plumbing (Part 02 §2.2 Channel A)

@Test
@MainActor
func configurationDocumentStyleDefaultsToNil() {
    #expect(MarkdownRendererConfiguration.compactChat.documentStyle == nil)
    #expect(MarkdownRendererConfiguration.document.documentStyle == nil)
    #expect(MarkdownRendererConfiguration().documentStyle == nil)
}

@Test
@MainActor
func configurationDocumentStyleRoundTripsThroughSetter() {
    let recorder = StyleInvocationRecorder()
    var configuration = MarkdownRendererConfiguration.compactChat
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "roundtrip", recorder: recorder)
    )

    let resolvedHeadingStyle = configuration.documentStyle?.headingStyle
    #expect(resolvedHeadingStyle != nil)
    if let resolvedHeadingStyle {
        invokeHeadingStyle(resolvedHeadingStyle)
        #expect(recorder.invokedNames == ["roundtrip"])
    }
}

// MARK: - Streaming / cache safety (INV-BS1, INV-BS6; Part 06 §6.2.4)

@Test
@MainActor
func documentStyleDoesNotAffectCodeHighlightCacheIdentity() throws {
    let block = try firstBlock("```swift\nlet x = 1\n```")
    let cache = MarkdownRenderPreparationCache()
    let recorder = MarkdownDiagnosticsRecorder()
    let styleRecorder = StyleInvocationRecorder()

    let baseConfiguration = MarkdownRendererConfiguration(
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    _ = baseConfiguration.prepare(block: block)
    let afterFirst = recorder.snapshot()

    var styledConfiguration = MarkdownRendererConfiguration(
        preparationCache: cache,
        diagnosticsRecorder: recorder
    )
    styledConfiguration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "styled", recorder: styleRecorder)
    )
    _ = styledConfiguration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    #expect(afterFirst.codeHighlightCount == 1)
    #expect(afterSecond.codeHighlightCount == afterFirst.codeHighlightCount)
    #expect(afterSecond.cacheHitCount >= afterFirst.cacheHitCount + 1)
}

@Test
@MainActor
func sealedBlockPrepareCountStableWhenDocumentStyleChanges() throws {
    let block = try firstBlock("A plain paragraph.")
    let recorder = MarkdownDiagnosticsRecorder()
    let styleRecorder = StyleInvocationRecorder()

    let unstyledConfiguration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    _ = unstyledConfiguration.prepare(block: block)
    let afterFirst = recorder.snapshot()

    var styledConfiguration = MarkdownRendererConfiguration(diagnosticsRecorder: recorder)
    styledConfiguration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "styled", recorder: styleRecorder)
    )
    _ = styledConfiguration.prepare(block: block)
    let afterSecond = recorder.snapshot()

    // `prepare` never reads `documentStyle` (INV-BS2) — both calls do the
    // same amount of prepare work; only the *chrome* differs downstream in
    // `MarkdownBlockView`, never the parse/highlight/layout pipeline.
    #expect(afterSecond.renderPreparationCount == afterFirst.renderPreparationCount + 1)
    #expect(styleRecorder.invokedNames.isEmpty)
}

// MARK: - Default style parity (Part 06 §6.2.1)

@Test
@MainActor
func defaultHeadingStylePassesThroughLabelUnchanged() {
    let label = MarkdownBlockStyleLabel(Text("Heading"))
    let configuration = MarkdownHeadingBlockStyleConfiguration(
        label: label,
        theme: .compactChat,
        blockID: MarkdownBlockID("heading"),
        indentationLevel: 0,
        headingLevel: 1
    )
    let body = MarkdownDefaultHeadingBlockStyle().makeBody(configuration: configuration)
    // No chrome/modifier is added around the prepared label — the default
    // heading style is a true pass-through, so the returned opaque view's
    // concrete type is exactly `MarkdownBlockStyleLabel`, not a
    // `ModifiedContent<...>` wrapper.
    #expect(body is MarkdownBlockStyleLabel)
}

@Test
@MainActor
func defaultBlockQuoteChromeMatchesLegacyGeometry() {
    #expect(MarkdownDefaultBlockQuoteStyle.leadingWidth == 3)
    #expect(MarkdownDefaultBlockQuoteStyle.spacing == 8)
}

@Test
@MainActor
func defaultCodeBlockCornerRadiusIsSix() {
    #expect(MarkdownDefaultCodeBlockStyle.cornerRadius == 6)
}

@Test
@MainActor
func defaultListMarkerWidths() {
    #expect(MarkdownDefaultUnorderedListMarkerStyle.width == 28)
    #expect(MarkdownDefaultOrderedListMarkerStyle.width == 34)
    #expect(MarkdownDefaultTaskListMarkerStyle.width == 28)
    #expect(MarkdownDefaultListItemStyle.spacing == 8)
    #expect(MarkdownDefaultUnorderedListMarkerStyle().markerWidth == 28)
    #expect(MarkdownDefaultOrderedListMarkerStyle().markerWidth == 34)
    #expect(MarkdownDefaultTaskListMarkerStyle().markerWidth == 28)
}

@Test
func leadingContentLayoutAlignsExplicitFirstTextBaselines() {
    let offsets = MarkdownStyleLeadingContentLayout.firstTextBaselineOffsets(
        leadingBaseline: 12,
        contentBaseline: 16
    )
    #expect(offsets.leading == 4)
    #expect(offsets.content == 0)
}

@Test
@MainActor
func defaultThematicBreakIsDivider() {
    let configuration = MarkdownThematicBreakStyleConfiguration(
        theme: .compactChat,
        blockID: MarkdownBlockID("break"),
        indentationLevel: 0
    )
    let body = MarkdownDefaultThematicBreakStyle().makeBody(configuration: configuration)
    #expect(body is Divider)
}

#if canImport(AppKit)
// MARK: - End-to-end environment injection (Part 02 §2.2 Channel B)

@Test
@MainActor
func preparedListMarkerAndTextShareFirstLineBaselineAcrossMacRenderingModes() throws {
    let block = try firstBlock("H")
    var theme = MarkdownTheme.compactChat
    theme.paragraphFont = .system(size: 16)
    theme.paragraphFontSize = 16
    theme.paragraphLineHeight = 24
    theme.paragraphFontProfiles = .paragraphDefault
    theme.textColor = .black
    let modes: [(MarkdownInlineRenderingMode, MarkdownNativeTextSelection)] = [
        (.coreTextPaintedLines, .disabled),
        (.systemText, .disabled),
        (.coreTextPaintedLines, .enabled),
    ]
    for (renderingMode, selectionMode) in modes {
        let configuration = MarkdownRendererConfiguration(
            theme: theme,
            inlineRenderingMode: renderingMode,
            nativeTextSelection: selectionMode
        )
        let inline = try #require(configuration.prepare(block: block).inlineLayout)
        let row = MarkdownStyleLeadingContentLayout(
            spacing: 8,
            verticalAlignment: .firstTextBaseline
        ) {
            Text("H")
                .font(theme.paragraphFont)
                .foregroundStyle(Color.black)
                .frame(width: 28, alignment: .trailing)
            InlineRunsView(
                prepared: inline,
                theme: theme,
                baseFont: theme.paragraphFont,
                inlineRenderingMode: renderingMode,
                nativeTextSelection: selectionMode
            )
        }

        let bitmap = try testBitmap(for: row, width: 160, height: 48)
        let scale = Double(bitmap.pixelsWide) / 160
        let marker = try #require(
            darkPixelVerticalBounds(
                in: bitmap,
                xRange: 0..<Int(28 * scale)
            )
        )
        let content = try #require(
            darkPixelVerticalBounds(
                in: bitmap,
                xRange: Int(36 * scale)..<Int(80 * scale)
            )
        )
        let markerMidpoint = Double(marker.lowerBound + marker.upperBound) / 2
        let contentMidpoint = Double(content.lowerBound + content.upperBound) / 2
        #expect(
            abs(markerMidpoint - contentMidpoint) <= max(1, scale),
            "rendering mode: \(renderingMode), selection mode: \(selectionMode), marker: \(marker), content: \(content)"
        )
    }
}

@Test
@MainActor
func defaultOrderedListNumeralSharesProductionContentBaseline() throws {
    let block = try firstBlock("1. 1")
    var theme = MarkdownTheme.compactChat
    theme.paragraphFont = .system(size: 16)
    theme.codeFont = .system(size: 16)
    theme.paragraphFontSize = 16
    theme.paragraphLineHeight = 24
    theme.codeFontSize = 16
    theme.paragraphFontProfiles = .paragraphDefault
    theme.textColor = .black
    theme.secondaryTextColor = .black
    let modes: [(MarkdownInlineRenderingMode, MarkdownNativeTextSelection)] = [
        (.coreTextPaintedLines, .disabled),
        (.systemText, .disabled),
        (.coreTextPaintedLines, .enabled),
    ]

    for (renderingMode, selectionMode) in modes {
        let configuration = MarkdownRendererConfiguration(
            theme: theme,
            inlineRenderingMode: renderingMode,
            nativeTextSelection: selectionMode
        )
        let view = MarkdownBlockView(
            block: block,
            configuration: configuration,
            preparedContent: configuration.prepare(block: block)
        )
        let bitmap = try testBitmap(for: view, width: 180, height: 48)
        let scale = Double(bitmap.pixelsWide) / 180
        let marker = try #require(
            darkPixelVerticalBounds(
                in: bitmap,
                xRange: 0..<Int(34 * scale)
            )
        )
        let content = try #require(
            darkPixelVerticalBounds(
                in: bitmap,
                xRange: Int(42 * scale)..<Int(82 * scale)
            )
        )
        let markerMidpoint = Double(marker.lowerBound + marker.upperBound) / 2
        let contentMidpoint = Double(content.lowerBound + content.upperBound) / 2
        #expect(
            abs(markerMidpoint - contentMidpoint) <= max(1, scale),
            "rendering mode: \(renderingMode), selection mode: \(selectionMode), marker: \(marker), content: \(content)"
        )
    }
}

@Test
@MainActor
func defaultTaskListSquareSharesFirstLineOpticalCenterAcrossMacRenderingModes() throws {
    let block = try firstBlock("- [ ] H")
    let themeMetrics = [
        (name: "compact", base: MarkdownTheme.compactChat, fontSize: 13.0, lineHeight: 18.0),
        (name: "document", base: MarkdownTheme.document, fontSize: 16.0, lineHeight: 24.0),
        (name: "larger type", base: MarkdownTheme.document, fontSize: 21.0, lineHeight: 30.0),
    ]
    var mutableConfiguration = MarkdownRendererConfiguration(theme: .compactChat)
    let compactGuide = mutableConfiguration.listMarkerBaselineMetrics
        .taskMarkerFirstTextBaselineFromTop
    var largerTheme = MarkdownTheme.document
    largerTheme.paragraphFontSize = 21
    largerTheme.paragraphLineHeight = 30
    mutableConfiguration.theme = largerTheme
    #expect(
        mutableConfiguration.listMarkerBaselineMetrics.taskMarkerFirstTextBaselineFromTop != compactGuide
    )
    let modes: [(MarkdownInlineRenderingMode, MarkdownNativeTextSelection)] = [
        (.coreTextPaintedLines, .disabled),
        (.systemText, .disabled),
        (.coreTextPaintedLines, .enabled),
    ]

    for metric in themeMetrics {
        var theme = metric.base
        theme.paragraphFont = .system(size: CGFloat(metric.fontSize))
        theme.paragraphFontSize = metric.fontSize
        theme.paragraphLineHeight = metric.lineHeight
        theme.paragraphFontProfiles = .paragraphDefault
        theme.textColor = .black
        theme.secondaryTextColor = .black

        for (renderingMode, selectionMode) in modes {
            let configuration = MarkdownRendererConfiguration(
                theme: theme,
                inlineRenderingMode: renderingMode,
                nativeTextSelection: selectionMode
            )
            let view = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: configuration.prepare(block: block)
            )
            let bitmap = try testBitmap(for: view, width: 180, height: 56)
            let scale = Double(bitmap.pixelsWide) / 180
            let marker = try #require(
                darkPixelVerticalBounds(
                    in: bitmap,
                    xRange: 0..<Int(28 * scale)
                )
            )
            let content = try #require(
                darkPixelVerticalBounds(
                    in: bitmap,
                    xRange: Int(36 * scale)..<Int(80 * scale)
                )
            )
            let markerMidpoint = Double(marker.lowerBound + marker.upperBound) / 2
            let contentMidpoint = Double(content.lowerBound + content.upperBound) / 2
            #expect(
                abs(markerMidpoint - contentMidpoint) <= max(1, scale),
                "theme: \(metric.name), rendering mode: \(renderingMode), selection mode: \(selectionMode), marker: \(marker), content: \(content)"
            )
        }
    }
}

@Test
@MainActor
func defaultTableCellDividerStretchesToTallestCell() throws {
    var theme = MarkdownTheme.compactChat
    theme.tableBorderColor = .black
    theme.tableHorizontalCellPadding = 0
    theme.tableVerticalCellPadding = 0
    let style = MarkdownDefaultTableCellStyle()
    let first = style.makeBody(
        configuration: MarkdownTableCellStyleConfiguration(
            label: MarkdownBlockStyleLabel(Color.clear.frame(height: 12)),
            theme: theme,
            blockID: MarkdownBlockID("row"),
            indentationLevel: 0,
            row: 0,
            column: 0,
            columnCount: 2,
            isHeader: false,
            isLastColumn: false,
            alignment: .left,
            width: 80
        )
    )
    let second = style.makeBody(
        configuration: MarkdownTableCellStyleConfiguration(
            label: MarkdownBlockStyleLabel(Color.clear.frame(height: 88)),
            theme: theme,
            blockID: MarkdownBlockID("row"),
            indentationLevel: 0,
            row: 0,
            column: 1,
            columnCount: 2,
            isHeader: false,
            isLastColumn: true,
            alignment: .left,
            width: 80
        )
    )
    let row = HStack(alignment: .top, spacing: 0) {
        first
        second
    }

    let bitmap = try testBitmap(for: row, width: 160, height: 96)
    let scale = Double(bitmap.pixelsWide) / 160
    #expect(
        hasDarkPixel(
            in: bitmap,
            xRange: Int(78 * scale)..<Int(82 * scale),
            yRange: Int(70 * scale)..<Int(86 * scale)
        )
    )
}

@Test
@MainActor
func customHeadingStyleInvokedWhenAppliedViaEnvironment() throws {
    let block = try firstBlock("## Heading Two")
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(block: block)
    let recorder = StyleInvocationRecorder()

    let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        .markdown.headingStyle(SpyHeadingStyle(name: "custom-heading", recorder: recorder))
        .frame(width: 320, alignment: .leading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    #expect(recorder.invokedNames == ["custom-heading"])
    #expect(recorder.headingLevels == [2])
}

@Test
@MainActor
func customCodeBlockStyleReceivesLanguageHintViaEnvironment() throws {
    let block = try firstBlock("```swift\nlet x = 1\n```")
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(block: block)
    let recorder = StyleInvocationRecorder()

    let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        .markdown.codeBlockStyle(SpyCodeBlockStyle(name: "custom-code", recorder: recorder))
        .frame(width: 320, alignment: .leading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 120))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    #expect(recorder.invokedNames == ["custom-code"])
    #expect(recorder.languageHints == ["swift"])
}

@Test
@MainActor
func perSlotOverrideWinsOverAggregateRegardlessOfModifierOrder() throws {
    let block = try firstBlock("# Heading One")
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(block: block)

    for overrideAppliedLast in [true, false] {
        let recorder = StyleInvocationRecorder()
        let override = SpyHeadingStyle(name: "override", recorder: recorder)
        let aggregate = SpyAggregateDocumentStyle(headingStyle: SpyHeadingStyle(name: "aggregate", recorder: recorder))

        let baseView = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        let view: AnyView = overrideAppliedLast
            ? AnyView(baseView.markdown.documentStyle(aggregate).markdown.headingStyle(override))
            : AnyView(baseView.markdown.headingStyle(override).markdown.documentStyle(aggregate))

        let hostingView = NSHostingView(rootView: view.frame(width: 320, alignment: .leading))
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 80))
        let window = offscreenTestWindow(hostingView)
        defer { tearDownWindow(window) }
        pumpLayout(hostingView)

        #expect(recorder.invokedNames == ["override"], "overrideAppliedLast: \(overrideAppliedLast)")
    }
}

@Test
@MainActor
func configurationDocumentStyleUsedWhenNoEnvironmentStyleSet() throws {
    let block = try firstBlock("# Heading One")
    var configuration = MarkdownRendererConfiguration.compactChat
    let recorder = StyleInvocationRecorder()
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "configuration", recorder: recorder)
    )
    let prepared = configuration.prepare(block: block)

    let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        .frame(width: 320, alignment: .leading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    #expect(recorder.invokedNames == ["configuration"])
}

@Test
@MainActor
func environmentAggregateOverridesConfigurationDocumentStyle() throws {
    let block = try firstBlock("# Heading One")
    var configuration = MarkdownRendererConfiguration.compactChat
    let recorder = StyleInvocationRecorder()
    configuration.documentStyle = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "configuration", recorder: recorder)
    )
    let prepared = configuration.prepare(block: block)
    let environmentAggregate = SpyAggregateDocumentStyle(
        headingStyle: SpyHeadingStyle(name: "environment-aggregate", recorder: recorder)
    )

    let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        .markdown.documentStyle(environmentAggregate)
        .frame(width: 320, alignment: .leading)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 80))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    #expect(recorder.invokedNames == ["environment-aggregate"])
}

@Test
@MainActor
func environmentStylesAreInvokedForRepresentativeBlockSlots() throws {
    let recorder = StyleInvocationRecorder()

    func renderStyledBlock(
        _ markdown: String,
        width: CGFloat = 360,
        height: CGFloat = 180,
        configure: (inout MarkdownRendererConfiguration) -> Void = { _ in },
        styledView: (MarkdownBlockView) -> AnyView
    ) throws {
        let block = try firstBlock(markdown)
        var configuration = MarkdownRendererConfiguration.compactChat
        configure(&configuration)
        let prepared = configuration.prepare(block: block)
        let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        renderOffscreen(styledView(view), width: width, height: height)
    }

    try renderStyledBlock("Plain paragraph.") { view in
        AnyView(view.markdown.paragraphStyle(SpyParagraphStyle(name: "paragraph", recorder: recorder)))
    }
    try renderStyledBlock("> Quoted text") { view in
        AnyView(view.markdown.blockQuoteStyle(SpyBlockQuoteStyle(name: "blockquote", recorder: recorder)))
    }
    try renderStyledBlock("---", height: 80) { view in
        AnyView(view.markdown.thematicBreakStyle(SpyThematicBreakStyle(name: "thematic", recorder: recorder)))
    }
    try renderStyledBlock("- item") { view in
        AnyView(view.markdown.listItemStyle(SpyListItemStyle(name: "list-item", recorder: recorder)))
    }
    try renderStyledBlock("3. item") { view in
        AnyView(view.markdown.orderedListMarkerStyle(SpyOrderedMarkerStyle(name: "ordered-marker", recorder: recorder)))
    }
    try renderStyledBlock("- [x] done") { view in
        AnyView(view.markdown.taskListMarkerStyle(SpyTaskMarkerStyle(name: "task-marker", recorder: recorder)))
    }
    try renderStyledBlock("""
    | A | B |
    | - | - |
    | C | D |
    """, height: 220) { view in
        AnyView(
            view
                .markdown.tableStyle(SpyTableBlockStyle(name: "table", recorder: recorder))
                .markdown.tableCellStyle(SpyTableCellStyle(name: "table-cell", recorder: recorder))
        )
    }
    try renderStyledBlock(
        "$$\nx^2\n$$",
        configure: { configuration in
            configuration.mathPolicy = AllowAllMathPolicy()
            configuration.mathRenderer = TextMathRenderer()
        }
    ) { view in
        AnyView(view.markdown.mathBlockStyle(SpyMathBlockStyle(name: "math", recorder: recorder)))
    }
    try renderStyledBlock(
        "<div>Hello</div>",
        configure: { configuration in
            configuration.htmlPolicy = AllowAllHTMLPolicy()
        }
    ) { view in
        AnyView(view.markdown.htmlBlockStyle(SpyHTMLBlockStyle(name: "html", recorder: recorder)))
    }
    try renderStyledBlock(
        """
        ```mermaid
        graph TD
        A-->B
        ```
        """,
        height: 240,
        configure: { configuration in
            configuration.mermaidRenderer = ASCIIOnlyMermaidRenderer()
        }
    ) { view in
        AnyView(view.markdown.mermaidBlockStyle(SpyMermaidBlockStyle(name: "mermaid", recorder: recorder)))
    }

    for expectedName in [
        "paragraph",
        "blockquote",
        "thematic",
        "list-item",
        "ordered-marker",
        "task-marker",
        "table",
        "table-cell",
        "math",
        "html",
        "mermaid"
    ] {
        #expect(
            recorder.invokedNames.contains(expectedName),
            "Expected \(expectedName) style to be invoked; invoked: \(recorder.invokedNames)"
        )
    }
}

@Test
@MainActor
func nestedListIndentationReadsCustomMarkerWidth() throws {
    let block = try firstBlock("""
    - parent
      - child
    """)
    let configuration = MarkdownRendererConfiguration.compactChat
    let prepared = configuration.prepare(block: block)
    let recorder = StyleInvocationRecorder()

    let view = MarkdownBlockView(block: block, configuration: configuration, preparedContent: prepared)
        .markdown.unorderedListMarkerStyle(SpyUnorderedMarkerStyle(width: 52, recorder: recorder))
        .frame(width: 320, alignment: .leading)

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: 120))
    let window = offscreenTestWindow(hostingView)
    defer { tearDownWindow(window) }
    pumpLayout(hostingView)

    #expect(recorder.markerWidthReadCount >= 1)
    #expect(recorder.unorderedMarkerIndentationLevels.contains(0))
    #expect(recorder.unorderedMarkerIndentationLevels.contains(1))
}
#endif
