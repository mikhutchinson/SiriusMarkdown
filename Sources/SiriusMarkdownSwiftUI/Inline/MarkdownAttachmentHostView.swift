import SiriusMarkdownCore
import SwiftUI

/// One SwiftUI/AppKit/UIKit host per attachment instance, positioned at
/// prepared CoreText gap rects (Inline Attachments Part 03). Hosts read
/// only already-prepared state (`MarkdownPreparedAttachment`) — no
/// `URLSession` or `CGImageSourceCreate*` call lives here (INV-IA3).
/// Reconciliation keys strictly by `MarkdownAttachmentID` so host count
/// always equals gap count (INV-IA6) and resolving bytes later swaps
/// content inside the same host instead of remounting unrelated
/// attachments.
enum MarkdownAttachmentHostDisplay {
    case data(Data)
    case placeholder(reason: String?)

    init(record: MarkdownPreparedAttachment?) {
        guard let record else {
            self = .placeholder(reason: nil)
            return
        }
        switch record.image.preparedSource {
        case let .data(data, _):
            self = .data(data)
        case let .placeholder(reason):
            self = .placeholder(reason: reason)
        case .localFile, .remote:
            // No local resolver/Async loader has patched bytes onto this
            // slot yet — reserve the box, do not fetch (INV-IA1/IA3).
            self = .placeholder(reason: nil)
        }
    }

    /// Failure/pending reason, when known — distinct from alt text, which
    /// callers should prefer first (§3.2.6).
    var failureReason: String? {
        switch self {
        case .data:
            return nil
        case let .placeholder(reason):
            return reason
        }
    }

    /// "Label = alt if non-empty, else generic / failure reason" (§3.2.6).
    static func accessibilityLabel(altText: String?, display: MarkdownAttachmentHostDisplay) -> String {
        if let altText, !altText.isEmpty {
            return altText
        }
        if let reason = display.failureReason, !reason.isEmpty {
            return reason
        }
        return "Image"
    }
}

#if os(macOS) && canImport(AppKit)
import AppKit

extension MarkdownCoreTextPaintedNSView {
    func reconcileAttachmentHosts() {
        var stillPresent: Set<MarkdownAttachmentID> = []
        for gap in plan.attachmentGaps {
            stillPresent.insert(gap.attachmentID)
            let host: MarkdownAttachmentHostNSView
            if let existing = attachmentHostsByID[gap.attachmentID] {
                host = existing
            } else {
                host = MarkdownAttachmentHostNSView()
                addSubview(host)
                attachmentHostsByID[gap.attachmentID] = host
            }
            host.frame = gap.rect
            host.record = plan.attachments[gap.attachmentID]
        }

        // Snapshot stale IDs into a plain array before mutating the
        // dictionary — do not remove keys while iterating the same
        // stored-property dictionary directly.
        let staleIDs = attachmentHostsByID.keys.filter { !stillPresent.contains($0) }
        for id in staleIDs {
            attachmentHostsByID[id]?.removeFromSuperview()
            attachmentHostsByID.removeValue(forKey: id)
        }
    }
}

final class MarkdownAttachmentHostNSView: NSView {
    var record: MarkdownPreparedAttachment? {
        didSet {
            guard record != oldValue else {
                return
            }
            updateContent()
        }
    }

    private var imageView: NSImageView?
    private var lastRenderedData: Data?
    private var placeholder: MarkdownAttachmentPlaceholderChromeLayer?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Decorative image content should not steal drag-selection or link
    /// clicks from the CoreText surface underneath (§3.2.7) — no "open
    /// image" affordance exists yet in v1, so hit-testing always falls
    /// through to the superview.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func updateContent() {
        let display = MarkdownAttachmentHostDisplay(record: record)
        setAccessibilityLabel(MarkdownAttachmentHostDisplay.accessibilityLabel(altText: record?.image.altText, display: display))

