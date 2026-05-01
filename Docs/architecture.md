# Architecture

SiriusMarkdown is split into Core, SwiftUI, and Pretext-support modules.

Core owns append-only source storage, sealed streaming regions, mutable-tail parsing, public render models, layout preparation contracts, policy hooks, caches, and diagnostics. SwiftUI owns rendering already-prepared snapshots. Pretext support owns fixture exchange with the JavaScript golden oracle.

SwiftUI views must receive `MarkdownSnapshot` values. They do not parse Markdown, perform syntax highlighting, or prepare inline layout from raw source in `body`.

