# Changelog

## Unreleased

- No unreleased changes.

## 0.3.1 - 2026-05-02

- Semver: patch release on top of `v0.3.0`, adding public code-block affordance controls without changing the renderer architecture or SwiftPM platform floor.
- Added `MarkdownCodeBlockAffordances` and `MarkdownTheme.codeBlockAffordances` so hosts can show or hide the generic code language label and copy-code button.
- Added normalized code-language display names for common fence aliases such as `language-swift`, `py`, `js`, `ts`, `objective-c`, and `c++`, while preserving conservative plain rendering for plaintext, nohighlight, unlabeled, and unsupported fences.
- Added native SwiftUI code-block chrome for language labels and copy-code actions above horizontally contained code blocks.
- Expanded render-plan and SwiftUI tests to prove code-language labels, copy visibility, copy text extraction, disabled chrome, and policy-denied code paths.

## v0.3.0 - 2026-05-02

- Semver: minor release, not `v0.2.1`, because this adds public renderer theme API (`MarkdownTextStyle`, `MarkdownHeadingStyles`, `MarkdownTheme.headings`) and deprecates the old singular H3-only compatibility fields.
- Added first-class H1-H6 heading typography to `MarkdownTheme` so visual SwiftUI fonts and CoreText measurement inputs resolve from the same `MarkdownTextStyle` source for every Markdown heading level.
- Replaced hardcoded H1/H2/H4-H6 visual fonts and prepared-line metrics with per-level `MarkdownHeadingStyles` lookup, keeping prepared-inline cache identity tied to resolved `fontSize`, `lineHeight`, and `fontProfiles`.
- Kept `headingFont`, `headingFontSize`, `headingLineHeight`, and `headingFontProfiles` as deprecated H3 compatibility aliases while documenting `MarkdownTheme.headings` as the general-purpose API.
- Added H1-H6 renderer-preparation contract tests, hardcoded-metric regression tests, heading cache-separation coverage, and a uniform compact-heading consumer-style test.

## v0.2.0 - 2026-05-02

- Replaced the default generic lexical code tokenizer with `DefaultMarkdownCodeHighlighter`, a language-aware highlighter backed by a pinned embedded `highlight.js` 11.11.1 common bundle through a synchronous JavaScriptCore wrapper on supported Apple platforms.
- Added `MarkdownCodeLanguage`, `MarkdownCodeHighlighterCacheIdentifying`, and `MarkdownSyntaxHighlightingPalette` so fence info strings are normalized, highlighter cache identities are stable, and syntax token colors belong to the theme.
- Updated code-block preparation to cache highlighted output by source hash, normalized language, theme palette identity, and highlighter identity while keeping all highlighting in render preparation.
- Made the default highlighter conservative: explicit supported languages are highlighted, while unsupported, plaintext, nohighlight, and unlabeled fences render as plain monospaced code instead of misleading lexical color.
- Added tests and product fixtures for alias normalization, supported-language semantic attributes, unsupported/plain fallback behavior, cache invalidation, width relayout reuse, and Swift/JSON/shell/YAML/diff/Markdown/plaintext/unsupported fences.
- Expanded the render probe and product gate with a code-highlighting document that verifies language-aware color variation and plain rendering for diagnostic/non-code fences.

## v0.1.1 and earlier

