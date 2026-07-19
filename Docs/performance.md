# Performance

The renderer contract is architectural: SwiftUI **`body`** must not parse Markdown, run syntax highlighting over raw source, rebuild the full document model, or drive wrapping via heavy per-fragment **`sizeThatFits`** over raw markdown strings. Width-driven work should stay on the **cheap layout** side of the prepare/layout split.

## Streaming and parsing

- **Tail**: While streaming and **`sealedUpperBound < source.byteCount`**, each **`snapshot()`** reparses only the **mutable tail** slice (diagnostics **`tailReparseCount`**).
- **Sealed regions**: Once sealed, blocks are reused from **`MarkdownParserCache`** keyed by **`MarkdownCacheKey`** (source range, content hash, namespace plus reference-definition context when later slices need prior definitions); hits increment sealed-region cache counters.
- **Boundary scanning**: `MarkdownStream` retains incremental scanner state for the active tail and records `boundaryScannedByteCount` / `boundaryScannedLineCount`; long open fences, math, HTML, reference-link ambiguity, literal unmatched-bracket recovery, and loose-list tails are covered by counter-based linear-scan tests.
- **AST source locations**: each `swift-markdown` parse boundary builds one
  UTF-8 line-start index. Block, list, table-cell, and inline source ranges use
  indexed line starts instead of rescanning the source prefix for every AST
  node; large single-block mutable tails therefore remain linear in AST size.
- **Identity**: Blocks expose stable **`MarkdownBlockID`** values derived in the AST converter from structural identity within each parse slice—not from fragile array indices in SwiftUI.

## Inline prepare / layout (Core)

**`InlineLayoutEngine`** implements the Pretext-inspired split:

1. **Prepare** — `PreparedInlineContent` normalizes runs into **`PreparedInlineSegment`** records (break opportunities, hard breaks).
2. **Measure** — **`VariableWidthLineWalker`** + **`InlineMeasuring`** (default **`CoreTextInlineMeasurer`** on Apple platforms where CoreText is linked) produces **`MeasuredInlineContent`** including **`naturalWidth`**.
3. **Layout** — **`layout(_:options:)`** yields **`InlineLayoutResult`** (line ranges, height) for a container width without re-preparing from scratch.

Bounded LRU-style caches (default capacity **256**) cover prepared, measured, layout, and overwide fallback unit results; **`MarkdownDiagnosticsRecorder`** records **prepareCount**, **layoutCount**, **widthRelayoutCount**, **overwideUnitFallbackCount**, and generic cache hit/miss counts. Per-character unit measurement is lazy and only runs for overwide segment splitting.

One render preparation cache also owns a bounded, thread-safe
**`MarkdownCoreTextMeasurementCache`** (16,384 widths and 64 fonts by default).
Its keys include the font profile, size, inline kind and presentation, missing-
glyph policy, and text. New preparation values for a growing tail therefore
reuse unchanged token widths without weakening font or presentation
invalidation.

Prepared, measured, and layout results also carry deterministic two-lane
**`MarkdownContentFingerprint`** values. The fingerprints are built when those
values are created or mutated, where content-sized work belongs. Layout cache
keys, SwiftUI prepared-content identity, and source-backed selection cache keys
then combine a fixed number of machine words; a cache hit must not rehash
natural text, inline runs, measured units, or line arrays. Layout-only
fingerprints intentionally exclude link destinations and caller-owned source
metadata from glyph measurement reuse, while the full prepared fingerprint
retains them for rendering and selection invalidation.

SwiftUI block views consume **prepared inline content** created by **`MarkdownRendererConfiguration.prepare(snapshot:)`**. The prepared inline payload stores both the attributed text and **`MeasuredInlineContent`** so view-time width changes can compute line breaks from cached segment/unit measurements. Use **`InlineLayoutEngine`** directly when you need deterministic metrics outside the SwiftUI renderer (tests, golden comparison, future layout-driven UI).

