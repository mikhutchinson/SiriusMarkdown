import Foundation

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if os(macOS)
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
typealias PlatformImage = UIImage
#endif

/// Multi-representation pasteboard payload.
///
/// A single copy operation can carry plain text, exact Markdown source, and optionally
/// derived RTF or HTML. Receivers pick the richest representation they support.
///
/// - `plainText`: visible text suitable for plain-text editors and Notes/Mail (written to
///   the standard string pasteboard type).
/// - `markdown`: exact Markdown source (written to `MarkdownPasteboard.markdownPasteboardType`).
/// - `rtf` / `html`: optional pre-derived rich representations; must not be produced via
///   network fetch or WebKit (INV-NS5).
public struct MarkdownPasteboardPayload: Sendable, Hashable {
    public var plainText: String
    public var markdown: String
    public var rtf: Data?
    public var html: Data?

    public init(
        plainText: String,
        markdown: String,
        rtf: Data? = nil,
        html: Data? = nil
    ) {
        self.plainText = plainText
        self.markdown = markdown
        self.rtf = rtf
        self.html = html
    }
}

public enum MarkdownPasteboard {
    /// The pasteboard type written for exact Markdown source.
    ///
    /// Hosts that previously assumed `.string` carried Markdown source must now read
    /// this type. The `.string` type carries human-readable plain text.
    public static let markdownPasteboardType: String = "net.siriusmarkdown.markdown"

    /// Writes a multi-representation payload to the system pasteboard.
    ///
    /// macOS: writes one `NSPasteboardItem` with `.string` = `plainText`,
    /// `net.siriusmarkdown.markdown` = `markdown`, and `.rtf` / `.html` when present.
    /// iOS/iPadOS: plain text goes to `UIPasteboard.string`; Markdown to an item with
    /// the custom type (best-effort; `UIPasteboard` has limited multi-type support).
    @MainActor
    public static func copy(_ payload: MarkdownPasteboardPayload) {
        #if os(macOS)
        let item = NSPasteboardItem()
        item.setString(payload.plainText, forType: .string)
        if let data = payload.markdown.data(using: .utf8) {
            item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: markdownPasteboardType))
        }
        if let rtf = payload.rtf {
            item.setData(rtf, forType: .rtf)
        }
        if let html = payload.html {
            item.setData(html, forType: .html)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        #elseif canImport(UIKit) && !os(tvOS) && !os(watchOS)
        // "public.utf8-plain-text" is the correct UTI for UTF-8 text items.
        // UIPasteboard accepts String values directly for this type.
        UIPasteboard.general.items = [
            [
                "public.utf8-plain-text": payload.plainText,
                markdownPasteboardType: payload.markdown,
            ]
        ]
        #endif
    }

    /// Convenience: writes a single string as both plain text and Markdown (they are equal).
    ///
    /// This preserves backward-compatibility for call sites that only have one string.
    @MainActor
    public static func copy(_ string: String) {
        copy(MarkdownPasteboardPayload(plainText: string, markdown: string))
    }
}

public enum MarkdownDocumentExporter {
    @MainActor
    public static func export(_ payload: MarkdownExportPayload) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = payload.suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        try? payload.markdown.write(to: url, atomically: true, encoding: .utf8)
        #else
        MarkdownPasteboard.copy(payload.markdown)
        #endif
    }
}

public enum MarkdownURLOpener {
    @MainActor
    public static func open(_ destination: String) {
        guard let url = URL(string: destination) else {
            return
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit) && !os(watchOS)
        UIApplication.shared.open(url)
        #endif
    }
}
