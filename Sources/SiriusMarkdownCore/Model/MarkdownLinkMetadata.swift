import Foundation

public enum MarkdownRemoteResourceKind: String, Sendable, Hashable, Codable {
    case linkMetadataDocument
    case linkIcon
}

public protocol MarkdownRemoteResourcePolicy: Sendable {
    func evaluateRemoteResource(
        _ url: URL,
        kind: MarkdownRemoteResourceKind
    ) -> MarkdownPolicyDecision
}

/// The network-independent first-line policy used by the package favicon
/// resolver. Runtime DNS validation is deliberately performed by the
/// resolver immediately before every request and redirect.
public struct DefaultMarkdownRemoteResourcePolicy: MarkdownRemoteResourcePolicy {
    public init() {}

    public func evaluateRemoteResource(
        _ url: URL,
        kind _: MarkdownRemoteResourceKind
    ) -> MarkdownPolicyDecision {
        guard url.scheme?.lowercased() == "https" else {
            return .deny(reason: "Remote rich content requires HTTPS.")
        }
        guard url.user == nil, url.password == nil else {
            return .deny(reason: "Remote rich content cannot contain user info.")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .deny(reason: "Remote rich content requires a host.")
        }
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard normalizedHost != "localhost",
              !normalizedHost.hasSuffix(".localhost"),
              !normalizedHost.hasSuffix(".local"),
              !normalizedHost.hasSuffix(".internal")
        else {
            return .deny(reason: "Local network destinations are disabled.")
        }
        return .allow
    }
}

public struct MarkdownLinkIcon: Sendable, Hashable {
    public var sourceURL: URL
    public var data: Data
    public var mimeType: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        sourceURL: URL,
        data: Data,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.sourceURL = sourceURL
        self.data = data
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum MarkdownLinkDecoration: Sendable, Hashable {
    case glyph(String)
    case favicon(MarkdownLinkIcon)
}

public struct MarkdownLinkMetadata: Sendable, Hashable {
    public var destination: URL
    public var title: String?
    public var decoration: MarkdownLinkDecoration

    public init(
        destination: URL,
        title: String? = nil,
        decoration: MarkdownLinkDecoration
    ) {
        self.destination = destination
        self.title = title
        self.decoration = decoration
    }
}

/// A non-nil cached resolution means lookup has completed. `.unavailable`
/// is negative-cache state and prevents failed sites from being hammered on
/// every render publication.
public enum MarkdownLinkMetadataResolution: Sendable, Hashable {
    case metadata(MarkdownLinkMetadata)
    case unavailable
}

public protocol MarkdownLinkMetadataResolver: Sendable {
    func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution?
    func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution
}

public protocol MarkdownLinkMetadataResolverCacheIdentifying: Sendable {
    var linkMetadataResolverCacheIdentity: String { get }
}