        switch display {
        case let .data(data):
            showImage(data: data)
        case let .placeholder(reason):
            showPlaceholder(reason: reason)
        }
    }

    private func showImage(data: Data) {
        placeholder?.removeFromSuperlayer()
        placeholder = nil

        if imageView == nil {
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            addSubview(view)
            imageView = view
        }
        imageView?.frame = bounds

        guard data != lastRenderedData else {
            return
        }
        lastRenderedData = data
        // `NSImage(data:)` lazily decodes; the plan's host-provider seam
        // (Part 04 §4.3) explicitly allows Sendable `Data` here as long as
        // construction is cheap and bytes are already off-body — this is
        // not a network fetch or a `CGImageSourceCreate*` probe loop.
        imageView?.image = NSImage(data: data)
    }

    private func showPlaceholder(reason: String?) {
        imageView?.removeFromSuperview()
        imageView = nil
        lastRenderedData = nil

        if placeholder == nil {
            let layer = MarkdownAttachmentPlaceholderChromeLayer()
            self.layer?.addSublayer(layer)
            placeholder = layer
        }
        placeholder?.frame = bounds
        placeholder?.apply(style: .default)
    }

    override func layout() {
        super.layout()
        imageView?.frame = bounds
        placeholder?.frame = bounds
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit

extension MarkdownCoreTextPaintedUIView {
    func reconcileAttachmentHosts() {
        var stillPresent: Set<MarkdownAttachmentID> = []
        for gap in plan.attachmentGaps {
            stillPresent.insert(gap.attachmentID)
            let host: MarkdownAttachmentHostUIView
            if let existing = attachmentHostsByID[gap.attachmentID] {
                host = existing
            } else {
                host = MarkdownAttachmentHostUIView()
                addSubview(host)
                attachmentHostsByID[gap.attachmentID] = host
            }
            host.frame = gap.rect
            host.record = plan.attachments[gap.attachmentID]
        }

        // Snapshot stale IDs into a plain array before mutating the
        // dictionary — do not remove keys while iterating the same
        // stored-property dictionary directly.
        let staleIDs = attachmentHostsByID.keys.filter { !stillPresent.contains($0) }
        for id in staleIDs {
            attachmentHostsByID[id]?.removeFromSuperview()
            attachmentHostsByID.removeValue(forKey: id)
        }
    }
}

final class MarkdownAttachmentHostUIView: UIView {
    var record: MarkdownPreparedAttachment? {
        didSet {
            guard record != oldValue else {
                return
            }
            updateContent()
        }
    }

    private var imageView: UIImageView?
    private var lastRenderedData: Data?
    private var placeholder: MarkdownAttachmentPlaceholderChromeLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Decorative image content should not steal drag-selection or
        // link touches from the CoreText surface underneath (§3.2.7).
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func updateContent() {
        let display = MarkdownAttachmentHostDisplay(record: record)
        accessibilityLabel = MarkdownAttachmentHostDisplay.accessibilityLabel(altText: record?.image.altText, display: display)

        switch display {
        case let .data(data):
            showImage(data: data)
        case let .placeholder(reason):
            showPlaceholder(reason: reason)
        }
    }

    private func showImage(data: Data) {
        placeholder?.removeFromSuperlayer()
        placeholder = nil

        if imageView == nil {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            addSubview(view)
            imageView = view
        }
        imageView?.frame = bounds

        guard data != lastRenderedData else {
            return
        }
        lastRenderedData = data
        imageView?.image = UIImage(data: data)
    }

    private func showPlaceholder(reason: String?) {
        imageView?.removeFromSuperview()
        imageView = nil
        lastRenderedData = nil

        if placeholder == nil {
            let chromeLayer = MarkdownAttachmentPlaceholderChromeLayer()
            layer.addSublayer(chromeLayer)
            placeholder = chromeLayer
        }
        placeholder?.frame = bounds
        placeholder?.apply(style: .default)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView?.frame = bounds
        placeholder?.frame = bounds
    }
}
#endif

#if canImport(QuartzCore) && !os(watchOS)
import QuartzCore

/// Quiet reserved-box chrome drawn without any host image/network
/// dependency — a rounded, lightly bordered rect, matching the "reserved
/// box UI" recommendation for denied/pending attachments (Part 03 §3.2.3).
final class MarkdownAttachmentPlaceholderChromeLayer: CALayer {
    func apply(style: MarkdownAttachmentPlaceholderStyle) {
        backgroundColor = style.backgroundColor.resolvedCGColor
        borderColor = style.borderColor.resolvedCGColor
        borderWidth = 1
        cornerRadius = style.cornerRadius
    }
}

private extension Color {
    var resolvedCGColor: CGColor {
        #if os(macOS)
        return NSColor(self).cgColor
        #else
        return UIColor(self).cgColor
        #endif
    }
}
#endif
