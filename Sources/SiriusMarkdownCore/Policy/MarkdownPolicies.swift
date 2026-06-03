import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum MarkdownPolicyDecision: Sendable, Hashable {
    case allow
    case deny(reason: String)
}

public protocol MarkdownLinkPolicy: Sendable {
    func evaluateLink(destination: String) -> MarkdownPolicyDecision
}

public protocol MarkdownLinkPolicyCacheIdentifying: Sendable {
    var linkPolicyCacheIdentity: String { get }
}

public protocol MarkdownLinkDestinationNormalizing: Sendable {
    func normalizedLinkDestination(for destination: String) -> String?
}

public protocol MarkdownImagePolicy: Sendable {
    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision
}

public protocol MarkdownImagePolicyCacheIdentifying: Sendable {
    var imagePolicyCacheIdentity: String { get }
}

public protocol MarkdownHTMLPolicy: Sendable {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision
}

public protocol MarkdownHTMLPolicyCacheIdentifying: Sendable {
    var htmlPolicyCacheIdentity: String { get }
}

public protocol MarkdownCodePolicy: Sendable {
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision
}

public protocol MarkdownCodePolicyCacheIdentifying: Sendable {
    var codePolicyCacheIdentity: String { get }
}

public protocol MarkdownMathPolicy: Sendable {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision
}

public protocol MarkdownMathPolicyCacheIdentifying: Sendable {
    var mathPolicyCacheIdentity: String { get }
}

public struct DefaultMarkdownPolicy:
    MarkdownLinkPolicy,
    MarkdownLinkDestinationNormalizing,
    MarkdownImagePolicy,
    MarkdownHTMLPolicy,
    MarkdownCodePolicy,
    MarkdownMathPolicy,
    MarkdownLinkPolicyCacheIdentifying,
    MarkdownImagePolicyCacheIdentifying,
    MarkdownHTMLPolicyCacheIdentifying,
    MarkdownCodePolicyCacheIdentifying,
    MarkdownMathPolicyCacheIdentifying
{
    public init() {}

    public var linkPolicyCacheIdentity: String {
        "siriusmarkdown.default-link-policy.v4"
    }

    public var imagePolicyCacheIdentity: String {
        "siriusmarkdown.default-image-policy.v1"
    }

    public var htmlPolicyCacheIdentity: String {
        "siriusmarkdown.default-html-policy.v1"
    }

    public var codePolicyCacheIdentity: String {
        "siriusmarkdown.default-code-policy.v1"
    }

    public var mathPolicyCacheIdentity: String {
        "siriusmarkdown.default-math-policy.v1"
    }

    public func evaluateLink(destination: String) -> MarkdownPolicyDecision {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = evaluateNormalizedLinkDestination(trimmed)
        guard case .allow = decision else {
            return decision
        }

        let htmlDecoded = htmlCharacterReferenceDecodedLinkDestination(trimmed)
        guard htmlDecoded != trimmed else {
            return decision
        }

        return evaluateNormalizedLinkDestination(htmlDecoded)
    }

    public func normalizedLinkDestination(for destination: String) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .allow = evaluateNormalizedLinkDestination(trimmed) else {
            return nil
        }

        let htmlDecoded = htmlCharacterReferenceDecodedLinkDestination(trimmed)
        guard htmlDecoded != trimmed else {
            return trimmed
        }

        guard case .allow = evaluateNormalizedLinkDestination(htmlDecoded) else {
            return nil
        }
        return htmlDecoded
    }

    public func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision {
        .deny(reason: "Image loading is disabled by default.")
    }

    public func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        .deny(reason: "Raw HTML is disabled by default.")
    }

    public func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision {
        .allow
    }

    public func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .allow
    }
}

