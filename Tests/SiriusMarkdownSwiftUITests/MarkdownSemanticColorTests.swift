import Foundation
import SiriusMarkdownCore
import SwiftUI
import Testing
@testable import SiriusMarkdownSwiftUI

#if canImport(AppKit) && canImport(CoreText)
import AppKit
import CoreText

@Test
@MainActor
func platformColorResolverUsesRequestedAppKitAppearance() throws {
    let lightPrimary = MarkdownPlatformColorResolver.appKitColor(.primary, colorScheme: .light)
    let darkPrimary = MarkdownPlatformColorResolver.appKitColor(.primary, colorScheme: .dark)
    let lightSecondary = MarkdownPlatformColorResolver.appKitColor(.secondary, colorScheme: .light)
    let darkSecondary = MarkdownPlatformColorResolver.appKitColor(.secondary, colorScheme: .dark)
    let fixedColor = Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.8)
    let lightFixed = MarkdownPlatformColorResolver.appKitColor(fixedColor, colorScheme: .light)
    let darkFixed = MarkdownPlatformColorResolver.appKitColor(fixedColor, colorScheme: .dark)

    #expect(rgbBrightness(lightPrimary) < 0.1)
    #expect(rgbBrightness(darkPrimary) > 0.9)
    #expect(rgbBrightness(lightSecondary) < 0.1)
    #expect(rgbBrightness(darkSecondary) > 0.9)
    #expect(lightSecondary.alphaComponent < lightPrimary.alphaComponent)
    #expect(darkSecondary.alphaComponent < darkPrimary.alphaComponent)
    #expect(lightFixed.isEqual(darkFixed))
}

@Test
@MainActor
func coreTextPaintedPrimaryColorTracksLiveSchemeWithoutRemounting() throws {
    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        theme: .compactChat,
        inlineRenderingMode: .coreTextPaintedLines,
        nativeTextSelection: .disabled,
        documentSelection: .enabled,
        diagnosticsRecorder: recorder
    )
    let prepared = preparedSnapshot(
        "Dark mode transcript text must stay readable.",
        configuration: configuration
    )
    let model = SemanticColorSchemeModel(colorScheme: .light)
    let root = SemanticCoreTextHarness(
        model: model,
        preparedSnapshot: prepared,
        configuration: configuration
    )
    .frame(width: 320, height: 96, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 96)
    let window = semanticColorTestWindow(hostingView)
    defer { tearDownSemanticColorWindow(window) }

    pumpSemanticColorLayout(hostingView)
    let lightView = try #require(coreTextPaintedViews(in: hostingView).first)
    let mountedIdentity = ObjectIdentifier(lightView)
    let lightLine = try #require(lightView.plan.lines.first)
    let lineIdentity = ObjectIdentifier(lightLine.ctLine as AnyObject)
    let countersBeforeSchemeChange = recorder.snapshot()
    let lightBitmap = try semanticColorBitmap(of: hostingView)
    #expect(rgbBrightness(lightView.textColor) < 0.1)
    #expect(darkPixelCount(in: lightBitmap) > 20)

    model.colorScheme = .dark
    pumpSemanticColorLayout(hostingView)

    let darkView = try #require(coreTextPaintedViews(in: hostingView).first)
    let darkLine = try #require(darkView.plan.lines.first)
    let darkBitmap = try semanticColorBitmap(of: hostingView)
    let countersAfterSchemeChange = recorder.snapshot()
    #expect(ObjectIdentifier(darkView) == mountedIdentity)
    #expect(ObjectIdentifier(darkLine.ctLine as AnyObject) == lineIdentity)
    #expect(rgbBrightness(darkView.textColor) > 0.9)
    #expect(brightPixelCount(in: darkBitmap) > 20)
    #expect(countersAfterSchemeChange.prepareCount == countersBeforeSchemeChange.prepareCount)
    #expect(
        countersAfterSchemeChange.coreTextLinePlanRebuiltInBodyCount ==
            countersBeforeSchemeChange.coreTextLinePlanRebuiltInBodyCount
    )
}

