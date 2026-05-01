# Performance

The **v0.1 contract** (see `plan.md` and `AGENTS.md`) is architectural: SwiftUI **`body`** must not parse Markdown, run syntax highlighting over raw source, rebuild the full document model, or drive wrapping via heavy per-fragment **`sizeThatFits`** over raw markdown strings. Width-driven work should stay on the **cheap layout** side of the prepare/layout split.

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

SwiftUI block views consume **`MarkdownInlineRun`** arrays already produced by the parser; use **`InlineLayoutEngine`** when you need deterministic metrics (tests, golden comparison, future layout-driven UI).

## Rendering path

- **`MarkdownDocumentView`** / **`StreamingMarkdownView`** render **`MarkdownSnapshot`** and **`MarkdownRendererConfiguration`** only—they do not call **`MarkdownStream`** or parsers inside **`body`**.
- **`MarkdownRendererConfiguration.prepare(snapshot:)`** returns **`MarkdownPreparedSnapshot`**, preparing inline attributed payloads, link/image policy decisions, code highlighting, math rendering, and HTML policy decisions before block bodies consume them. `MarkdownRenderPreparationCache` bounds inline/code/math reuse by source range, content hash, and preparation namespace.
- **`MarkdownBlockView`** consumes **`MarkdownPreparedBlockContent`** for paragraphs, headings, lists, tables, code, math, and HTML, and exposes copy/context hooks through **`MarkdownCopyProvider`**.

## Accelerate and Metal

**CoreText** owns glyph measurement for **`CoreTextInlineMeasurer`**. **Accelerate** / **vDSP** are reserved for proven layout math wins; **Metal** is not part of v0.1 text layout (future visualization or specialized canvases only).

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