private func evaluateNormalizedLinkDestination(_ trimmed: String) -> MarkdownPolicyDecision {
    guard !trimmed.isEmpty else {
        return .deny(reason: "Empty link destination.")
    }

    if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
        return .deny(reason: "Control characters are disabled in link destinations by default.")
    }

    if let schemeCandidate = leadingSchemeCandidate(in: trimmed) {
        switch schemeCandidate {
        case let .valid(scheme):
            switch scheme {
            case "http", "https":
                guard !containsInvalidRawHTTPURLCharacter(trimmed),
                      !containsInvalidDecodedHTTPURLCharacter(trimmed),
                      URL(string: trimmed) != nil
                else {
                    return .deny(reason: "Malformed URL destination.")
                }
                guard let url = URL(string: trimmed) else {
                    return .deny(reason: "Malformed URL destination.")
                }
                guard url.user == nil,
                      url.password == nil
                else {
                    return .deny(reason: "HTTP(S) link destinations cannot contain user info by default.")
                }
                guard let host = url.host,
                      !host.isEmpty
                else {
                    return .deny(reason: "HTTP(S) link destinations require a host by default.")
                }
                guard !containsInvalidHTTPPort(trimmed) else {
                    return .deny(reason: "Malformed URL destination.")
                }
                guard !containsPercentEncodedHTTPHostCharacter(trimmed) else {
                    return .deny(reason: "Malformed URL destination.")
                }
                guard !containsInvalidDecodedHTTPHostCharacter(host) else {
                    return .deny(reason: "Malformed URL destination.")
                }
                return .allow
            case "mailto":
                guard !containsInvalidRawMailtoURLCharacter(trimmed),
                      !containsInvalidDecodedMailtoURLCharacter(trimmed),
                      !containsInvalidDecodedMailtoRecipientCharacter(trimmed),
                      !containsUnsafeDecodedMailtoQueryValueDelimiter(trimmed),
                      URL(string: trimmed) != nil
                else {
                    return .deny(reason: "Malformed URL destination.")
                }
                if let unsafeHeader = unsafeMailtoHeaderFieldName(in: trimmed) {
                    return .deny(reason: "Unsafe mailto header field is disabled by default: \(unsafeHeader)")
                }
                return .allow
            default:
                return .deny(reason: "URL scheme is disabled by default: \(scheme)")
            }
        case .malformed:
            return .deny(reason: "Malformed URL scheme is disabled by default.")
        }
    }

    if trimmed.hasPrefix("//") {
        return .deny(reason: "Protocol-relative external URLs are disabled by default.")
    }

    guard !containsInvalidRelativeURLCharacter(trimmed) else {
        return .deny(reason: "Malformed URL destination.")
    }

    return .allow
}

private enum MarkdownLinkSchemeCandidate: Sendable, Hashable {
    case valid(String)
    case malformed
}

private func htmlCharacterReferenceDecodedLinkDestination(_ destination: String) -> String {
    var decoded = ""
    decoded.reserveCapacity(destination.count)

    var cursor = destination.startIndex
    while cursor < destination.endIndex {
        if destination[cursor] == "&",
           let reference = decodedHTMLCharacterReference(in: destination, at: cursor) {
            decoded.append(reference.character)
            cursor = reference.upperBound
        } else {
            decoded.append(destination[cursor])
            cursor = destination.index(after: cursor)
        }
    }

    return decoded
}

private func decodedHTMLCharacterReference(
    in destination: String,
    at ampersand: String.Index
) -> (character: Character, upperBound: String.Index)? {
    decodedHTMLNumericCharacterReference(in: destination, at: ampersand) ??
        decodedHTMLNamedCharacterReference(in: destination, at: ampersand)
}

private func decodedHTMLNumericCharacterReference(
    in destination: String,
    at ampersand: String.Index
) -> (character: Character, upperBound: String.Index)? {
    var cursor = destination.index(after: ampersand)
    guard cursor < destination.endIndex,
          destination[cursor] == "#"
    else {
        return nil
    }

    cursor = destination.index(after: cursor)
    var radix: UInt32 = 10
    if cursor < destination.endIndex,
       destination[cursor] == "x" || destination[cursor] == "X" {
        radix = 16
        cursor = destination.index(after: cursor)
    }

    var value: UInt32 = 0
    var hasDigit = false
    while cursor < destination.endIndex,
          let digit = htmlCharacterReferenceDigitValue(destination[cursor], radix: radix) {
        hasDigit = true
        guard value <= (0x10_FFFF - digit) / radix else {
            return nil
        }
        value = (value * radix) + digit
        cursor = destination.index(after: cursor)
    }

    guard hasDigit,
          let scalar = UnicodeScalar(value)
    else {
        return nil
    }

    if cursor < destination.endIndex,
       destination[cursor] == ";" {
        cursor = destination.index(after: cursor)
    }

    return (Character(scalar), cursor)
}

private func decodedHTMLNamedCharacterReference(
    in destination: String,
    at ampersand: String.Index
) -> (character: Character, upperBound: String.Index)? {
    let nameStart = destination.index(after: ampersand)
    for reference in htmlLinkDestinationNamedReferences() {
        guard destination[nameStart...].hasPrefix(reference.name),
              let nameEnd = destination.index(
                nameStart,
                offsetBy: reference.name.count,
                limitedBy: destination.endIndex
              )
        else {
            continue
        }

        if nameEnd < destination.endIndex,
           destination[nameEnd] == ";" {
            return (reference.character, destination.index(after: nameEnd))
        }

        if reference.allowsMissingSemicolon,
           (nameEnd == destination.endIndex || !isASCIIAlphanumeric(destination[nameEnd])) {
            return (reference.character, nameEnd)
        }
    }

    return nil
}

