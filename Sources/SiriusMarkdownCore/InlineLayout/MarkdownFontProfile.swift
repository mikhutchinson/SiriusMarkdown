import Foundation

public enum MarkdownFontWeight: String, Sendable, Hashable {
    case regular
    case medium
    case semibold
    case bold
}

public enum MarkdownFontDesign: String, Sendable, Hashable {
    case `default`
    case serif
    case rounded
    case monospaced
}

public enum MarkdownFontProfile: Sendable, Hashable {
    case system(weight: MarkdownFontWeight = .regular, design: MarkdownFontDesign = .default)
    case monospacedSystem(weight: MarkdownFontWeight = .regular)
    case named(String, weight: MarkdownFontWeight = .regular)

    public var cacheKey: String {
        switch self {
        case let .system(weight, design):
            return "system:\(design.rawValue):\(weight.rawValue)"
        case let .monospacedSystem(weight):
            return "system:monospaced:\(weight.rawValue)"
        case let .named(name, weight):
            return "named:\(name):\(weight.rawValue)"
        }
    }
}

public struct MarkdownInlineFontProfiles: Sendable, Hashable {
    public var body: MarkdownFontProfile
    public var emphasis: MarkdownFontProfile
    public var strong: MarkdownFontProfile
    public var code: MarkdownFontProfile
    public var math: MarkdownFontProfile
    public var imagePlaceholder: MarkdownFontProfile

    public init(
        body: MarkdownFontProfile = .system(),
        emphasis: MarkdownFontProfile = .system(),
        strong: MarkdownFontProfile = .system(weight: .bold),
        code: MarkdownFontProfile = .monospacedSystem(),
        math: MarkdownFontProfile = .monospacedSystem(),
        imagePlaceholder: MarkdownFontProfile = .system()
    ) {
        self.body = body
        self.emphasis = emphasis
        self.strong = strong
        self.code = code
        self.math = math
        self.imagePlaceholder = imagePlaceholder
    }

    public init(uniform profile: MarkdownFontProfile) {
        self.init(
            body: profile,
            emphasis: profile,
            strong: profile,
            code: profile,
            math: profile,
            imagePlaceholder: profile
        )
    }

    public var cacheKey: String {
        [
            "body=\(body.cacheKey)",
            "emphasis=\(emphasis.cacheKey)",
            "strong=\(strong.cacheKey)",
            "code=\(code.cacheKey)",
            "math=\(math.cacheKey)",
            "image=\(imagePlaceholder.cacheKey)"
        ].joined(separator: "|")
    }

    public func profile(for kind: MarkdownInlineKind) -> MarkdownFontProfile {
        switch kind {
        case .emphasis:
            return emphasis
        case .strong:
            return strong
        case .code:
            return code
        case .math:
            return math
        case .image:
            return imagePlaceholder
        default:
            return body
        }
    }
}
