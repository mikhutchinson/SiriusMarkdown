# Bugfix Log

## Open

- No parser-slice defects recorded after the AST-conversion repair.

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