private func htmlLinkDestinationNamedReferences() -> [(name: String, character: Character, allowsMissingSemicolon: Bool)] {
    [
        ("NewLine", "\n", false),
        ("commat", "@", false),
        ("colon", ":", true),
        ("Tab", "\t", false),
        ("bsol", "\\", false),
        ("sol", "/", true)
    ]
}

private func htmlCharacterReferenceDigitValue(_ character: Character, radix: UInt32) -> UInt32? {
    guard let ascii = asciiValue(of: character) else {
        return nil
    }

    let value: UInt32?
    switch ascii {
    case 48...57:
        value = ascii - 48
    case 65...70:
        value = ascii - 55
    case 97...102:
        value = ascii - 87
    default:
        value = nil
    }

    guard let value,
          value < radix
    else {
        return nil
    }

    return value
}

private func leadingSchemeCandidate(in destination: String) -> MarkdownLinkSchemeCandidate? {
    var cursor = destination.startIndex
    while cursor < destination.endIndex {
        switch destination[cursor] {
        case ":":
            let candidate = destination[..<cursor]
            guard !candidate.isEmpty,
                  let first = candidate.first,
                  isASCIILetter(first),
                  candidate.dropFirst().allSatisfy(isSchemeContinuation)
            else {
                return .malformed
            }
            return .valid(candidate.lowercased())
        case "/", "?", "#":
            return nil
        default:
            cursor = destination.index(after: cursor)
        }
    }

    return nil
}

private func containsInvalidRawHTTPURLCharacter(_ destination: String) -> Bool {
    if destination.contains("\\") {
        return true
    }

    return destination.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
}

private func containsInvalidRawMailtoURLCharacter(_ destination: String) -> Bool {
    if destination.contains("\\") {
        return true
    }

    return destination.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
}

private func containsInvalidDecodedMailtoURLCharacter(_ destination: String) -> Bool {
    guard let decoded = destination.removingPercentEncoding else {
        return true
    }

    if decoded.contains("\\") {
        return true
    }

    return decoded.rangeOfCharacter(from: .controlCharacters) != nil
}

private func containsInvalidDecodedMailtoRecipientCharacter(_ destination: String) -> Bool {
    guard let schemeEnd = destination.firstIndex(of: ":") else {
        return true
    }

    let recipientStart = destination.index(after: schemeEnd)
    let recipientEnd = destination[recipientStart...].firstIndex { character in
        character == "?" || character == "#"
    } ?? destination.endIndex
    let rawRecipient = String(destination[recipientStart..<recipientEnd])
    guard let decodedRecipient = rawRecipient.removingPercentEncoding else {
        return true
    }

    if decodedRecipient.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
        return true
    }

    return decodedRecipient.contains("/") ||
        decodedRecipient.contains("?") ||
        decodedRecipient.contains("#")
}

private func unsafeMailtoHeaderFieldName(in destination: String) -> String? {
    guard let queryItems = URLComponents(string: destination)?.queryItems else {
        return nil
    }

    for item in queryItems {
        let name = item.name.lowercased()
        if name != "subject" {
            return name
        }
    }

    return nil
}

private func containsUnsafeDecodedMailtoQueryValueDelimiter(_ destination: String) -> Bool {
    guard destination.contains("?") else {
        return false
    }

    guard let queryItems = URLComponents(string: destination)?.queryItems else {
        return true
    }

    for item in queryItems {
        guard let value = item.value else {
            continue
        }

        if value.contains("&") || value.contains(";") {
            return true
        }
    }

    return false
}

private func containsPercentEncodedControlCharacter(_ destination: String) -> Bool {
    guard let decoded = destination.removingPercentEncoding else {
        return true
    }

    return decoded.rangeOfCharacter(from: .controlCharacters) != nil
}

private func containsInvalidDecodedHTTPURLCharacter(_ destination: String) -> Bool {
    guard let decoded = destination.removingPercentEncoding else {
        return true
    }

    if decoded.contains("\\") {
        return true
    }

    return decoded.rangeOfCharacter(from: .controlCharacters) != nil
}

