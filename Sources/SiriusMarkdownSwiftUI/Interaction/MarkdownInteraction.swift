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

    public init(markdownSource: String) {
        let store = MarkdownSourceCopyStore(markdownSource)
        self.markdown = { range in
            store.markdown(in: range)
        }
    }
}

private final class MarkdownSourceCopyStore: @unchecked Sendable {
    private let source: String

    init(_ source: String) {
        self.source = source
    }

    func markdown(in sourceRange: MarkdownSourceRange) -> String? {
        let byteRange = sourceRange.byteRange
        guard byteRange.lowerBound >= 0,
              byteRange.lowerBound <= byteRange.upperBound,
              byteRange.upperBound <= source.utf8.count,
              let lowerUTF8 = source.utf8.index(
                  source.utf8.startIndex,
                  offsetBy: byteRange.lowerBound,
                  limitedBy: source.utf8.endIndex
              ),
              let upperUTF8 = source.utf8.index(
                  source.utf8.startIndex,
                  offsetBy: byteRange.upperBound,
                  limitedBy: source.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: source),
              let upper = String.Index(upperUTF8, within: source)
        else {
            return nil
        }

        return String(source[lower..<upper])
    }
}
