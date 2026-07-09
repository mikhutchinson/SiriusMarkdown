import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

// MARK: - Helpers

private func makeBlockID(_ raw: String) -> MarkdownBlockID {
    MarkdownBlockID(raw)
}

private func makeSourceRange(_ byteRange: Range<Int>) -> MarkdownSourceRange {
    MarkdownSourceRange(byteRange: byteRange, lineRange: 1..<2)
}

private func prepareContextSnapshot(
    _ source: String
) -> (snapshot: MarkdownSnapshot, prepared: MarkdownPreparedSnapshot) {
    var configuration = MarkdownRendererConfiguration.document
    configuration.copyProvider = MarkdownCopyProvider(markdownSource: source)
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let snapshot = stream.snapshot()
    let prepared = configuration.prepare(snapshot: snapshot)
    return (snapshot, prepared)
}

// MARK: - Part 02: Scrollable region selection contexts

@Suite(.serialized)
struct MarkdownSelectionContextTests {

    // MARK: - Default context

    @Test
    @MainActor
    func defaultContextIsDocument() {
        let controller = MarkdownSelectionController()
        #expect(controller.activeContext == .document)
    }

    // MARK: - Activating a scrollable region clears document selection

    @Test
    @MainActor
    func testActivateScrollableRegionClearsDocumentSelection() {
        let source = "Hello\n\nWorld"
        let (snapshot, _) = prepareContextSnapshot(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)

        // Select multiple blocks at document level.
        let blockIDs = snapshot.blocks.map(\.id)
        guard blockIDs.count >= 2 else { return }
        controller.selectRange(from: blockIDs[0], to: blockIDs[1])
        #expect(!controller.selectedBlockIDs.isEmpty, "Precondition: document selection must be active")
        #expect(controller.activeContext == .document)

        // Activate a scrollable region.
        let regionID = MarkdownScrollableSelectionRegionID(blockID: blockIDs[0], role: .codeBlock)
        controller.activateContext(.scrollableRegion(regionID))

        #expect(controller.activeContext == .scrollableRegion(regionID))
        #expect(controller.selectedBlockIDs.isEmpty, "Activating scrollable region must clear document selection")
        #expect(controller.selectedSourceRanges.isEmpty, "Activating scrollable region must clear source ranges")
    }

    // MARK: - Document context activation clears region selection

    @Test
    @MainActor
    func testDocumentActivationClearsScrollableRegionSelection() {
        let source = "Paragraph"
        let (snapshot, _) = prepareContextSnapshot(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)

        let blockID = snapshot.blocks[0].id
        let regionID = MarkdownScrollableSelectionRegionID(blockID: blockID, role: .codeBlock)

        // Start in scrollable region context with a selection.
        controller.activateContext(.scrollableRegion(regionID))
        controller.selectSourceRanges([makeSourceRange(0..<5)], selectedBlockIDs: [blockID])
        #expect(!controller.selectedSourceRanges.isEmpty, "Precondition: region selection must exist")

        // Activate document context.
        controller.activateContext(.document)

        #expect(controller.activeContext == .document)
        #expect(controller.selectedSourceRanges.isEmpty, "Activating document context must clear region selection")
    }

    // MARK: - No-op when activating same context

    @Test
    @MainActor
    func testActivatingSameContextIsNoOp() {
        let source = "Text"
        let (snapshot, _) = prepareContextSnapshot(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)

        let blockID = snapshot.blocks[0].id
        controller.selectSourceRanges([makeSourceRange(0..<4)], selectedBlockIDs: [blockID])
        #expect(!controller.selectedSourceRanges.isEmpty, "Precondition: selection must exist")

        // Activating the same (.document) context is a no-op.
        controller.activateContext(.document)
        #expect(!controller.selectedSourceRanges.isEmpty, "Same-context activation must not clear selection")
    }

    // MARK: - Copy uses active context ranges

    @Test
    @MainActor
    func testCopyUsesActiveContextRanges() {
        let source = "Hello world"
        let (snapshot, prepared) = prepareContextSnapshot(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)

        let blockID = snapshot.blocks[0].id
        let selectedRange = makeSourceRange(0..<5) // "Hello"
        controller.selectSourceRanges([selectedRange], selectedBlockIDs: [blockID])

        let copyProvider = MarkdownCopyProvider(markdownSource: source)
        let copiedMarkdown = controller.selectedMarkdown(in: prepared, copyProvider: copyProvider)
        #expect(copiedMarkdown == "Hello", "Copy must return the clamped active context source slice")
    }

    // MARK: - Streaming append does not change context without user input

    @Test
    @MainActor
    func testStreamingAppendDoesNotChangeContextWithoutUserInput() {
        let controller = MarkdownSelectionController()

        // Simulate progressive streaming appends.
        for i in 1...10 {
            var stream = MarkdownStream()
            stream.append(String(repeating: "word ", count: i * 5))
            stream.finish()
            let snapshot = stream.snapshot()
            controller.updateSnapshot(snapshot)
        }

        // Context must remain document (default) without explicit activateContext calls.
        #expect(controller.activeContext == .document, "Streaming append must not change activeContext")
    }

    // MARK: - Scrollable region context kind equality

    @Test
    @MainActor
    func testScrollableRegionContextKindEquality() {
        let blockID = makeBlockID("block-1")
        let id1 = MarkdownScrollableSelectionRegionID(blockID: blockID, role: .codeBlock)
        let id2 = MarkdownScrollableSelectionRegionID(blockID: blockID, role: .codeBlock)
        let id3 = MarkdownScrollableSelectionRegionID(blockID: blockID, role: .table)

        #expect(MarkdownSelectionContextKind.scrollableRegion(id1) == .scrollableRegion(id2))
        #expect(MarkdownSelectionContextKind.scrollableRegion(id1) != .scrollableRegion(id3))
        #expect(MarkdownSelectionContextKind.document != .scrollableRegion(id1))
    }

    // MARK: - Clear selection resets to document context (via clearSelection, not activateContext)

    @Test
    @MainActor
    func testClearSelectionDoesNotChangeActiveContext() {
        let source = "Text"
        let (snapshot, _) = prepareContextSnapshot(source)
        let controller = MarkdownSelectionController()
        controller.updateSnapshot(snapshot)

        let blockID = snapshot.blocks[0].id
        let regionID = MarkdownScrollableSelectionRegionID(blockID: blockID, role: .table)
        controller.activateContext(.scrollableRegion(regionID))
        controller.selectSourceRanges([makeSourceRange(0..<4)], selectedBlockIDs: [blockID])

        // clearSelection alone should not change the active context.
        controller.clearSelection()
        #expect(controller.activeContext == .scrollableRegion(regionID),
                "clearSelection alone must not change activeContext; use activateContext to switch")
        #expect(controller.selectedSourceRanges.isEmpty)
    }
}
