import SiriusMarkdownCore
import SwiftUI

/// GitHub-inspired unordered marker: a hierarchical bullet glyph that
/// cycles disc → circle → square as `indentationLevel` increases,
/// matching GitHub's nested unordered-list rendering (Part 03 §3.3.2).
/// Ordered markers are not customized (`"N."` is structurally the same as
/// the default per Part 03 §3.3.2), so there is no `MarkdownGitHubOrderedListMarkerStyle`.
public struct MarkdownGitHubUnorderedListMarkerStyle: MarkdownUnorderedListMarkerStyle {
    static let width: CGFloat = 28

    public init() {}

    public var markerWidth: CGFloat? { Self.width }

    public func makeBody(configuration: Configuration) -> some View {
        Text(Self.glyph(for: configuration.indentationLevel))
            .font(configuration.theme.codeFont)
            .foregroundStyle(configuration.theme.secondaryTextColor)
            .frame(width: Self.width, alignment: .trailing)
    }

    /// `internal` (not `private`) so `@testable import` can assert the
    /// disc → circle → square cycle directly, without reflecting into
    /// `Text`'s private storage (Part 06 §6.2.5 `gitHubUnorderedMarkersAreHierarchical`).
    static func glyph(for indentationLevel: Int) -> String {
        switch ((indentationLevel % 3) + 3) % 3 {
        case 0:
            return "•"
        case 1:
            return "◦"
        default:
            return "▪"
        }
    }
}

extension MarkdownUnorderedListMarkerStyle where Self == MarkdownGitHubUnorderedListMarkerStyle {
    public static var gitHub: Self { .init() }
}
