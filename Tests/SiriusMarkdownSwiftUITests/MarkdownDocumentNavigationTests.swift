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

    @Test
    func hostScrolledTranscriptFindAndAnchorsRevealWithoutNestedScroller() async throws {
        let markdown = "[Jump](#target) First needle.\n\n" +
            (0..<45).map { "Paragraph \($0) provides scrolling space.\n\n" }.joined() +
            "# Target\n\nLast needle."
        var configuration = MarkdownRendererConfiguration.document
        configuration.linkMetadataResolver = nil
        configuration.documentSelection = .disabled
        let prepared = prepare(markdown, configuration: configuration)
        let find = MarkdownDocumentFindController()
        let selection = MarkdownSelectionController()
        let host = NSHostingView(rootView: AnyView(ScrollView {
            StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration, selectionController: selection)
                .documentFindController(find)
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
        find.next()
        await settle(host)
        #expect(scroll.contentView.bounds.minY > 400)
        #expect(selection.selectedSourceRanges == [try #require(find.currentMatch).sourceRange])
        #expect(descendants(host).compactMap { $0 as? MarkdownHostScrollRevealView }.count == 1)
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
