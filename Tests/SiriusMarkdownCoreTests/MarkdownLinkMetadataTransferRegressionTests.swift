import Foundation
import Testing
@testable import SiriusMarkdownCore

@Suite(.serialized)
struct MarkdownLinkMetadataTransferRegressionTests {
    @Test
    func oversizedDocumentCancelsUnusedResponseBody() async throws {
        try await assertDocumentTransferIsCancelled(path: "/", mimeType: "text/html", bodySize: 2048)
    }

    @Test
    func rejectedDocumentMIMECancelsUnusedResponseBody() async throws {
        try await assertDocumentTransferIsCancelled(path: "/", mimeType: "application/octet-stream", bodySize: 1)
    }

    private func assertDocumentTransferIsCancelled(path: String, mimeType: String, bodySize: Int) async throws {
        HangingMetadataProtocol.state.install(mimeType: mimeType, bodySize: bodySize)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingMetadataProtocol.self]
        let resolver = DefaultMarkdownLinkMetadataResolver(
            limits: .init(maximumDocumentBytes: 1024, maximumIconCandidates: 1, requestTimeout: 1, maximumResolutionDuration: 1),
            sessionConfiguration: configuration
        )
        _ = await resolver.resolveMetadata(for: URL(string: "https://93.184.216.34/")!)
        for _ in 0..<100 {
            if HangingMetadataProtocol.state.documentWasStopped { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HangingMetadataProtocol.state.documentWasStopped)
    }
}

private final class HangingMetadataProtocol: URLProtocol, @unchecked Sendable {
    static let state = State()

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var mimeType = "text/html"
        private var bodySize = 2048
        private var stopped = false

        func install(mimeType: String, bodySize: Int) {
            lock.withLock {
                self.mimeType = mimeType
                self.bodySize = bodySize
                stopped = false
            }
        }

        var response: (String, Int) { lock.withLock { (mimeType, bodySize) } }
        var documentWasStopped: Bool { lock.withLock { stopped } }
        func recordStop() { lock.withLock { stopped = true } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/" {
            let (mimeType, size) = Self.state.response
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mimeType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(repeating: 32, count: size))
            // Intentionally never finish: the resolver owns abandoning bytes
            // beyond its limit, including responses rejected from their headers.
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        if request.url?.path == "/" { Self.state.recordStop() }
    }
}
