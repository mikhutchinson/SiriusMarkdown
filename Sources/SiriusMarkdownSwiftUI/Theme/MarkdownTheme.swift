import SwiftUI

public struct MarkdownTheme: Sendable, Hashable {
    public var paragraphFont: Font
    public var codeFont: Font
    public var headingFont: Font
    public var textColor: Color
    public var secondaryTextColor: Color
    public var codeBackground: Color
    public var quoteAccent: Color
    public var blockSpacing: CGFloat

    public init(
        paragraphFont: Font = .body,
        codeFont: Font = .system(.body, design: .monospaced),
        headingFont: Font = .title3.bold(),
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        codeBackground: Color = Color.gray.opacity(0.12),
        quoteAccent: Color = Color.accentColor.opacity(0.65),
        blockSpacing: CGFloat = 8
    ) {
        self.paragraphFont = paragraphFont
        self.codeFont = codeFont
        self.headingFont = headingFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.codeBackground = codeBackground
        self.quoteAccent = quoteAccent
        self.blockSpacing = blockSpacing
    }

    public static let compactChat = MarkdownTheme(blockSpacing: 6)
    public static let document = MarkdownTheme(blockSpacing: 12)
}
