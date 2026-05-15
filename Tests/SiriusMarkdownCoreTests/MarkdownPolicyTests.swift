import Testing
@testable import SiriusMarkdownCore

@Test
func defaultPolicyRejectsUnsafeLinkSchemes() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "javascript:alert(1)") == .deny(reason: "URL scheme is disabled by default: javascript"))
    #expect(policy.evaluateLink(destination: "file:///tmp/secret") == .deny(reason: "URL scheme is disabled by default: file"))
    #expect(policy.evaluateLink(destination: "custom-scheme:value") == .deny(reason: "URL scheme is disabled by default: custom-scheme"))
    #expect(policy.evaluateLink(destination: "//example.com/path") == .deny(reason: "Protocol-relative external URLs are disabled by default."))
    #expect(policy.evaluateLink(destination: "https://example.com") == .allow)
    #expect(policy.evaluateLink(destination: "http://example.com") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com") == .allow)
    #expect(policy.evaluateLink(destination: "/relative/path") == .allow)
    #expect(policy.evaluateLink(destination: "relative/path") == .allow)
    #expect(policy.evaluateLink(destination: "#fragment") == .allow)
}

@Test
func defaultPolicyBlocksImageLoading() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateImage(source: "https://example.com/image.png", altText: "example") == .deny(reason: "Image loading is disabled by default."))
    #expect(policy.evaluateImage(source: "/local/image.png", altText: nil) == .deny(reason: "Image loading is disabled by default."))
}
