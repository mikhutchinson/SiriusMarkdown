import SwiftUI
import SiriusMarkdownCore

public struct MarkdownTextStyle: Sendable, Hashable {
    public var font: Font
    public var fontSize: Double
    public var lineHeight: Double
    public var fontProfiles: MarkdownInlineFontProfiles

    public init(
        font: Font,
        fontSize: Double,
        lineHeight: Double,
        fontProfiles: MarkdownInlineFontProfiles
    ) {
        self.font = font
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontProfiles = fontProfiles
    }
}

public struct MarkdownHeadingStyles: Sendable, Hashable {
    public var h1: MarkdownTextStyle
    public var h2: MarkdownTextStyle
    public var h3: MarkdownTextStyle
    public var h4: MarkdownTextStyle
    public var h5: MarkdownTextStyle
    public var h6: MarkdownTextStyle

    public init(
        h1: MarkdownTextStyle,
        h2: MarkdownTextStyle,
        h3: MarkdownTextStyle,
        h4: MarkdownTextStyle,
        h5: MarkdownTextStyle,
        h6: MarkdownTextStyle
    ) {
        self.h1 = h1
        self.h2 = h2
        self.h3 = h3
        self.h4 = h4
        self.h5 = h5
        self.h6 = h6
    }

    public subscript(level: Int) -> MarkdownTextStyle {
        get {
            switch level {
            case 1:
                return h1
            case 2:
                return h2
            case 3:
                return h3
            case 4:
                return h4
            case 5:
                return h5
            case 6:
                return h6
            default:
                return h3
            }
        }
        set {
            switch level {
            case 1:
                h1 = newValue
            case 2:
                h2 = newValue
            case 3:
                h3 = newValue
            case 4:
                h4 = newValue
            case 5:
                h5 = newValue
            case 6:
                h6 = newValue
            default:
                h3 = newValue
            }
        }
    }

    public func style(for level: Int?) -> MarkdownTextStyle {
        self[level ?? 3]
    }

    public static func uniform(_ style: MarkdownTextStyle) -> MarkdownHeadingStyles {
        MarkdownHeadingStyles(
            h1: style,
            h2: style,
            h3: style,
            h4: style,
            h5: style,
            h6: style
        )
    }

    public static var standard: MarkdownHeadingStyles {
        MarkdownHeadingStyles(
            h1: MarkdownTextStyle(
                font: .system(size: 34, weight: .bold),
                fontSize: 34,
                lineHeight: 42,
                fontProfiles: .headingDefault
            ),
            h2: MarkdownTextStyle(
                font: .system(size: 28, weight: .bold),
                fontSize: 28,
                lineHeight: 36,
                fontProfiles: .headingDefault
            ),
            h3: MarkdownTextStyle(
                font: .system(size: 20, weight: .bold),
                fontSize: 20,
                lineHeight: 28,
                fontProfiles: .headingDefault
            ),
            h4: MarkdownTextStyle(
                font: .system(size: 18, weight: .bold),
                fontSize: 18,
                lineHeight: 24,
                fontProfiles: .headingDefault
            ),
            h5: MarkdownTextStyle(
                font: .system(size: 16, weight: .bold),
                fontSize: 16,
                lineHeight: 22,
                fontProfiles: .headingDefault
            ),
            h6: MarkdownTextStyle(
                font: .system(size: 14, weight: .bold),
                fontSize: 14,
                lineHeight: 20,
                fontProfiles: .headingDefault
            )
        )
    }

    public static func standard(h3: MarkdownTextStyle) -> MarkdownHeadingStyles {
        var styles = standard
        styles.h3 = h3
        return styles
    }
}

public struct MarkdownCodeBlockAffordances: Sendable, Hashable {
    public var showsLanguageLabel: Bool
    public var showsCopyButton: Bool
    public var showsExportButton: Bool
    public var showsCollapseButton: Bool
    public var startsCollapsed: Bool