Prepared inline layout is the cacheable measurement, resize, diagnostics, and metadata layer. The packaged chat and document presets **`MarkdownRendererConfiguration.compactChat`** and **`.document`**, plus direct custom configuration, use **`MarkdownInlineRenderingMode.coreTextPaintedLines`** by default. That mode consumes **`InlineLayoutResult`** ranges, resolves CT fonts from **`MarkdownInlineFontProfiles`**, builds link hit regions only from prepared attributed link attributes that survived policy filtering, and paints each whole line through CoreText **`CTLineDraw`** in narrow AppKit/UIKit platform bridges. **`MarkdownInlineRenderingMode.preparedNativeLines`** and **`.systemText`** remain explicit compatibility fallbacks. All inline rendering modes keep parsing, policy preparation, code/math rendering, and inline measurement out of SwiftUI **`body`**.

### CTLine plan preparation (INV-P1)

**`MarkdownCoreTextPaintedLinePlan`** is created during **`prepare(snapshot:)`**, not in `updateNSView`/`updateUIView`. The representable assigns a pre-built plan. CTLine creation, font attribute application, and typographic measurement run in the prepare phase, cached by content identity. When the actual container width differs from the default width used during preparation, the representable rebuilds the plan from the refined layout result — but this only happens on width change, not on every SwiftUI update.

### Single-pass layout (INV-P2)

**`PreparedInlineTextView`** pre-computes layout at a default width (**680pt** standard chat column) during preparation. The first render shows content immediately; `canRenderNativeLines` is true on first appearance without waiting for the width preference. Width refinement adjusts line breaks in a single pass via the cheap `layout()` path. This eliminates the two-pass latency where new blocks rendered empty until the `GeometryReader` width preference arrived.

### Incremental snapshot publishing (INV-P3)

**`MarkdownRenderSession`** publishes a **`MarkdownPreparedSnapshotDiff`** alongside the full `MarkdownPreparedSnapshot`. The diff identifies changed, new, and removed item IDs since the last published snapshot. The existing `reusedPreparedItem` logic already identifies unchanged items — the diff is a byproduct of the existing reuse detection. Only changed/new items trigger preparation; sealed blocks hit the reuse path.

The session's parse/highlight/prepare pump originates from a detached
user-initiated task. Its MainActor isolation exists only for pending-operation
drain and `ObservableObject` publication; expensive pipeline work must not
inherit a SwiftUI caller's actor or task-local context.

### Bounded streaming layout (INV-P5)

`StreamingMarkdownView` divides prepared render items into regions of at most
16 items. A custom non-lazy `Layout` keeps every structured Markdown view
mounted but caches sealed region sizes by identity, content revision, and
proposal width. A normal append changes only the final region; stable history
is placed from cached sizes. Region geometry publication is asynchronous,
quantized, and coalesced so it cannot form a synchronous AppKit/SwiftUI fitting
loop.

The prepared snapshot path intentionally does not use `LazyVStack` for live
streams. This avoids depending on private viewport item-phase behavior while
preserving tables, math, Mermaid, attachments, links, copy, and document
selection in their native SwiftUI block hierarchy.

### Incremental streaming table layout (INV-P9)

Prepared tables treat every completed body row as an immutable subregion of
the otherwise mutable table block. Preparation retains that row prefix, reuses
unchanged tail cells by source hash/range, and records cell comparison,
preparation, reuse, column-scan, and width-revision counters. Column maxima are
updated only from changed cells while streaming; 64-point effective-width
buckets bound the number of global row invalidations, followed by one exact
sealed pass.

The table row `Layout` never derives widths or measures raw text. Its bounded
cross-publication size cache is keyed by row content fingerprint and prepared
column-width revision. The 120x6 AppKit regression publishes two chunks per
row, including URL splits, without newline gating. It requires fewer than
1,200 row measurements, keeps late main-thread settle below 16 ms, and rejects
historical cell comparison/preparation that scales as rows x publications.

