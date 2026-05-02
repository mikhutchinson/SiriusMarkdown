# Native Renderer Product Scorecard

SiriusMarkdown should be chosen when the current checkout proves the product bar below without weakening the architecture in `AGENTS.md`.

The goal is a native, streaming-first Markdown renderer for Apple applications: `swift-markdown` owns semantics, source storage stays append-only, sealed regions are immutable and cacheable, SwiftUI consumes prepared snapshots, width changes perform cheap layout only, and interaction remains bounded under long chat and document workloads.

## Required Wins

- Semantics: Markdown structure comes from `swift-markdown`, not string-rule parsing.
- Streaming: appends reparse only the mutable tail; sealed regions stay immutable and cacheable.
- Resize: width changes perform cheap prepared layout only.
- Rendering: paragraphs, headings, nested/task lists, quotes, code, tables, math, links, images, and host boundaries have structured native render paths.
- Inline caveat: prepared inline layout supports caching, resize diagnostics, source ranges, and future hit testing; the default visible text path still uses SwiftUI `Text(AttributedString)` through `MarkdownInlineRenderingMode.systemText`. `MarkdownInlineRenderingMode.preparedNativeLines` is opt-in and renders prepared attributed line slices through SwiftUI `Text(AttributedString)`. It is a prepared-line rendering mode, not a fully custom glyph renderer.
- Safety: links, images, HTML, code, and math stay policy controlled, with no remote image fetch by default.
- Interaction: selection and copy are bounded at block/range level and never create unbounded per-fragment overlays.
- Product surfaces: demos show clean transcript and reader behavior first, with diagnostics available as inspection rather than primary UI.

## Product Gate

Run:

```sh
bash Tools/product-check.sh
```

The gate wraps the release check and adds focused product checks for render sessions, selection, long transcript behavior, resize discipline, and AppKit-rendered output.

## Release Claim

Do not claim prepared inline layout owns default on-screen glyph placement unless a future renderer actually owns shaped glyph drawing, reaches visual parity, the product gate includes visual checks that would catch spacing/alignment/font regressions, and the SwiftUI `Text(AttributedString)` path remains available until the replacement is proven under chat and document workloads. Today, `preparedNativeLines` proves prepared line slicing and render integration; it does not eliminate every SwiftUI text drawing or selection caveat.

Do not claim native-renderer product quality unless the product gate passes and a Sirius canary path uses only public SiriusMarkdown APIs with no parsing, highlighting, or raw Markdown layout in SwiftUI `body`.
