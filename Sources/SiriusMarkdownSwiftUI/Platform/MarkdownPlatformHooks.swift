import Foundation

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum MarkdownPasteboard {
    @MainActor
    public static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
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
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}
