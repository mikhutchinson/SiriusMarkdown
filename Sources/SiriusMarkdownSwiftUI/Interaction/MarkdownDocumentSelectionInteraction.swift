#if os(macOS)
import AppKit
import SwiftUI
import SiriusMarkdownCore

/// One interaction state for the document, independent of the native leaf that
/// happens to receive an AppKit event. Source offsets remain the copy contract.
@MainActor
final class MarkdownDocumentSelectionInteraction {
    let controller: MarkdownSelectionController
    var fragments: [MarkdownDocumentSelectionFragment] = [] {
        didSet { validateEndpoints() }
    }
    var snapshot: MarkdownSnapshot?
    private(set) var anchor: MarkdownDocumentSelectionEndpoint?
    private(set) var focus: MarkdownDocumentSelectionEndpoint?
    private var pointerStart: CGPoint?
    private var dragActivated = false
    private var initialUnit: (MarkdownDocumentSelectionEndpoint, MarkdownDocumentSelectionEndpoint)?
    private var clickCount = 1
    private var preferredX: CGFloat?
    private var publishedRanges: [MarkdownSourceRange] = []

    private func validateEndpoints() {
        let invalidAnchor = anchor.map { fragment(containing: $0) == nil } ?? false
        let invalidFocus = focus.map { fragment(containing: $0) == nil } ?? false
        guard invalidAnchor || invalidFocus else { return }
        anchor = nil
        focus = nil
        preferredX = nil
        mouseUp()
    }

    private func reconcileSelection() {
        guard publishedRanges != controller.selectedSourceRanges else { return }
        let selected = selectedEndpoints()
        anchor = selected?.0
        focus = selected?.1
        publishedRanges = controller.selectedSourceRanges
    }

    init(controller: MarkdownSelectionController) { self.controller = controller }

    @discardableResult
    func mouseDown(at point: CGPoint, clickCount: Int, extending: Bool) -> Bool {
        reconcileSelection()
        guard let fragment = hit(point) else { return false }
        let endpoint = fragment.endpoint(at: point)
        pointerStart = point
        dragActivated = false
        preferredX = nil
        self.clickCount = clickCount
        initialUnit = nil
        if extending {
            anchor = anchor ?? selectedEndpoints()?.0 ?? endpoint
            focus = endpoint
            publish()
        } else if clickCount >= 2 {
            let unit = selectionUnit(at: endpoint, fragment: fragment, paragraph: clickCount >= 3)
            anchor = unit.0
            focus = unit.1
            initialUnit = unit
            publish()
        } else {
            anchor = endpoint
            focus = endpoint
            controller.clearSelection()
            publishedRanges = []
        }
        return true
    }

    @discardableResult
    func mouseDragged(to point: CGPoint) -> Bool {
        guard let start = pointerStart,
              dragActivated || MarkdownDocumentSelectionDragActivation().hasActivated(start: start, current: point),
              let fragment = hit(point), let anchor else { return false }
        dragActivated = true
        let endpoint = fragment.endpoint(at: point)
        if let initialUnit, clickCount >= 2 {
            let unit = selectionUnit(at: endpoint, fragment: fragment, paragraph: clickCount >= 3)
            if endpoint.sourceByteOffset < initialUnit.0.sourceByteOffset {
                self.anchor = initialUnit.1
                focus = unit.0
            } else {
                self.anchor = initialUnit.0
                focus = unit.1
            }
        } else {
            self.anchor = anchor
            focus = endpoint
        }
        publish()
        return true
    }

    func mouseUp() { pointerStart = nil; initialUnit = nil; dragActivated = false }

    func synchronizeSelectAll() {
        guard let first = fragments.first, let last = fragments.last else { return }
        anchor = endpoint(first.sourceRange.byteRange.lowerBound, in: first)
        focus = endpoint(last.sourceRange.byteRange.upperBound, in: last)
        publishedRanges = controller.selectedSourceRanges
    }

