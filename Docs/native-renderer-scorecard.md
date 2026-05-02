# Native Renderer Product Scorecard

SiriusMarkdown should be chosen when the current checkout proves the product bar below without weakening the architecture in `AGENTS.md`.

The goal is a native, streaming-first Markdown renderer for Apple applications: `swift-markdown` owns semantics, source storage stays append-only, sealed regions are immutable and cacheable, SwiftUI consumes prepared snapshots, width changes perform cheap layout only, and interaction remains bounded under long chat and document workloads.

## Required Wins

- Semantics: Markdown structure comes from `swift-markdown`, not string-rule parsing.
- Streaming: appends reparse only the mutable tail; sealed regions stay immutable and cacheable.
- Resize: width changes perform cheap prepared layout only.
- Rendering: paragraphs, headings, nested/task lists, quotes, code, tables, math, links, images, and host boundaries have structured native render paths.
- Inline rendering: packaged chat and document presets use `MarkdownInlineRenderingMode.preparedNativeLines`, so visible wrapping is driven by cached prepared line ranges. `MarkdownInlineRenderingMode.systemText` remains an explicit compatibility fallback for custom configurations.
- Safety: links, images, HTML, code, and math stay policy controlled, with no remote image fetch by default.
- Interaction: selection and copy are bounded at block/range level and never create unbounded per-fragment overlays.
- Product surfaces: demos show clean transcript and reader behavior first, with diagnostics available as inspection rather than primary UI.

## Product Gate

Run:

```sh
bash Tools/product-check.sh
```

The gate wraps the release check and adds focused product checks for render sessions, selection, long transcript behavior, resize discipline, required Pretext fixture groups, and AppKit-rendered document/chat/overflow/multilingual output.

## Release Claim

The public product claim is prepared-line rendering: layout ranges come from SiriusMarkdown's prepared layout engine and SwiftUI renders those prepared attributed lines. Do not describe it as a custom glyph renderer unless a future renderer actually owns shaped glyph drawing and the product gate proves visual parity.

Do not claim native-renderer product quality unless the product gate passes and at least one consuming app path uses only public SiriusMarkdown APIs with no parsing, highlighting, or raw Markdown layout in SwiftUI `body`.
