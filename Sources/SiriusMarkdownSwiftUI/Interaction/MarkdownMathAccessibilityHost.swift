#if os(macOS)
import AppKit
import SwiftUI

struct MarkdownMathAccessibilityHost: NSViewRepresentable {
    let tree: MarkdownMathAccessibilityTree
    func makeNSView(context: Context) -> MarkdownMathAccessibilityHostView { MarkdownMathAccessibilityHostView() }
    func updateNSView(_ view: MarkdownMathAccessibilityHostView, context: Context) { view.update(tree: tree) }
}

final class MarkdownMathAccessibilityHostView: NSView {
    private var tree: MarkdownMathAccessibilityTree?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(tree: MarkdownMathAccessibilityTree) {
        guard self.tree != tree else { return }
        self.tree = tree
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(tree.root.label)
        setAccessibilityChildren(tree.root.children.map { MarkdownMathAccessibilityElement(node: $0, host: self, parent: self) })
    }
}

// These native UI elements are confined to the main thread. Objective-C
// accessibility overrides assert that boundary before accessing actor state.
@MainActor
final class MarkdownMathAccessibilityElement: NSAccessibilityElement {
    private weak var host: NSView?
    private var frameProvider: (() -> NSRect)?
    init(node: MarkdownMathAccessibilityNode, host: NSView, parent: Any, frameProvider: (() -> NSRect)? = nil) {
        self.host = host
        self.frameProvider = frameProvider
        super.init()
        setAccessibilityRole(node.children.isEmpty ? .staticText : .group)
        setAccessibilityLabel(node.label)
        setAccessibilityParent(parent)
        setAccessibilityChildren(node.children.map { MarkdownMathAccessibilityElement(node: $0, host: host, parent: self, frameProvider: frameProvider) })
    }
    nonisolated override func accessibilityFrame() -> NSRect {
        let reference = MarkdownAccessibilityMainThreadReference(value: self)
        return MainActor.assumeIsolated {
            if let frameProvider = reference.value.frameProvider { return frameProvider() }
            guard let host = reference.value.host, let window = host.window else { return .zero }
            return window.convertToScreen(host.convert(host.bounds, to: nil))
        }
    }
}
extension NSAttributedString.Key {
    static let markdownMathAccessibility = NSAttributedString.Key("SiriusMarkdown.mathAccessibility")
}

final class MarkdownMathAccessibilityBox: NSObject, NSCopying {
    let tree: MarkdownMathAccessibilityTree
    init(_ tree: MarkdownMathAccessibilityTree) { self.tree = tree }
    func copy(with zone: NSZone? = nil) -> Any { self }
    override var hash: Int { tree.hashValue }
    override func isEqual(_ object: Any?) -> Bool { (object as? MarkdownMathAccessibilityBox)?.tree == tree }
}
#endif
