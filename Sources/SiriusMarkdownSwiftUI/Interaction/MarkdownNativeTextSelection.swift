import SwiftUI

/// Controls whether SiriusMarkdown installs native text selection for rendered
/// Markdown text leaves.
///
/// This is a leaf-level compatibility knob. Cross-block document selection,
/// drag highlights, and Cmd-C source copy are owned by
/// `MarkdownRendererConfiguration.documentSelection` and do not require this
/// setting to be enabled.
///
/// The default is `.disabled`: the package's source-backed document selection
/// layer (`MarkdownSelectionController`) provides cross-block drag selection,
/// highlight overlays, and Cmd-C source copy without requiring SwiftUI's
/// native text-selection overlay. When enabled, native platform text selection
/// is installed on stable bounded text leaves for hosts that prefer platform
/// selection behavior.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. This is the leaf-selection default. Document selection
    /// and `MarkdownSelectionController` remain available through the
    /// separate document-selection layer.
    case disabled
    /// Render Markdown text with native selection enabled on stable bounded
    /// text leaves.
    case enabled
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