@Test
@MainActor
func selectableTextAndMathFallbackTrackLiveSemanticColor() throws {
    let model = SemanticColorSchemeModel(colorScheme: .light)
    let root = SemanticSelectableTextHarness(model: model)
        .frame(width: 320, height: 80, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
    let window = semanticColorTestWindow(hostingView)
    defer { tearDownSemanticColorWindow(window) }

    pumpSemanticColorLayout(hostingView)
    let lightTextView = try #require(textViews(in: hostingView).first)
    let mountedIdentity = ObjectIdentifier(lightTextView)
    #expect(rgbBrightness(try #require(lightTextView.textColor)) < 0.1)
    #expect(rgbBrightness(try foregroundColor(in: lightTextView)) < 0.1)

    model.colorScheme = .dark
    pumpSemanticColorLayout(hostingView)

    let darkTextView = try #require(textViews(in: hostingView).first)
    #expect(ObjectIdentifier(darkTextView) == mountedIdentity)
    #expect(rgbBrightness(try #require(darkTextView.textColor)) > 0.9)
    #expect(rgbBrightness(try foregroundColor(in: darkTextView)) > 0.9)
}

@Test
@MainActor
func attachmentPlaceholderChromeTracksLiveSemanticColors() throws {
    var theme = MarkdownTheme.compactChat
    theme.attachmentPlaceholder = MarkdownAttachmentPlaceholderStyle(
        pointWidth: 160,
        pointHeight: 80,
        backgroundColor: .primary,
        borderColor: .secondary
    )
    let configuration = MarkdownRendererConfiguration(
        theme: theme,
        inlineRenderingMode: .coreTextPaintedLines,
        nativeTextSelection: .disabled,
        imagePolicy: SemanticColorAllowImagePolicy(),
        imageResolver: SemanticColorPlaceholderImageResolver()
    )
    let prepared = preparedSnapshot(
        "![diagram](https://example.com/diagram.png)",
        configuration: configuration
    )
    let model = SemanticColorSchemeModel(colorScheme: .light)
    let root = SemanticCoreTextHarness(
        model: model,
        preparedSnapshot: prepared,
        configuration: configuration
    )
    .frame(width: 320, height: 120, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
    let window = semanticColorTestWindow(hostingView)
    defer { tearDownSemanticColorWindow(window) }

    pumpSemanticColorLayout(hostingView)
    let lightHost = try #require(attachmentHosts(in: hostingView).first)
    let lightChrome = try #require(placeholderChrome(in: lightHost))
    let hostIdentity = ObjectIdentifier(lightHost)
    let chromeIdentity = ObjectIdentifier(lightChrome)
    #expect(rgbBrightness(try #require(lightChrome.backgroundColor)) < 0.1)
    #expect(rgbBrightness(try #require(lightChrome.borderColor)) < 0.1)

    model.colorScheme = .dark
    pumpSemanticColorLayout(hostingView)

    let darkHost = try #require(attachmentHosts(in: hostingView).first)
    let darkChrome = try #require(placeholderChrome(in: darkHost))
    #expect(ObjectIdentifier(darkHost) == hostIdentity)
    #expect(ObjectIdentifier(darkChrome) == chromeIdentity)
    #expect(rgbBrightness(try #require(darkChrome.backgroundColor)) > 0.9)
    #expect(rgbBrightness(try #require(darkChrome.borderColor)) > 0.9)
}

@Test
@MainActor
func largeCoreTextTranscriptAppearanceSwitchReusesPreparedLinePlans() throws {
    var stream = MarkdownStream()
    for index in 0..<150 {
        stream.append("Paragraph \(index) with **strong text** and [link](https://example.com/\(index)).\n\n")
    }
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    let configuration = MarkdownRendererConfiguration(
        theme: .compactChat,
        inlineRenderingMode: .coreTextPaintedLines,
        nativeTextSelection: .disabled,
        documentSelection: .enabled,
        diagnosticsRecorder: recorder
    )
    let prepared = configuration.prepare(snapshot: stream.snapshot())
    let model = SemanticColorSchemeModel(colorScheme: .light)
    let root = SemanticCoreTextHarness(
        model: model,
        preparedSnapshot: prepared,
        configuration: configuration
    )
    .frame(width: 320, height: 6_000, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 6_000)
    let window = semanticColorTestWindow(hostingView)
    defer { tearDownSemanticColorWindow(window) }

    pumpSemanticColorLayout(hostingView)
    let lightViews = coreTextPaintedViews(in: hostingView)
    let lightLineIdentities = coreTextLineIdentities(in: lightViews)
    let countersBeforeSchemeChange = recorder.snapshot()
    #expect(lightViews.count == 150)
    #expect(lightLineIdentities.isEmpty == false)

    model.colorScheme = .dark
    pumpSemanticColorLayout(hostingView)

    let darkViews = coreTextPaintedViews(in: hostingView)
    let countersAfterSchemeChange = recorder.snapshot()
    #expect(darkViews.count == lightViews.count)
    #expect(coreTextLineIdentities(in: darkViews) == lightLineIdentities)
    #expect(countersAfterSchemeChange.parseCount == countersBeforeSchemeChange.parseCount)
    #expect(countersAfterSchemeChange.prepareCount == countersBeforeSchemeChange.prepareCount)
    #expect(
        countersAfterSchemeChange.coreTextLinePlanRebuiltInBodyCount ==
            countersBeforeSchemeChange.coreTextLinePlanRebuiltInBodyCount
    )
}

@MainActor
private final class SemanticColorSchemeModel: ObservableObject {
    @Published var colorScheme: ColorScheme

    init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }
}

