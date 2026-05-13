import SwiftUI

/// Controls whether SiriusMarkdown asks SwiftUI to install native text
/// selection for rendered Markdown.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. Copy affordances and `MarkdownSelectionController`
    /// remain available where configured.
    case disabled
    /// Render Markdown text with native SwiftUI selection enabled.
    ///
    /// This remains an explicit host opt-in because macOS 26 samples
    /// show SwiftUI's private `SelectionOverlay` can spin the main
    /// thread under complex renderer trees.
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
