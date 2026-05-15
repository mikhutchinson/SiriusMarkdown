import SwiftUI

/// Controls whether SiriusMarkdown installs native text selection for rendered
/// Markdown text leaves.
///
/// This is a leaf-level compatibility knob. Cross-block document selection,
/// drag highlights, and Cmd-C source copy are owned by
/// `MarkdownRendererConfiguration.documentSelection` and do not require this
/// setting to be enabled.
///
/// Regression history: macOS 26 Sirius samples could peg the main thread
/// when SwiftUI's private `SelectionOverlay.updateNSView` path repeatedly
/// invalidated AppKit `NSTextField` font/layout state while `GraphHost`
/// flushed transactions. The default stays `.disabled` as a conservative
/// public-package default. When enabled on macOS, SiriusMarkdown uses
/// package-owned AppKit selectable text leaves so SwiftUI's private
/// SelectionOverlay is not mounted during host view transitions. On other
/// Apple platforms, the helper can still use SwiftUI's native selection
/// modifier on stable bounded text leaves instead of document, scroll, stack,
/// custom leading-layout, table-grid, toolbar, Mermaid-control, or host
/// containers.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. This remains the conservative leaf-selection default.
    /// Document selection and `MarkdownSelectionController` remain available
    /// through the separate document-selection layer.
    case disabled
    /// Render Markdown text with native selection enabled on stable bounded
    /// text leaves.
    ///
    /// If a selection regression returns, sample the process and look for
    /// `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` ->
    /// `NSTextField setFont:` / `_invalidateEffectiveFont`.
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
            #else
            self.textSelection(.enabled)
            #endif
        }
    }
}
