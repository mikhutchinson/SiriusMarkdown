import Foundation

public enum MarkdownPolicyDecision: Sendable, Hashable {
    case allow
    case deny(reason: String)
}

public protocol MarkdownLinkPolicy: Sendable {
    func evaluateLink(destination: String) -> MarkdownPolicyDecision
}

public protocol MarkdownLinkPolicyCacheIdentifying: Sendable {
    var linkPolicyCacheIdentity: String { get }
}

public protocol MarkdownImagePolicy: Sendable {
    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision
}

public protocol MarkdownImagePolicyCacheIdentifying: Sendable {
    var imagePolicyCacheIdentity: String { get }
}

public protocol MarkdownHTMLPolicy: Sendable {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision
}

public protocol MarkdownHTMLPolicyCacheIdentifying: Sendable {
    var htmlPolicyCacheIdentity: String { get }
}

public protocol MarkdownCodePolicy: Sendable {
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision
}

public protocol MarkdownCodePolicyCacheIdentifying: Sendable {
    var codePolicyCacheIdentity: String { get }
}

public protocol MarkdownMathPolicy: Sendable {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision
}

public protocol MarkdownMathPolicyCacheIdentifying: Sendable {
    var mathPolicyCacheIdentity: String { get }
}

public struct DefaultMarkdownPolicy:
    MarkdownLinkPolicy,
    MarkdownImagePolicy,
    MarkdownHTMLPolicy,
    MarkdownCodePolicy,
    MarkdownMathPolicy,
    MarkdownLinkPolicyCacheIdentifying,
    MarkdownImagePolicyCacheIdentifying,
    MarkdownHTMLPolicyCacheIdentifying,
    MarkdownCodePolicyCacheIdentifying,
    MarkdownMathPolicyCacheIdentifying
{
    public init() {}

    public var linkPolicyCacheIdentity: String {
        "siriusmarkdown.default-link-policy.v1"
    }

    public var imagePolicyCacheIdentity: String {
        "siriusmarkdown.default-image-policy.v1"
    }

    public var htmlPolicyCacheIdentity: String {
        "siriusmarkdown.default-html-policy.v1"
    }

    public var codePolicyCacheIdentity: String {
        "siriusmarkdown.default-code-policy.v1"
    }

    public var mathPolicyCacheIdentity: String {
        "siriusmarkdown.default-math-policy.v1"
    }

    public func evaluateLink(destination: String) -> MarkdownPolicyDecision {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .deny(reason: "Empty link destination.")
        }

        if trimmed.hasPrefix("//") {
            return .deny(reason: "Protocol-relative external URLs are disabled by default.")
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .allow
        }

        switch scheme {
        case "http", "https", "mailto":
            return .allow
        default:
            return .deny(reason: "URL scheme is disabled by default: \(scheme)")
        }
    }

    public func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision {
        .deny(reason: "Image loading is disabled by default.")
    }

    public func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        .deny(reason: "Raw HTML is disabled by default.")
    }

    public func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision {
        .allow
    }

    public func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .allow
    }
}
