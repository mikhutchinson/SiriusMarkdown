import Foundation
import SwiftSoup

#if canImport(Darwin)
import Darwin
#endif
#if canImport(ImageIO)
import ImageIO
#endif

public final class DefaultMarkdownLinkMetadataResolver:
    MarkdownLinkMetadataResolver,
    MarkdownLinkMetadataResolverCacheIdentifying,
    @unchecked Sendable
{
    public static let shared = DefaultMarkdownLinkMetadataResolver()

    public struct Limits: Sendable, Hashable {
        public var maximumDocumentBytes: Int
        public var maximumIconBytes: Int
        public var maximumIconDimension: Int
        public var maximumRedirects: Int
        public var maximumIconCandidates: Int
        public var maximumConcurrentOrigins: Int
        public var requestTimeout: TimeInterval
        public var maximumResolutionDuration: TimeInterval
        public var positiveCacheLifetime: TimeInterval
        public var negativeCacheLifetime: TimeInterval
        public var cacheCapacity: Int
        public var userAgent: String

        public init(
            maximumDocumentBytes: Int = 512 * 1_024,
            maximumIconBytes: Int = 512 * 1_024,
            maximumIconDimension: Int = 2_048,
            maximumRedirects: Int = 6,
            maximumIconCandidates: Int = 16,
            maximumConcurrentOrigins: Int = 8,
            requestTimeout: TimeInterval = 6,
            maximumResolutionDuration: TimeInterval = 15,
            positiveCacheLifetime: TimeInterval = 24 * 60 * 60,
            negativeCacheLifetime: TimeInterval = 30 * 60,
            cacheCapacity: Int = 256,
            userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 SiriusMarkdown/1.0"
        ) {
            self.maximumDocumentBytes = max(1_024, maximumDocumentBytes)
            self.maximumIconBytes = max(1_024, maximumIconBytes)
            self.maximumIconDimension = max(16, maximumIconDimension)
            self.maximumRedirects = max(0, maximumRedirects)
            self.maximumIconCandidates = max(1, maximumIconCandidates)
            self.maximumConcurrentOrigins = max(1, maximumConcurrentOrigins)
            self.requestTimeout = max(1, requestTimeout)
            self.maximumResolutionDuration = max(1, maximumResolutionDuration)
            self.positiveCacheLifetime = max(1, positiveCacheLifetime)
            self.negativeCacheLifetime = max(1, negativeCacheLifetime)
            self.cacheCapacity = max(1, cacheCapacity)
            self.userAgent = userAgent
        }

        public static let `default` = Limits()
    }

    private struct CacheEntry {
        var resolution: MarkdownLinkMetadataResolution
        var expiration: Date
        var accessOrdinal: UInt64
    }

    private struct IconCandidate: Sendable, Hashable {
        var url: URL
        var declaredSize: Int?
        var relationshipRank: Int
        var discoveryOrdinal: Int
        var requiresSquareAspect: Bool
    }

    private struct HTTPPayload: Sendable {
        var data: Data
        var response: HTTPURLResponse
        var finalURL: URL
    }

    private let policy: any MarkdownRemoteResourcePolicy
    private let limits: Limits
    private let sessionConfiguration: URLSessionConfiguration
    private let requestLimiter: MarkdownLinkMetadataRequestLimiter
    private let lock = NSLock()
    private var cache: [URL: CacheEntry] = [:]
    private var inFlight: [URL: Task<MarkdownLinkMetadataResolution, Never>] = [:]
    private var failureDescriptionsByOrigin: [URL: [String]] = [:]
    private var accessOrdinal: UInt64 = 0
    private var cacheGeneration: UInt64 = 0

    public init(
        policy: any MarkdownRemoteResourcePolicy = DefaultMarkdownRemoteResourcePolicy(),
        limits: Limits = .default,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.policy = policy
        self.limits = limits
        self.sessionConfiguration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        requestLimiter = MarkdownLinkMetadataRequestLimiter(limit: limits.maximumConcurrentOrigins)
    }

    public var linkMetadataResolverCacheIdentity: String {
        [
            "siriusmarkdown.default-link-metadata-resolver.v1",
            String(limits.maximumDocumentBytes),
            String(limits.maximumIconBytes),
            String(limits.maximumIconDimension),
            String(limits.maximumRedirects),
            String(limits.maximumIconCandidates),
            String(limits.maximumConcurrentOrigins),
            String(limits.maximumResolutionDuration)
        ].joined(separator: ":")
    }

    public func cachedResolution(for destination: URL) -> MarkdownLinkMetadataResolution? {
        guard let origin = Self.originURL(for: destination) else { return .unavailable }
        return lock.withLock {
            guard var entry = cache[origin] else { return nil }
            guard entry.expiration > Date() else {
                cache.removeValue(forKey: origin)
                failureDescriptionsByOrigin.removeValue(forKey: origin)
                return nil
            }
            accessOrdinal &+= 1
            entry.accessOrdinal = accessOrdinal
            cache[origin] = entry
            return entry.resolution
        }
    }

    public func resolveMetadata(for destination: URL) async -> MarkdownLinkMetadataResolution {
        guard let origin = Self.originURL(for: destination) else { return .unavailable }
        if let cached = cachedResolution(for: origin) {
            return cached
        }

        let (task, generation) = lock.withLock { () -> (Task<MarkdownLinkMetadataResolution, Never>, UInt64) in
            let generation = cacheGeneration
            if let existing = inFlight[origin] {
                return (existing, generation)
            }
            let created = Task { [self] in
                await requestLimiter.run {
                    await discoverMetadata(for: origin, generation: generation)
                }
            }
            inFlight[origin] = created
            return (created, generation)
        }
        let resolution = await task.value
        store(resolution, for: origin, generation: generation)
        return resolution
    }

    public func removeAllCachedMetadata() {
        let tasks = lock.withLock { () -> [Task<MarkdownLinkMetadataResolution, Never>] in
            let tasks = Array(inFlight.values)
            cacheGeneration &+= 1
            inFlight.removeAll()
            cache.removeAll()
            failureDescriptionsByOrigin.removeAll()
            return tasks
        }
        tasks.forEach { $0.cancel() }
    }

    public func failureDescriptions(for destination: URL) -> [String] {
        guard let origin = Self.originURL(for: destination) else { return ["invalid HTTPS origin"] }
        return lock.withLock { failureDescriptionsByOrigin[origin] ?? [] }
    }

    private func store(
        _ resolution: MarkdownLinkMetadataResolution,
        for origin: URL,
        generation: UInt64
    ) {
        lock.withLock {
            // A clear can race an in-flight URLSession cancellation. Never let
            // a completion from the retired generation recreate either the
            // positive or negative cache entry the caller explicitly cleared.
            guard generation == cacheGeneration else { return }
            inFlight.removeValue(forKey: origin)
            accessOrdinal &+= 1
            let lifetime: TimeInterval
            switch resolution {
            case .metadata:
                lifetime = limits.positiveCacheLifetime
            case .unavailable:
                lifetime = limits.negativeCacheLifetime
            }
            cache[origin] = CacheEntry(
                resolution: resolution,
                expiration: Date().addingTimeInterval(lifetime),
                accessOrdinal: accessOrdinal
            )
            if cache.count > limits.cacheCapacity,
               let leastRecentlyUsed = cache.min(by: { $0.value.accessOrdinal < $1.value.accessOrdinal })?.key {
                cache.removeValue(forKey: leastRecentlyUsed)
                failureDescriptionsByOrigin.removeValue(forKey: leastRecentlyUsed)
            }
        }
    }

    private func discoverMetadata(
        for origin: URL,
        generation: UInt64
    ) async -> MarkdownLinkMetadataResolution {
        guard !Task.isCancelled,
              case .allow = policy.evaluateRemoteResource(origin, kind: .linkMetadataDocument)
        else {
            return .unavailable
        }

        var failures: [String] = []
        var title: String?
        var candidates: [IconCandidate] = []
        var fallbackOrigins: [URL] = [origin]
        var fetchedDocument = false
        let deadline = Date().addingTimeInterval(limits.maximumResolutionDuration)
        do {
            let documentPayload = try await fetch(
                origin,
                kind: .linkMetadataDocument,
                maximumBytes: limits.maximumDocumentBytes,
                acceptedMIMETypes: ["text/html", "application/xhtml+xml"],
                deadline: deadline
            )
            fetchedDocument = true
            let parsed = Self.parseDocumentMetadata(
                documentPayload.data,
                baseURL: documentPayload.finalURL,
                candidateLimit: limits.maximumIconCandidates
            )
            title = parsed.title
            candidates = parsed.candidates
            if candidates.isEmpty {
                failures.append(
                    "document \(documentPayload.finalURL.absoluteString) contained no usable icon declarations " +
                    "(\(documentPayload.data.count) bytes, title: \(parsed.title ?? "none"))"
                )
            }
            if let finalOrigin = Self.originURL(for: documentPayload.finalURL),
               finalOrigin != origin {
                fallbackOrigins.insert(finalOrigin, at: 0)
            }
        } catch {
            failures.append("document \(Self.failureDescription(error))")
        }

        let fallbackPaths: [(path: String, relationshipRank: Int, declaredSize: Int)] = fetchedDocument
            ? [
                ("/favicon.ico", 3, 32),
                ("/favicon.png", 4, 32),
                ("/apple-touch-icon.png", 4, 180),
                ("/apple-touch-icon-precomposed.png", 4, 180),
            ]
            : [("/favicon.ico", 3, 32)]
        for fallbackOrigin in fallbackOrigins {
            for fallbackPath in fallbackPaths {
                guard let fallback = URL(string: fallbackPath.path, relativeTo: fallbackOrigin)?.absoluteURL,
                      !candidates.contains(where: { $0.url == fallback })
                else {
                    continue
                }
                candidates.append(
                    IconCandidate(
                        url: fallback,
                        declaredSize: fallbackPath.declaredSize,
                        relationshipRank: fallbackPath.relationshipRank,
                        discoveryOrdinal: candidates.count,
                        requiresSquareAspect: false
                    )
                )
            }
        }

        candidates = Self.rankedCandidates(candidates, origin: origin)
        for candidate in candidates.prefix(limits.maximumIconCandidates) {
            guard deadline > Date(),
                  !Task.isCancelled,
                  case .allow = policy.evaluateRemoteResource(candidate.url, kind: .linkIcon)
            else {
                break
            }
            let payload: HTTPPayload
            do {
                payload = try await fetch(
                    candidate.url,
                    kind: .linkIcon,
                    maximumBytes: limits.maximumIconBytes,
                    acceptedMIMETypes: Self.acceptedIconMIMETypes,
                    deadline: deadline
                )
            } catch {
                failures.append("icon \(candidate.url.absoluteString) \(Self.failureDescription(error))")
                continue
            }
            guard let image = Self.validatedIcon(
                    payload.data,
                    response: payload.response,
                    finalURL: payload.finalURL,
                    maximumDimension: limits.maximumIconDimension
                  ) else {
                failures.append("icon \(candidate.url.absoluteString) failed native image validation")
                continue
            }
            if candidate.requiresSquareAspect {
                let shorterSide = min(image.pixelWidth, image.pixelHeight)
                let longerSide = max(image.pixelWidth, image.pixelHeight)
                guard shorterSide > 0, longerSide <= shorterSide * 5 / 4 else {
                    failures.append("icon \(candidate.url.absoluteString) is not square fallback artwork")
                    continue
                }
            }
            storeFailureDescriptions([], for: origin, generation: generation)
            return .metadata(
                MarkdownLinkMetadata(
                    destination: origin,
                    title: title,
                    decoration: .favicon(image)
                )
            )
        }

        storeFailureDescriptions(failures, for: origin, generation: generation)
        return .unavailable
    }

    private func storeFailureDescriptions(
        _ descriptions: [String],
        for origin: URL,
        generation: UInt64
    ) {
        lock.withLock {
            guard generation == cacheGeneration else { return }
            if descriptions.isEmpty {
                failureDescriptionsByOrigin.removeValue(forKey: origin)
            } else {
                failureDescriptionsByOrigin[origin] = Array(
                    descriptions.prefix(limits.maximumIconCandidates + 2)
                )
            }
        }
    }

    private static func failureDescription(_ error: Error) -> String {
        if let metadataError = error as? MarkdownLinkMetadataError {
            return metadataError.description
        }
        if let urlError = error as? URLError {
            return "URL error \(urlError.code.rawValue)"
        }
        return String(describing: error)
    }

    private func fetch(
        _ initialURL: URL,
        kind: MarkdownRemoteResourceKind,
        maximumBytes: Int,
        acceptedMIMETypes: Set<String>,
        deadline: Date
    ) async throws -> HTTPPayload {
        var currentURL = initialURL
        var visited: Set<URL> = []

        // A fresh ephemeral jar may retain cookies issued during this one
        // anonymous navigation (some public sites require that to complete a
        // same-site redirect), but it can never see host-app ambient cookies
        // or persist metadata after the fetch finishes.
        let navigationCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage
        let configuration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = limits.requestTimeout
        configuration.timeoutIntervalForResource = limits.maximumResolutionDuration
        let usesCustomProtocol = configuration.protocolClasses?.isEmpty == false
        let redirectDelegate = MarkdownNoRedirectURLSessionDelegate()
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        for redirectCount in 0...limits.maximumRedirects {
            try Task.checkCancellation()
            guard deadline > Date() else {
                throw MarkdownLinkMetadataError.resolutionTimeout
            }
            guard visited.insert(currentURL).inserted else {
                throw MarkdownLinkMetadataError.redirectLoop
            }
            guard case .allow = policy.evaluateRemoteResource(currentURL, kind: kind),
                  await Self.hostResolvesOnlyToPublicAddresses(currentURL.host)
            else {
                throw MarkdownLinkMetadataError.disallowedDestination
            }
            let remainingDuration = deadline.timeIntervalSinceNow
            guard remainingDuration > 0 else {
                throw MarkdownLinkMetadataError.resolutionTimeout
            }
            let requestTimeout = max(0.1, min(limits.requestTimeout, remainingDuration))

            var request = URLRequest(
                url: currentURL,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: requestTimeout
            )
            request.httpMethod = "GET"
            request.setValue(limits.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(kind == .linkIcon ? "image/*" : "text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            if kind == .linkMetadataDocument {
                // This is an anonymous top-level metadata navigation. Supplying
                // the standard navigation context avoids public sites returning
                // bot/error variants solely because URLSession omits browser
                // fetch metadata headers.
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
                request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
                request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
                request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
            }
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.setValue(nil, forHTTPHeaderField: "Cookie")
            request.setValue(nil, forHTTPHeaderField: "Proxy-Authorization")
            request.setValue(nil, forHTTPHeaderField: "Referer")
            if let navigationCookies = navigationCookieStorage?.cookies(for: currentURL),
               !navigationCookies.isEmpty {
                for (field, value) in HTTPCookie.requestHeaderFields(with: navigationCookies) {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }

            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MarkdownLinkMetadataError.invalidResponse
            }
            let responseHeaders = http.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
                guard let name = entry.key as? String else { return }
                fields[name] = String(describing: entry.value)
            }
            let issuedCookies = HTTPCookie.cookies(
                withResponseHeaderFields: responseHeaders,
                for: currentURL
            )
            navigationCookieStorage?.setCookies(
                issuedCookies,
                for: currentURL,
                mainDocumentURL: initialURL
            )
            if (300..<400).contains(http.statusCode) {
                guard redirectCount < limits.maximumRedirects,
                      let location = http.value(forHTTPHeaderField: "Location"),
                      let redirected = URL(string: location, relativeTo: currentURL)?.absoluteURL
                else {
                    throw MarkdownLinkMetadataError.redirectLimit
                }
                currentURL = redirected
                continue
            }
            let mimeType = Self.normalizedMIMEType(http.mimeType)
            let isBoundedClientErrorDocument = kind == .linkMetadataDocument
                && (400..<500).contains(http.statusCode)
                && http.statusCode != 401
                && http.statusCode != 407
                && mimeType.map(acceptedMIMETypes.contains) == true
            guard (200..<300).contains(http.statusCode) || isBoundedClientErrorDocument else {
                throw MarkdownLinkMetadataError.httpStatus(http.statusCode)
            }
            if let expectedLength = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
               expectedLength > maximumBytes,
               kind != .linkMetadataDocument {
                throw MarkdownLinkMetadataError.tooLarge
            }
            if !acceptedMIMETypes.isEmpty,
               let mimeType,
               !acceptedMIMETypes.contains(mimeType),
               !(kind == .linkIcon && mimeType.hasPrefix("image/")) {
                throw MarkdownLinkMetadataError.unsupportedMIMEType
            }

            var data = Data()
            data.reserveCapacity(min(maximumBytes, 32 * 1_024))
            for try await byte in bytes {
                guard data.count < maximumBytes else {
                    if kind == .linkMetadataDocument {
                        // Favicon declarations belong in `<head>`. Preserve
                        // the bounded prefix of oversized pages instead of
                        // discarding useful metadata because the body is huge.
                        break
                    }
                    throw MarkdownLinkMetadataError.tooLarge
                }
                data.append(byte)
            }
            guard !data.isEmpty else { throw MarkdownLinkMetadataError.emptyResponse }
            // DNS is checked immediately before the request, and task metrics
            // verify the endpoint URLSession actually contacted. The second
            // check closes the DNS-rebinding window between `getaddrinfo` and
            // connection establishment. Custom URLProtocol configurations are
            // test/host interception surfaces and do not expose a real socket.
            let contactedOnlyPublicAddresses = usesCustomProtocol
                ? true
                : await redirectDelegate.contactedOnlyPublicAddresses()
            guard contactedOnlyPublicAddresses else {
                throw MarkdownLinkMetadataError.disallowedDestination
            }
            return HTTPPayload(data: data, response: http, finalURL: currentURL)
        }
        throw MarkdownLinkMetadataError.redirectLimit
    }

    private static func parseDocumentMetadata(
        _ data: Data,
        baseURL: URL,
        candidateLimit: Int
    ) -> (title: String?, candidates: [IconCandidate]) {
        let html = String(decoding: data, as: UTF8.self)
        guard let document = try? SwiftSoup.parse(html, baseURL.absoluteString) else {
            return (nil, [])
        }
        let title = (try? document.title())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(256)
        var candidates: [IconCandidate] = []
        if let links = try? document.select("link[href]") {
            for element in links where candidates.count < candidateLimit {
                let relationship = ((try? element.attr("rel")) ?? "").lowercased()
                let tokens = Set(relationship.split(whereSeparator: \.isWhitespace).map(String.init))
                let rank: Int
                if tokens.contains("icon") {
                    rank = tokens.contains("shortcut") ? 1 : 0
                } else if tokens.contains("apple-touch-icon") || tokens.contains("apple-touch-icon-precomposed") {
                    rank = 2
                } else {
                    continue
                }
                let href = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty,
                      let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                      url.scheme?.lowercased() == "https"
                else {
                    continue
                }
                candidates.append(
                    IconCandidate(
                        url: url,
                        declaredSize: declaredIconSize((try? element.attr("sizes")) ?? ""),
                        relationshipRank: rank,
                        discoveryOrdinal: candidates.count,
                        requiresSquareAspect: false
                    )
                )
            }
        }
        if candidates.count < candidateLimit,
           let metadata = try? document.select("meta[content]") {
            for element in metadata where candidates.count < candidateLimit {
                let property = ((try? element.attr("property")) ?? "").lowercased()
                let name = ((try? element.attr("name")) ?? "").lowercased()
                guard property == "og:image" || name == "twitter:image" else { continue }
                let content = ((try? element.attr("content")) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty,
                      let url = URL(string: content, relativeTo: baseURL)?.absoluteURL,
                      url.scheme?.lowercased() == "https"
                else {
                    continue
                }
                candidates.append(
                    IconCandidate(
                        url: url,
                        declaredSize: nil,
                        relationshipRank: 5,
                        discoveryOrdinal: candidates.count,
                        requiresSquareAspect: true
                    )
                )
            }
        }
        return (title.map(String.init), candidates)
    }

    private static func rankedCandidates(_ candidates: [IconCandidate], origin: URL) -> [IconCandidate] {
        var seen: Set<URL> = []
        return candidates
            .filter { seen.insert($0.url).inserted }
            .sorted { lhs, rhs in
                // Authored icon declarations always outrank the conventional
                // `/favicon.ico` fallback, including when the declaration is
                // hosted on the site's public CDN.
                if lhs.relationshipRank != rhs.relationshipRank { return lhs.relationshipRank < rhs.relationshipRank }
                let lhsSameOrigin = lhs.url.host?.lowercased() == origin.host?.lowercased()
                let rhsSameOrigin = rhs.url.host?.lowercased() == origin.host?.lowercased()
                if lhsSameOrigin != rhsSameOrigin { return lhsSameOrigin }
                let lhsDistance = abs((lhs.declaredSize ?? 32) - 32)
                let rhsDistance = abs((rhs.declaredSize ?? 32) - 32)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                return lhs.discoveryOrdinal < rhs.discoveryOrdinal
            }
    }

    private static func declaredIconSize(_ value: String) -> Int? {
        value.lowercased().split(whereSeparator: \.isWhitespace).compactMap { token in
            let dimensions = token.split(separator: "x", maxSplits: 1).compactMap { Int($0) }
            guard dimensions.count == 2 else { return nil }
            return max(dimensions[0], dimensions[1])
        }.min()
    }

    private static let acceptedIconMIMETypes: Set<String> = [
        "image/png", "image/x-icon", "image/vnd.microsoft.icon", "image/ico",
        "image/jpeg", "image/gif", "image/webp", "application/octet-stream",
        "binary/octet-stream"
    ]

    private static func validatedIcon(
        _ data: Data,
        response: HTTPURLResponse,
        finalURL: URL,
        maximumDimension: Int
    ) -> MarkdownLinkIcon? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              (1...64).contains(CGImageSourceGetCount(source))
        else {
            return nil
        }
        var pixelWidth = 0
        var pixelHeight = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0, height > 0,
                  width <= maximumDimension, height <= maximumDimension
            else {
                return nil
            }
            pixelWidth = max(pixelWidth, width)
            pixelHeight = max(pixelHeight, height)
        }
        let mimeType = normalizedMIMEType(response.mimeType) ?? inferredIconMIMEType(data) ?? "image/x-icon"
        return MarkdownLinkIcon(
            sourceURL: finalURL,
            data: data,
            mimeType: mimeType,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        #else
        return nil
        #endif
    }

    private static func inferredIconMIMEType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) { return "image/x-icon" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.starts(with: Array("RIFF".utf8)), bytes.count >= 12,
           Array(bytes[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        return nil
    }

    private static func normalizedMIMEType(_ value: String?) -> String? {
        value?.split(separator: ";", maxSplits: 1).first.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func originURL(for destination: URL) -> URL? {
        guard destination.scheme?.lowercased() == "https",
              destination.user == nil,
              destination.password == nil,
              let host = destination.host,
              !host.isEmpty
        else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.lowercased()
        components.port = destination.port == 443 ? nil : destination.port
        components.path = "/"
        return components.url
    }

    private static func hostResolvesOnlyToPublicAddresses(_ host: String?) async -> Bool {
        guard let host, !host.isEmpty else { return false }
        return await Task.detached(priority: .utility) {
            let addresses = resolvedAddresses(for: host)
            return !addresses.isEmpty && addresses.allSatisfy(isPublicAddress)
        }.value
    }

    private static func resolvedAddresses(for host: String) -> [String] {
        #if canImport(Darwin)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, nil, &result) == 0, let first = result else {
            return []
        }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor?.pointee {
            if let address = entry.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    entry.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
                    addresses.append(String(decoding: buffer[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self))
                }
            }
            cursor = entry.ai_next
        }
        return Array(Set(addresses))
        #else
        return []
        #endif
    }

    static func isPublicAddress(_ address: String) -> Bool {
        #if canImport(Darwin)
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let a = UInt8((value >> 24) & 0xFF)
            let b = UInt8((value >> 16) & 0xFF)
            let c = UInt8((value >> 8) & 0xFF)
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 192 && b == 0 && (c == 0 || c == 2) { return false }
            if a == 192 && b == 88 && c == 99 { return false }
            if a == 198 && (b == 18 || b == 19) { return false }
            if a == 198 && b == 51 && c == 100 { return false }
            if a == 203 && b == 0 && c == 113 { return false }
            return true
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes.allSatisfy({ $0 == 0 }) { return false }
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false }
            if bytes[0] & 0xFE == 0xFC { return false }
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return false }
            if bytes[0] == 0xFF { return false }
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
                let mapped = "\(bytes[12]).\(bytes[13]).\(bytes[14]).\(bytes[15])"
                return isPublicAddress(mapped)
            }
            // The IANA well-known NAT64 prefix embeds an IPv4 destination;
            // validate that destination rather than allowing private v4 via
            // its synthesized v6 form.
            if bytes[0..<12].elementsEqual([0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0]) {
                let translated = "\(bytes[12]).\(bytes[13]).\(bytes[14]).\(bytes[15])"
                return isPublicAddress(translated)
            }

            // Public web endpoints should be global unicast (2000::/3).
            // Fail closed for every other IPv6 class and the non-global
            // special-purpose blocks that sit inside global unicast.
            guard bytes[0] & 0xE0 == 0x20 else { return false }
            if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] <= 0x01 { return false } // 2001::/23
            if bytes[0...3].elementsEqual([0x20, 0x01, 0x0D, 0xB8]) { return false } // documentation
            if bytes[0] == 0x20, bytes[1] == 0x02 { return false } // 6to4
            if bytes[0] == 0x3F, bytes[1] == 0xFF, bytes[2] & 0xF0 == 0 { return false } // documentation
            return true
        }
        #endif
        return false
    }
}