    @discardableResult
    func keyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        reconcileSelection()
        guard [123, 124, 125, 126, 115, 119, 53].contains(keyCode) else { return false }
        if keyCode == 53 {
            controller.clearSelection(); anchor = nil; focus = nil; return true
        }
        guard !fragments.isEmpty else { return false }
        let extending = modifiers.contains(.shift)
        let backward = keyCode == 123 || keyCode == 126 || keyCode == 115
        if focus == nil, let selected = selectedEndpoints() {
            anchor = selected.0; focus = selected.1
        }
        if focus == nil, let first = fragments.first {
            focus = endpoint(first.sourceRange.byteRange.lowerBound, in: first)
            anchor = focus
        }
        guard let current = focus else { return false }
        if !extending, !controller.selectedSourceRanges.isEmpty,
           !modifiers.contains(.command), !modifiers.contains(.option),
           keyCode == 123 || keyCode == 124,
           let selected = selectedEndpoints() {
            let endpoints = (anchor ?? selected.0, focus ?? selected.1)
            let ordered = visualPrecedes(endpoints.0, endpoints.1) ? endpoints : (endpoints.1, endpoints.0)
            focus = backward ? ordered.0 : ordered.1
            anchor = focus
            controller.clearSelection()
            publishedRanges = []
            return true
        }
        let destination: MarkdownDocumentSelectionEndpoint
        if keyCode == 115 || keyCode == 119 ||
            (modifiers.contains(.command) && (keyCode == 125 || keyCode == 126)) {
            let fragment = backward ? fragments[0] : fragments[fragments.count - 1]
            destination = endpoint(backward ? fragment.sourceRange.byteRange.lowerBound : fragment.sourceRange.byteRange.upperBound, in: fragment)
        } else if let fragment = fragment(containing: current) {
            if modifiers.contains(.command) {
                destination = visualEdge(in: fragment, left: backward)
            } else if keyCode == 125 || keyCode == 126 {
                let x = preferredX ?? (fragment.rect.minX + (fragment.textGeometry?.caretX(forSourceByteOffset: current.sourceByteOffset, secondary: current.isSecondaryCaret) ?? 0))
                preferredX = x
                let candidates = fragments.filter { backward ? $0.rect.midY < fragment.rect.midY - 1 : $0.rect.midY > fragment.rect.midY + 1 }
                if let row = candidates.min(by: { abs($0.rect.midY - fragment.rect.midY) < abs($1.rect.midY - fragment.rect.midY) }),
                   let target = MarkdownDocumentSelectionFragment.hitFragment(at: CGPoint(x: x, y: row.rect.midY), in: fragments, hitSlop: 4) {
                    destination = target.endpoint(at: CGPoint(x: x, y: target.rect.midY))
                } else {
                    destination = endpoint(backward ? fragment.sourceRange.byteRange.lowerBound : fragment.sourceRange.byteRange.upperBound, in: fragment)
                }
            } else {
                preferredX = nil
                destination = visualHorizontalDestination(from: current, left: backward, byWord: modifiers.contains(.option))
            }
        } else { return false }
        if extending { anchor = anchor ?? current } else { anchor = destination }
        focus = destination
        publish()
        return true
    }

    private func visualPrecedes(_ lhs: MarkdownDocumentSelectionEndpoint, _ rhs: MarkdownDocumentSelectionEndpoint) -> Bool {
        guard let first = fragment(containing: lhs), let second = fragment(containing: rhs) else { return lhs.sourceByteOffset < rhs.sourceByteOffset }
        if abs(first.rect.midY - second.rect.midY) > 1 { return first.rect.midY < second.rect.midY }
        let x1 = first.rect.minX + (first.textGeometry?.caretX(forSourceByteOffset: lhs.sourceByteOffset, secondary: lhs.isSecondaryCaret) ?? 0)
        let x2 = second.rect.minX + (second.textGeometry?.caretX(forSourceByteOffset: rhs.sourceByteOffset, secondary: rhs.isSecondaryCaret) ?? 0)
        return x1 <= x2
    }

    private func visualEndpoint(_ caret: MarkdownDocumentSelectionVisualCaret, in fragment: MarkdownDocumentSelectionFragment) -> MarkdownDocumentSelectionEndpoint {
        var result = endpoint(caret.sourceByteOffset, in: fragment)
        result.isSecondaryCaret = caret.isSecondary
        return result
    }

    private func visualEdge(in fragment: MarkdownDocumentSelectionFragment, left: Bool) -> MarkdownDocumentSelectionEndpoint {
        if let geometry = fragment.textGeometry,
           let caret = left ? geometry.visualCarets.first : geometry.visualCarets.last {
            return visualEndpoint(caret, in: fragment)
        }
        return endpoint(left ? fragment.sourceRange.byteRange.lowerBound : fragment.sourceRange.byteRange.upperBound, in: fragment)
    }

    private func visualHorizontalDestination(from current: MarkdownDocumentSelectionEndpoint, left: Bool, byWord: Bool) -> MarkdownDocumentSelectionEndpoint {
        guard let fragment = fragment(containing: current), let geometry = fragment.textGeometry else {
            return horizontalDestination(from: current, backward: left, byWord: byWord)
        }
        let x = geometry.caretX(forSourceByteOffset: current.sourceByteOffset, secondary: current.isSecondaryCaret)
        let candidates = geometry.visualCarets.filter { left ? $0.x < x - 0.01 : $0.x > x + 0.01 }
        let nearest = candidates.min {
            let d1 = abs($0.x - x), d2 = abs($1.x - x)
            if abs(d1 - d2) > 0.01 { return d1 < d2 }
            return abs($0.sourceByteOffset - current.sourceByteOffset) < abs($1.sourceByteOffset - current.sourceByteOffset)
        }
        if byWord {
            let nextDifferent = candidates.filter { $0.sourceByteOffset != current.sourceByteOffset }.min { abs($0.x - x) < abs($1.x - x) }
            let logicalBackward = nextDifferent.map { $0.sourceByteOffset < current.sourceByteOffset } ?? (left != geometry.isRightToLeft)
            var target = horizontalDestination(from: current, backward: logicalBackward, byWord: true)
            if let targetFragment = self.fragment(containing: target), targetFragment.id == fragment.id,
               let caret = geometry.visualCarets.filter({ $0.sourceByteOffset == target.sourceByteOffset && (left ? $0.x < x : $0.x > x) }).min(by: { abs($0.x - x) < abs($1.x - x) }) {
                target.isSecondaryCaret = caret.isSecondary
            }
            return target
        }
        if let nearest { return visualEndpoint(nearest, in: fragment) }
        // At a visual edge, continue in paragraph reading order across wraps.
        let logicalBackward = left != geometry.isRightToLeft
        if let index = fragments.firstIndex(where: { $0.id == fragment.id }) {
            let adjacent = index + (logicalBackward ? -1 : 1)
            if fragments.indices.contains(adjacent) { return visualEdge(in: fragments[adjacent], left: !left) }
        }
        return current
    }

    private func horizontalDestination(from current: MarkdownDocumentSelectionEndpoint, backward: Bool, byWord: Bool) -> MarkdownDocumentSelectionEndpoint {
        var stops: [MarkdownDocumentSelectionEndpoint] = []
        let ordered = backward ? Array(fragments.reversed()) : fragments
        for fragment in ordered {
            if backward && fragment.sourceRange.byteRange.lowerBound >= current.sourceByteOffset { continue }
            if !backward && fragment.sourceRange.byteRange.upperBound <= current.sourceByteOffset { continue }
            guard let geometry = fragment.textGeometry else {
                stops.append(endpoint(fragment.sourceRange.byteRange.lowerBound, in: fragment))
                stops.append(endpoint(fragment.sourceRange.byteRange.upperBound, in: fragment))
                break
            }
            if byWord {
                var boundaries = [backward ? 0 : geometry.leafText.utf8.count]
                geometry.leafText.enumerateSubstrings(in: geometry.leafText.startIndex..<geometry.leafText.endIndex, options: .byWords) { _, range, _, _ in
                    let boundary = backward ? range.lowerBound : range.upperBound
                    boundaries.append(geometry.leafText[..<boundary].utf8.count)
                }
                let currentVisible = geometry.visibleByteOffset(forSourceByteOffset: current.sourceByteOffset)
                let candidates = boundaries.filter { backward ? $0 < currentVisible : $0 > currentVisible }
                if let nearest = candidates.min(by: { abs($0 - currentVisible) < abs($1 - currentVisible) }) {
                    stops.append(leafEndpoint(atVisibleOffset: nearest, in: fragment, upstream: !backward))
                }
            } else {
                var offsets = [0, geometry.lineText.utf8.count]
                var offset = 0
                for character in geometry.lineText { offset += character.utf8.count; offsets.append(offset) }
                stops.append(contentsOf: offsets.map { endpoint(geometry.sourceByteOffset(forVisibleByteOffset: geometry.visibleByteRange.lowerBound + $0), in: fragment) })
            }
            if stops.contains(where: { backward ? $0.sourceByteOffset < current.sourceByteOffset : $0.sourceByteOffset > current.sourceByteOffset }) { break }
        }
        let candidates = stops.filter { backward ? $0.sourceByteOffset < current.sourceByteOffset : $0.sourceByteOffset > current.sourceByteOffset }
        return candidates.min { abs($0.sourceByteOffset - current.sourceByteOffset) < abs($1.sourceByteOffset - current.sourceByteOffset) } ?? current
    }

    private func selectionUnit(at endpoint: MarkdownDocumentSelectionEndpoint, fragment: MarkdownDocumentSelectionFragment, paragraph: Bool) -> (MarkdownDocumentSelectionEndpoint, MarkdownDocumentSelectionEndpoint) {
        if paragraph {
            let range = fragment.textGeometry?.leafSourceByteRange ?? fragment.sourceRange.byteRange
            return (self.endpoint(range.lowerBound, in: fragment), self.endpoint(range.upperBound, in: fragment))
        }
        guard let geometry = fragment.textGeometry, !geometry.lineText.isEmpty else {
            return (self.endpoint(fragment.sourceRange.byteRange.lowerBound, in: fragment), self.endpoint(fragment.sourceRange.byteRange.upperBound, in: fragment))
        }
        let text = geometry.leafText
        let local = min(max(0, geometry.visibleByteOffset(forSourceByteOffset: endpoint.sourceByteOffset)), text.utf8.count - 1)
        var selected: Range<String.Index>?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, stop in
            let lower = text[..<range.lowerBound].utf8.count
            let upper = text[..<range.upperBound].utf8.count
            if lower <= local && local < upper { selected = range; stop = true }
        }
        if selected == nil {
            var cursor = text.startIndex
            while cursor < text.endIndex {
                let next = text.index(after: cursor)
                if text[..<next].utf8.count > local { selected = cursor..<next; break }
                cursor = next
            }
        }
        guard let range = selected else { return (endpoint, endpoint) }
        let lower = text[..<range.lowerBound].utf8.count
        let upper = text[..<range.upperBound].utf8.count
        return (leafEndpoint(atVisibleOffset: lower, in: fragment, upstream: false), leafEndpoint(atVisibleOffset: upper, in: fragment, upstream: true))
    }

    private func hit(_ point: CGPoint) -> MarkdownDocumentSelectionFragment? {
        MarkdownDocumentSelectionFragment.hitFragment(at: point, in: fragments, hitSlop: 4)
    }
    private func fragment(containing endpoint: MarkdownDocumentSelectionEndpoint) -> MarkdownDocumentSelectionFragment? {
        let candidates = fragments.filter { $0.blockID == endpoint.blockID && $0.sourceRange.byteRange.lowerBound <= endpoint.sourceByteOffset && endpoint.sourceByteOffset <= $0.sourceRange.byteRange.upperBound }
        return candidates.first { $0.id == endpoint.fragmentID } ?? candidates.first
    }

    private func leafEndpoint(atVisibleOffset offset: Int, in fragment: MarkdownDocumentSelectionFragment, upstream: Bool) -> MarkdownDocumentSelectionEndpoint {
        guard let geometry = fragment.textGeometry else { return endpoint(offset, in: fragment) }
        let candidates = fragments.filter {
            guard $0.blockID == fragment.blockID, let candidate = $0.textGeometry else { return false }
            return candidate.leafSourceByteRange == geometry.leafSourceByteRange &&
                candidate.visibleByteRange.lowerBound <= offset && offset <= candidate.visibleByteRange.upperBound
        }
        let target = (upstream ? candidates.first : candidates.last) ?? fragment
        let sourceOffset = target.textGeometry?.sourceByteOffset(forVisibleByteOffset: offset) ?? offset
        return endpoint(sourceOffset, in: target)
    }
    private func endpoint(_ offset: Int, in fragment: MarkdownDocumentSelectionFragment) -> MarkdownDocumentSelectionEndpoint {
        .init(blockID: fragment.blockID, sourceByteOffset: offset, line: fragment.sourceRange.lineRange.lowerBound, fragmentID: fragment.id)
    }
    private func selectedEndpoints() -> (MarkdownDocumentSelectionEndpoint, MarkdownDocumentSelectionEndpoint)? {
        guard let lower = controller.selectedSourceRanges.map(\.byteRange.lowerBound).min(),
              let upper = controller.selectedSourceRanges.map(\.byteRange.upperBound).max(),
              let first = fragments.first(where: { $0.sourceRange.byteRange.upperBound > lower }),
              let last = fragments.last(where: { $0.sourceRange.byteRange.lowerBound < upper }) else { return nil }
        return (endpoint(lower, in: first), endpoint(upper, in: last))
    }
    private func publish() {
        guard let anchor, let focus else { return }
        if anchor.blockID == focus.blockID,
           let block = snapshot?.blocks.first(where: { $0.id == anchor.blockID }),
           block.kind == .codeBlock || block.kind == .table {
            controller.activateContext(.scrollableRegion(.init(blockID: block.id, role: block.kind == .table ? .table : .codeBlock)))
        } else { controller.activateContext(.document) }
        let selection = MarkdownDocumentSelectionFragment.selection(from: anchor, to: focus, in: fragments)
        controller.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
        publishedRanges = controller.selectedSourceRanges
    }
}

