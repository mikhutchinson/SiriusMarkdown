import Foundation

struct MarkdownRemoteHTTPPayload: Sendable {
    var data: Data
    var response: HTTPURLResponse
    var finalURL: URL
}

/// Shared bounded transport for decorative metadata and explicitly opted-in
/// images. Every path uses the same redirect, DNS, endpoint and privacy checks.
final class MarkdownRemoteResourceTransport: @unchecked Sendable {
    let policy: any MarkdownRemoteResourcePolicy
    let limits: DefaultMarkdownLinkMetadataResolver.Limits
    let sessionConfiguration: URLSessionConfiguration

    init(policy: any MarkdownRemoteResourcePolicy, limits: DefaultMarkdownLinkMetadataResolver.Limits, sessionConfiguration: URLSessionConfiguration) {
        self.policy = policy
        self.limits = limits
        self.sessionConfiguration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
    }

    func fetch(
        _ initialURL: URL,
        kind: MarkdownRemoteResourceKind,
        maximumBytes: Int,
        acceptedMIMETypes: Set<String>,
        deadline: Date
    ) async throws -> MarkdownRemoteHTTPPayload {
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
        configuration.timeoutIntervalForResource = max(0.1, min(limits.maximumResolutionDuration, deadline.timeIntervalSinceNow))
        let usesCustomProtocol = configuration.protocolClasses?.isEmpty == false
        let redirectDelegate = MarkdownNoRedirectURLSessionDelegate()
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var startedRequestCount = 0

        for redirectCount in 0...limits.maximumRedirects {
            try Task.checkCancellation()
            guard deadline > Date() else {
                throw MarkdownLinkMetadataError.resolutionTimeout
            }
            guard visited.insert(currentURL).inserted else {
                throw MarkdownLinkMetadataError.redirectLoop
            }
            guard case .allow = policy.evaluateRemoteResource(currentURL, kind: kind),
                  await DefaultMarkdownLinkMetadataResolver.hostResolvesOnlyToPublicAddresses(currentURL.host)
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
            request.setValue(kind == .linkMetadataDocument ? "text/html,application/xhtml+xml" : "image/*", forHTTPHeaderField: "Accept")
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

            startedRequestCount += 1
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
                // Manual redirects do not consume their response body. End
                // that transfer before opening the next one or awaiting metrics.
                bytes.task.cancel()
                currentURL = redirected
                continue
            }
            let mimeType = Self.normalizedMIMEType(http.mimeType)
            if kind == .image, mimeType.map(acceptedMIMETypes.contains) != true {
                throw MarkdownLinkMetadataError.unsupportedMIMEType
            }
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
                        // Cancellation also completes endpoint metrics without
                        // waiting for the unused (possibly endless) body.
                        bytes.task.cancel()
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
                : await redirectDelegate.contactedOnlyPublicAddresses(
                    afterCollecting: startedRequestCount
                )
            guard contactedOnlyPublicAddresses else {
                throw MarkdownLinkMetadataError.disallowedDestination
            }
            return MarkdownRemoteHTTPPayload(data: data, response: http, finalURL: currentURL)
        }
        throw MarkdownLinkMetadataError.redirectLimit
    }

    private static func normalizedMIMEType(_ value: String?) -> String? {
        value?.split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
}
