import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public struct MarkdownRemoteImageData: Sendable {
    public let sourceURL: URL
    public let data: Data
    public let mimeType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Stable for this cached result; consumers need not hash image bytes.
    public let cacheIdentity: UUID
}

public enum MarkdownRemoteImageResolution: Sendable {
    case available(MarkdownRemoteImageData)
    case unavailable

    public var cacheIdentity: UUID? {
        if case let .available(image) = self { return image.cacheIdentity }
        return nil
    }
}

public enum MarkdownRemoteImageLoaderError: Error, Sendable {
    case capacityExceeded
}

/// Explicitly opt-in raster image loading. The default renderer does not create
/// or call this loader. Cached reads are synchronous; transport/decoding never
/// run on the caller's actor. Private origins and ambient credentials are denied.
public final class DefaultMarkdownRemoteImageLoader: @unchecked Sendable {
    public struct Limits: Sendable {
        public let maximumBytes: Int
        public let maximumDimension: Int
        public let maximumDecodedPixels: Int
        public let maximumFrames: Int
        public let maximumConcurrentRequests: Int
        public let maximumPendingRequests: Int
        public let cacheCapacity: Int
        public let maximumCachedBytes: Int
        public let positiveCacheLifetime: TimeInterval
        public let negativeCacheLifetime: TimeInterval
        public let maximumRedirects: Int
        public let requestTimeout: TimeInterval
        public let maximumResolutionDuration: TimeInterval

        public init(maximumBytes: Int = 8 * 1_024 * 1_024, maximumDimension: Int = 8_192,
                    maximumDecodedPixels: Int = 16_777_216, maximumFrames: Int = 1,
                    maximumConcurrentRequests: Int = 4, maximumPendingRequests: Int = 64,
                    cacheCapacity: Int = 64, maximumCachedBytes: Int = 32 * 1_024 * 1_024,
                    positiveCacheLifetime: TimeInterval = 3_600, negativeCacheLifetime: TimeInterval = 60,
                    maximumRedirects: Int = 4, requestTimeout: TimeInterval = 6, maximumResolutionDuration: TimeInterval = 20) {
            self.maximumBytes = min(128 * 1_024 * 1_024, max(1_024, maximumBytes))
            self.maximumDimension = min(16_384, max(1, maximumDimension))
            self.maximumDecodedPixels = min(67_108_864, max(1, maximumDecodedPixels))
            self.maximumFrames = min(64, max(1, maximumFrames))
            self.maximumConcurrentRequests = min(32, max(1, maximumConcurrentRequests))
            self.maximumPendingRequests = min(1_024, max(1, maximumPendingRequests))
            self.cacheCapacity = min(1_024, max(1, cacheCapacity))
            self.maximumCachedBytes = min(256 * 1_024 * 1_024, max(1_024, maximumCachedBytes))
            self.positiveCacheLifetime = Self.duration(positiveCacheLifetime, fallback: 3_600)
            self.negativeCacheLifetime = Self.duration(negativeCacheLifetime, fallback: 60)
            self.maximumRedirects = min(16, max(0, maximumRedirects))
            self.requestTimeout = Self.duration(requestTimeout, fallback: 6)
            self.maximumResolutionDuration = Self.duration(maximumResolutionDuration, fallback: 20)
        }

        private static func duration(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
            value.isFinite ? min(86_400, max(0.1, value)) : fallback
        }
    }

    public let remoteImageLoaderCacheIdentity = UUID()
    private let cache: MarkdownRemoteImageCache
    private let coordinator: MarkdownRemoteImageCoordinator

    public init(policy: any MarkdownRemoteResourcePolicy = DefaultMarkdownRemoteResourcePolicy(), limits: Limits = .init(), sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        let cache = MarkdownRemoteImageCache(limits: limits)
        self.cache = cache
        let transportLimits = DefaultMarkdownLinkMetadataResolver.Limits(maximumRedirects: limits.maximumRedirects, requestTimeout: limits.requestTimeout, maximumResolutionDuration: limits.maximumResolutionDuration)
        let transport = MarkdownRemoteResourceTransport(policy: MarkdownImageTransportPolicy(additional: policy), limits: transportLimits, sessionConfiguration: sessionConfiguration)
        self.coordinator = MarkdownRemoteImageCoordinator(cache: cache, transport: transport, limits: limits)
    }

    public func cachedResolution(for destination: URL) -> MarkdownRemoteImageResolution? {
        guard let key = Self.cacheKey(destination) else { return .unavailable }
        return cache.value(for: key)
    }

