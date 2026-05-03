# DemoSupport

Shared SwiftUI support package for the bundled macOS demos.

`DemoSupport` keeps demo-only presentation tokens and shell components out of
the public renderer package while giving `MarkdownDemoApp`,
`DocumentReaderDemo`, and `StreamingTranscriptDemo` one visual language.

Included primitives:

- macOS color tokens for window, document, inspector, separator, and quiet fills.
- Sidebar rows, metric rows, status pills, icon buttons, and affordance bars.
- Reusable document/inspector surfaces, assertion strips, and empty states.

It does not parse Markdown, prepare render models, perform layout, or implement
renderer policies. Demo apps still exercise the public `SiriusMarkdown` APIs for
all Markdown behavior.