    public init(
        showsLanguageLabel: Bool = true,
        showsCopyButton: Bool = true,
        showsExportButton: Bool = true,
        showsCollapseButton: Bool = true,
        startsCollapsed: Bool = false
    ) {
        self.showsLanguageLabel = showsLanguageLabel
        self.showsCopyButton = showsCopyButton
        self.showsExportButton = showsExportButton
        self.showsCollapseButton = showsCollapseButton
        self.startsCollapsed = startsCollapsed
    }

    public static let `default` = MarkdownCodeBlockAffordances()
    public static let hidden = MarkdownCodeBlockAffordances(
        showsLanguageLabel: false,
        showsCopyButton: false,
        showsExportButton: false,
        showsCollapseButton: false,
        startsCollapsed: false
    )
}

public struct MarkdownDocumentAffordances: Sendable, Hashable {
    public var showsCopyButton: Bool
    public var showsExportButton: Bool
    public var showsCollapseButton: Bool
    public var startsCollapsed: Bool

    public init(
        showsCopyButton: Bool = true,
        showsExportButton: Bool = true,
        showsCollapseButton: Bool = true,
        startsCollapsed: Bool = false
    ) {
        self.showsCopyButton = showsCopyButton
        self.showsExportButton = showsExportButton
        self.showsCollapseButton = showsCollapseButton
        self.startsCollapsed = startsCollapsed
    }

    public static let `default` = MarkdownDocumentAffordances()
    public static let hidden = MarkdownDocumentAffordances(
        showsCopyButton: false,
        showsExportButton: false,
        showsCollapseButton: false,
        startsCollapsed: false
    )
}

public struct MarkdownTheme: Sendable, Hashable {
    public var paragraphFont: Font
    public var codeFont: Font
    public var headings: MarkdownHeadingStyles
    public var textColor: Color
    public var secondaryTextColor: Color
    public var codeBackground: Color
    public var quoteAccent: Color
    public var tableBackground: Color
    public var tableHeaderBackground: Color
    public var tableAlternateRowBackground: Color
    public var tableBorderColor: Color
    public var tableAccentColor: Color
    public var tableCornerRadius: CGFloat
    public var tableHorizontalCellPadding: CGFloat
    public var tableVerticalCellPadding: CGFloat
    public var blockSpacing: CGFloat
    public var paragraphFontSize: Double
    public var paragraphLineHeight: Double
    public var codeFontSize: Double
    public var codeLineHeight: Double
    public var paragraphFontProfiles: MarkdownInlineFontProfiles
    public var codeFontProfiles: MarkdownInlineFontProfiles
    public var syntaxHighlightingPalette: MarkdownSyntaxHighlightingPalette
    public var codeBlockAffordances: MarkdownCodeBlockAffordances

    @available(*, deprecated, message: "Use headings.h3.font or MarkdownTheme.headings for per-level heading typography.")
    public var headingFont: Font {
        get { headings.h3.font }
        set { headings.h3.font = newValue }
    }

    @available(*, deprecated, message: "Use headings.h3.fontSize or MarkdownTheme.headings for per-level heading typography.")
    public var headingFontSize: Double {
        get { headings.h3.fontSize }
        set { headings.h3.fontSize = newValue }
    }

    @available(*, deprecated, message: "Use headings.h3.lineHeight or MarkdownTheme.headings for per-level heading typography.")
    public var headingLineHeight: Double {
        get { headings.h3.lineHeight }
        set { headings.h3.lineHeight = newValue }
    }

    @available(*, deprecated, message: "Use headings.h3.fontProfiles or MarkdownTheme.headings for per-level heading typography.")
    public var headingFontProfiles: MarkdownInlineFontProfiles {
        get { headings.h3.fontProfiles }
        set { headings.h3.fontProfiles = newValue }
    }

