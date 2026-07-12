import SwiftUI

/// Controls whether SiriusMarkdown installs native text selection for rendered
/// Markdown text leaves.
///
/// This is a leaf-level compatibility knob. Cross-block document selection,
/// drag highlights, and Cmd-C source copy are owned by
/// `MarkdownRendererConfiguration.documentSelection` and do not require this
/// setting to be enabled.
///
/// On macOS the platform default is `.enabled`, backed by bounded `NSTextView`
/// leaves so selection appearance, keyboard behavior, and contextual commands
/// come from AppKit. Other platforms retain the source-backed document
/// selection default. Hosts can still opt into SiriusMarkdown's cross-block
/// source selector explicitly through
/// `MarkdownRendererConfiguration.documentSelection`.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without native text-selection behavior. Document
    /// selection and `MarkdownSelectionController` remain available through
    /// the separate source-backed document-selection layer.
    case disabled
    /// Render Markdown text with native selection enabled on stable bounded
    /// text leaves.
    case enabled

    /// The platform-appropriate default selection surface.
    public static var platformDefault: Self {
        #if os(macOS)
        .enabled
        #else
        .disabled
        #endif
    }
}

extension View {
    @ViewBuilder
    func markdownNativeTextSelection(_ mode: MarkdownNativeTextSelection) -> some View {
        switch mode {
        case .disabled:
            self
        case .enabled:
            #if os(macOS)
            self
            #elseif os(tvOS) || os(watchOS)
            self
            #else
            self.textSelection(.enabled)
            #endif
        }
    }
}