### Mutable-tail cache and highlighting policy (INV-P6)

Unsealed inline, code, math, and Mermaid values bypass stable preparation
caches. Plain and Highlight.js-backed highlighters retain one rolling state per
active block, highlight appended suffixes with the parser's real continuation,
take a full-context checkpoint every 16 KiB, and always perform a full highlight
when the block seals. The native Swift and arbitrary host highlighters retain
full-document behavior where no proven continuation is available. Diagnostics expose
`codeHighlightByteCount` as well as invocation count so cumulative work is
testable directly.

### Selection preference caching (INV-P4)

**`MarkdownDocumentSelectionLayer.onPreferenceChange`** skips sorting and storage when fragments are unchanged. `MarkdownDocumentSelectionFragment` conforms to `Equatable`, so the comparison is exact. This prevents redundant `sortedForSelection()` calls and `recordSelectionPreferenceChange()` increments during streaming when no blocks change position.

### Benchmark results

Performance benchmarks live in `Tests/SiriusMarkdownSwiftUITests/MarkdownPerformanceBenchmarkTests.swift`. Run with `swift test -c release --filter MarkdownPerformanceBenchmark` for accurate timing.

| Operation | Budget | Rationale |
|-----------|--------|-----------|
| Append to 100-block transcript | <16ms | 60fps frame budget |
| Width change on single block | <4ms | Quarter frame budget (layout only, no parsing) |
| CTLine creation in SwiftUI body | 0 after preparation | All CTLine work in prepare phase |
| Selection preference publication | 0 new builds after warmup | No work when nothing changed |
| 1,300-line hosted selection invalidation | <16ms median after warmup | One 60fps frame; release reference is 0.418ms |
| 8x mutable-tail table growth | <20x parse time | Reject quadratic AST source-location conversion; release reference is 8.02x |
| 179 KB / 90-publication AppKit stream | <16ms mutable-tail median | Only the final bounded region should remeasure; release reference is 2.71ms |
| 120x6 live table / 240 partial publications | <16ms late median; <1,200 row measurements | Completed rows reuse persistent preparation and layout; debug host reference is 0.62ms, 586 measurements |
| 500x6 partial-cell preparation | <5.25x 120-row cell/column operations | Reject rows x publications preparation and width scans |

## Rendering path

- **`MarkdownDocumentView`** / **`StreamingMarkdownView`** should receive **`MarkdownPreparedSnapshot`** values prepared outside SwiftUI body evaluation. Deprecated direct `snapshot:` initializers are kept only for small compatibility cases; they enforce cheap block policies but intentionally skip full highlighting, math rendering, and inline layout preparation.
- **`MarkdownRendererConfiguration.prepare(snapshot:)`** returns **`MarkdownPreparedSnapshot`**, preparing inline attributed payloads, measured inline content, link/image policy decisions, code highlighting, math rendering, and HTML policy decisions before block bodies consume them. `MarkdownRenderPreparationCache` bounds sealed inline/code/math reuse by source range, content hash, normalized code language, highlighter identity, theme palette identity, and preparation namespace; mutable values use the rolling/bounded paths described above instead of filling stable caches.
- **`MarkdownBlockView`** consumes **`MarkdownPreparedBlockContent`** for paragraphs, headings, lists, tables, code, math, and HTML, and exposes copy/context hooks through **`MarkdownCopyProvider`**.

The suite includes headless renderer-performance contract tests:

