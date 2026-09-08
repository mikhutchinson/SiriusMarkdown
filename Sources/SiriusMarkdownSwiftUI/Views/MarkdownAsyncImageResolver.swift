import Foundation
import SiriusMarkdownCore

/// Immutable completion state with a cheap per-resource cache token. Sessions
/// consume this value directly, even if a bounded resolver cache evicts it.
public struct MarkdownAsyncImageResolution: Sendable {
    public let preparedSource: MarkdownPreparedImageSource
    public let cacheIdentity: String
    public init(preparedSource: MarkdownPreparedImageSource, cacheIdentity: String) {
        self.preparedSource = preparedSource
        self.cacheIdentity = cacheIdentity
    }
}

/// Opt-in asynchronous image preparation. The render session authorizes source
/// images before scheduling this hook; preparation itself never starts a load.
public protocol MarkdownAsyncImageResolver: MarkdownImageResolver {
    func cachedImageResolution(for source: String) -> MarkdownAsyncImageResolution?
    func resolveImage(for source: String) async -> MarkdownAsyncImageResolution
}

/// Package-owned remote images, explicitly enabled by assigning this resolver
/// and an allowing image policy. The default renderer never fetches images.
public struct RemoteMarkdownImageResolver: MarkdownAsyncImageResolver, MarkdownImageResolverCacheIdentifying {
    public let loader: DefaultMarkdownRemoteImageLoader
    private let failures = MarkdownImageTransientFailures()
    public init(loader: DefaultMarkdownRemoteImageLoader = .init()) { self.loader = loader }
    public var imageResolverCacheIdentity: String { "remote-images:\(loader.remoteImageLoaderCacheIdentity)" }

    public func cachedImageResolution(for source: String) -> MarkdownAsyncImageResolution? {
        guard let url = URL(string: source) else { return Self.unavailable }
        if let resolution = loader.cachedResolution(for: url) { return Self.prepared(resolution) }
        return failures.contains(source) ? Self.unavailable : nil
    }

    public func resolveImage(for source: String) async -> MarkdownAsyncImageResolution {
        guard let url = URL(string: source) else { return Self.unavailable }
        do { return Self.prepared(try await loader.resolveImage(for: url)) }
        catch {
            if !Task.isCancelled { failures.record(source) }
            return Self.unavailable
        }
    }

    public func preparedImage(source: String, altText: String?, sourceRange: MarkdownSourceRange?, policyDecision: MarkdownPolicyDecision) -> MarkdownPreparedImage {
        let prepared: MarkdownPreparedImageSource
        switch policyDecision {
        case .allow: prepared = cachedImageResolution(for: source)?.preparedSource ?? .placeholder(reason: "Loading image")
        case let .deny(reason): prepared = .placeholder(reason: reason)
        }
        return .init(source: source, altText: altText, sourceRange: sourceRange, preparedSource: prepared)
    }

    private static var unavailable: MarkdownAsyncImageResolution {
        .init(preparedSource: .placeholder(reason: "Image unavailable"), cacheIdentity: "unavailable")
    }
    private static func prepared(_ resolution: MarkdownRemoteImageResolution) -> MarkdownAsyncImageResolution {
        switch resolution {
        case .unavailable: return unavailable
        case let .available(image):
            return .init(preparedSource: .data(image.data, mimeType: image.mimeType), cacheIdentity: image.cacheIdentity.uuidString)
        }
    }
}


/// Bounds transient capacity failures too, so a completed attempt never leaves
/// a permanent loading placeholder. No image bytes are duplicated here.
private final class MarkdownImageTransientFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Date] = [:]
    func contains(_ source: String) -> Bool {
        lock.withLock {
            guard let expiry = entries[source] else { return false }
            if expiry <= Date() { entries.removeValue(forKey: source); return false }
            return true
        }
    }
    func record(_ source: String) {
        lock.withLock {
            if entries.count >= 64, let oldest = entries.min(by: { $0.value < $1.value })?.key { entries.removeValue(forKey: oldest) }
            entries[source] = Date().addingTimeInterval(30)
        }
    }
}


/// A pipeline-scoped view of image state retained by the current document.
/// Original policies are still evaluated before preparedImage is called.
struct MarkdownImageCompletionResolver: MarkdownAsyncImageResolver, MarkdownImageResolverCacheIdentifying {
    let base: any MarkdownImageResolver
    let resolutions: [String: MarkdownAsyncImageResolution]
    private let uncachedIdentity = UUID()
    init(base: any MarkdownImageResolver, resolutions: [String: MarkdownAsyncImageResolution]) {
        self.base = base
        self.resolutions = resolutions
    }
    var imageResolverCacheIdentity: String {
        (base as? any MarkdownImageResolverCacheIdentifying)?.imageResolverCacheIdentity ?? uncachedIdentity.uuidString
    }
    func cachedImageResolution(for source: String) -> MarkdownAsyncImageResolution? {
        resolutions[source] ?? (base as? any MarkdownAsyncImageResolver)?.cachedImageResolution(for: source)
    }
    func resolveImage(for source: String) async -> MarkdownAsyncImageResolution {
        if let result = cachedImageResolution(for: source) { return result }
        if let asynchronous = base as? any MarkdownAsyncImageResolver { return await asynchronous.resolveImage(for: source) }
        return .init(preparedSource: .placeholder(reason: "Image unavailable"), cacheIdentity: "unavailable")
    }
    func preparedImage(source: String, altText: String?, sourceRange: MarkdownSourceRange?, policyDecision: MarkdownPolicyDecision) -> MarkdownPreparedImage {
        guard case .allow = policyDecision, let resolution = cachedImageResolution(for: source) else {
            return base.preparedImage(source: source, altText: altText, sourceRange: sourceRange, policyDecision: policyDecision)
        }
        return .init(source: source, altText: altText, sourceRange: sourceRange, preparedSource: resolution.preparedSource)
    }
}