    public init(
        paragraphFont: Font = .body,
        codeFont: Font = .system(.body, design: .monospaced),
        headingFont: Font = .title3.bold(),
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        codeBackground: Color = Color.gray.opacity(0.12),
        quoteAccent: Color = Color.accentColor.opacity(0.65),
        tableBackground: Color = Color.primary.opacity(0.018),
        tableHeaderBackground: Color = Color.accentColor.opacity(0.095),
        tableAlternateRowBackground: Color = Color.primary.opacity(0.032),
        tableBorderColor: Color = Color.primary.opacity(0.13),
        tableAccentColor: Color = Color.accentColor.opacity(0.85),
        tableCornerRadius: CGFloat = 8,
        tableHorizontalCellPadding: CGFloat = 12,
        tableVerticalCellPadding: CGFloat = 9,
        blockSpacing: CGFloat = 8,
        paragraphFontSize: Double = 16,
        paragraphLineHeight: Double = 22,
        headingFontSize: Double = 20,
        headingLineHeight: Double = 28,
        codeFontSize: Double = 14,
        codeLineHeight: Double = 20,
        paragraphFontProfiles: MarkdownInlineFontProfiles = .paragraphDefault,
        headingFontProfiles: MarkdownInlineFontProfiles = .headingDefault,
        codeFontProfiles: MarkdownInlineFontProfiles = .codeDefault,
        headings: MarkdownHeadingStyles? = nil
    ) {
        self.init(
            paragraphFont: paragraphFont,
            codeFont: codeFont,
            headingFont: headingFont,
            textColor: textColor,
            secondaryTextColor: secondaryTextColor,
            codeBackground: codeBackground,
            quoteAccent: quoteAccent,
            tableBackground: tableBackground,
            tableHeaderBackground: tableHeaderBackground,
            tableAlternateRowBackground: tableAlternateRowBackground,
            tableBorderColor: tableBorderColor,
            tableAccentColor: tableAccentColor,
            tableCornerRadius: tableCornerRadius,
            tableHorizontalCellPadding: tableHorizontalCellPadding,
            tableVerticalCellPadding: tableVerticalCellPadding,
            blockSpacing: blockSpacing,
            paragraphFontSize: paragraphFontSize,
            paragraphLineHeight: paragraphLineHeight,
            headingFontSize: headingFontSize,
            headingLineHeight: headingLineHeight,
            codeFontSize: codeFontSize,
            codeLineHeight: codeLineHeight,
            paragraphFontProfiles: paragraphFontProfiles,
            headingFontProfiles: headingFontProfiles,
            codeFontProfiles: codeFontProfiles,
            headings: headings,
            syntaxHighlightingPalette: .default
        )
    }

    public init(
        paragraphFont: Font = .body,
        codeFont: Font = .system(.body, design: .monospaced),
        headingFont: Font = .title3.bold(),
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        codeBackground: Color = Color.gray.opacity(0.12),
        quoteAccent: Color = Color.accentColor.opacity(0.65),
        tableBackground: Color = Color.primary.opacity(0.018),
        tableHeaderBackground: Color = Color.accentColor.opacity(0.095),
        tableAlternateRowBackground: Color = Color.primary.opacity(0.032),
        tableBorderColor: Color = Color.primary.opacity(0.13),
        tableAccentColor: Color = Color.accentColor.opacity(0.85),
        tableCornerRadius: CGFloat = 8,
        tableHorizontalCellPadding: CGFloat = 12,
        tableVerticalCellPadding: CGFloat = 9,
        blockSpacing: CGFloat = 8,
        paragraphFontSize: Double = 16,
        paragraphLineHeight: Double = 22,
        headingFontSize: Double = 20,
        headingLineHeight: Double = 28,
        codeFontSize: Double = 14,
        codeLineHeight: Double = 20,
        paragraphFontProfiles: MarkdownInlineFontProfiles = .paragraphDefault,
        headingFontProfiles: MarkdownInlineFontProfiles = .headingDefault,
        codeFontProfiles: MarkdownInlineFontProfiles = .codeDefault,
        headings: MarkdownHeadingStyles? = nil,
        syntaxHighlightingPalette: MarkdownSyntaxHighlightingPalette
    ) {
        self.paragraphFont = paragraphFont
        self.codeFont = codeFont
        self.headings = headings ?? MarkdownHeadingStyles.standard(
            h3: MarkdownTextStyle(
                font: headingFont,
                fontSize: headingFontSize,
                lineHeight: headingLineHeight,
                fontProfiles: headingFontProfiles
            )
        )
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.codeBackground = codeBackground
        self.quoteAccent = quoteAccent
        self.tableBackground = tableBackground
        self.tableHeaderBackground = tableHeaderBackground
        self.tableAlternateRowBackground = tableAlternateRowBackground
        self.tableBorderColor = tableBorderColor
        self.tableAccentColor = tableAccentColor
        self.tableCornerRadius = tableCornerRadius
        self.tableHorizontalCellPadding = tableHorizontalCellPadding
        self.tableVerticalCellPadding = tableVerticalCellPadding
        self.blockSpacing = blockSpacing
        self.paragraphFontSize = paragraphFontSize
        self.paragraphLineHeight = paragraphLineHeight
        self.codeFontSize = codeFontSize
        self.codeLineHeight = codeLineHeight
        self.paragraphFontProfiles = paragraphFontProfiles
        self.codeFontProfiles = codeFontProfiles
        self.syntaxHighlightingPalette = syntaxHighlightingPalette
        self.codeBlockAffordances = .default
    }

