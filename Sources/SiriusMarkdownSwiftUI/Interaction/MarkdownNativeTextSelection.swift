import SwiftUI

/// Controls whether SiriusMarkdown asks SwiftUI to install native text
/// selection for rendered Markdown.
///
/// Selection is applied at renderer roots, not per paragraph/list
/// item/table cell, so hosts keep selectable text without growing a
/// private SwiftUI selection overlay for every rendered fragment.
public enum MarkdownNativeTextSelection: Sendable, Hashable {
    /// Render Markdown text without SwiftUI's native text-selection
    /// overlay. Copy affordances and `MarkdownSelectionController`
    /// remain available where configured.
    case disabled
    /// Render Markdown text with native SwiftUI selection enabled at
    /// the bounded document or streaming root.
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
