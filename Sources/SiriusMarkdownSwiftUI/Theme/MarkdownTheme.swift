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
    public var paragraphFontSize: Double
    public var paragraphLineHeight: Double
    public var headingFontSize: Double
    public var headingLineHeight: Double
    public var codeFontSize: Double
    public var codeLineHeight: Double

    public init(
        paragraphFont: Font = .body,
        codeFont: Font = .system(.body, design: .monospaced),
        headingFont: Font = .title3.bold(),
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        codeBackground: Color = Color.gray.opacity(0.12),
        quoteAccent: Color = Color.accentColor.opacity(0.65),
        blockSpacing: CGFloat = 8,
        paragraphFontSize: Double = 16,
        paragraphLineHeight: Double = 22,
        headingFontSize: Double = 20,
        headingLineHeight: Double = 28,
        codeFontSize: Double = 14,
        codeLineHeight: Double = 20
    ) {
        self.paragraphFont = paragraphFont
        self.codeFont = codeFont
        self.headingFont = headingFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.codeBackground = codeBackground
        self.quoteAccent = quoteAccent
        self.blockSpacing = blockSpacing
        self.paragraphFontSize = paragraphFontSize
        self.paragraphLineHeight = paragraphLineHeight
        self.headingFontSize = headingFontSize
        self.headingLineHeight = headingLineHeight
        self.codeFontSize = codeFontSize
        self.codeLineHeight = codeLineHeight
    }

    public static let compactChat = MarkdownTheme(blockSpacing: 6)
    public static let document = MarkdownTheme(blockSpacing: 12)
}
