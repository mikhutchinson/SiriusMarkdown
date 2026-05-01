import SiriusMarkdownCore
import SwiftUI

public struct MarkdownCopyPayload: Sendable, Hashable {
    public var markdown: String
    public var sourceRange: MarkdownSourceRange

    public init(markdown: String, sourceRange: MarkdownSourceRange) {
        self.markdown = markdown
        self.sourceRange = sourceRange
    }
}

public struct MarkdownLinkAction: Sendable {
    public var open: @Sendable (String) -> Void

    public init(open: @escaping @Sendable (String) -> Void) {
        self.open = open
    }
}

public struct MarkdownCopyProvider: Sendable {
    public var markdown: @Sendable (MarkdownSourceRange) -> String?

    public init(markdown: @escaping @Sendable (MarkdownSourceRange) -> String?) {
        self.markdown = markdown
    }
}