struct MarkdownDocumentSelectionEventHandler: NSViewRepresentable {
    var fragments: [MarkdownDocumentSelectionFragment]
    var copyContext: MarkdownDocumentSelectionCopyContext

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        view.interaction = MarkdownDocumentSelectionInteraction(controller: copyContext.selectionController)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: EventView, context: Context) {
        view.copyContext = copyContext
        view.interaction?.fragments = fragments
        view.interaction?.snapshot = copyContext.preparedSnapshot.snapshot
    }
    static func dismantleNSView(_ view: EventView, coordinator: ()) { view.removeMonitor() }

    final class EventView: NSView, NSUserInterfaceValidations {
        var interaction: MarkdownDocumentSelectionInteraction?
        var copyContext: MarkdownDocumentSelectionCopyContext?
        private var monitor: Any?
        private var tracking = false
        private var consumedDrag = false
        private var autoscrollTimer: Timer?
        private var dragEvent: NSEvent?
        var hasActiveAutoscroll: Bool { autoscrollTimer?.isValid == true }
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }
        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            cancelGesture()
        }
        private func cancelGesture() {
            tracking = false
            interaction?.mouseUp()
            autoscrollTimer?.invalidate(); autoscrollTimer = nil; dragEvent = nil
        }
        /// Shared by the installed monitor and mounted event regressions.
        func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                guard visibleRect.contains(point), !event.modifierFlags.contains(.control) else { return event }
                if let hit = window.contentView?.hitTest(window.contentView!.convert(event.locationInWindow, from: nil)) {
                    var current: NSView? = hit
                    while let view = current {
                        if view is NSControl || (view as? NSTextView)?.isSelectable == true { return event }
                        current = view.superview
                    }
                }
                consumedDrag = false
                tracking = interaction?.mouseDown(at: point, clickCount: event.clickCount, extending: event.modifierFlags.contains(.shift)) == true
                if tracking { window.makeFirstResponder(self) }
                return tracking && (event.clickCount >= 2 || event.modifierFlags.contains(.shift)) ? nil : event
            case .leftMouseDragged:
                guard tracking else { return event }
                if interaction?.mouseDragged(to: point) == true {
                    window.makeFirstResponder(self)
                    consumedDrag = true
                    dragEvent = event
                    autoscroll(with: event)
                    if autoscrollTimer == nil {
                        autoscrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                            MainActor.assumeIsolated {
                                guard let self, let event = self.dragEvent else { return }
                                self.autoscroll(with: event)
                                _ = self.interaction?.mouseDragged(to: self.convert(event.locationInWindow, from: nil))
                            }
                        }
                    }
                    return nil
                }
            case .leftMouseUp:
                autoscrollTimer?.invalidate(); autoscrollTimer = nil; dragEvent = nil
                if tracking { interaction?.mouseUp(); tracking = false }
                if consumedDrag { consumedDrag = false; return nil }
            default: break
            }
            return event
        }
        @objc func copy(_ sender: Any?) {
            copyContext?.copySelection()
        }

        override func selectAll(_ sender: Any?) {
            copyContext?.selectAll()
            interaction?.synchronizeSelectAll()
        }

        func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(copy(_:)) {
                guard let controller = copyContext?.selectionController else { return false }
                return !controller.selectedSourceRanges.isEmpty || !controller.selectedBlockIDs.isEmpty
            }
            if item.action == #selector(selectAll(_:)) {
                return copyContext?.preparedSnapshot.snapshot.blocks.isEmpty == false
            }
            return false
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { cancelGesture() }
            if event.modifierFlags.contains(.command), let character = event.charactersIgnoringModifiers?.lowercased() {
                if character == "c" { copy(nil); return }
                if character == "a" { selectAll(nil); return }
            }
            if interaction?.keyDown(keyCode: event.keyCode, modifiers: event.modifierFlags) == true { return }
            super.keyDown(with: event)
        }
    }
}
#endif
