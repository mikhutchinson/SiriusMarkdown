import SwiftUI

/// Controls whether SiriusMarkdown asks SwiftUI to install native text
/// selection for rendered Markdown.
///
/// Known unresolved issue: macOS 26 Sirius samples can peg the main thread
/// when SwiftUI's private `SelectionOverlay.updateNSView` path repeatedly
/// invalidates AppKit `NSTextField` font/layout state while `GraphHost`
/// flushes transactions. The default stays `.disabled` as a mitigation.
/// This switch only controls SwiftUI's explicit native-selection overlay;
/// source-backed copy affordances and any host/AppKit selection behavior
/// outside that overlay are separate.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. This is the default while the `SelectionOverlay` hang
    /// remains unresolved. Copy affordances and
    /// `MarkdownSelectionController` remain available where configured.
    case disabled
    /// Render Markdown text with native SwiftUI selection enabled.
    ///
    /// This remains an explicit host opt-in because macOS 26 samples show
    /// SwiftUI's private `SelectionOverlay` can spin the main thread under
    /// complex renderer trees. If the hang returns, sample the process and
    /// look for `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView`
    /// -> `NSTextField setFont:` / `_invalidateEffectiveFont`.
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
