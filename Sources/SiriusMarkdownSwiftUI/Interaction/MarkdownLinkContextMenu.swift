#if os(macOS)
import AppKit

/// A native menu for an already policy-approved, prepared link. The menu owns
/// its actions, so a delayed click cannot accidentally use another link's URL.
@MainActor
final class MarkdownLinkContextMenu: NSMenu {
    private var openLink: (@MainActor () -> Void)?
    private var copyLink: (@MainActor () -> Void)?

    init(destination: String, linkAction: MarkdownLinkAction?, pasteboard: NSPasteboard = .general) {
        super.init(title: "Link")
        autoenablesItems = false
        openLink = {
            if let linkAction {
                linkAction.open(destination)
            } else {
                MarkdownURLOpener.open(destination)
            }
        }
        copyLink = {
            let item = NSPasteboardItem()
            item.setString(destination, forType: .string)
            if URL(string: destination)?.scheme != nil {
                item.setString(destination, forType: .URL)
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
        }
        let open = addItem(withTitle: "Open Link", action: #selector(openDestination(_:)), keyEquivalent: "")
        open.target = self
        let copy = addItem(withTitle: "Copy Link Address", action: #selector(copyDestination(_:)), keyEquivalent: "")
        copy.target = self
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func openDestination(_ sender: Any?) { openLink?() }
    @objc private func copyDestination(_ sender: Any?) { copyLink?() }
}
#endif