private func containsPercentEncodedHTTPHostCharacter(_ destination: String) -> Bool {
    guard let schemeEnd = destination.firstIndex(of: ":") else {
        return false
    }

    let afterScheme = destination.index(after: schemeEnd)
    guard destination[afterScheme...].hasPrefix("//") else {
        return false
    }

    let authorityStart = destination.index(afterScheme, offsetBy: 2)
    let authorityEnd = destination[authorityStart...].firstIndex { character in
        character == "/" || character == "?" || character == "#"
    } ?? destination.endIndex

    var hostStart = authorityStart
    if let userInfoEnd = destination[authorityStart..<authorityEnd].lastIndex(of: "@") {
        hostStart = destination.index(after: userInfoEnd)
    }

    let hostRange: Range<String.Index>
    if hostStart < authorityEnd,
       destination[hostStart] == "[" {
        if let closingBracket = destination[hostStart..<authorityEnd].firstIndex(of: "]") {
            hostRange = hostStart..<destination.index(after: closingBracket)
        } else {
            hostRange = hostStart..<authorityEnd
        }
    } else if let portStart = destination[hostStart..<authorityEnd].firstIndex(of: ":") {
        hostRange = hostStart..<portStart
    } else {
        hostRange = hostStart..<authorityEnd
    }

    return destination[hostRange].contains("%")
}

private func containsInvalidHTTPPort(_ destination: String) -> Bool {
    guard let portRange = rawHTTPPortRange(in: destination) else {
        return false
    }

    let port = destination[portRange]
    guard !port.isEmpty,
          port.allSatisfy(isASCIIDigit)
    else {
        return true
    }

    var value = 0
    for digit in port {
        guard let ascii = asciiValue(of: digit) else {
            return true
        }
        value = (value * 10) + Int(ascii - 48)
        if value > 65_535 {
            return true
        }
    }

    return value == 0
}

private func rawHTTPPortRange(in destination: String) -> Range<String.Index>? {
    guard let schemeEnd = destination.firstIndex(of: ":") else {
        return nil
    }

    let afterScheme = destination.index(after: schemeEnd)
    guard destination[afterScheme...].hasPrefix("//") else {
        return nil
    }

    let authorityStart = destination.index(afterScheme, offsetBy: 2)
    let authorityEnd = destination[authorityStart...].firstIndex { character in
        character == "/" || character == "?" || character == "#"
    } ?? destination.endIndex

    var hostStart = authorityStart
    if let userInfoEnd = destination[authorityStart..<authorityEnd].lastIndex(of: "@") {
        hostStart = destination.index(after: userInfoEnd)
    }

    let portStart: String.Index?
    if hostStart < authorityEnd,
       destination[hostStart] == "[" {
        guard let closingBracket = destination[hostStart..<authorityEnd].firstIndex(of: "]") else {
            return nil
        }
        let afterBracket = destination.index(after: closingBracket)
        if afterBracket < authorityEnd,
           destination[afterBracket] == ":" {
            portStart = afterBracket
        } else {
            portStart = nil
        }
    } else {
        portStart = destination[hostStart..<authorityEnd].firstIndex(of: ":")
    }

    guard let portStart else {
        return nil
    }

    let portValueStart = destination.index(after: portStart)
    return portValueStart..<authorityEnd
}

private func containsInvalidRelativeURLCharacter(_ destination: String) -> Bool {
    guard let decoded = destination.removingPercentEncoding else {
        return true
    }

    if decoded.contains("\\") {
        return true
    }

    if decoded.rangeOfCharacter(from: .controlCharacters) != nil {
        return true
    }

    if decoded.hasPrefix("//") {
        return true
    }

    return leadingSchemeCandidate(in: decoded) != nil
}

private func containsInvalidDecodedHTTPHostCharacter(_ host: String) -> Bool {
    var invalidHostCharacters = CharacterSet.whitespacesAndNewlines
    invalidHostCharacters.formUnion(.controlCharacters)
    invalidHostCharacters.formUnion(CharacterSet(charactersIn: "/\\@?#[]"))
    if host.rangeOfCharacter(from: invalidHostCharacters) != nil {
        return true
    }

    return host.contains(":") && !isIPv6LiteralHost(host)
}

private func isIPv6LiteralHost(_ host: String) -> Bool {
#if canImport(Darwin)
    var address = in6_addr()
    return host.withCString { pointer in
        inet_pton(AF_INET6, pointer, &address) == 1
    }
#else
    return false
#endif
}

private func isSchemeContinuation(_ character: Character) -> Bool {
    isASCIILetter(character) ||
        isASCIIDigit(character) ||
        character == "+" ||
        character == "-" ||
        character == "."
}

private func isASCIILetter(_ character: Character) -> Bool {
    guard let value = asciiValue(of: character) else {
        return false
    }

    return (65...90).contains(value) || (97...122).contains(value)
}

private func isASCIIDigit(_ character: Character) -> Bool {
    guard let value = asciiValue(of: character) else {
        return false
    }

    return (48...57).contains(value)
}

private func isASCIIAlphanumeric(_ character: Character) -> Bool {
    isASCIILetter(character) || isASCIIDigit(character)
}

private func asciiValue(of character: Character) -> UInt32? {
    guard character.unicodeScalars.count == 1,
          let value = character.unicodeScalars.first?.value,
          value <= 127
    else {
        return nil
    }

    return value
}