- repeated preparation of the same snapshot must keep `prepareCount`, `codeHighlightCount`, and `mathRenderCount` stable while cache hits increase;
- language-aware code highlighting must run only for uncached explicit supported-language fences; plaintext, nohighlight, unlabeled, and unsupported default fences stay plain and do not increment highlight work counters;
- Highlight.js-backed highlighting of a growing code tail must process only appended bytes between full-context checkpoints, match a full highlight across multiline lexical state, and perform a full highlight on seal; the native Swift and custom paths remain full-context;
- stable streaming regions must retain their revisions while only the mutable-tail region changes, and AppKit-hosted rapid publication must stay inside the frame budget without constraint recursion;
- streaming tables must expose partial cells immediately, retain completed row/cell identity, compare and prepare only the mutable suffix, bound column-width revisions, and reuse historical row measurements across prepared-root publications;
- equivalent CoreText token measurements must hit the shared bounded cache across distinct measurer values;
- large streaming transcript preparation must create unique prepared item IDs for every block and keep an active tail prepared without forcing a full finish;
- renderer preparation must not eagerly generate per-character unit measurements for every segment;
- explicit overwide fallback layout can use prepared unit measurements, while SwiftUI view-time line breaking refuses measurement fallback and uses already prepared segment widths only.

Strict Pretext fixture drift is a release blocker. The Swift fixture comparison now requires the full product fixture corpus: paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content.

## Accelerate and Metal

**CoreText** owns glyph measurement for **`CoreTextInlineMeasurer`**. **Accelerate** / **vDSP** are reserved for proven layout math wins; **Metal** is not part of the current text layout path (future visualization or specialized canvases only).

## Math rendering quality

Native LaTeX math through `SiriusMarkdownMath`'s `NativeMarkdownMathRenderer`
(backed by the vendored SwiftMath target under `Sources/SwiftMath`) produces
`MarkdownPreparedMathImage` values with display-list typographic metrics:

- **Display-list ascent/descent**: `SwiftMathTypesetter` uses vendored
  `MTMathImage.asImage()` → `LayoutInfo` from `MTMathListDisplay`, then maps
  those metrics onto the rasterized image height so
  `ascent + descent == pointHeight`. This replaces both the old
  `ascent = pointHeight, descent = 0` placeholder and the interim atom-tree
  fraction estimator.
- **Baseline alignment**: `InlineMathTextView.baselineOffset(for:)` uses
  `-descent` to align the equation's typographic baseline with the surrounding
  text baseline, replacing the prior `−overshoot × 0.32` heuristic.
- **Screen-matched rasterization**: `NativeMarkdownMathRenderer.renderScale`
  resolves to the screen's backing scale (min 2.0) instead of a fixed 3.0,
  ensuring sharp glyphs on both 2x Retina and 3x Pro displays.
- **Interpolation**: `MarkdownMathImageView` uses `.interpolation(.medium)` for
  sharper glyph edges on template images at exact point size.
- **Streaming detection**: The boundary scanner tracks open `$$` fences,
  `\[...\]` display math, and `\begin{...}...\end{...}` LaTeX environments,
  preventing early sealing during streaming. Inline `\(...\)` is not a block
  fence. Partial display LaTeX renders as text until sealed, then typesets
  correctly (INV-M5).
- **Packaged apps**: Host `.app` bundles must ship
  `SiriusMarkdown_SwiftMath.bundle` under `Contents/Resources`. Font loading
  uses `MTFont.mathFontsBundleURL` and never relies on SwiftPM's generated
  `Bundle.module` accessor inside a signed `.app`.

All math preparation (typesetting, rasterization, metric extraction) runs in
the prepare phase; SwiftUI only draws the prepared image (INV-M2).

## Diagnostics

Use **`MarkdownStream.diagnosticsCounters`** and **`InlineLayoutEngine.diagnosticsCounters`** (after configuring a shared **`MarkdownDiagnosticsRecorder`** where applicable) to validate:

- bounded tail reparses vs sealed parses,
- cache effectiveness,
- prepare/layout frequency under resize or streaming scenarios,
- render preparation, code highlighting, math rendering, boundary scanning, and overwide fallback counts.

## Related docs

- `Docs/architecture.md` — where caches and engines live.
- `Docs/streaming.md` — what gets reparsed when appending.
- `Docs/native-renderer-scorecard.md` — product quality bar.