    /// Cancellation detaches only this caller; the transfer is cancelled when
    /// its last subscriber cancels. Queue overflow is never negative-cached.
    public func resolveImage(for destination: URL) async throws -> MarkdownRemoteImageResolution {
        try Task.checkCancellation()
        guard let key = Self.cacheKey(destination) else { return .unavailable }
        return try await coordinator.resolve(key)
    }

    public func removeAllCachedImages() async { await coordinator.removeAll() }

    private static func cacheKey(_ destination: URL) -> URL? {
        guard DefaultMarkdownRemoteResourcePolicy().evaluateRemoteResource(destination, kind: .image) == .allow,
              DefaultMarkdownPolicy().evaluateLink(destination: destination.absoluteString) == .allow,
              var components = URLComponents(url: destination, resolvingAgainstBaseURL: true) else { return nil }
        components.fragment = nil
        return components.url
    }
}

private struct MarkdownImageTransportPolicy: MarkdownRemoteResourcePolicy {
    let additional: any MarkdownRemoteResourcePolicy
    func evaluateRemoteResource(_ url: URL, kind: MarkdownRemoteResourceKind) -> MarkdownPolicyDecision {
        let base = DefaultMarkdownRemoteResourcePolicy().evaluateRemoteResource(url, kind: kind)
        guard base == .allow else { return base }
        let link = DefaultMarkdownPolicy().evaluateLink(destination: url.absoluteString)
        guard link == .allow else { return link }
        return additional.evaluateRemoteResource(url, kind: kind)
    }
}

private final class MarkdownRemoteImageCache: @unchecked Sendable {
    private struct Entry {
        var resolution: MarkdownRemoteImageResolution
        var expiration: Date
        var ordinal: UInt64
        var bytes: Int
    }
    private let lock = NSLock()
    private let limits: DefaultMarkdownRemoteImageLoader.Limits
    private var entries: [URL: Entry] = [:]
    private var ordinal: UInt64 = 0
    private var byteCount = 0

    init(limits: DefaultMarkdownRemoteImageLoader.Limits) { self.limits = limits }

    func value(for key: URL) -> MarkdownRemoteImageResolution? {
        lock.withLock {
            guard var entry = entries[key] else { return nil }
            guard entry.expiration > Date() else {
                byteCount -= entry.bytes
                entries.removeValue(forKey: key)
                return nil
            }
            ordinal &+= 1
            entry.ordinal = ordinal
            entries[key] = entry
            return entry.resolution
        }
    }

    func store(_ resolution: MarkdownRemoteImageResolution, for key: URL) {
        lock.withLock {
            let bytes: Int
            let lifetime: TimeInterval
            switch resolution {
            case let .available(image): bytes = image.data.count; lifetime = limits.positiveCacheLifetime
            case .unavailable: bytes = 0; lifetime = limits.negativeCacheLifetime
            }
            guard bytes <= limits.maximumCachedBytes else { return }
            if let old = entries.removeValue(forKey: key) { byteCount -= old.bytes }
            ordinal &+= 1
            entries[key] = Entry(resolution: resolution, expiration: Date().addingTimeInterval(lifetime), ordinal: ordinal, bytes: bytes)
            byteCount += bytes
            while entries.count > limits.cacheCapacity || byteCount > limits.maximumCachedBytes {
                guard let oldest = entries.min(by: { $0.value.ordinal < $1.value.ordinal })?.key,
                      let removed = entries.removeValue(forKey: oldest) else { break }
                byteCount -= removed.bytes
            }
        }
    }

    func clear() { lock.withLock { entries.removeAll(); byteCount = 0 } }
}

