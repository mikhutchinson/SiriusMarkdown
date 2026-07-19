import Foundation
import Testing
@testable import SiriusMarkdownCore

@Suite(.serialized)
struct MarkdownLinkMetadataResolverTests {
    private let origin = URL(string: "https://93.184.216.34/")!

    @Test
    func discoversRelativeHTMLIconAndCachesValidatedBytes() async throws {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<html><head><title>Example</title><link rel=\"icon\" sizes=\"32x32\" href=\"/icon.png\"></head></html>")
            case "/icon.png":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }
        let resolver = makeResolver()

        let first = await resolver.resolveMetadata(for: origin)
        guard case let .metadata(metadata) = first,
              case let .favicon(icon) = metadata.decoration
        else {
            Issue.record("Expected validated favicon metadata")
            return
        }
        #expect(metadata.title == "Example")
        #expect(icon.sourceURL.path == "/icon.png")
        #expect(icon.pixelWidth == 1)
        #expect(icon.pixelHeight == 1)
        #expect(icon.data == Self.onePixelPNG)

        let cached = await resolver.resolveMetadata(for: origin.appending(path: "another-page"))
        #expect(cached == first)
        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/") == 1)
        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/icon.png") == 1)
    }

    @Test
    func concurrentRequestsForOneOriginAreCoalesced() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<link rel=\"shortcut icon\" href=\"/favicon.ico\">")
            case "/favicon.ico":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }
        let resolver = makeResolver()

        await withTaskGroup(of: MarkdownLinkMetadataResolution.self) { group in
            for index in 0..<20 {
                group.addTask {
                    await resolver.resolveMetadata(for: self.origin.appending(path: "page-\(index)"))
                }
            }
            for await resolution in group {
                guard case .metadata = resolution else {
                    Issue.record("Coalesced resolution unexpectedly failed")
                    continue
                }
            }
        }

        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/") == 1)
        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/favicon.ico") == 1)
    }

    @Test
    func originDiscoveryConcurrencyIsGloballyBounded() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            request.url?.path == "/"
                ? .html("<link rel=icon href=/icon.png>", delayNanoseconds: 40_000_000)
                : .png(Self.onePixelPNG, delayNanoseconds: 40_000_000)
        }
        let resolver = makeResolver(limits: .init(maximumConcurrentOrigins: 2, requestTimeout: 2))

        await withTaskGroup(of: MarkdownLinkMetadataResolution.self) { group in
            for suffix in 34...41 {
                group.addTask {
                    await resolver.resolveMetadata(
                        for: URL(string: "https://93.184.216.\(suffix)/")!
                    )
                }
            }
            for await resolution in group {
                #expect(resolution != .unavailable)
            }
        }

        #expect(MarkdownLinkMetadataMockRegistry.shared.maximumConcurrentRequestCount <= 2)
    }

    @Test
    func clearingCacheCannotBeUndoneByAnInFlightCancellation() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            request.url?.path == "/"
                ? .html("<link rel=icon href=/icon.png>", delayNanoseconds: 250_000_000)
                : .png(Self.onePixelPNG)
        }
        let resolver = makeResolver()
        let resolutionTask = Task {
            await resolver.resolveMetadata(for: origin)
        }

        while MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/") == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        resolver.removeAllCachedMetadata()
        _ = await resolutionTask.value

        #expect(resolver.cachedResolution(for: origin) == nil)
        #expect(resolver.failureDescriptions(for: origin).isEmpty)
    }

    @Test
    func rejectsRedirectsToPrivateNetworkAddresses() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .redirect("https://127.0.0.1/private-icon.png")
            case "/favicon.ico":
                return .status(404)
            default:
                Issue.record("Private redirect target should never be requested: \(request.url?.absoluteString ?? "nil")")
                return .status(500)
            }
        }
        let resolver = makeResolver()

        let resolution = await resolver.resolveMetadata(for: origin)
        #expect(resolution == .unavailable)
        #expect(MarkdownLinkMetadataMockRegistry.shared.totalRequestCount == 2)
    }

    @Test
    func negativeResultsAreCachedWithoutRefetching() async {
        MarkdownLinkMetadataMockRegistry.shared.install { _ in .status(404) }
        let resolver = makeResolver()

        #expect(await resolver.resolveMetadata(for: origin) == .unavailable)
        let countAfterFirstAttempt = MarkdownLinkMetadataMockRegistry.shared.totalRequestCount
        #expect(await resolver.resolveMetadata(for: origin) == .unavailable)
        #expect(MarkdownLinkMetadataMockRegistry.shared.totalRequestCount == countAfterFirstAttempt)
        #expect(resolver.cachedResolution(for: origin) == .unavailable)
    }

    @Test
    func cacheAndFailureDiagnosticsEvictTogetherAtCapacity() async {
        MarkdownLinkMetadataMockRegistry.shared.install { _ in .status(404) }
        let resolver = makeResolver(limits: .init(requestTimeout: 2, cacheCapacity: 2))
        let origins = (34...36).map { URL(string: "https://93.184.216.\($0)/")! }

        for origin in origins {
            #expect(await resolver.resolveMetadata(for: origin) == .unavailable)
        }

        #expect(resolver.cachedResolution(for: origins[0]) == nil)
        #expect(resolver.failureDescriptions(for: origins[0]).isEmpty)
        #expect(resolver.cachedResolution(for: origins[1]) == .unavailable)
        #expect(resolver.cachedResolution(for: origins[2]) == .unavailable)
    }

    @Test
    func doesNotMisclassifyPublic192DotZeroNetworksAsPrivate() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            request.url?.path == "/favicon.ico" ? .png(Self.onePixelPNG) : .html("<title>Public host</title>")
        }
        let resolver = makeResolver()
        let publicAutomatticRange = URL(string: "https://192.0.77.32/")!

        let resolution = await resolver.resolveMetadata(for: publicAutomatticRange)
        guard case .metadata = resolution else {
            Issue.record("192.0.77.0/24 is public and must not be rejected as 192.0.0.0/24")
            return
        }
    }

    @Test
    func discoversUnquotedRootRelativeIconAttributesUsedByNature() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<link rel=\"icon\" type=\"image/png\" sizes=\"32x32\" href=/static/favicon.png>")
            case "/static/favicon.png":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }
        let resolver = makeResolver()
        let resolution = await resolver.resolveMetadata(for: origin)
        guard case .metadata = resolution else {
            Issue.record("Valid unquoted root-relative href was not discovered")
            return
        }
    }

    @Test
    func defaultRedirectBudgetAllowsLegitimateFiveHopMetadataNavigation() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .redirect("https://93.184.216.34/step-1")
            case "/step-1":
                return .redirect("https://93.184.216.34/step-2")
            case "/step-2":
                return .redirect("https://93.184.216.34/step-3")
            case "/step-3":
                return .redirect("https://93.184.216.34/step-4")
            case "/step-4":
                return .redirect("https://93.184.216.34/step-5")
            case "/step-5":
                return .html("<link rel=icon href=/brand.png>")
            case "/brand.png":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }

        guard case .metadata = await makeResolver().resolveMetadata(for: origin) else {
            Issue.record("Default redirect budget rejected a bounded five-hop public navigation")
            return
        }
    }

    @Test
    func navigationHeadersAndBoundedClientErrorHTMLDiscoverDeclaredIcon() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch (request.url?.host, request.url?.path) {
            case ("93.184.216.34", "/"):
                #expect(request.value(forHTTPHeaderField: "Sec-Fetch-Site") == "none")
                #expect(request.value(forHTTPHeaderField: "Sec-Fetch-Mode") == "navigate")
                #expect(request.value(forHTTPHeaderField: "Sec-Fetch-Dest") == "document")
                #expect(request.value(forHTTPHeaderField: "Upgrade-Insecure-Requests") == "1")
                return .html(
                    "<link rel=icon href=https://93.184.216.35/error-page-icon.png>",
                    statusCode: 400
                )
            case ("93.184.216.35", "/error-page-icon.png"):
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }

        guard case let .metadata(metadata) = await makeResolver().resolveMetadata(for: origin),
              case let .favicon(icon) = metadata.decoration
        else {
            Issue.record("Bounded public 4xx metadata did not yield its declared icon")
            return
        }
        #expect(icon.sourceURL.host == "93.184.216.35")
    }

    @Test
    func authenticationChallengeHTMLCannotSupplyDecorativeMetadata() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<link rel=icon href=/must-not-load.png>", statusCode: 401)
            case "/must-not-load.png":
                Issue.record("Authentication challenge metadata must not be followed")
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }

        let resolver = makeResolver()
        #expect(await resolver.resolveMetadata(for: origin) == .unavailable)
        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/must-not-load.png") == 0)
    }

    @Test
    func usesConventionalAppleTouchIconWhenDocumentHasNoDeclaration() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<title>No explicit icon</title>")
            case "/apple-touch-icon.png":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }

        guard case let .metadata(metadata) = await makeResolver().resolveMetadata(for: origin),
              case let .favicon(icon) = metadata.decoration
        else {
            Issue.record("Conventional Apple touch icon was not used")
            return
        }
        #expect(icon.sourceURL.path == "/apple-touch-icon.png")
    }

    @Test
    func squareOpenGraphImageIsLastResortAfterUnrenderableDeclaredIcon() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html(
                    """
                    <link rel=icon href=/vector.svg>
                    <meta property=og:image content=https://93.184.216.34/square-brand.png>
                    """
                )
            case "/vector.svg":
                return .svg("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
            case "/square-brand.png":
                return .png(Self.onePixelPNG)
            default:
                return .status(404)
            }
        }

        guard case let .metadata(metadata) = await makeResolver().resolveMetadata(for: origin),
              case let .favicon(icon) = metadata.decoration
        else {
            Issue.record("Square Open Graph fallback was not used")
            return
        }
        #expect(icon.sourceURL.path == "/square-brand.png")
    }

    @Test
    func nonSquareOpenGraphArtworkCannotBecomeALinkIcon() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch request.url?.path {
            case "/":
                return .html("<meta property=og:image content=/wide-artwork.png>")
            case "/wide-artwork.png":
                return .png(Self.twoByOnePNG)
            default:
                return .status(404)
            }
        }

        let resolver = makeResolver()
        #expect(await resolver.resolveMetadata(for: origin) == .unavailable)
        #expect(
            resolver.failureDescriptions(for: origin).contains {
                $0.contains("is not square fallback artwork")
            }
        )
    }

    @Test
    func authoredCDNIconOutranksConventionalOriginFallback() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            switch (request.url?.host, request.url?.path) {
            case ("93.184.216.34", "/"):
                return .html("<link rel=icon href=https://93.184.216.35/brand.png>")
            case ("93.184.216.35", "/brand.png"):
                return .png(Self.onePixelPNG)
            case ("93.184.216.34", "/favicon.ico"):
                Issue.record("Fallback must not outrank an authored icon declaration")
                return .status(500)
            default:
                return .status(404)
            }
        }
        let resolver = makeResolver()

        guard case let .metadata(metadata) = await resolver.resolveMetadata(for: origin),
              case let .favicon(icon) = metadata.decoration
        else {
            Issue.record("Expected authored CDN favicon")
            return
        }
        #expect(icon.sourceURL.host == "93.184.216.35")
        #expect(MarkdownLinkMetadataMockRegistry.shared.requestCount(forPath: "/favicon.ico") == 0)
    }

    @Test
    func stripsAmbientCredentialsCookiesAndReferrers() async {
        MarkdownLinkMetadataMockRegistry.shared.install { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Proxy-Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Referer") == nil)
            return request.url?.path == "/favicon.ico"
                ? .png(Self.onePixelPNG)
                : .html("<title>Anonymous</title>")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarkdownLinkMetadataMockURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer ambient-secret",
            "Cookie": "ambient=cookie",
            "Proxy-Authorization": "Basic ambient-secret",
            "Referer": "https://private.example/"
        ]
        let resolver = DefaultMarkdownLinkMetadataResolver(
            limits: .init(requestTimeout: 2),
            sessionConfiguration: configuration
        )

        guard case .metadata = await resolver.resolveMetadata(for: origin) else {
            Issue.record("Anonymous intercepted request did not resolve")
            return
        }
    }

    @Test
    func addressClassificationRejectsEveryPrivateAndSpecialWebDestination() {
        let denied = [
            "0.0.0.1", "10.0.0.1", "100.64.0.1", "127.0.0.1", "169.254.1.1",
            "172.16.0.1", "192.0.0.8", "192.0.2.1", "192.88.99.1", "192.168.1.1",
            "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
            "::", "::1", "::ffff:127.0.0.1", "64:ff9b::7f00:1", "64:ff9b:1::1",
            "100::1", "2001::1", "2001:2::1", "2001:db8::1", "2002::1",
            "3fff::1", "5f00::1", "fc00::1", "fe80::1", "ff02::1"
        ]
        let allowed = [
            "8.8.8.8", "192.0.77.32", "192.31.196.1", "192.175.48.1",
            "64:ff9b::808:808", "2606:4700:4700::1111"
        ]

        #expect(denied.allSatisfy { !DefaultMarkdownLinkMetadataResolver.isPublicAddress($0) })
        #expect(allowed.allSatisfy(DefaultMarkdownLinkMetadataResolver.isPublicAddress))
    }

    private func makeResolver(
        limits: DefaultMarkdownLinkMetadataResolver.Limits = .init(requestTimeout: 2)
    ) -> DefaultMarkdownLinkMetadataResolver {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarkdownLinkMetadataMockURLProtocol.self]
        return DefaultMarkdownLinkMetadataResolver(
            limits: limits,
            sessionConfiguration: configuration
        )
    }

    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private static let twoByOnePNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAAqADAAQAAAABAAAAAQAAAACJcORAAAAADklEQVQIHWNk+A+EQAAADAYCAMOu3HwAAAAASUVORK5CYII="
    )!
}

