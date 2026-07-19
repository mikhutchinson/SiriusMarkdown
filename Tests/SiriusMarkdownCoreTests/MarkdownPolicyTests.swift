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
    #expect(policy.evaluateLink(destination: "http://localhost") == .allow)
    #expect(policy.evaluateLink(destination: "http://[::1]") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com") == .allow)
    #expect(policy.evaluateLink(destination: "/relative/path") == .allow)
    #expect(policy.evaluateLink(destination: "relative/path") == .allow)
    #expect(policy.evaluateLink(destination: "#fragment") == .allow)
}

@Test
func defaultPolicyRejectsControlCharacterLinkDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "java\nscript:alert(1)") == .deny(reason: "Control characters are disabled in link destinations by default."))
    #expect(policy.evaluateLink(destination: "java\tscript:alert(1)") == .deny(reason: "Control characters are disabled in link destinations by default."))
    #expect(policy.evaluateLink(destination: "java\u{0000}script:alert(1)") == .deny(reason: "Control characters are disabled in link destinations by default."))
}

@Test
func defaultPolicyRejectsMalformedAbsoluteLinkDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "http://exa mple.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "http://") == .deny(reason: "HTTP(S) link destinations require a host by default."))
    #expect(policy.evaluateLink(destination: "https://") == .deny(reason: "HTTP(S) link destinations require a host by default."))
    #expect(policy.evaluateLink(destination: "http:example.com") == .deny(reason: "HTTP(S) link destinations require a host by default."))
    #expect(policy.evaluateLink(destination: "https://example.com:443/path") == .allow)
    #expect(policy.evaluateLink(destination: "http://localhost:8080/path") == .allow)
    #expect(policy.evaluateLink(destination: "http://[::1]:8080/path") == .allow)
    #expect(policy.evaluateLink(destination: "https://example.com:/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com:999999999999/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://[::1]:999999999999/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "java%0ascript:alert(1)") == .deny(reason: "Malformed URL scheme is disabled by default."))
    #expect(policy.evaluateLink(destination: "docs/foo:bar") == .allow)
    #expect(policy.evaluateLink(destination: "relative path") == .allow)
}

@Test
func defaultPolicyRejectsAmbiguousHTTPDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "https://example.com\\@evil.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com/path\\segment") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://exa%20mple.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://exa%00mple.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com/%0a") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com/a%20b") == .allow)
}

@Test
func defaultPolicyRejectsPercentEncodedHTTPDelimiterSmuggling() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "https://example.com%5C@evil.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://exa%5Cmple.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com%2F.evil.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com%40evil.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com%3A443/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com%3Aevil/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://%65xample.com/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example%2ecom/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example%2Dadmin.com/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://%31%32%37.0.0.1/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com/%5C@evil.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com/a%5Cb") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https://example.com@evil.com") == .deny(reason: "HTTP(S) link destinations cannot contain user info by default."))
    #expect(policy.evaluateLink(destination: "https://user:pass@example.com") == .deny(reason: "HTTP(S) link destinations cannot contain user info by default."))
    #expect(policy.evaluateLink(destination: "https://example.com/a%2Fb") == .allow)
    #expect(policy.evaluateLink(destination: "http://[::1]") == .allow)
}

@Test
func defaultPolicyRejectsAmbiguousMailtoDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "mailto:user@example.com") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello%20there") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?SUBJECT=Hello%20there") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello there") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%20attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com\\evil") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%5Cevil") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hi%5Cthere") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%3Fbcc=attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%3Fsubject=Hi%26bcc=attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%23fragment") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto://evil@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:/user@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com/evil") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:%2F%2Fevil@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%2Fevil") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?bcc=attacker@example.com") == .deny(reason: "Unsafe mailto header field is disabled by default: bcc"))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?cc=copy@example.com") == .deny(reason: "Unsafe mailto header field is disabled by default: cc"))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?body=secret") == .deny(reason: "Unsafe mailto header field is disabled by default: body"))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?x-custom=1") == .deny(reason: "Unsafe mailto header field is disabled by default: x-custom"))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%0aBcc:attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello%0d%0aBcc:attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com%00") == .deny(reason: "Malformed URL destination."))
}

@Test
func defaultPolicyRejectsEncodedMailtoQuerySeparators() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello%26bcc=attacker@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello%3Bcc=copy@example.com") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Hello%20there") == .allow)
    #expect(policy.evaluateLink(destination: "mailto:user@example.com?subject=Question%3F") == .allow)
}

@Test
func defaultPolicyRejectsAmbiguousRelativeDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "/safe%20path") == .allow)
    #expect(policy.evaluateLink(destination: "relative%20path") == .allow)
    #expect(policy.evaluateLink(destination: "/bad%0apath") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "docs%00path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "relative%0d%0aHeader") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "100%") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "%ZZ") == .deny(reason: "Malformed URL destination."))
}

@Test
func defaultPolicyRejectsRelativeBackslashDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "/docs\\admin") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "docs\\admin") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "/docs%5Cadmin") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "docs%5Cadmin") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "%5C%5Cexample.com/path") == .deny(reason: "Malformed URL destination."))
}

@Test
func defaultPolicyRejectsPercentEncodedAbsoluteRelativeDestinations() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateLink(destination: "javascript%3Aalert(1)") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "file%3A///tmp/secret") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "https%3A//example.com/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "%2F%2Fexample.com/path") == .deny(reason: "Malformed URL destination."))
    #expect(policy.evaluateLink(destination: "docs/foo%3Abar") == .allow)
}

@Test
func defaultPolicyRejectsHTMLEntityEncodedAbsoluteRelativeDestinations() throws {
    let policy = DefaultMarkdownPolicy()
    let unsafeDestinations = [
        try parsedLinkDestination("[x](javascript&#58alert)"),
        try parsedLinkDestination("[x](javascript&#x3A-alert)"),
        try parsedLinkDestination("[x](file&#58///tmp/secret)"),
        try parsedLinkDestination("[x](file&#x3A///tmp/secret)"),
        try parsedLinkDestination("[x](data&#58text/html;base64,SGVsbG8=)"),
        try parsedLinkDestination("[x](&#47&#47example.com/path)")
    ]

    for destination in unsafeDestinations {
        if case .allow = policy.evaluateLink(destination: destination) {
            Issue.record("Unsafe entity-encoded destination was allowed: \(destination)")
        }
    }

    #expect(policy.evaluateLink(destination: try parsedLinkDestination("[x](https&#58//example.com/path)")) == .allow)
    #expect(policy.evaluateLink(destination: try parsedLinkDestination("[x](docs&#47safe)")) == .allow)
}

@Test
func defaultPolicyBlocksImageLoading() {
    let policy = DefaultMarkdownPolicy()

    #expect(policy.evaluateImage(source: "https://example.com/image.png", altText: "example") == .deny(reason: "Image loading is disabled by default."))
    #expect(policy.evaluateImage(source: "/local/image.png", altText: nil) == .deny(reason: "Image loading is disabled by default."))
}

@Test
func defaultPolicyAllowsOnlyTheSanitizedNativeHTMLPath() {
    let policy = DefaultMarkdownPolicy()
    #expect(policy.evaluateHTML("<script>alert(1)</script>") == .allow)
    // Authorization here is not execution authorization: parser tests prove
    // active subtrees are dropped and links/images retain their own policies.
}

private func parsedLinkDestination(_ markdown: String) throws -> String {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()

    let link = try #require(stream.snapshot().blocks.flatMap(\.inlines).first { $0.destination != nil })
    return try #require(link.destination)
}
