# Architecture

SiriusMarkdown is a Swift Package split into **Core**, **SwiftUI**, and **Pretext support**, matching `plan.md` and `AGENTS.md`: semantics come from `swift-markdown`; streaming keeps immutable sealed regions plus one mutable tail; SwiftUI renders **already parsed** models and must not parse Markdown or run expensive layout from `body`.

## Modules and layout (as implemented)

```text
Sources/SiriusMarkdownCore/
  Source/MarkdownSourceBuffer.swift      — append-only UTF-8, slices, line map
  Stream/MarkdownStream.swift             — append, seal, host boundaries, snapshot
  Parser/SwiftMarkdownParser.swift        — Document parsing → render model
  Parser/MarkdownBoundaryScanner.swift   — incremental conservative seal scanning
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
- **Stream**: `MarkdownStream.append`, automatic `sealBoundaryIfPossible()`, `appendHostBoundary(id:)`, `finish()`, `snapshot()`, and source-backed `markdown(in:)`. Sealed ranges are parsed once and stored; the tail is reparsed while streaming. `MarkdownBoundaryScanState` prevents cumulative rescans of long active tails, and `MarkdownParserCache` keys sealed parses by source range and content hash.
- **Parser**: `SwiftMarkdownParser` drives `Document(parsing:)` and converts the AST to `MarkdownBlock` / `MarkdownInlineRun` with block kinds (paragraph, heading, lists, task lists, quotes, code, tables, thematic breaks, math, HTML, blank).
- **Model**: `MarkdownSnapshot` exposes `blocks`, ordered `items` (blocks interleaved with `MarkdownHostBoundary`), `generation`, `sourceLength`, `isFinished`. Identity for rendering uses `MarkdownBlock.id`, not array position.
- **Inline layout**: `PreparedInlineContent`, `VariableWidthLineWalker`, `InlineLayoutEngine` with bounded caches for prepared, measured, and laid-out inline results; `CoreTextInlineMeasurer` where CoreText is available. This is the Pretext-style **prepare** vs **layout** split for measurements that must not live in SwiftUI `body`.
- **Policy**: protocols (`MarkdownLinkPolicy`, `MarkdownImagePolicy`, etc.) and `DefaultMarkdownPolicy` (safe schemes for links; images and raw HTML denied by default).
- **Diagnostics**: `MarkdownDiagnosticsRecorder` / `MarkdownDiagnosticsCounters` (parse, tail vs sealed parse, boundary scan work, render preparation, highlighting/math, prepare, layout, width relayout, cache hits/misses) plus signpost helpers.

### SwiftUI

- **`MarkdownDocumentView`** (default theme `.document`) and **`StreamingMarkdownView`** (default `.compactChat`) should be driven with precomputed `MarkdownPreparedSnapshot` values. Direct `snapshot:` initializers remain as deprecated compatibility shims only; long or streaming content should prepare in the host model layer.
- **`MarkdownRendererConfiguration`** wires `MarkdownTheme`, policies, optional `MarkdownLinkAction`, `MarkdownCopyProvider`, `MarkdownCodeHighlighter`, and `MarkdownMathRenderer` (`PlainMarkdownCodeHighlighter` / `PlainMarkdownMathRenderer` ship as defaults). Its `prepare(block:)` / `prepare(snapshot:)` methods move inline attributed text, measured inline content, link/image policy decisions, code highlighting, math rendering, and HTML policy decisions out of block `body` evaluation, with `MarkdownRenderPreparationCache` bounding inline/highlighted-code/rendered-math reuse.
- **`MarkdownBlockView`** branches on `MarkdownBlockKind` for structured blocks and consumes `MarkdownPreparedBlockContent` for inline text, lists, nested lists, tables, code, math, and HTML. List and table rendering uses prepared source-range IDs rather than array offsets. Tables use prepared cell inline layouts and measured natural widths to choose bounded adaptive columns in SwiftUI; the view layer does not reparse table Markdown or measure raw source.
- **`MarkdownTheme`** owns renderer-level table presentation tokens (`tableBackground`, header/alternate-row backgrounds, border/accent colors, corner radius, and cell padding). This keeps table styling part of the public renderer surface instead of a demo-only skin.

Host-native content between Markdown segments is modeled in Core via **`MarkdownSnapshot.items`** and **`appendHostBoundary`**; built-in document views now render prepared items and expose a host-boundary closure with an empty default.

### Pretext support

- **`PretextFixture`** / **`PretextExpectedLayout`** describe markdown, required product group metadata, font/spacing profile, and expected line/natural-width/height metrics.
- **`PretextGoldenComparator`** compares `InlineLayoutResult` from Swift to fixture tolerances.
- Full golden pipeline runs in **`Tools/pretext-golden`** against real Pretext output; see repository `runbook.md`.

## Boundaries (non‑negotiable)

- **`MarkdownBoundaryScanner`** only decides **when** a suffix may be sealed; it does not replace `swift-markdown` block classification.
- No WebKit on the core path; no row-hosted WebViews; avoid unbounded overlay fragments for links or selection.
- Public APIs stay general-purpose (no private transcript/tool/runtime concepts); prefer names like `MarkdownStream`, `MarkdownSnapshot`, `MarkdownTheme`, `MarkdownRendererConfiguration`, policies, `InlineLayoutEngine`, `TextMeasurer`, as in `AGENTS.md`.

## Verification shape

Renderer verification intentionally favors deterministic contracts over fragile UI-process snapshots:

- representative documents must prepare structured renderer inputs for headings, paragraphs, task lists, quotes, code, tables, and math;
- repeated preparation of the same snapshot must reuse inline, highlighted-code, and rendered-math caches and record diagnostics cache hits;
- large streaming transcripts must produce unique prepared item IDs for hundreds of sealed blocks plus the active tail;
- nested list metadata and table row/cell identities must come from the AST-backed render model, not SwiftUI offsets;
- native SwiftUI rendering must produce nonblank pixels for representative structured documents, with `Tools/RenderProbe` exercising `MarkdownDocumentView` through an AppKit host outside Swift Testing's helper process;
- Pretext fixtures remain the layout oracle for line count, natural width, height, paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content. Known drift is not whitelisted, and missing required groups fail the gate.

## Related docs

- `Docs/streaming.md` — seal algorithm and host boundaries.
- `Docs/performance.md` — caches, diagnostics, measurement.
- `plan.md`, `AGENTS.md` — authoritative plan and contributor rules.