private struct MarkdownLinkMetadataMockResponse: Sendable {
    var statusCode: Int
    var headers: [String: String]
    var data: Data
    var delayNanoseconds: UInt64 = 0

    static func html(
        _ html: String,
        statusCode: Int = 200,
        delayNanoseconds: UInt64 = 0
    ) -> Self {
        Self(
            statusCode: statusCode,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            data: Data(html.utf8),
            delayNanoseconds: delayNanoseconds
        )
    }

    static func svg(_ svg: String) -> Self {
        Self(
            statusCode: 200,
            headers: ["Content-Type": "image/svg+xml"],
            data: Data(svg.utf8)
        )
    }

    static func png(_ data: Data, delayNanoseconds: UInt64 = 0) -> Self {
        Self(
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            data: data,
            delayNanoseconds: delayNanoseconds
        )
    }

    static func redirect(_ location: String) -> Self {
        Self(statusCode: 302, headers: ["Location": location], data: Data())
    }

    static func status(_ code: Int) -> Self {
        Self(statusCode: code, headers: [:], data: Data("status".utf8))
    }
}

private final class MarkdownLinkMetadataMockRegistry: @unchecked Sendable {
    static let shared = MarkdownLinkMetadataMockRegistry()

    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) -> MarkdownLinkMetadataMockResponse)?
    private var counts: [String: Int] = [:]
    private var activeRequestCount = 0
    private var maximumActiveRequestCount = 0

    var totalRequestCount: Int {
        lock.withLock { counts.values.reduce(0, +) }
    }

    var maximumConcurrentRequestCount: Int {
        lock.withLock { maximumActiveRequestCount }
    }

    func install(_ handler: @escaping @Sendable (URLRequest) -> MarkdownLinkMetadataMockResponse) {
        lock.withLock {
            self.handler = handler
            counts.removeAll()
            activeRequestCount = 0
            maximumActiveRequestCount = 0
        }
    }

    func response(for request: URLRequest) -> MarkdownLinkMetadataMockResponse {
        lock.withLock {
            counts[request.url?.path ?? "nil", default: 0] += 1
            activeRequestCount += 1
            maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)
            return handler?(request) ?? .status(500)
        }
    }

    func requestDidComplete() {
        lock.withLock {
            activeRequestCount = max(0, activeRequestCount - 1)
        }
    }

    func requestCount(forPath path: String) -> Int {
        lock.withLock { counts[path, default: 0] }
    }
}

private final class MarkdownLinkMetadataMockURLProtocol: URLProtocol, @unchecked Sendable {
    private let stateLock = NSLock()
    private var isStopped = false
    private var didFinishTracking = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = MarkdownLinkMetadataMockRegistry.shared.response(for: request)
        let deliver: @Sendable () -> Void = { [weak self] in
            self?.deliver(result)
        }
        if result.delayNanoseconds > 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .nanoseconds(Int(result.delayNanoseconds)),
                execute: deliver
            )
        } else {
            deliver()
        }
    }

    override func stopLoading() {
        stateLock.withLock { isStopped = true }
        finishTrackingRequest()
    }

    private func deliver(_ result: MarkdownLinkMetadataMockResponse) {
        guard !stateLock.withLock({ isStopped }) else { return }
        defer { finishTrackingRequest() }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !result.data.isEmpty {
            client?.urlProtocol(self, didLoad: result.data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func finishTrackingRequest() {
        let shouldFinish = stateLock.withLock { () -> Bool in
            guard !didFinishTracking else { return false }
            didFinishTracking = true
            return true
        }
        if shouldFinish {
            MarkdownLinkMetadataMockRegistry.shared.requestDidComplete()
        }
    }
}