    public static var compactChat: MarkdownTheme {
        MarkdownTheme(blockSpacing: 6)
    }

    public static var document: MarkdownTheme {
        MarkdownTheme(blockSpacing: 12)
    }

    public func headingStyle(for level: Int?) -> MarkdownTextStyle {
        headings.style(for: level)
    }
}

public struct MarkdownSyntaxHighlightingPalette: Sendable, Hashable {
    public var keyword: MarkdownSyntaxHighlightingColor
    public var string: MarkdownSyntaxHighlightingColor
    public var number: MarkdownSyntaxHighlightingColor
    public var comment: MarkdownSyntaxHighlightingColor
    public var property: MarkdownSyntaxHighlightingColor
    public var type: MarkdownSyntaxHighlightingColor
    public var function: MarkdownSyntaxHighlightingColor
    public var literal: MarkdownSyntaxHighlightingColor
    public var operatorToken: MarkdownSyntaxHighlightingColor
    public var punctuation: MarkdownSyntaxHighlightingColor
    public var addition: MarkdownSyntaxHighlightingColor
    public var deletion: MarkdownSyntaxHighlightingColor
    public var meta: MarkdownSyntaxHighlightingColor
    public var section: MarkdownSyntaxHighlightingColor

    public init(
        keyword: MarkdownSyntaxHighlightingColor = .purple,
        string: MarkdownSyntaxHighlightingColor = .green,
        number: MarkdownSyntaxHighlightingColor = .orange,
        comment: MarkdownSyntaxHighlightingColor = .secondary,
        property: MarkdownSyntaxHighlightingColor = .blue,
        type: MarkdownSyntaxHighlightingColor = .teal,
        function: MarkdownSyntaxHighlightingColor = .indigo,
        literal: MarkdownSyntaxHighlightingColor = .pink,
        operatorToken: MarkdownSyntaxHighlightingColor = .secondary,
        punctuation: MarkdownSyntaxHighlightingColor = .secondary,
        addition: MarkdownSyntaxHighlightingColor = .green,
        deletion: MarkdownSyntaxHighlightingColor = .red,
        meta: MarkdownSyntaxHighlightingColor = .secondary,
        section: MarkdownSyntaxHighlightingColor = .blue
    ) {
        self.keyword = keyword
        self.string = string
        self.number = number
        self.comment = comment
        self.property = property
        self.type = type
        self.function = function
        self.literal = literal
        self.operatorToken = operatorToken
        self.punctuation = punctuation
        self.addition = addition
        self.deletion = deletion
        self.meta = meta
        self.section = section
    }

    public static let `default` = MarkdownSyntaxHighlightingPalette()

