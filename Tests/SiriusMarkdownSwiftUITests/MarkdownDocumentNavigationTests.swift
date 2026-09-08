import Foundation
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI
#if os(macOS)
import AppKit
import SwiftUI

@Suite(.serialized)
@MainActor
struct MarkdownDocumentNavigationTests {
    @Test
    func selectedAndUnselectedPaintClipsDoNotDoubleCompositeAntialiasedPixels() throws {
        let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let selected = [CGRect(x: 5, y: 0, width: 10, height: 20), CGRect(x: 10, y: 0, width: 5, height: 20)]
        context.setFillColor(CGColor(gray: 0, alpha: 0.5))
        context.saveGState()
        MarkdownDocumentSelectionPaint.clipOutside(selected, bounds: bounds, in: context)
        context.fill(bounds)
        context.restoreGState()
        context.saveGState()
        context.addRects(selected)
        context.clip()
        context.fill(bounds)
        context.restoreGState()
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let outside = pixels[10 * 80 + 2 * 4 + 3]
        let inside = pixels[10 * 80 + 7 * 4 + 3]
        let overlap = pixels[10 * 80 + 12 * 4 + 3]
        #expect(outside >= 127 && outside <= 128)
        #expect(inside == outside)
        #expect(overlap == outside)
    }

    @Test
    func selectionForegroundMaskPreservesIntrinsicColorPixels() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let intrinsic = CGRect(x: 5, y: 5, width: 10, height: 10)
        context.setFillColor(NSColor.red.cgColor)
        context.fill(bounds)
        MarkdownDocumentSelectionPaint.drawSelectedGlyphs(in: context, rects: [bounds],
            color: .white, bounds: bounds, excluding: [intrinsic]) {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(bounds)
            }
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(pixels[10 * 80 + 10 * 4] == 255)
        #expect(pixels[10 * 80 + 10 * 4 + 1] == 0)
        #expect(pixels[1 * 80 + 1 * 4 + 1] == 255)
    }

    @Test
    func mountedDocumentSelectionPaintReachesTableAndClearsNativeCodeSelection() async throws {
        var configuration = MarkdownRendererConfiguration.document
        configuration.documentSelection = .enabled
        let prepared = prepare("# Heading\n\nA wrapping paragraph with many words repeated across several native lines in this narrow column.\n\n| Name | Value |\n| --- | --- |\n| First | Second |\n\n```swift\nlet selected = true // 🌈\n```", configuration: configuration)
        let selection = MarkdownSelectionController()
        let host = NSHostingView(rootView: AnyView(MarkdownDocumentView(preparedSnapshot: prepared,
            configuration: configuration, selectionController: selection).frame(width: 340, height: 700)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        let ranges = prepared.snapshot.blocks.map(\.sourceRange)
        selection.selectSourceRanges(ranges, selectedBlockIDs: prepared.snapshot.blocks.map(\.id))
        await settle(host)
        let painted = descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }
        #expect(painted.count >= 4)
        #expect(painted.filter { !$0.selectionRects.isEmpty }.count >= 4)
        let code = try #require(descendants(host).compactMap { $0 as? MarkdownAppKitNativeSelectableTextView }.first)
        #expect(!code.isSelectable)
        #expect(code.documentSelectionBlockID != nil)
        #expect(!code.documentSelectionPaint.ranges.isEmpty)
        // Simulate a stale native range left by a previous native owner. The
        // next document update must clear it instead of leaving two selections.
        code.setSelectedRange(NSRange(location: 0, length: 3))
        let heading = try #require(prepared.snapshot.blocks.first)
        selection.selectSourceRanges([heading.sourceRange], selectedBlockIDs: [heading.id])
        await settle(host)
        #expect(code.selectedRanges.allSatisfy { $0.rangeValue.length == 0 })
        #expect(code.documentSelectionPaint.ranges == [heading.sourceRange])
        selection.clearSelection()
        await settle(host)
        #expect(painted.allSatisfy { $0.selectionRects.isEmpty })
        #expect(code.documentSelectionPaint.ranges.isEmpty)
    }

    @Test
    func navigationBuildsOnlyOnDemandAndReindexesEqualLengthReplacement() async throws {
        let original = prepare("alpha")
        let replacementSource = prepare("bravo")
        var replacementBlock = try #require(replacementSource.snapshot.blocks.first)
        replacementBlock.id = try #require(original.snapshot.blocks.first).id
        var replacementModel = original.snapshot
        replacementModel.blocks = [replacementBlock]
        replacementModel.items = [.block(replacementBlock)]
        let replacement = MarkdownRendererConfiguration().prepare(snapshot: replacementModel)
        let find = MarkdownDocumentFindController()
        let state = MarkdownDocumentNavigationState(snapshot: original, findController: find, externalLinkAction: nil)
        state.update(snapshot: original, externalLinkAction: nil)
        #expect(state.indexBuildCount == 0)
        find.isPresented = true
        find.query = "alpha"
        await state.prepareIndex()
        #expect(find.matches.count == 1)
        await state.prepareIndex()
        #expect(state.indexBuildCount == 1)
        state.update(snapshot: replacement, externalLinkAction: nil)
        await state.prepareIndex()
        #expect(state.indexBuildCount == 2)
        #expect(find.matches.isEmpty)
        find.query = "bravo"
        #expect(find.matches.count == 1)
    }

    @Test
    func mountedDocumentFindShowsNativeFieldAndHighlightsCurrentSourceMatch() async throws {
        let prepared = prepare("First needle.\n\nSecond needle.")
        let find = MarkdownDocumentFindController()
        let selection = MarkdownSelectionController()
        let host = NSHostingView(rootView: AnyView(MarkdownDocumentView(
            preparedSnapshot: prepared, configuration: .document, selectionController: selection
        ).documentFindController(find).preferredColorScheme(.light).background(Color.white).frame(width: 600, height: 300)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        #expect(find.matches.isEmpty)
        find.isPresented = true
        find.query = "needle"
        await settle(host)
        #expect(find.matches.count == 2)
        #expect(descendants(host).contains { ($0 as? NSTextField)?.placeholderString == "Find in Document" })
        let match = try #require(find.currentMatch)
        #expect(selection.selectedSourceRanges == [match.sourceRange])
        find.next()
        await settle(host)
        #expect(selection.selectedSourceRanges == [try #require(find.currentMatch).sourceRange])
        if let path = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_FIND_PROBE_OUTPUT"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            let lightRoot = host.rootView
            window.appearance = NSAppearance(named: .darkAqua)
            host.rootView = AnyView(MarkdownDocumentView(
                preparedSnapshot: prepared, configuration: .document, selectionController: selection
            ).documentFindController(find).preferredColorScheme(.dark)
                .background(Color(nsColor: .windowBackgroundColor)).frame(width: 600, height: 300))
            await settle(host)
            if let darkBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: darkBitmap)
                try darkBitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".dark.png"))
            }
            window.appearance = NSAppearance(named: .aqua)
            host.rootView = lightRoot
            await settle(host)
        }
        find.query = "missing"
        await settle(host)
        #expect(selection.selectedSourceRanges.isEmpty)
        find.isPresented = false
        selection.selectSourceRanges([match.sourceRange], selectedBlockIDs: [match.blockID])
        let replacement = prepare("x")
        #expect(replacement.snapshot.generation == prepared.snapshot.generation)
        host.rootView = AnyView(MarkdownDocumentView(
            preparedSnapshot: replacement, configuration: .document, selectionController: selection
        ).documentFindController(find).preferredColorScheme(.light).background(Color.white).frame(width: 600, height: 300))
        await settle(host)
        #expect(selection.selectedSourceRanges.isEmpty)
    }

    @Test
    func mountedHeadingLinkRevealsOffscreenHeadingAndExternalLinksReachHost() async throws {
        let recorder = NavigationLinkRecorder()
        let markdown = "[Jump](#destination) and [External](https://example.com).\n\n" +
            (0..<45).map { "Paragraph \($0) fills the scrolling document.\n\n" }.joined() + "# Destination\n"
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        configuration.linkAction = MarkdownLinkAction { recorder.append($0) }
        let prepared = prepare(markdown, configuration: configuration)
        let find = MarkdownDocumentFindController()
        let host = NSHostingView(rootView: AnyView(MarkdownDocumentView(
            preparedSnapshot: prepared, configuration: configuration
        ).documentFindController(find).preferredColorScheme(.light).background(Color.white).frame(width: 600, height: 240)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        let leaf = try #require(descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }.first {
            $0.plan.linkFragments.contains { $0.destination == "#destination" }
        })
        let action = try #require(leaf.linkAction)
        action.open("https://example.com")
        await settle(host)
        #expect(recorder.values == ["https://example.com"])
        action.open("#destination")
        await settle(host)
        #expect(find.index.heading(forFragment: "#destination") != nil)
        #expect(recorder.values == ["https://example.com"])
        let scrollViews = descendants(host).compactMap { $0 as? NSScrollView }
        #expect(scrollViews.contains { $0.contentView.bounds.minY > 100 })
        #expect(!find.isPresented)
    }

    @Test(arguments: [true, false])
    func hostScrolledTranscriptFindAndAnchorsRevealWithoutNestedScroller(showsInlineControls: Bool) async throws {
        let markdown = "[Jump](#target) First needle.\n\n" +
            (0..<45).map { "Paragraph \($0) provides scrolling space.\n\n" }.joined() +
            "# Target\n\nLast needle."
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        configuration.documentSelection = .disabled
        let prepared = prepare(markdown, configuration: configuration)
        let find = MarkdownDocumentFindController()
        let selection = MarkdownSelectionController()
        let host = NSHostingView(rootView: AnyView(VStack(spacing: 0) {
            if !showsInlineControls { MarkdownDocumentFindBar(controller: find) }
            ScrollView {
                StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration, selectionController: selection)
                    .documentFindController(find, showsInlineControls: showsInlineControls)
            }
        }.frame(width: 600, height: 240)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        #expect(descendants(host).compactMap { $0 as? NSScrollView }.count == 1)
        find.isPresented = true
        find.query = "needle"
        await settle(host)
        #expect(find.matches.count == 2)
        let fields = descendants(host).compactMap { $0 as? NSTextField }.filter { $0.placeholderString == "Find in Document" }
        #expect(fields.count == 1, "External Find controls must not duplicate inline controls")
        let field = try #require(fields.first)
        let fieldOrigin = field.convert(NSPoint.zero, to: host)
        find.next()
        await settle(host)
        #expect(scroll.contentView.bounds.minY > 400)
        #expect(selection.selectedSourceRanges == [try #require(find.currentMatch).sourceRange])
        #expect(descendants(host).compactMap { $0 as? MarkdownHostScrollRevealView }.count == 1)
        if !showsInlineControls {
            #expect(abs(field.convert(NSPoint.zero, to: host).y - fieldOrigin.y) < 1,
                    "External Find bar must stay fixed while its document scrolls")
        }
        find.previous()
        await settle(host)
        #expect(scroll.contentView.bounds.minY < 100)
        find.isPresented = false
        let leaf = try #require(descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }.first {
            $0.plan.linkFragments.contains { $0.destination == "#target" }
        })
        try #require(leaf.linkAction).open("#target")
        await settle(host)
        #expect(scroll.contentView.bounds.minY > 400)
        #expect(descendants(host).compactMap { $0 as? NSScrollView }.count == 1)
    }

    @Test(arguments: ["<p id=\"empty\"></p>", "Before <a id=\"empty\"></a> after."])
    func hostScrolledEmptyAnchorsRevealWithoutAddingHeightOrSelection(anchorSource: String) async throws {
        let markdown = "[Jump](#empty)\n\n" +
            (0..<45).map { "Paragraph \($0) provides scrolling space.\n\n" }.joined() +
            anchorSource + "\n\n### Appendix content\n\nVisible continuation."
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        let prepared = prepare(markdown, configuration: configuration)
        let find = MarkdownDocumentFindController()
        let selection = MarkdownSelectionController()
        let host = NSHostingView(rootView: AnyView(ScrollView {
            StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration, selectionController: selection)
                .documentFindController(find, showsInlineControls: false)
        }.frame(width: 600, height: 240)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let initialHeight = try #require(scroll.documentView).frame.height
        let leaf = try #require(descendants(host).compactMap { $0 as? MarkdownCoreTextPaintedNSView }.first {
            $0.plan.linkFragments.contains { $0.destination == "#empty" }
        })
        try #require(leaf.linkAction).open("#empty")
        await settle(host)
        #expect(find.index.anchor(forFragment: "#empty") != nil)
        #expect(scroll.contentView.bounds.minY > 400)
        #expect(abs(try #require(scroll.documentView).frame.height - initialHeight) < 1)
        #expect(selection.selectedSourceRanges.isEmpty)
        #expect(descendants(host).compactMap { $0 as? MarkdownHostScrollRevealView }.count == 1)
        #expect(descendants(host).compactMap { $0 as? NSScrollView }.count == 1)
    }

    @Test
    func findRevealsHorizontallyOverflowingCodeAndTableCells() async throws {
        let wideCode = String(repeating: "long_identifier_", count: 25) + "CODE_TARGET"
        let columns = (0..<12).map { "Column \($0)" }
        let table = "| " + columns.joined(separator: " | ") + " |\n| " +
            Array(repeating: "---", count: columns.count).joined(separator: " | ") + " |\n| " +
            (0..<12).map { $0 == 11 ? "TABLE_TARGET" : "Value \($0)" }.joined(separator: " | ") + " |"
        let source = "```text\n" + wideCode + "\nSECOND_TARGET\n```\n\n" + table
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        let prepared = prepare(source, configuration: configuration)
        let find = MarkdownDocumentFindController()
        let host = NSHostingView(rootView: AnyView(ScrollView {
            StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
                .documentFindController(find)
        }.preferredColorScheme(.light).background(Color.white).frame(width: 600, height: 240)))
        let window = makeWindow(host)
        defer { tearDown(host, window) }
        await settle(host)
        find.isPresented = true
        find.query = "CODE_TARGET"
        await settle(host)
        #expect(find.matches.count == 1)
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        let codeScroll = try #require(scrolls.first { ($0.documentView?.frame.width ?? 0) > 2000 })
        #expect(codeScroll.contentView.bounds.minX > 1000)
        find.query = "SECOND_TARGET"
        await settle(host)
        #expect(find.matches.count == 1)
        #expect(codeScroll.contentView.bounds.minX < 50)
        find.query = "TABLE_TARGET"
        await settle(host)
        #expect(find.matches.count == 1)
        let tableScroll = try #require(scrolls.first {
            $0 !== codeScroll && ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 100
        })
        #expect(tableScroll.contentView.bounds.minX > 100)
        if let path = ProcessInfo.processInfo.environment["SIRIUS_MARKDOWN_OVERFLOW_FIND_PROBE_OUTPUT"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    private func prepare(_ markdown: String, configuration: MarkdownRendererConfiguration = .document) -> MarkdownPreparedSnapshot {
        var stream = MarkdownStream()
        stream.append(markdown)
        stream.finish()
        return configuration.prepare(snapshot: stream.snapshot())
    }

    private func makeWindow(_ host: NSHostingView<AnyView>) -> NSWindow {
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private func tearDown(_ host: NSHostingView<AnyView>, _ window: NSWindow) {
        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

private final class NavigationLinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.withLock { storage.append(value) } }
    var values: [String] { lock.withLock { storage } }
}
#endif
