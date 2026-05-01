# Architecture

SiriusMarkdown is a Swift Package split into **Core**, **SwiftUI**, and **Pretext support**, matching `plan.md` and `AGENTS.md`: semantics come from `swift-markdown`; streaming keeps immutable sealed regions plus one mutable tail; SwiftUI renders **already parsed** models and must not parse Markdown or run expensive layout from `body`.

## Modules and layout (as implemented)

```text
Sources/SiriusMarkdownCore/
  Source/MarkdownSourceBuffer.swift      — append-only UTF-8, slices, line map
  Stream/MarkdownStream.swift             — append, seal, host boundaries, snapshot
  Parser/SwiftMarkdownParser.swift        — Document parsing → render model
  Parser/MarkdownBoundaryScanner.swift   — conservative seal upper bounds
  Model/MarkdownModel.swift               — MarkdownSnapshot, MarkdownBlock, IDs, ranges
  InlineLayout/InlineLayout.swift         — prepare/measure/layout, InlineLayoutEngine, caches
  Policy/MarkdownPolicies.swift           — link/image/HTML/code/math policy protocols
  Cache/MarkdownCaches.swift              — bounded parser / generic caches
  Diagnostics/MarkdownDiagnostics.swift    — counters, debug helpers

Sources/SiriusMarkdownSwiftUI/
  Views/MarkdownDocumentView.swift       — MarkdownDocumentView, StreamingMarkdownView
  Views/MarkdownRendererConfiguration.swift — theme, policies, highlighter/math hooks
  Blocks/MarkdownBlockView.swift
  Inline/InlineRunsView.swift, InlineRunView.swift
  Theme/MarkdownTheme.swift
  Interaction/MarkdownInteraction.swift
  Platform/MarkdownPlatformHooks.swift

Sources/SiriusMarkdownPretextSupport/
  Golden/PretextFixture.swift             — fixture schema + golden comparator (Swift side)
  Fixtures/                               — bundled JSON resources for tests
Tools/pretext-golden/                     — Node/Bun oracle (`@chenglou/pretext`), see runbook
```

Products (see `Package.swift`): **`SiriusMarkdown`** (app-facing umbrella module that re-exports Core + SwiftUI), **`SiriusMarkdownCore`**, **`SiriusMarkdownSwiftUI`**, **`SiriusMarkdownPretextSupport`**.

## Responsibilities

### Core

- **Source**: `MarkdownSourceBuffer` holds append-only chunks; `MarkdownSourceSlice` bridges to `String` at parse boundaries for `swift-markdown`.
- **Stream**: `MarkdownStream.append`, automatic `sealBoundaryIfPossible()`, `appendHostBoundary(id:)`, `finish()`, `snapshot()`. Sealed ranges are parsed once and stored; the tail is reparsed while streaming. `MarkdownParserCache` keys sealed parses by source range and content hash.
- **Parser**: `SwiftMarkdownParser` drives `Document(parsing:)` and converts the AST to `MarkdownBlock` / `MarkdownInlineRun` with block kinds (paragraph, heading, lists, task lists, quotes, code, tables, thematic breaks, math, HTML, blank).
- **Model**: `MarkdownSnapshot` exposes `blocks`, ordered `items` (blocks interleaved with `MarkdownHostBoundary`), `generation`, `sourceLength`, `isFinished`. Identity for rendering uses `MarkdownBlock.id`, not array position.
- **Inline layout**: `PreparedInlineContent`, `VariableWidthLineWalker`, `InlineLayoutEngine` with bounded caches for prepared, measured, and laid-out inline results; `CoreTextInlineMeasurer` where CoreText is available. This is the Pretext-style **prepare** vs **layout** split for measurements that must not live in SwiftUI `body`.
- **Policy**: protocols (`MarkdownLinkPolicy`, `MarkdownImagePolicy`, etc.) and `DefaultMarkdownPolicy` (safe schemes for links; images and raw HTML denied by default).
- **Diagnostics**: `MarkdownDiagnosticsRecorder` / `MarkdownDiagnosticsCounters` (parse, tail vs sealed parse, prepare, layout, cache hits/misses). `MarkdownStream` can share recorder semantics via injected recorder where APIs allow.

### SwiftUI

- **`MarkdownDocumentView`** (default theme `.document`) and **`StreamingMarkdownView`** (default `.compactChat`) take a `MarkdownSnapshot` and `MarkdownRendererConfiguration` (or theme only).
- **`MarkdownRendererConfiguration`** wires `MarkdownTheme`, policies, optional `MarkdownLinkAction`, `MarkdownCodeHighlighter`, and `MarkdownMathRenderer` (`PlainMarkdownCodeHighlighter` / `PlainMarkdownMathRenderer` ship as defaults). Its `prepare(block:)` / `prepare(snapshot:)` methods move code highlighting, math rendering, and HTML policy decisions out of block `body` evaluation, with `MarkdownRenderPreparationCache` bounding highlighted-code and rendered-math reuse.
- **`MarkdownBlockView`** branches on `MarkdownBlockKind` for structured blocks; inline text uses `InlineRunsView` over AST inline runs (not raw Markdown strings), while code/math/HTML blocks consume `MarkdownPreparedBlockContent`.

Host-native content between Markdown segments is modeled in Core via **`MarkdownSnapshot.items`** and **`appendHostBoundary`**; built-in document views currently iterate **`snapshot.blocks`**—use **`items`** when you need to splice native UI at recorded boundaries.

### Pretext support

- **`PretextFixture`** / **`PretextExpectedLayout`** describe markdown + expected line/natural-width/height metrics.
- **`PretextGoldenComparator`** compares `InlineLayoutResult` from Swift to fixture tolerances.
- Full golden pipeline runs in **`Tools/pretext-golden`** against real Pretext output; see repository `runbook.md`.

## Boundaries (non‑negotiable)

- **`MarkdownBoundaryScanner`** only decides **when** a suffix may be sealed; it does not replace `swift-markdown` block classification.
- No WebKit on the core path; no row-hosted WebViews; avoid unbounded overlay fragments for links or selection.
- Public APIs stay general-purpose (no private transcript/tool/runtime concepts); prefer names like `MarkdownStream`, `MarkdownSnapshot`, `MarkdownTheme`, `MarkdownRendererConfiguration`, policies, `InlineLayoutEngine`, `TextMeasurer`, as in `AGENTS.md`.

## Related docs

- `Docs/streaming.md` — seal algorithm and host boundaries.
- `Docs/performance.md` — caches, diagnostics, measurement.
- `plan.md`, `AGENTS.md` — authoritative plan and contributor rules.
