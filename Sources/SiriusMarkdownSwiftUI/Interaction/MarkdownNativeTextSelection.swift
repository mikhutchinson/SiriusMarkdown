import SwiftUI

/// Controls whether SiriusMarkdown asks SwiftUI to install native text
/// selection for rendered Markdown text surfaces.
///
/// Regression history: macOS 26 Sirius samples could peg the main thread
/// when SwiftUI's private `SelectionOverlay.updateNSView` path repeatedly
/// invalidated AppKit `NSTextField` font/layout state while `GraphHost`
/// flushed transactions. The default stays `.disabled` as a conservative
/// public-package default. When enabled, SiriusMarkdown applies native
    /// selection only to stable bounded text leaves instead of document, scroll,
    /// stack, custom leading-layout, table-grid, toolbar, Mermaid-control, or
    /// host containers.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. This remains the conservative package default. Copy
    /// affordances and `MarkdownSelectionController` remain available where
    /// configured.
    case disabled
    /// Render Markdown text with native SwiftUI selection enabled on stable
    /// bounded text leaves.
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
            self.textSelection(.enabled)
        }
    }
}
