#if os(macOS)
import AppKit

/// Bridges a synchronous Objective-C callback into its main-thread UI owner.
/// The value is accessed only inside MainActor.assumeIsolated; this wrapper
/// avoids Swift 6 region inference treating Objective-C self as transferable.
struct MarkdownAccessibilityMainThreadReference<Value: AnyObject>: @unchecked Sendable {
    let value: Value
}

/// One accessibility element per semantic link, including links spanning lines.
/// Geometry stays in the native host's coordinates so scrolling never requires
/// rebuilding the accessibility tree.
// These native UI elements are confined to the main thread. Objective-C
// accessibility overrides assert that boundary before accessing actor state.
@MainActor
final class MarkdownAccessibleLink: NSAccessibilityElement {
    weak var host: MarkdownCoreTextPaintedNSView?
    var localFrame: CGRect
    let destination: String

    init(host: MarkdownCoreTextPaintedNSView, label: String, destination: String, frame: CGRect) {
        self.host = host
        self.localFrame = frame
        self.destination = destination
        super.init()
        setAccessibilityRole(.link)
        setAccessibilityLabel(label)
        setAccessibilityURL(URL(string: destination))
        setAccessibilityParent(host)
    }

    nonisolated override func accessibilityFrame() -> NSRect {
        let reference = MarkdownAccessibilityMainThreadReference(value: self)
        return MainActor.assumeIsolated {
            guard let host = reference.value.host, let window = host.window else { return .zero }
            return window.convertToScreen(host.convert(reference.value.localFrame, to: nil))
        }
    }

    nonisolated override func accessibilityPerformPress() -> Bool {
        let reference = MarkdownAccessibilityMainThreadReference(value: self)
        return MainActor.assumeIsolated {
            guard let host = reference.value.host else { return false }
            host.openAccessibleLink(reference.value.destination)
            return true
        }
    }
}
#endif
