import SwiftUI

/// Reuses a leaf's already-published selection geometry. A marker exists only
/// for the active result, inside the scrollable content that owns that leaf.
struct MarkdownLeafSourceRevealMarker: View {
    let fragments: [MarkdownDocumentSelectionFragment]
    let origin: CGPoint
    @Environment(\.markdownDocumentRevealRequest) private var request

    var body: some View {
        if let request, let highlight = request.highlight(in: fragments) {
            MarkdownHostScrollRevealMarker(requestID: request.id)
                .frame(width: 1, height: 1)
                .position(x: highlight.rect.midX - origin.x, y: highlight.rect.midY - origin.y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}


#if os(macOS)
import AppKit

/// Only the active source match mounts this marker. Its native ancestor chain
/// reaches the host scroller without introducing another scroll view.
struct MarkdownHostScrollRevealMarker: NSViewRepresentable {
    let requestID: UUID
    func makeNSView(context: Context) -> MarkdownHostScrollRevealView { .init() }
    func updateNSView(_ view: MarkdownHostScrollRevealView, context: Context) { view.request(requestID) }
}

final class MarkdownHostScrollRevealView: NSView {
    private var requestID: UUID?
    private var completedID: UUID?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
    func request(_ id: UUID) { requestID = id; schedule() }
    private func schedule() {
        guard let id = requestID, id != completedID else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.requestID == id, self.completedID != id else { return }
            var ancestor = self.superview
            var revealed = false
            while let view = ancestor {
                if let scroll = view as? NSScrollView, let document = scroll.documentView {
                    let rect = self.convert(self.bounds, to: document)
                    let clip = scroll.contentView
                    let target = NSPoint(
                        x: min(max(document.bounds.minX, rect.midX - clip.bounds.width / 2), max(document.bounds.minX, document.bounds.maxX - clip.bounds.width)),
                        y: min(max(document.bounds.minY, rect.midY - clip.bounds.height / 2), max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)))
                    clip.scroll(to: target)
                    scroll.reflectScrolledClipView(clip)
                    revealed = true
                }
                ancestor = view.superview
            }
            if revealed { self.completedID = id }
        }
    }
}
#elseif os(iOS) || os(visionOS) || os(tvOS)
import UIKit
struct MarkdownHostScrollRevealMarker: UIViewRepresentable {
    let requestID: UUID
    func makeUIView(context: Context) -> MarkdownHostScrollRevealView { .init() }
    func updateUIView(_ view: MarkdownHostScrollRevealView, context: Context) { view.request(requestID) }
}
final class MarkdownHostScrollRevealView: UIView {
    private var requestID: UUID?
    private var completedID: UUID?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func didMoveToWindow() { super.didMoveToWindow(); schedule() }
    func request(_ id: UUID) { requestID = id; schedule() }
    private func schedule() {
        guard let id = requestID, id != completedID else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.requestID == id, self.completedID != id else { return }
            var ancestor = self.superview
            var revealed = false
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    scroll.scrollRectToVisible(self.convert(self.bounds, to: scroll), animated: false)
                    revealed = true
                }
                ancestor = view.superview
            }
            if revealed { self.completedID = id }
        }
    }
}
#else
struct MarkdownHostScrollRevealMarker: View {
    let requestID: UUID
    var body: some View { Color.clear }
}
#endif