private struct SemanticCoreTextHarness: View {
    @ObservedObject var model: SemanticColorSchemeModel
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration

    var body: some View {
        StreamingMarkdownView(
            preparedSnapshot: preparedSnapshot,
            configuration: configuration
        )
        .environment(\.colorScheme, model.colorScheme)
        .background(model.colorScheme == .dark ? Color.black : Color.white)
    }
}

private struct SemanticSelectableTextHarness: View {
    @ObservedObject var model: SemanticColorSchemeModel

    var body: some View {
        MarkdownSelectableText(
            attributed: AttributedString("Selectable semantic text"),
            font: .body,
            fontSize: 16,
            lineHeight: 22,
            fontProfile: .system(),
            textColor: .primary,
            linkAction: nil,
            nativeTextSelection: .enabled
        )
        .environment(\.colorScheme, model.colorScheme)
    }
}

private struct SemanticColorAllowImagePolicy: MarkdownImagePolicy, MarkdownImagePolicyCacheIdentifying {
    let imagePolicyCacheIdentity = "semantic-color-allow"

    func evaluateImage(source _: String, altText _: String?) -> MarkdownPolicyDecision {
        .allow
    }
}

private struct SemanticColorPlaceholderImageResolver:
    MarkdownImageResolver,
    MarkdownImageResolverCacheIdentifying
{
    let imageResolverCacheIdentity = "semantic-color-placeholder"

    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision _: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: .placeholder(reason: "pending")
        )
    }
}

private func preparedSnapshot(
    _ markdown: String,
    configuration: MarkdownRendererConfiguration
) -> MarkdownPreparedSnapshot {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return configuration.prepare(snapshot: stream.snapshot())
}

@MainActor
private func semanticColorTestWindow<V: View>(_ hostingView: NSHostingView<V>) -> NSWindow {
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
private func pumpSemanticColorLayout<V: View>(_ hostingView: NSHostingView<V>) {
    for _ in 0..<8 {
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func tearDownSemanticColorWindow(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
}

@MainActor
private func coreTextPaintedViews(in view: NSView) -> [MarkdownCoreTextPaintedNSView] {
    var result = (view as? MarkdownCoreTextPaintedNSView).map { [$0] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: coreTextPaintedViews(in: subview))
    }
    return result
}

@MainActor
private func coreTextLineIdentities(
    in views: [MarkdownCoreTextPaintedNSView]
) -> [ObjectIdentifier] {
    views.flatMap { view in
        view.plan.lines.map { ObjectIdentifier($0.ctLine as AnyObject) }
    }
}

@MainActor
private func textViews(in view: NSView) -> [NSTextView] {
    var result = (view as? NSTextView).map { [$0] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: textViews(in: subview))
    }
    return result
}

@MainActor
private func attachmentHosts(in view: NSView) -> [MarkdownAttachmentHostNSView] {
    var result = (view as? MarkdownAttachmentHostNSView).map { [$0] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: attachmentHosts(in: subview))
    }
    return result
}

@MainActor
private func placeholderChrome(
    in host: MarkdownAttachmentHostNSView
) -> MarkdownAttachmentPlaceholderChromeLayer? {
    host.layer?.sublayers?.compactMap { $0 as? MarkdownAttachmentPlaceholderChromeLayer }.first
}

@MainActor
private func foregroundColor(in textView: NSTextView) throws -> NSColor {
    let storage = try #require(textView.textStorage)
    return try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
}

@MainActor
private func semanticColorBitmap<V: View>(of hostingView: NSHostingView<V>) throws -> NSBitmapImageRep {
    let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    return bitmap
}

private func brightPixelCount(in bitmap: NSBitmapImageRep) -> Int {
    pixelCount(in: bitmap) { color in
        color.redComponent > 0.6 &&
            color.greenComponent > 0.6 &&
            color.blueComponent > 0.6 &&
            color.alphaComponent > 0.5
    }
}

private func darkPixelCount(in bitmap: NSBitmapImageRep) -> Int {
    pixelCount(in: bitmap) { color in
        color.redComponent < 0.4 &&
            color.greenComponent < 0.4 &&
            color.blueComponent < 0.4 &&
            color.alphaComponent > 0.5
    }
}

private func pixelCount(
    in bitmap: NSBitmapImageRep,
    matching predicate: (NSColor) -> Bool
) -> Int {
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            if predicate(color) {
                count += 1
            }
        }
    }
    return count
}

private func rgbBrightness(_ color: NSColor) -> CGFloat {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return -1 }
    return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
}

private func rgbBrightness(_ color: CGColor) -> CGFloat {
    guard let appKitColor = NSColor(cgColor: color) else { return -1 }
    return rgbBrightness(appKitColor)
}
#endif
