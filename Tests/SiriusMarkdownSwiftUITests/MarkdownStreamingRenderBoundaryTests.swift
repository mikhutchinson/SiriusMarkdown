#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownStreamingRenderBoundaryTests {
    @Test func unchangedPreparedBlocksReuseBodiesWhilePublicMutationsInvalidateThem() async throws {
        var stream = MarkdownStream()
        stream.append("Stable paragraph.\n\n")
        var configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
        let first = configuration.prepare(snapshot: stream.snapshot())
        stream.append("New paragraph")
        let next = configuration.prepare(snapshot: stream.snapshot(), reusing: first)
        let block = try #require(next.snapshot.blocks.first)
        var content = try #require(next.preparedContentByBlockID[block.id])
        #expect(content.renderRevision == first.preparedContentByBlockID[block.id]?.renderRevision)
        let counter = StreamingBoundaryCounter()
        func root() -> AnyView {
            AnyView(MarkdownStreamingBlockRenderBoundary(block: block,
                preparedRevision: content.renderRevision, configurationRevision: configuration.renderRevision,
                selectionController: nil) {
                counter.evaluations += 1
                return Text(content.code.map { String($0.characters) } ?? "Stable paragraph.")
            }.equatable().frame(width: 300, height: 100))
        }
        let host = NSHostingView(rootView: root())
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        defer {
            host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        func settle() async {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        await settle()
        let initial = counter.evaluations
        #expect(initial > 0)
        host.rootView = root()
        await settle()
        #expect(counter.evaluations == initial)
        // Public prepared values are mutable: their nested writeback must not
        // leave a mounted block stuck behind an old equality token.
        content.code = AttributedString("Updated content")
        host.rootView = root()
        await settle()
        #expect(counter.evaluations > initial)
        let afterContent = counter.evaluations
        let previousRevision = content.renderRevision
        content.code?.append(AttributedString(" again"))
        #expect(content.renderRevision != previousRevision)
        configuration.theme.paragraphFontSize += 1
        host.rootView = root()
        await settle()
        #expect(counter.evaluations > afterContent)
        let beforeCallback = configuration.renderRevision
        configuration.linkAction = MarkdownLinkAction { _ in }
        #expect(configuration.renderRevision != beforeCallback)
    }
}

@MainActor private final class StreamingBoundaryCounter { var evaluations = 0 }
#endif
