# Notices

SiriusMarkdown is distributed under the MIT License. The project also relies on and credits these third-party projects:

- `swift-markdown` by the Swift project and Apple Inc. provides the runtime Markdown parsing semantics. It is licensed under Apache License 2.0. See `Package.resolved` for the pinned revision used by this checkout.
- `highlight.js` provides the embedded common-language grammar bundle used by `DefaultMarkdownCodeHighlighter`. SiriusMarkdown vendors the pinned browser build as a SwiftPM resource and uses it locally through JavaScriptCore. It is licensed under the BSD 3-Clause License; the bundled license lives at `Sources/SiriusMarkdownSwiftUI/Resources/HighlightJS/LICENSE-BSD-3-Clause.txt`.
- `beautiful-mermaid` by Craft Docs provides the bundled Mermaid-compatible diagram runtime used by `DefaultMarkdownMermaidRenderer`. SiriusMarkdown vendors a locally bundled JavaScript build as a SwiftPM resource and executes it through JavaScriptCore. It is licensed under the MIT License; the bundled license lives at `Sources/SiriusMarkdownSwiftUI/Resources/MermaidJS/LICENSE-MIT.txt`.
- `@chenglou/pretext` by Cheng Lou provides the JavaScript text-layout oracle used by `Tools/pretext-golden` for golden layout comparisons. It is licensed under the MIT License. SiriusMarkdown uses Pretext as a development and release-gate reference; the Swift runtime does not vendor or execute Pretext.
- `@napi-rs/canvas` provides the Node canvas measurement context used by `Tools/pretext-golden` when running Pretext outside a browser. It is licensed under the MIT License.
- `linebreak` by Devon Govett provides the vendored JavaScript UAX #14 line-breaking oracle used by `Tools/pretext-golden` for transcript/path wrapping fixtures. It is licensed under the MIT License; the bundled license lives at `Tools/pretext-golden/vendor/linebreak/package/LICENSE`. Its vendored runtime dependencies, `unicode-trie`, `base64-js`, and `tiny-inflate`, are also MIT-licensed and include their package metadata and available license/readme files under `Tools/pretext-golden/vendor/linebreak/package/node_modules`.

Pinned Node tool versions are recorded in `Tools/pretext-golden/package-lock.json`.