- Created the SiriusMarkdown package scaffold as a public MIT Swift package.
- Added the verbatim renderer plan at `plan.md` for implementation tracking.
- Added `AGENTS.md` as repo-local agent guidance so future work treats `plan.md` as binding project architecture.
- Added initial core source-buffer, streaming, parser, model, policy, cache, diagnostics, inline-layout, SwiftUI-renderer, and Pretext-support surfaces.
- Added a working Pretext golden smoke harness backed by `@chenglou/pretext` and a Node canvas shim.
- Expanded Swift coverage to 167 runner-counted tests plus parameterized edge cases for streaming equivalence, stable block IDs, source byte/line maps, conservative and incremental boundary scanning, block and inline classification, structured AST conversion, policy handling, cache eviction, diagnostics, renderer behavior, prepared snapshots, large-transcript prepared item identity, repeated preparation cache reuse, source-backed copy, umbrella import ergonomics, strict Pretext fixture drift, CoreText-vs-Pretext font-profile measurement, and deterministic inline layout.
- Fixed stable block identity so active-tail block IDs survive sealing.
- Fixed conservative boundary scanning so a single trailing newline does not seal a block or split multi-line blockquotes during streaming.
- Reworked parsing so `swift-markdown` owns Markdown semantics and the package converts the AST into the public render model.
- Added structured render-model data for task/list items, nested list items, ordered-list starts, table cells, table column alignments, and deterministic block content hashes.
- Switched source slices to segment-backed storage and made the boundary scanner iterate source lines without copying the full tail.
- Switched inline layout to a Pretext-shaped prepare/layout split with cached measured segments and cheap width-change layout.
- Removed SwiftUI-owned inline fragment measurement from `InlineRunsView`; inline rendering now consumes runs as one attributed payload with policy-gated links/images.
- Added structured SwiftUI render paths for lists, task lists, tables, code blocks, math blocks, and HTML blocks.
- Tightened default link/image policy and added a protocol-driven renderer configuration surface for links, images, HTML, code, math, code highlighting, and math rendering.
- Integrated parser, prepared-inline, measured-inline, and layout caches with diagnostics counters instead of leaving cache/counter types as passive scaffolding.
- Moved SwiftUI code highlighting and math rendering into explicit prepared block content with bounded reuse through `MarkdownRenderPreparationCache`, so `MarkdownBlockView.body` consumes prepared output.
- Added a real `SiriusMarkdown` umbrella target that re-exports Core and SwiftUI, plus a consumer-facing import test and DocC links for the app-facing module.
- Replaced the static-document demo placeholder with a buildable SwiftPM SwiftUI demo that imports the public `SiriusMarkdown` product.
- Added incremental active-tail boundary scanning, source-backed copy slices, prepared snapshots, host-boundary rendering hooks, broader diagnostics/signposts, lazy overwide inline fallback measurement, expanded Pretext fixtures, and buildable streaming/document reader demos.
- Added meaningful headless renderer contract tests in place of fragile default-suite AppKit bitmap snapshots, covering representative documents, large streaming transcripts, prepared identity stability, and render-preparation cache reuse.
- Count highlighted-code and rendered-math cache hits/misses in `MarkdownDiagnosticsRecorder` so repeated preparation proves cache reuse through counters, not only through highlighter/renderer call counts.
- Updated README, DocC, architecture, streaming, performance, and runbook documentation to make prepared snapshots the primary integration path and to describe the renderer/performance verification contract.
- Tightened the Pretext Swift fixture comparison so emoji/CJK, multilingual, and RTL drift now fails the test suite instead of being treated as a passing known issue.
- Fixed the native inline measurer so strict Pretext fixtures for emoji/CJK, multilingual, RTL, and long overwide words pass without fixture allowlists.
- Stopped renderer preparation from eagerly populating per-character inline unit measurements, added a view-time layout mode that refuses overwide measurement fallback, and added tests for both paths.
- Fixed boundary scanning for incomplete active-tail lines so repeated appends without a newline do not rescan the same unfinished line.
- Made `BoundedMarkdownCache` update recency on cache hits and added a real least-recently-used eviction assertion.
- Restored native pixel coverage for representative structured documents through `Tools/RenderProbe`, which renders `MarkdownDocumentView` through AppKit in its own release-gated process.
- Added `Tools/release-check.sh` and made CI call the same release gate used locally.
- Made CI's Pretext golden step clean-checkout safe with `npm ci`.
- Differentiated `DocumentReaderDemo` from the renderer workbench by turning it into a reader product surface with document metadata, outline navigation, reading-width controls, full-source copy, reader-specific sample content, and no visible pipeline counters.
- Added renderer-level table presentation tokens to `MarkdownTheme` and redesigned SwiftUI table rendering around prepared cell measurements, bounded adaptive columns, header/accent styling, row separators, and subtle banding.
- Stopped `StreamingTranscriptDemo` from publishing renderer configuration changes, avoiding unnecessary Combine copies during macOS window startup while still refreshing prepared snapshots through the model.
- Redesigned `MarkdownDemoApp` into a sidebar-driven static-document workbench with renderer coverage metrics, pipeline counters, and expanded examples for inline policy, tables, wide blocks, multilingual layout, math/HTML policy, and long-form documents.
- Added `MarkdownRenderSession` as the public streaming/document integration seam that owns stream state, long-lived renderer configuration, source-backed copy, prepared snapshots, caches, and diagnostics counters.
- Replaced SwiftUI's newline-injected prepared-inline render path with native `Text(AttributedString)` rendering while still consuming prepared `InlineLayoutResult` records for width-change diagnostics and layout reuse.
- Added `MarkdownInlineRenderingMode.preparedNativeLines`, which renders prepared attributed line slices through SwiftUI `Text(AttributedString)` and is guarded by a representative document render probe plus a word-spacing check. This is prepared-line rendering, not a fully custom glyph renderer.
- Added bounded `MarkdownSelectionController` support for block-level selection, source-backed Markdown copy, plain-text copy, and selection rendering without per-fragment overlay growth.
- Added source-preserving inline math detection outside code spans/fences, prepared image decisions with placeholder-safe defaults, a theme-aware default code highlighter, and an optional `SiriusMarkdownMath` product used by the demos.
- Added `Docs/native-renderer-scorecard.md` and `Tools/product-check.sh` to make native-renderer product quality a gate instead of a claim.
- Expanded Pretext from a nine-fixture seed to a required 25-group product corpus covering paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content.
- Promoted packaged chat and document presets to `MarkdownInlineRenderingMode.preparedNativeLines` while keeping direct custom configurations on `.systemText` for compatibility.
- Expanded `Tools/RenderProbe` to cover compact chat, multilingual text, inline attributes crossing lines, code/table overflow, hard breaks, long words, width reach, color variation, and collapsed word-spacing checks.
- Added large-product stress surfaces to the demos: a generated big cached document in `MarkdownDemoApp`, a generated very-long streaming document with burst controls in `StreamingTranscriptDemo`, and a generated cached appendix in `DocumentReaderDemo`.