    public var cacheIdentity: String {
        [
            keyword, string, number, comment, property, type, function, literal,
            operatorToken, punctuation, addition, deletion, meta, section
        ].map(\.cacheIdentity).joined(separator: "|")
    }

    func foregroundColor(for classes: [String]) -> Color? {
        let classSet = Set(classes)

        if classSet.contains("comment") || classSet.contains("quote") {
            return comment.swiftUIColor
        }
        if classSet.contains("deletion") {
            return deletion.swiftUIColor
        }
        if classSet.contains("addition") {
            return addition.swiftUIColor
        }
        if classSet.contains("string") || classSet.contains("regexp") {
            return string.swiftUIColor
        }
        if classSet.contains("number") {
            return number.swiftUIColor
        }
        if classSet.contains("literal") || classSet.contains("symbol") || classSet.contains("bullet") {
            return literal.swiftUIColor
        }
        if classSet.contains("keyword") {
            return keyword.swiftUIColor
        }
        if classSet.contains("attr")
            || classSet.contains("attribute")
            || classSet.contains("property")
            || classSet.contains("params")
        {
            return property.swiftUIColor
        }
        if classSet.contains("title") || classSet.contains("function_") || classSet.contains("function") {
            return function.swiftUIColor
        }
        if classSet.contains("type") || classSet.contains("class_") || classSet.contains("built_in") {
            return type.swiftUIColor
        }
        if classSet.contains("operator") {
            return operatorToken.swiftUIColor
        }
        if classSet.contains("punctuation") {
            return punctuation.swiftUIColor
        }
        if classSet.contains("meta") || classSet.contains("doctag") {
            return meta.swiftUIColor
        }
        if classSet.contains("section") || classSet.contains("selector-tag") || classSet.contains("name") {
            return section.swiftUIColor
        }

        return nil
    }
}

public struct MarkdownSyntaxHighlightingColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let blue = MarkdownSyntaxHighlightingColor(red: 0.0, green: 0.36, blue: 0.82)
    public static let green = MarkdownSyntaxHighlightingColor(red: 0.12, green: 0.48, blue: 0.22)
    public static let indigo = MarkdownSyntaxHighlightingColor(red: 0.27, green: 0.31, blue: 0.84)
    public static let orange = MarkdownSyntaxHighlightingColor(red: 0.78, green: 0.37, blue: 0.04)
    public static let pink = MarkdownSyntaxHighlightingColor(red: 0.78, green: 0.16, blue: 0.47)
    public static let purple = MarkdownSyntaxHighlightingColor(red: 0.48, green: 0.25, blue: 0.72)
    public static let red = MarkdownSyntaxHighlightingColor(red: 0.76, green: 0.13, blue: 0.13)
    public static let secondary = MarkdownSyntaxHighlightingColor(red: 0.42, green: 0.42, blue: 0.46, opacity: 0.92)
    public static let teal = MarkdownSyntaxHighlightingColor(red: 0.0, green: 0.47, blue: 0.52)

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var cacheIdentity: String {
        "\(red),\(green),\(blue),\(opacity)"
    }
}

public extension MarkdownInlineFontProfiles {
    static let paragraphDefault = MarkdownInlineFontProfiles(
        body: .system(),
        emphasis: .system(),
        strong: .system(weight: .bold),
        code: .monospacedSystem(),
        math: .monospacedSystem(),
        imagePlaceholder: .system()
    )

    static let headingDefault = MarkdownInlineFontProfiles(
        body: .system(weight: .bold),
        emphasis: .system(weight: .bold),
        strong: .system(weight: .bold),
        code: .monospacedSystem(weight: .semibold),
        math: .monospacedSystem(weight: .semibold),
        imagePlaceholder: .system(weight: .bold)
    )

    static let codeDefault = MarkdownInlineFontProfiles(
        body: .monospacedSystem(),
        emphasis: .monospacedSystem(),
        strong: .monospacedSystem(weight: .bold),
        code: .monospacedSystem(),
        math: .monospacedSystem(),
        imagePlaceholder: .monospacedSystem()
    )
}
