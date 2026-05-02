# Bugfix Log

## Open

- No open bugfix entries for the Pretext/product gate fixed in this slice.

## Fixed

- Replaced the decorative `swift-markdown` parser call with an AST-to-render-model converter. Block kinds, headings, task list state, ordered-list starts, table cells/alignments, inline runs, code info strings, and HTML blocks now come from `swift-markdown` instead of the earlier line/delimiter classifier.
- Fixed parser identity to satisfy the streaming contract: active-tail IDs stay stable while appending and survive sealing, while deterministic `contentHash` values are stored separately for cache keys.
- Fixed table cell conversion to expose semantic cell text and inline runs instead of raw pipe-padding source text.
- Fixed source slicing and boundary scanning so append-time sealing iterates source lines without materializing the full growing tail string; parser string materialization remains bounded to sealed-region/tail parse boundaries.
- Fixed source line scanning to store chunk slice references instead of allocating per-line byte arrays. Line `String` materialization is now lazy at scanner call sites that explicitly ask for text.
- Fixed inline layout to split `prepare` from cheap width-dependent `layout`. `MeasuredInlineContent` caches segment and unit widths during prepare, so resize/layout passes reuse prepared measurements instead of calling CoreText again.
- Removed the custom SwiftUI inline flow `Layout` that measured each inline fragment with `sizeThatFits`. Inline rendering now builds one policy-gated attributed text payload and leaves wrapping to the platform text system.
- Fixed the SwiftUI renderer to handle structured lists, task lists, tables, code blocks, math blocks, and HTML blocks through block-specific render paths instead of generic `Text(block.text)` fallbacks.
- Fixed renderer configuration to expose protocol hooks for link, image, HTML, code, math, code highlighting, and math rendering.
- Fixed default policy safety by rejecting unknown/file/javascript/data link schemes and blocking image loading by default.
- Fixed CI's Pretext smoke path to run `npm ci` before `npm test`, making the workflow clean-checkout safe.
- Fixed `Tools/pretext-golden/src/index.js` resolving fixtures from `Tools/fixtures` instead of `Tools/pretext-golden/fixtures`.
- Fixed the Pretext golden smoke harness to use the currently published `@chenglou/pretext` package version and provide a Node canvas measurement context.
- Fixed `MarkdownBlockID` churn when a block moved from mutable tail to sealed storage by removing tail/sealed namespace from generated IDs.
- Fixed `MarkdownBoundaryScanner` treating a single trailing newline as a blank-line seal boundary, which split streamed multi-line blockquotes and could seal too early.
- Corrected source-buffer UTF-8 test expectations for Arabic and mixed Unicode byte offsets after expanding byte/line-map coverage.
- Wired parser and inline layout caches into executable code paths with diagnostics counters for tail reparses, sealed-region cache hits/misses, inline prepare, and layout.
- Moved code highlighting, math rendering, and HTML policy evaluation out of `MarkdownBlockView.body` into `MarkdownPreparedBlockContent`, with highlighted-code and rendered-math cache reuse.
- Fixed the public `SiriusMarkdown` product so it now builds an importable umbrella module instead of only composing Core and SwiftUI targets, and added a test that exercises the consumer import surface.
- Fixed active-tail boundary scanning to retain scanner state and scan newly appended complete lines once, preventing long open tails from accumulating O(n²) scan work.
- Fixed active-tail boundary scanning again so incomplete lines already inspected during prior appends are not rescanned until a newline arrives.
- Fixed inline measurement so per-character unit measurement is a cached overwide fallback instead of eager work during normal prepare.
- Fixed renderer preparation so it no longer eagerly stores per-character fallback units for every inline segment.
- Fixed SwiftUI width-dependent inline layout so it can refuse view-time overwide fallback measurement and consume only prepared segment measurements.
- Fixed `BoundedMarkdownCache` to update recency on cache hits instead of behaving like FIFO while claiming LRU-style behavior.
- Fixed the built-in SwiftUI document/streaming views to consume `MarkdownPreparedSnapshot` items, preserve host boundaries, and keep inline policy decisions out of block body evaluation.
- Fixed the default test suite instability caused by AppKit bitmap snapshot rendering under Swift Testing by keeping deterministic headless renderer contract tests in Swift Testing and moving the `MarkdownDocumentView` AppKit pixel check into `Tools/RenderProbe`, a separate release-gated process.
- Fixed diagnostics coverage for render-preparation caches so highlighted-code and rendered-math cache hits/misses are recorded alongside inline cache reuse.
- Fixed the weak Pretext assertion that treated emoji/CJK and RTL drift as an expected passing condition; strict drift now fails the suite instead of being whitelisted.
- Fixed Swift CoreText measurement to match Pretext's selected-font profile for unsupported glyphs by using the selected font's missing-glyph advance instead of silently measuring native fallback fonts.
- Fixed the overwide inline unit fallback cache so Swift Testing no longer crashes while exercising long-word Pretext fixtures.
- Fixed `DocumentReaderDemo` launch crashing in `initializeWithCopy for MarkdownRendererConfiguration` after backend copy-provider changes. Document-style demos now use a source-backed `MarkdownCopyProvider(markdownSource:)` that slices exact UTF-8 source ranges without capturing a full `MarkdownStream` inside renderer configuration; added Unicode slice coverage and verified `swift test`, `Examples/MarkdownDemoApp`, and bundled `DocumentReaderDemo.app` launch.
- Fixed the integration footgun where hosts had to manually keep stream state, renderer configuration, copy providers, caches, and prepared snapshots aligned by adding `MarkdownRenderSession`.
- Fixed the remaining newline-injected prepared-inline view path so SwiftUI now renders the attributed payload natively while prepared line layout is still consumed for width-change counters and tests.
- Fixed inline math coverage by detecting `$...$` as typed math runs without rewriting source and without touching code spans or fenced code.
- Fixed image handling being only visible text by adding prepared image decisions; default behavior remains placeholder-only with no remote loading.
- Fixed selection/copy being purely ad hoc text selection by adding a bounded block-level selection controller with source-backed Markdown and plain-text copy helpers.
- Fixed the Pretext gate being limited to a narrow seed corpus by requiring a 25-group product fixture set with metadata, duplicate name/group rejection, JS mirror parity, and strict Swift-vs-Pretext layout comparison.
- Fixed packaged chat and document presets still requiring callers to opt into prepared-line rendering; `.compactChat` and `.document` now select `.preparedNativeLines`, while raw custom configurations keep `.systemText` as a compatibility fallback.
