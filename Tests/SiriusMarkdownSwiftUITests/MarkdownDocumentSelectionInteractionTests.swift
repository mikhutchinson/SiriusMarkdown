#if os(macOS)
import AppKit
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownDocumentSelectionInteractionTests {
    private func fixture(_ source: String) -> MarkdownDocumentSelectionInteraction {
        var stream = MarkdownStream(); stream.append(source); stream.finish()
        let configuration = MarkdownRendererConfiguration()
        let snapshot = stream.snapshot()
        let interaction = MarkdownDocumentSelectionInteraction(controller: MarkdownSelectionController())
        interaction.controller.updateSnapshot(snapshot)
        interaction.snapshot = snapshot
        interaction.fragments = snapshot.blocks.enumerated().flatMap { index, block in
            MarkdownDocumentSelectionFragment.fragments(for: block, preparedContent: configuration.prepare(block: block), rect: CGRect(x: 0, y: index * 80, width: 220, height: 60))
        }.sortedForSelection()
        return interaction
    }

    @Test func dragCrossesParagraphsAndShiftClickKeepsAnchor() throws {
        let interaction = fixture("Alpha beta gamma\n\nDelta epsilon")
        let first = try #require(interaction.fragments.first)
        let last = try #require(interaction.fragments.last)
        let start = CGPoint(x: first.rect.minX, y: first.rect.midY)
        let end = CGPoint(x: last.rect.maxX, y: last.rect.midY)
        #expect(interaction.mouseDown(at: start, clickCount: 1, extending: false))
        #expect(interaction.mouseDragged(to: end))
        interaction.mouseUp()
        #expect(interaction.controller.selectedBlockIDs.count == 2)
        let anchor = interaction.anchor
        #expect(interaction.mouseDown(at: CGPoint(x: last.rect.midX, y: last.rect.midY), clickCount: 1, extending: true))
        #expect(interaction.anchor == anchor)
    }

    @Test func wordAndParagraphClicksSelectSemanticUnits() throws {
        let interaction = fixture("Alpha beta gamma\n\nDelta epsilon")
        let first = try #require(interaction.fragments.first)
        #expect(interaction.mouseDown(at: CGPoint(x: first.rect.minX + 2, y: first.rect.midY), clickCount: 2, extending: false))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<5)
        interaction.mouseUp()
        #expect(interaction.mouseDown(at: CGPoint(x: first.rect.minX + 2, y: first.rect.midY), clickCount: 3, extending: false))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<16)
        #expect(interaction.controller.selectedBlockIDs.count == 1)
    }

    @Test func mountedEventBridgeConsumesDragReleaseButPreservesContextClick() throws {
        let interaction = fixture("Alpha beta gamma")
        let view = MarkdownDocumentSelectionEventHandler.EventView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        view.interaction = interaction
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.removeMonitor(); window.contentView = nil; window.close() }
        func event(_ type: NSEvent.EventType, x: CGFloat, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(CGPoint(x: x, y: 10), to: nil), modifierFlags: modifiers,
                              timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(view.handle(event(.leftMouseDown, x: 2)) != nil)
        #expect(view.handle(event(.leftMouseDragged, x: 100)) == nil)
        // Even returning over the original link must never activate it.
        #expect(view.handle(event(.leftMouseUp, x: 2)) == nil)
        #expect(!interaction.controller.selectedSourceRanges.isEmpty)
        #expect(view.handle(event(.leftMouseDown, x: 2, modifiers: .control)) != nil)
    }

    @Test func activatedDragCanReturnToItsOriginalCaret() throws {
        let interaction = fixture("Alpha beta gamma")
        let fragment = try #require(interaction.fragments.first)
        let start = CGPoint(x: fragment.rect.minX, y: fragment.rect.midY)
        _ = interaction.mouseDown(at: start, clickCount: 1, extending: false)
        #expect(interaction.mouseDragged(to: CGPoint(x: fragment.rect.maxX, y: start.y)))
        #expect(!interaction.controller.selectedSourceRanges.isEmpty)
        #expect(interaction.mouseDragged(to: start))
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
        #expect(interaction.focus == interaction.anchor)
        interaction.mouseUp()
    }

    @Test func replacingDocumentInvalidatesCollapsedCaretBeforeShiftClick() throws {
        let interaction = fixture("# Previous heading")
        let oldFragment = try #require(interaction.fragments.first)
        _ = interaction.mouseDown(at: CGPoint(x: oldFragment.rect.maxX, y: oldFragment.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.anchor != nil)
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
        let replacement = fixture("New")
        interaction.controller.updateSnapshot(try #require(replacement.snapshot))
        interaction.snapshot = replacement.snapshot
        interaction.fragments = replacement.fragments
        #expect(interaction.anchor == nil)
        #expect(interaction.focus == nil)
        let fragment = try #require(interaction.fragments.first)
        _ = interaction.mouseDown(at: CGPoint(x: fragment.rect.minX, y: fragment.rect.midY), clickCount: 1, extending: true)
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
        #expect(interaction.anchor?.blockID == fragment.blockID)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.shift]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<1)
    }

    @Test func optionArrowsUseDirectionalWordBoundaries() throws {
        let interaction = fixture("Alpha beta gamma")
        let first = try #require(interaction.fragments.first)
        _ = interaction.mouseDown(at: CGPoint(x: first.rect.minX, y: first.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.option]))
        #expect(interaction.focus?.sourceByteOffset == 5)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.option]))
        #expect(interaction.focus?.sourceByteOffset == 10)
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.option]))
        #expect(interaction.focus?.sourceByteOffset == 6)
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.option, .shift]))
        #expect(interaction.focus?.sourceByteOffset == 0)
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<6)
    }

    @Test func escapeCancelsMountedAutoscrollAndPendingDrag() throws {
        let interaction = fixture("Alpha beta gamma")
        let view = MarkdownDocumentSelectionEventHandler.EventView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        view.interaction = interaction
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.removeMonitor(); window.contentView = nil; window.close() }
        func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(CGPoint(x: x, y: 10), to: nil), modifierFlags: [],
                              timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        _ = view.handle(event(.leftMouseDown, x: 2))
        #expect(view.handle(event(.leftMouseDragged, x: 300)) == nil)
        #expect(view.hasActiveAutoscroll)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                                                   charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        #expect(!view.hasActiveAutoscroll)
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
        #expect(view.handle(event(.leftMouseDragged, x: 100)) != nil)
        #expect(!view.hasActiveAutoscroll)
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
        // Cancellation still suppresses release of the leaf's original click.
        #expect(view.handle(event(.leftMouseUp, x: 2)) == nil)
    }

    @Test func mountedNativeMenuActionsSelectAndCopyThroughResponderSelectors() throws {
        @MainActor final class Recorder {
            var payload: MarkdownPasteboardPayload?
        }
        let recorder = Recorder()
        let interaction = fixture("Alpha **beta**")
        let snapshot = try #require(interaction.snapshot)
        let configuration = MarkdownRendererConfiguration()
        let view = MarkdownDocumentSelectionEventHandler.EventView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        view.interaction = interaction
        view.copyContext = MarkdownDocumentSelectionCopyContext(
            selectionController: interaction.controller,
            preparedSnapshot: configuration.prepare(snapshot: snapshot),
            copyProvider: MarkdownCopyProvider(markdownSource: "Alpha **beta**"),
            affordanceActionHandler: MarkdownAffordanceActionHandler(copyPayload: { recorder.payload = $0 })
        )
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.removeMonitor(); window.contentView = nil; window.close() }
        #expect(window.makeFirstResponder(view))
        let copyItem = NSMenuItem(title: "Copy", action: #selector(MarkdownDocumentSelectionEventHandler.EventView.copy(_:)), keyEquivalent: "c")
        let allItem = NSMenuItem(title: "Select All", action: #selector(MarkdownDocumentSelectionEventHandler.EventView.selectAll(_:)), keyEquivalent: "a")
        #expect(!view.validateUserInterfaceItem(copyItem))
        #expect(view.validateUserInterfaceItem(allItem))
        #expect(NSApp.sendAction(try #require(allItem.action), to: window.firstResponder, from: allItem))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<14)
        #expect(interaction.focus?.sourceByteOffset == 14)
        #expect(view.validateUserInterfaceItem(copyItem))
        #expect(NSApp.sendAction(try #require(copyItem.action), to: window.firstResponder, from: copyItem))
        #expect(recorder.payload?.markdown == "Alpha **beta**")
        #expect(recorder.payload?.plainText == "Alpha beta")
        interaction.controller.clearSelection()
        #expect(!view.validateUserInterfaceItem(copyItem))
        #expect(NSApp.sendAction(try #require(copyItem.action), to: window.firstResponder, from: copyItem))
        #expect(recorder.payload?.markdown == "Alpha **beta**")
    }

    private func wrappedFixture(_ source: String, ranges: [Range<Int>]) throws -> MarkdownDocumentSelectionInteraction {
        let interaction = fixture(source)
        let block = try #require(interaction.snapshot?.blocks.first)
        let prepared = try #require(MarkdownRendererConfiguration().prepare(block: block).inlineLayout)
        // Feed the same prepared text through explicit physical line ranges;
        // emergency wrapping may split a word at any grapheme boundary.
        interaction.fragments = try ranges.enumerated().map { index, range in
            let geometry = try #require(MarkdownDocumentSelectionTextGeometry(prepared: prepared, line: InlineLineRange(byteRange: range, width: 80)))
            return MarkdownDocumentSelectionFragment(id: "wrap:\(index)", blockID: block.id,
                sourceRange: MarkdownSourceRange(byteRange: range, lineRange: 1..<2),
                rect: CGRect(x: 0, y: index * 30, width: 80, height: 20), textGeometry: geometry)
        }
        return interaction
    }

    @Test func wrappedCaretKeepsClickedLineForLineAndVerticalCommands() throws {
        let interaction = try wrappedFixture("alphabetical", ranges: [0..<5, 5..<10, 10..<12])
        let second = interaction.fragments[1]
        let start = CGPoint(x: second.rect.minX, y: second.rect.midY)
        _ = interaction.mouseDown(at: start, clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.focus?.sourceByteOffset == 5)
        #expect(interaction.focus?.fragmentID == second.id)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.command, .shift]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 5..<10)
        _ = interaction.mouseDown(at: start, clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.command]))
        #expect(interaction.focus?.sourceByteOffset == 5)
        #expect(interaction.keyDown(keyCode: 125, modifiers: []))
        #expect(interaction.focus?.fragmentID == interaction.fragments[2].id)
        #expect(interaction.focus?.sourceByteOffset == 10)
        #expect(interaction.keyDown(keyCode: 126, modifiers: []))
        #expect(interaction.focus?.fragmentID == second.id)
        #expect(interaction.focus?.sourceByteOffset == 5)
    }

    @Test func doubleClickSelectsWholeWordAcrossEmergencyWraps() throws {
        let interaction = try wrappedFixture("alphabetical", ranges: [0..<5, 5..<10, 10..<12])
        let middle = interaction.fragments[1]
        _ = interaction.mouseDown(at: CGPoint(x: middle.rect.minX + 2, y: middle.rect.midY), clickCount: 2, extending: false)
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<12)
        #expect(interaction.anchor?.fragmentID == interaction.fragments[0].id)
        #expect(interaction.focus?.fragmentID == interaction.fragments[2].id)
    }

    @Test func optionArrowsSkipArtificialWordWrapBoundaries() throws {
        let interaction = try wrappedFixture("alpha beta", ranges: [0..<7, 7..<10])
        let first = interaction.fragments[0]
        _ = interaction.mouseDown(at: CGPoint(x: first.rect.minX, y: first.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.option]))
        #expect(interaction.focus?.sourceByteOffset == 5)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.option, .shift]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 5..<10)
        #expect(interaction.focus?.fragmentID == interaction.fragments[1].id)
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.option]))
        #expect(interaction.focus?.sourceByteOffset == 6)
        #expect(interaction.focus?.fragmentID == first.id)
        let second = interaction.fragments[1]
        _ = interaction.mouseDown(at: CGPoint(x: second.rect.minX + 2, y: second.rect.midY), clickCount: 2, extending: false)
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 6..<10)
    }

    private func visualX(_ interaction: MarkdownDocumentSelectionInteraction) throws -> CGFloat {
        let focus = try #require(interaction.focus)
        let fragment = try #require(interaction.fragments.first { $0.id == focus.fragmentID })
        let geometry = try #require(fragment.textGeometry)
        return geometry.caretX(forSourceByteOffset: focus.sourceByteOffset, secondary: focus.isSecondaryCaret)
    }

    @Test func rtlArrowsAndCommandEdgesMoveInVisualDirections() throws {
        let interaction = fixture("אבגדה")
        let fragment = try #require(interaction.fragments.first)
        let geometry = try #require(fragment.textGeometry)
        let left = try #require(geometry.visualCarets.first?.x)
        let right = try #require(geometry.visualCarets.last?.x)
        #expect(right > left)
        _ = interaction.mouseDown(at: CGPoint(x: fragment.rect.minX + left, y: fragment.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(abs(try visualX(interaction) - left) < 0.01)
        #expect(interaction.keyDown(keyCode: 124, modifiers: []))
        #expect(try visualX(interaction) > left)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.command]))
        #expect(abs(try visualX(interaction) - right) < 0.01)
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.command, .shift]))
        #expect(abs(try visualX(interaction) - left) < 0.01)
        #expect(!interaction.controller.selectedSourceRanges.isEmpty)
        #expect(interaction.keyDown(keyCode: 124, modifiers: []))
        #expect(abs(try visualX(interaction) - right) < 0.01)
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
    }

    @Test func mixedBidiEmojiTraversalUsesShapedCaretPositions() throws {
        let source = "abc אבג 😀 xyz"
        let interaction = fixture(source)
        let fragment = try #require(interaction.fragments.first)
        let geometry = try #require(fragment.textGeometry)
        #expect(geometry.visualCarets.contains { $0.isSecondary })
        var legalOffsets = Set([0])
        var offset = 0
        for character in source { offset += character.utf8.count; legalOffsets.insert(offset) }
        let left = try #require(geometry.visualCarets.first?.x)
        let right = try #require(geometry.visualCarets.last?.x)
        _ = interaction.mouseDown(at: CGPoint(x: fragment.rect.minX + left, y: fragment.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        var previous = try visualX(interaction)
        for _ in 0..<geometry.visualCarets.count {
            #expect(interaction.keyDown(keyCode: 124, modifiers: []))
            let next = try visualX(interaction)
            #expect(legalOffsets.contains(try #require(interaction.focus?.sourceByteOffset)))
            #expect(next >= previous)
            if abs(next - previous) < 0.01 { break }
            previous = next
        }
        #expect(abs(try visualX(interaction) - right) < 0.01)
        for _ in 0..<geometry.visualCarets.count {
            let previous = try visualX(interaction)
            #expect(interaction.keyDown(keyCode: 123, modifiers: []))
            let next = try visualX(interaction)
            #expect(next <= previous)
            if abs(next - previous) < 0.01 { break }
        }
        #expect(abs(try visualX(interaction) - left) < 0.01)
    }

    @Test func rtlWrapCrossingRetainsVisualLineAndWordNavigation() throws {
        let interaction = try wrappedFixture("אבגדהוזח", ranges: [0..<8, 8..<16])
        let first = interaction.fragments[0]
        let second = interaction.fragments[1]
        let geometry = try #require(first.textGeometry)
        let secondGeometry = try #require(second.textGeometry)
        let left = try #require(geometry.visualCarets.first?.x)
        _ = interaction.mouseDown(at: CGPoint(x: first.rect.minX + left, y: first.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.keyDown(keyCode: 123, modifiers: []))
        #expect(interaction.focus?.fragmentID == second.id)
        #expect(abs(try visualX(interaction) - (try #require(secondGeometry.visualCarets.last?.x))) < 0.01)
        #expect(interaction.keyDown(keyCode: 123, modifiers: [.option, .shift]))
        #expect(abs(try visualX(interaction) - (try #require(secondGeometry.visualCarets.first?.x))) < 0.01)
        #expect(!interaction.controller.selectedSourceRanges.isEmpty)
    }

    @Test func keyboardSelectionRespectsGraphemesAndExternalReset() throws {
        let interaction = fixture("😀 alpha beta")
        let first = try #require(interaction.fragments.first)
        _ = interaction.mouseDown(at: CGPoint(x: first.rect.minX, y: first.rect.midY), clickCount: 1, extending: false)
        interaction.mouseUp()
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.shift]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<4)
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.shift, .command]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange.upperBound == 15)
        interaction.controller.clearSelection()
        #expect(interaction.keyDown(keyCode: 124, modifiers: [.shift]))
        #expect(interaction.controller.selectedSourceRanges.first?.byteRange == 0..<4)
        #expect(interaction.keyDown(keyCode: 53, modifiers: []))
        #expect(interaction.controller.selectedSourceRanges.isEmpty)
    }
}
#endif