/// Bounds complete origin-discovery jobs, not merely connections to one host.
/// Each job performs at most one request at a time, so this also bounds active
/// URLSession tasks and decoded icon work across a document with many links.
private actor MarkdownLinkMetadataRequestLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var nextWaiterIndex = 0

    init(limit: Int) {
        availablePermits = max(1, limit)
    }

    func run<T: Sendable>(
        _ operation: @Sendable () async -> T
    ) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if nextWaiterIndex >= waiters.count {
            waiters.removeAll(keepingCapacity: true)
            nextWaiterIndex = 0
            availablePermits += 1
        } else {
            let continuation = waiters[nextWaiterIndex]
            nextWaiterIndex += 1
            continuation.resume()
        }
    }
}

private final class MarkdownNoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var publicEndpointResult: Bool?
    private var endpointContinuations: [CheckedContinuation<Bool, Never>] = []

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let addresses = metrics.transactionMetrics.compactMap(\.remoteAddress)
        let result = !addresses.isEmpty && addresses.allSatisfy(
            DefaultMarkdownLinkMetadataResolver.isPublicAddress
        )
        let continuations = lock.withLock { () -> [CheckedContinuation<Bool, Never>] in
            guard publicEndpointResult == nil else { return [] }
            publicEndpointResult = result
            let continuations = endpointContinuations
            endpointContinuations.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(returning: result) }
    }

    func contactedOnlyPublicAddresses() async -> Bool {
        await withCheckedContinuation { continuation in
            let result = lock.withLock { () -> Bool? in
                if let publicEndpointResult { return publicEndpointResult }
                endpointContinuations.append(continuation)
                return nil
            }
            if let result {
                continuation.resume(returning: result)
            }
        }
    }
}

private enum MarkdownLinkMetadataError: Error, CustomStringConvertible {
    case disallowedDestination
    case redirectLoop
    case redirectLimit
    case invalidResponse
    case httpStatus(Int)
    case tooLarge
    case unsupportedMIMEType
    case emptyResponse
    case resolutionTimeout

    var description: String {
        switch self {
        case .disallowedDestination: return "disallowed destination"
        case .redirectLoop: return "redirect loop"
        case .redirectLimit: return "redirect limit"
        case .invalidResponse: return "invalid response"
        case let .httpStatus(status): return "HTTP \(status)"
        case .tooLarge: return "response exceeds byte limit"
        case .unsupportedMIMEType: return "unsupported MIME type"
        case .emptyResponse: return "empty response"
        case .resolutionTimeout: return "origin resolution deadline exceeded"
        }
    }
}
