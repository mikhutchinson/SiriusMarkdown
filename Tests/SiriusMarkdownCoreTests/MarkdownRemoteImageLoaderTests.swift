import Foundation
import Testing
@testable import SiriusMarkdownCore

@Suite(.serialized)
struct MarkdownRemoteImageLoaderTests {
    @Test func imagesCoalesceAndCacheWithoutAmbientCredentials() async throws {
        ImageLoaderProtocol.state.reset()
        let configuration = configuration()
        configuration.httpAdditionalHeaders = ["Authorization": "secret", "Cookie": "ambient=secret", "Referer": "https://private.example/"]
        let loader = DefaultMarkdownRemoteImageLoader(limits: .init(cacheCapacity: 1), sessionConfiguration: configuration)
        let url = url("/image")
        let identities = try await withThrowingTaskGroup(of: UUID?.self) { group in
            for _ in 0..<20 { group.addTask { try await loader.resolveImage(for: url).cacheIdentity } }
            var values: [UUID?] = []
            for try await identity in group { values.append(identity) }
            return values
        }
        #expect(identities.count == 20)
        #expect(identities.allSatisfy { $0 != nil && $0 == identities.first! })
        #expect(ImageLoaderProtocol.state.requests.count == 1)
        let request = try #require(ImageLoaderProtocol.state.requests.first)
        for field in ["Authorization", "Cookie", "Referer", "Proxy-Authorization"] {
            #expect(request.value(forHTTPHeaderField: field) == nil)
        }
        guard case let .available(image) = loader.cachedResolution(for: url) else {
            Issue.record("Expected validated cached image"); return
        }
        #expect(image.pixelWidth == 1 && image.pixelHeight == 1)
        #expect(image.mimeType == "image/png")
        _ = try await loader.resolveImage(for: self.url("/second"))
        #expect(loader.cachedResolution(for: url) == nil)
    }

    @Test func imagePolicyRedirectByteAndDecodeLimitsAreEnforced() async throws {
        ImageLoaderProtocol.state.reset()
        let loader = DefaultMarkdownRemoteImageLoader(limits: .init(maximumBytes: 1024, maximumDimension: 1), sessionConfiguration: configuration())
        for destination in [URL(string: "http://93.184.216.34/image")!, URL(string: "https://127.0.0.1/image")!, url("/redirect"), url("/oversized"), url("/wide"), url("/bad-mime")] {
            guard case .unavailable = try await loader.resolveImage(for: destination) else {
                Issue.record("Unsafe or invalid image accepted: \(destination)"); continue
            }
        }
        let requests = ImageLoaderProtocol.state.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.url?.host == "93.184.216.34" })
        let count = requests.count
        _ = try await loader.resolveImage(for: url("/wide"))
        #expect(ImageLoaderProtocol.state.requests.count == count)
    }

    @Test func cancellationStopsLastSubscriberAndPendingWorkIsBounded() async throws {
        ImageLoaderProtocol.state.reset()
        let loader = DefaultMarkdownRemoteImageLoader(limits: .init(maximumConcurrentRequests: 1, maximumPendingRequests: 1), sessionConfiguration: configuration())
        let first = Task { try await loader.resolveImage(for: url("/hang")) }
        for _ in 0..<100 {
            if !ImageLoaderProtocol.state.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ImageLoaderProtocol.state.requests.count == 1)
        let second = Task { try await loader.resolveImage(for: url("/queued")) }
        // A third subscriber exceeds the bounded active + pending budget.
        try await Task.sleep(for: .milliseconds(30))
        do {
            _ = try await loader.resolveImage(for: url("/overflow"))
            Issue.record("Expected capacity rejection")
        } catch MarkdownRemoteImageLoaderError.capacityExceeded {} catch { Issue.record("Unexpected error: \(error)") }
        first.cancel()
        do { _ = try await first.value; Issue.record("Expected cancellation") } catch is CancellationError {}
        guard case .available = try await second.value else { Issue.record("Queued request failed"); return }
        #expect(loader.cachedResolution(for: url("/hang")) == nil)
        #expect(ImageLoaderProtocol.state.stoppedHang)
        #expect(ImageLoaderProtocol.state.requests.count == 2)
        await loader.removeAllCachedImages()
        #expect(loader.cachedResolution(for: url("/queued")) == nil)
    }

    private func url(_ path: String) -> URL { URL(string: "https://93.184.216.34" + path)! }
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageLoaderProtocol.self]
        return configuration
    }
}

private final class ImageLoaderProtocol: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private var stopped = false
        var requests: [URLRequest] { lock.withLock { recorded } }
        var stoppedHang: Bool { lock.withLock { stopped } }
        func reset() { lock.withLock { recorded = []; stopped = false } }
        func record(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
        func stop() { lock.withLock { stopped = true } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.record(request)
        let path = url.path
        var headers = ["Content-Type": path == "/bad-mime" ? "text/html" : "image/png"]
        if path == "/redirect" { headers["Location"] = "https://127.0.0.1/private" }
        let response = HTTPURLResponse(url: url, statusCode: path == "/redirect" ? 302 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/hang" { return }
        let image = path == "/wide"
            ? "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAAqADAAQAAAABAAAAAQAAAACJcORAAAAADklEQVQIHWNk+A+EQAAADAYCAMOu3HwAAAAASUVORK5CYII="
            : "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        client?.urlProtocol(self, didLoad: path == "/oversized" ? Data(repeating: 0, count: 2048) : Data(base64Encoded: image)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { if request.url?.path == "/hang" { Self.state.stop() } }
}