private actor MarkdownRemoteImageCoordinator {
    private struct Job {
        let id = UUID()
        var subscribers: [UUID: CheckedContinuation<MarkdownRemoteImageResolution, any Error>] = [:]
        var task: Task<Void, Never>?
    }
    private let cache: MarkdownRemoteImageCache
    private let transport: MarkdownRemoteResourceTransport
    private let limits: DefaultMarkdownRemoteImageLoader.Limits
    private var jobs: [URL: Job] = [:]
    private var pending: [URL] = []
    private var active: Set<UUID> = []

    init(cache: MarkdownRemoteImageCache, transport: MarkdownRemoteResourceTransport, limits: DefaultMarkdownRemoteImageLoader.Limits) {
        self.cache = cache; self.transport = transport; self.limits = limits
    }

    func resolve(_ key: URL) async throws -> MarkdownRemoteImageResolution {
        try Task.checkCancellation()
        if let cached = cache.value(for: key) { return cached }
        let subscriber = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                guard jobs.values.reduce(0, { $0 + $1.subscribers.count }) < limits.maximumPendingRequests + limits.maximumConcurrentRequests else {
                    continuation.resume(throwing: MarkdownRemoteImageLoaderError.capacityExceeded); return
                }
                if jobs[key] == nil {
                    guard jobs.count < limits.maximumPendingRequests + limits.maximumConcurrentRequests else {
                        continuation.resume(throwing: MarkdownRemoteImageLoaderError.capacityExceeded); return
                    }
                    jobs[key] = Job()
                    pending.append(key)
                }
                jobs[key]?.subscribers[subscriber] = continuation
                startPending()
            }
        } onCancel: {
            Task { await self.cancel(subscriber, for: key) }
        }
    }

    func removeAll() {
        let old = jobs
        jobs.removeAll(); pending.removeAll()
        cache.clear()
        for job in old.values {
            job.task?.cancel()
            for subscriber in job.subscribers.values { subscriber.resume(throwing: CancellationError()) }
        }
    }

    private func cancel(_ subscriber: UUID, for key: URL) {
        guard var job = jobs[key], let continuation = job.subscribers.removeValue(forKey: subscriber) else { return }
        continuation.resume(throwing: CancellationError())
        if job.subscribers.isEmpty {
            job.task?.cancel()
            jobs.removeValue(forKey: key)
            pending.removeAll { $0 == key }
            startPending()
        } else { jobs[key] = job }
    }

    private func startPending() {
        while active.count < limits.maximumConcurrentRequests, !pending.isEmpty {
            let key = pending.removeFirst()
            guard var job = jobs[key] else { continue }
            let jobID = job.id
            active.insert(jobID)
            let transport = transport
            let limits = limits
            job.task = Task.detached { [weak self] in
                let resolution: MarkdownRemoteImageResolution
                do {
                    try Task.checkCancellation()
                    let payload = try await transport.fetch(key, kind: .image, maximumBytes: limits.maximumBytes,
                        acceptedMIMETypes: ["image/png", "image/jpeg", "image/gif", "image/webp"],
                        deadline: Date().addingTimeInterval(limits.maximumResolutionDuration))
                    try Task.checkCancellation()
                    resolution = Self.validatedImage(payload, limits: limits).map(MarkdownRemoteImageResolution.available) ?? .unavailable
                } catch { resolution = .unavailable }
                await self?.complete(key, id: jobID, resolution: resolution)
            }
            jobs[key] = job
        }
    }

    private func complete(_ key: URL, id: UUID, resolution: MarkdownRemoteImageResolution) {
        // A cancelled transfer retains its concurrency slot until transport has
        // actually exited, even if a new request for the same URL is queued.
        guard active.remove(id) != nil else { return }
        guard let job = jobs[key], job.id == id else { startPending(); return }
        jobs.removeValue(forKey: key)
        cache.store(resolution, for: key)
        for subscriber in job.subscribers.values { subscriber.resume(returning: resolution) }
        startPending()
    }

    private nonisolated static func validatedImage(_ payload: MarkdownRemoteHTTPPayload, limits: DefaultMarkdownRemoteImageLoader.Limits) -> MarkdownRemoteImageData? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(payload.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { return nil }
        let types = ["public.png": "image/png", "public.jpeg": "image/jpeg", "com.compuserve.gif": "image/gif", "org.webmproject.webp": "image/webp"]
        guard let mimeType = types[type], (1...limits.maximumFrames).contains(CGImageSourceGetCount(source)) else { return nil }
        var totalPixels = 0
        var displayWidth = 0
        var displayHeight = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard !Task.isCancelled,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0, height > 0, width <= limits.maximumDimension, height <= limits.maximumDimension,
                  width <= (limits.maximumDecodedPixels - totalPixels) / height else { return nil }
            totalPixels += width * height
            guard let decoded = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  decoded.width == width, decoded.height == height else { return nil }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            displayWidth = max(displayWidth, (5...8).contains(orientation) ? height : width)
            displayHeight = max(displayHeight, (5...8).contains(orientation) ? width : height)
        }
        return MarkdownRemoteImageData(sourceURL: payload.finalURL, data: payload.data, mimeType: mimeType, pixelWidth: displayWidth, pixelHeight: displayHeight, cacheIdentity: UUID())
        #else
        return nil
        #endif
    }
}
