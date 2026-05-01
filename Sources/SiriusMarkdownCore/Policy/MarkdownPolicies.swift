import Foundation

public enum MarkdownPolicyDecision: Sendable, Hashable {
    case allow
    case deny(reason: String)
}

public protocol MarkdownLinkPolicy: Sendable {
    func evaluateLink(destination: String) -> MarkdownPolicyDecision
}

public protocol MarkdownImagePolicy: Sendable {
    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision
}

public protocol MarkdownHTMLPolicy: Sendable {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision
}

public protocol MarkdownCodePolicy: Sendable {
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision
}

public protocol MarkdownMathPolicy: Sendable {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision
}

public struct DefaultMarkdownPolicy:
    MarkdownLinkPolicy,
    MarkdownImagePolicy,
    MarkdownHTMLPolicy,
    MarkdownCodePolicy,
    MarkdownMathPolicy
{
    public init() {}

    public func evaluateLink(destination: String) -> MarkdownPolicyDecision {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .deny(reason: "Empty link destination.")
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
