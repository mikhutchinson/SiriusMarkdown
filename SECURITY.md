# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in SiriusMarkdown, please report it privately. **Do not open a public issue.**

Email: **mikhutchinson@users.noreply.github.com**

Include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce, or a minimal code sample that demonstrates the issue.
- The SiriusMarkdown version or commit hash you tested against.

You should receive an acknowledgment within 72 hours. Fixes for confirmed vulnerabilities will be released as patch versions and credited in `changelog.md` unless you request otherwise.

## Scope

SiriusMarkdown is a Swift Package that processes untrusted Markdown input and renders it in SwiftUI. The following areas are in scope for security review:

- **Link policy**: `DefaultMarkdownPolicy` restricts URL schemes to `http`, `https`, `mailto`, and relative URLs. Bypasses that allow `javascript:`, `data:`, or `file:` schemes through the default policy are vulnerabilities.
- **Image policy**: The default policy does not fetch remote images. A code path that loads network resources without an explicit host resolver opt-in is a vulnerability.
- **Raw HTML policy**: Raw HTML is denied or rendered inertly by default. Execution of embedded scripts or injection of active content through the default HTML policy is a vulnerability.
- **JavaScriptCore evaluation**: The default code highlighter and Mermaid renderer execute vendored JavaScript bundles through JavaScriptCore in isolated context groups. Escapes from the JSC sandbox, cross-context data leaks, or crashes exploitable through crafted Markdown input are vulnerabilities.
- **Source buffer handling**: The append-only UTF-8 source buffer processes arbitrary byte sequences. Memory safety violations, out-of-bounds access, or denial-of-service through crafted input are vulnerabilities.

Out of scope:

- Vulnerabilities in `swift-markdown` itself (report those to the [Swift project](https://github.com/swiftlang/swift-markdown)).
- Rendering artifacts or layout bugs that do not have a security impact.
- Behavior that requires the host application to explicitly opt in through custom policy protocols (e.g., a custom `MarkdownLinkPolicy` that allows `javascript:` URLs).

## Supported versions

Security fixes are applied to the latest release. Older minor versions do not receive backports unless the severity warrants it.

| Version | Supported |
| --- | --- |
| Latest release (`0.4.x`) | Yes |
| Older minor versions | Case by case |

## Design principles

SiriusMarkdown's default configuration is designed to be safe for rendering untrusted input:

- Policy protocols govern every category of potentially dangerous content (links, images, HTML, code, math).
- Host applications must explicitly opt in to broader behavior through policy hooks.
- JavaScriptCore contexts for highlight.js and Mermaid run in isolated VM groups to prevent cross-runtime interference.
- No network requests are made by the package unless a host application provides an explicit image resolver.
