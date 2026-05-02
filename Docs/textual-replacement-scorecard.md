# Textual-Replacement Scorecard

SiriusMarkdown should be chosen over Textual only when the current checkout proves the product bar below without weakening the architecture in `AGENTS.md`.

## Required Wins

- Streaming: appends reparse only the mutable tail; sealed regions stay immutable and cacheable.
- Resize: width changes perform cheap prepared layout only.
- Rendering: paragraphs, headings, nested/task lists, quotes, code, tables, math, links, images, and host boundaries have structured native render paths.
- Safety: links, images, HTML, code, and math stay policy controlled, with no remote image fetch by default.
- Interaction: selection and copy are bounded at block/range level and never create unbounded per-fragment overlays.
- Product surfaces: demos show clean transcript and reader behavior first, with diagnostics available as inspection rather than primary UI.

## Product Gate

Run:

```sh
bash Tools/product-check.sh
```

The gate wraps the release check and adds focused product checks for render sessions, selection, long transcript behavior, and AppKit-rendered output. Textual is not a test dependency; it remains the regression lesson and product bar.

## Release Claim

Do not claim “Textual replacement” quality unless the product gate passes and a Sirius canary path uses only public SiriusMarkdown APIs with no parsing, highlighting, or raw Markdown layout in SwiftUI `body`.
