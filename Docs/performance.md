# Performance

The renderer contract is architectural: SwiftUI **`body`** must not parse Markdown, run syntax highlighting over raw source, rebuild the full document model, or drive wrapping via heavy per-fragment **`sizeThatFits`** over raw markdown strings. Width-driven work should stay on the **cheap layout** side of the prepare/layout split.

## Streaming and parsing

- **Tail**: While streaming and **`sealedUpperBound < source.byteCount`**, each **`snapshot()`** reparses only the **mutable tail** slice (diagnostics **`tailReparseCount`**).
- **Sealed regions**: Once sealed, blocks are reused from **`MarkdownParserCache`** keyed by **`MarkdownCacheKey`** (source range, content hash, namespace plus reference-definition context when later slices need prior definitions); hits increment sealed-region cache counters.
- **Boundary scanning**: `MarkdownStream` retains incremental scanner state for the active tail and records `boundaryScannedByteCount` / `boundaryScannedLineCount`; long open fences, math, HTML, reference-link ambiguity, literal unmatched-bracket recovery, and loose-list tails are covered by counter-based linear-scan tests.
- **Identity**: Blocks expose stable **`MarkdownBlockID`** values derived in the AST converter from structural identity within each parse slice—not from fragile array indices in SwiftUI.

## Inline prepare / layout (Core)

**`InlineLayoutEngine`** implements the Pretext-inspired split:

1. **Prepare** — `PreparedInlineContent` normalizes runs into **`PreparedInlineSegment`** records (break opportunities, hard breaks).
2. **Measure** — **`VariableWidthLineWalker`** + **`InlineMeasuring`** (default **`CoreTextInlineMeasurer`** on Apple platforms where CoreText is linked) produces **`MeasuredInlineContent`** including **`naturalWidth`**.
3. **Layout** — **`layout(_:options:)`** yields **`InlineLayoutResult`** (line ranges, height) for a container width without re-preparing from scratch.

Bounded LRU-style caches (default capacity **256**) cover prepared, measured, layout, and overwide fallback unit results; **`MarkdownDiagnosticsRecorder`** records **prepareCount**, **layoutCount**, **widthRelayoutCount**, **overwideUnitFallbackCount**, and generic cache hit/miss counts. Per-character unit measurement is lazy and only runs for overwide segment splitting.

SwiftUI block views consume **prepared inline content** created by **`MarkdownRendererConfiguration.prepare(snapshot:)`**. The prepared inline payload stores both the attributed text and **`MeasuredInlineContent`** so view-time width changes can compute line breaks from cached segment/unit measurements. Use **`InlineLayoutEngine`** directly when you need deterministic metrics outside the SwiftUI renderer (tests, golden comparison, future layout-driven UI).

Prepared inline layout is the cacheable measurement, resize, diagnostics, and metadata layer. The packaged chat and document presets **`MarkdownRendererConfiguration.compactChat`** and **`.document`**, plus direct custom configuration, use **`MarkdownInlineRenderingMode.coreTextPaintedLines`** by default. That mode consumes **`InlineLayoutResult`** ranges, resolves CT fonts from **`MarkdownInlineFontProfiles`**, builds link hit regions only from prepared attributed link attributes that survived policy filtering, and paints each whole line through CoreText **`CTLineDraw`** in narrow AppKit/UIKit platform bridges. **`MarkdownInlineRenderingMode.preparedNativeLines`** and **`.systemText`** remain explicit compatibility fallbacks. All inline rendering modes keep parsing, policy preparation, code/math rendering, and inline measurement out of SwiftUI **`body`**.

### CTLine plan preparation (INV-P1)

**`MarkdownCoreTextPaintedLinePlan`** is created during **`prepare(snapshot:)`**, not in `updateNSView`/`updateUIView`. The representable assigns a pre-built plan. CTLine creation, font attribute application, and typographic measurement run in the prepare phase, cached by content identity. When the actual container width differs from the default width used during preparation, the representable rebuilds the plan from the refined layout result — but this only happens on width change, not on every SwiftUI update.

### Single-pass layout (INV-P2)

**`PreparedInlineTextView`** pre-computes layout at a default width (**680pt** standard chat column) during preparation. The first render shows content immediately; `canRenderNativeLines` is true on first appearance without waiting for the width preference. Width refinement adjusts line breaks in a single pass via the cheap `layout()` path. This eliminates the two-pass latency where new blocks rendered empty until the `GeometryReader` width preference arrived.

### Incremental snapshot publishing (INV-P3)

**`MarkdownRenderSession`** publishes a **`MarkdownPreparedSnapshotDiff`** alongside the full `MarkdownPreparedSnapshot`. The diff identifies changed, new, and removed item IDs since the last published snapshot. The existing `reusedPreparedItem` logic already identifies unchanged items — the diff is a byproduct of the existing reuse detection. Only changed/new items trigger preparation; sealed blocks hit the reuse path.

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

## Rendering path

- **`MarkdownDocumentView`** / **`StreamingMarkdownView`** should receive **`MarkdownPreparedSnapshot`** values prepared outside SwiftUI body evaluation. Deprecated direct `snapshot:` initializers are kept only for small compatibility cases; they enforce cheap block policies but intentionally skip full highlighting, math rendering, and inline layout preparation.
- **`MarkdownRendererConfiguration.prepare(snapshot:)`** returns **`MarkdownPreparedSnapshot`**, preparing inline attributed payloads, measured inline content, link/image policy decisions, code highlighting, math rendering, and HTML policy decisions before block bodies consume them. `MarkdownRenderPreparationCache` bounds inline/code/math reuse by source range, content hash, normalized code language, highlighter identity, theme palette identity, and preparation namespace.
- **`MarkdownBlockView`** consumes **`MarkdownPreparedBlockContent`** for paragraphs, headings, lists, tables, code, math, and HTML, and exposes copy/context hooks through **`MarkdownCopyProvider`**.

The suite includes headless renderer-performance contract tests:

- repeated preparation of the same snapshot must keep `prepareCount`, `codeHighlightCount`, and `mathRenderCount` stable while cache hits increase;
- language-aware code highlighting must run only for uncached explicit supported-language fences; plaintext, nohighlight, unlabeled, and unsupported default fences stay plain and do not increment highlight work counters;
- large streaming transcript preparation must create unique prepared item IDs for every block and keep an active tail prepared without forcing a full finish;
- renderer preparation must not eagerly generate per-character unit measurements for every segment;
- explicit overwide fallback layout can use prepared unit measurements, while SwiftUI view-time line breaking refuses measurement fallback and uses already prepared segment widths only.

Strict Pretext fixture drift is a release blocker. The Swift fixture comparison now requires the full product fixture corpus: paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content.

## Accelerate and Metal

**CoreText** owns glyph measurement for **`CoreTextInlineMeasurer`**. **Accelerate** / **vDSP** are reserved for proven layout math wins; **Metal** is not part of the current text layout path (future visualization or specialized canvases only).

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
