# Performance

The renderer contract (see `plan.md` and `AGENTS.md`) is architectural: SwiftUI **`body`** must not parse Markdown, run syntax highlighting over raw source, rebuild the full document model, or drive wrapping via heavy per-fragment **`sizeThatFits`** over raw markdown strings. Width-driven work should stay on the **cheap layout** side of the prepare/layout split.

## Streaming and parsing

- **Tail**: While streaming and **`sealedUpperBound < source.byteCount`**, each **`snapshot()`** reparses only the **mutable tail** slice (diagnostics **`tailReparseCount`**).
- **Sealed regions**: Once sealed, blocks are reused from **`MarkdownParserCache`** keyed by **`MarkdownCacheKey`** (source range, content hash, namespace); hits increment sealed-region cache counters.
- **Boundary scanning**: `MarkdownStream` retains incremental scanner state for the active tail and records `boundaryScannedByteCount` / `boundaryScannedLineCount`; long open fences, math, HTML, and loose-list tails are covered by counter-based linear-scan tests.
- **Identity**: Blocks expose stable **`MarkdownBlockID`** values derived in the AST converter from structural identity within each parse slice—not from fragile array indices in SwiftUI.

## Inline prepare / layout (Core)

**`InlineLayoutEngine`** implements the Pretext-inspired split:

1. **Prepare** — `PreparedInlineContent` normalizes runs into **`PreparedInlineSegment`** records (break opportunities, hard breaks).
2. **Measure** — **`VariableWidthLineWalker`** + **`InlineMeasuring`** (default **`CoreTextInlineMeasurer`** on Apple platforms where CoreText is linked) produces **`MeasuredInlineContent`** including **`naturalWidth`**.
3. **Layout** — **`layout(_:options:)`** yields **`InlineLayoutResult`** (line ranges, height) for a container width without re-preparing from scratch.

Bounded LRU-style caches (default capacity **256**) cover prepared, measured, layout, and overwide fallback unit results; **`MarkdownDiagnosticsRecorder`** records **prepareCount**, **layoutCount**, **widthRelayoutCount**, **overwideUnitFallbackCount**, and generic cache hit/miss counts. Per-character unit measurement is lazy and only runs for overwide segment splitting.

SwiftUI block views consume **prepared inline content** created by **`MarkdownRendererConfiguration.prepare(snapshot:)`**. The prepared inline payload stores both the attributed text and **`MeasuredInlineContent`** so view-time width changes can compute line breaks from cached segment/unit measurements. Use **`InlineLayoutEngine`** directly when you need deterministic metrics outside the SwiftUI renderer (tests, golden comparison, future layout-driven UI).

Prepared inline layout is the cacheable measurement, resize, diagnostics, and metadata layer. The packaged chat and document presets **`MarkdownRendererConfiguration.compactChat`** and **`.document`** use **`MarkdownInlineRenderingMode.preparedNativeLines`**, which consumes **`InlineLayoutResult`** ranges, slices the prepared attributed payload into prepared lines, and renders those lines with SwiftUI **`Text(AttributedString)`**. Direct custom configuration keeps **`MarkdownInlineRenderingMode.systemText`** available as a compatibility fallback. Both paths keep parsing, policy preparation, code/math rendering, and inline measurement out of SwiftUI **`body`**.

## Rendering path

- **`MarkdownDocumentView`** / **`StreamingMarkdownView`** should receive **`MarkdownPreparedSnapshot`** values prepared outside SwiftUI body evaluation. Deprecated direct `snapshot:` initializers prepare at the view boundary and are kept only for small compatibility cases.
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
- `AGENTS.md` — testing and regression expectations.
