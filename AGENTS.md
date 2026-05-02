# AGENTS.md

This repository builds `SiriusMarkdown`: a public Swift Package for native, streaming-first Markdown rendering on Apple platforms.

The goal is not to make a small demo renderer. The goal is to build the best Markdown renderer available to SwiftUI applications: native, fast, streaming-aware, cacheable, policy-driven, and stable under long AI/chat/document workloads.

`plan.md` is binding. Do not reinterpret the architecture away from it.

## Why This Exists

This project exists because existing approaches failed core requirements:

- “Unbounded selection overlays can spin the main thread while the transcript is streaming.”
- “A renderer dependency can be too expensive even when parsing is cached.”
- “Do not assume an opt-in modifier is the only activation point.”
- “The current native parser should not be the final assistant Markdown renderer.”

Those are not flavor text. They are failure modes this package must avoid.

## Non-Negotiable Architecture

- Native SwiftUI renderer, not WebKit.
- `swift-markdown` owns Markdown semantics. Do not replace it with a homegrown Markdown parser.
- The streaming model is immutable sealed regions plus one mutable tail.
- Streaming append reparses only the mutable tail.
- Sealed regions are immutable and cacheable.
- Stable renderer identity comes from block IDs, not array offsets.
- Source storage is append-only UTF-8 chunks with slice references.
- Convert source to `String` only at sealed-region and mutable-tail parse boundaries because `swift-markdown` requires `String`.
- Pretext is the layout reference model and golden oracle.
- Swift native layout mirrors Pretext’s `prepare()` / cheap `layout()` split.
- CoreText owns native glyph measurement and shaping.
- Accelerate/vDSP may be used only where benchmarks prove value.
- Metal is not a v0.1 text-layout dependency. Reserve it for later debug visualization, static-document raster experiments, or custom canvas renderers after correctness lands.
- No row-hosted WebViews.
- No unbounded per-fragment overlays for links, attachments, or selection.

## Hard Performance Rules

SwiftUI `body` must never:

- parse Markdown
- perform syntax highlighting
- prepare inline layout from raw Markdown
- run expensive text measurement loops
- rebuild the full document model from source
- depend on array offsets for identity

Width changes may call cheap layout only. They must not parse, highlight, or prepare inline content again.

If a change moves parsing, highlighting, source scanning, AST conversion, or expensive layout into SwiftUI view evaluation, reject that direction.

## Module Ownership

### `SiriusMarkdownCore`

Core owns the expensive pipeline:

- `Source/`: append-only UTF-8 source buffer, region slices, byte offsets, line maps, source-range conversion.
- `Stream/`: `MarkdownStream`, sealed regions, mutable tail, host boundaries, safe boundary scanner.
- `Parser/`: `swift-markdown` adapter, AST-to-render-model converter, math scanner, HTML classification.
- `Model/`: public `MarkdownSnapshot`, `MarkdownBlock`, `MarkdownInlineRun`, `MarkdownBlockID`, `MarkdownSourceRange`.
- `InlineLayout/`: prepared inline content, measured segments, line ranges, natural width, line stats, variable-width line walker.
- `Policy/`: link, image, raw HTML, code, and math policy protocols.
- `Cache/`: parser cache, prepared-inline cache, highlighted-code cache, measured-layout cache.
- `Diagnostics/`: counters, signposts, debug dumps, and performance assertions.

Core must produce `Sendable` value models that SwiftUI can render without recomputing the world.

### `SiriusMarkdownSwiftUI`

SwiftUI owns presentation of already-prepared data:

- `Views/`: `StreamingMarkdownView`, `MarkdownDocumentView`.
- `Blocks/`: paragraphs, headings, lists, task lists, quotes, code, tables, thematic breaks, math blocks.
- `Inline/`: rendering of prepared inline runs and layout records, not raw Markdown preparation.
- `Theme/`: `MarkdownTheme`, typography, spacing, color tokens, compact chat and document presets.
- `Interaction/`: per-block selection, copy-as-Markdown, link actions, image placeholders.
- `Platform/`: AppKit/UIKit/CoreText bridges, pasteboard, and openURL helpers.

SwiftUI may compose views. It must not become the parser, highlighter, or layout engine.

### `SiriusMarkdownPretextSupport`

Pretext support owns layout truth:

- shared fixture schema for Swift and JavaScript
- golden comparisons against real `@chenglou/pretext`
- drift tests for line breaking, height, natural width, CJK, RTL, emoji, code spans, hard breaks, and atomic inline items

Pretext is not just a smoke test. It is the reference model for the prepare/layout contract.

## Renderer Quality Bar

This package should clear a higher bar for streaming SwiftUI workloads and exceed a raw Pretext integration for Apple apps by combining:

- native SwiftUI block rendering
- `swift-markdown` semantic correctness
- Pretext-style prepared layout
- CoreText measurement
- stable streaming identity
- policy-controlled links/images/HTML/code/math
- bounded caches
- long-transcript performance tests
- polished chat and document themes

Do not settle for “renders common Markdown.” The renderer must handle AI/chat/document workloads where content is long, streamed, mixed with host-native insertions, and repeatedly resized.

## Required Public Surface Direction

Keep public APIs general-purpose. Sirius is the brand, not a dependency on private app concepts.

Public types should remain in this family:

- `MarkdownStream`
- `MarkdownSnapshot`
- `MarkdownBlock`
- `MarkdownInlineRun`
- `MarkdownTheme`
- `MarkdownRendererConfiguration`
- `MarkdownCodeHighlighter`
- `MarkdownMathRenderer`
- `MarkdownLinkPolicy`
- `MarkdownImagePolicy`
- `MarkdownHTMLPolicy`
- `InlineLayoutEngine`
- `TextMeasurer`

Do not expose private transcript, tool, browser, runtime-event, or plan-mode concepts.

## Parsing Rules

Use `swift-markdown` for Markdown semantics.

Allowed scanner responsibility:

- finding conservative safe streaming seal points
- tracking open code fences
- tracking HTML block ambiguity
- tracking math fences
- tracking blank-line stability
- respecting host boundaries

Forbidden scanner responsibility:

- classifying Markdown blocks semantically
- parsing lists, tables, headings, emphasis, links, or code blocks as final truth
- replacing cmark-gfm behavior with string rules

The scanner can decide when a region is safe to parse. It cannot decide what the Markdown means.

## Source Storage Rules

Source storage should be append-only UTF-8 chunks.

Prefer:

- byte offsets
- line maps
- slice references
- bounded copies
- lazy decoding only at parser boundaries

Avoid:

- copying growing tails repeatedly
- decoding lines to `String` during every append scan
- storing duplicate full-source strings
- O(n²) append or scan behavior

`swift-markdown` requires `String`, so conversion is acceptable at sealed-region and mutable-tail parse boundaries. Treat other conversions as suspect until justified.

## Inline Layout Rules

Inline layout must follow the Pretext-inspired split:

1. Prepare once:
   - normalize inline runs
   - shape/measure stable segments
   - compute natural width
   - build break opportunities
   - store compact segment records
   - cache by content hash, source range, theme/font traits, and policy-relevant inputs

2. Layout cheaply:
   - consume prepared segments
   - compute line ranges for a width
   - reuse measurements
   - support variable-width line iteration
   - avoid per-character CoreText calls except for explicitly cached emergency fallback paths

SwiftUI layout must not call `sizeThatFits` over many inline run subviews as the primary wrapping strategy. That recreates the UI-thrashing failure this package exists to avoid.

## Policy And Safety Rules

Default behavior must be safe for a public package:

- Links: allow only safe default schemes such as `http`, `https`, `mailto`, and relative URLs.
- Images: do not fetch network images by default.
- Raw HTML: deny or render inertly by default.
- Code: render text safely; highlighting is pluggable.
- Math: validation/rendering is pluggable.
- Host apps can opt into broader behavior through explicit policy hooks.

Do not hardcode app-specific URL routing, image loading, browser behavior, or tool affordances.

## SwiftUI Renderer Rules

Renderer implementation must include real structured block renderers:

- paragraphs
- headings
- block quotes
- thematic breaks
- unordered lists
- ordered lists
- nested lists
- task lists
- fenced code blocks
- tables with horizontal overflow containment
- inline emphasis, strong, strikethrough, code, links, autolinks
- math blocks through renderer hooks
- image placeholders through policy hooks

Do not render structured blocks as raw `Text(block.text)` except as a temporary failing implementation with tests proving the gap.

Wide code and tables must have explicit overflow containment. Text must not overlap or cause unstable row sizing.

## Caching Rules

Caches are part of the architecture, not an optimization afterthought.

Required cache families:

- sealed-region parser cache
- prepared-inline cache
- highlighted-code cache
- math validation/render cache
- measured-layout cache

Caches must be bounded and testable. Cache keys should use source ranges, content hashes, renderer configuration, theme/font traits, and policy-relevant inputs as appropriate.

## Diagnostics And Performance Evidence

Add diagnostics that make regressions visible:

- parse counts
- tail reparse counts
- sealed-region cache hits/misses
- inline prepare counts
- layout counts
- width-change relayout counts
- highlighting counts
- main-thread assertions for forbidden work where practical
- signposts for parse, prepare, layout, render, and cache activity

Do not claim performance from intuition. Add tests, counters, signposts, or benchmarks.

## Testing Requirements

Core tests must cover:

- whole-document parse equals streamed parse across many chunk sizes
- stable block IDs do not churn when appending to the active tail
- host boundaries seal Markdown before native insertions
- loose ordered lists do not seal early
- nested lists and task lists come from the AST
- long fences and shorter inner fences do not seal early
- tables, HTML, and math fences do not seal early
- unsafe links/images/HTML are governed by policy
- source storage avoids O(n²) append behavior

Layout tests must cover:

- prepared inline content reused across width changes
- width changes do cheap layout only
- Pretext golden fixtures for multilingual text, emoji, CJK, RTL, code spans, hard breaks, soft wraps, and atomic inline items
- natural width, line ranges, line count, and height drift
- performance budgets for large paragraphs and long transcripts

Renderer tests must cover:

- SwiftUI snapshots for paragraphs, headings, lists, quotes, code, tables, math, links, images, dark/light themes
- table/code overflow
- link and image policy behavior
- accessibility labels
- copy-as-Markdown
- hundreds of sealed blocks plus active streaming tail

Release checks must include:

- `swift test`
- DocC build
- demo app build
- `npm ci` and Pretext golden tests under `Tools/pretext-golden`
- clean-checkout SPM dependency resolution

A test that only constructs a SwiftUI view is not a renderer test.

## Implementation Discipline

Before coding:

1. Read `plan.md`.
2. Read this file.
3. Inspect the current implementation.
4. Identify whether the change belongs in Core, SwiftUI, or PretextSupport.
5. Keep expensive work out of SwiftUI.
6. Add or update tests that prove the relevant contract.

When fixing review findings, fix the architecture, not just the symptom.

Examples:

- If `swift-markdown` is decorative, replace the string classifier with AST conversion.
- If source slicing copies, redesign slices around chunk references.
- If layout measures in the hot path, move measurement into prepare and cache it.
- If SwiftUI wraps inline runs with `sizeThatFits`, feed it prepared layout records instead.
- If policies are concrete defaults only, expose protocol-driven hooks.
- If tests only instantiate views, add real rendering, policy, layout, and snapshot assertions.

## What Not To Build

Do not build:

- a WebKit renderer as the core path
- a string-rule Markdown parser
- a SwiftUI body parser
- a per-character layout loop in the resize path
- unbounded overlay fragments
- app-private transcript/tool/browser concepts
- network image loading by default
- policy bypasses for convenience
- demo-only behavior that cannot survive long streaming transcripts

## Definition Of Done

A change is not done until it preserves the architecture in `plan.md`.

For meaningful renderer or pipeline work, done means:

- semantics come from `swift-markdown`
- streaming reparses only the mutable tail
- sealed regions remain immutable and cacheable
- source copies are bounded and intentional
- inline prepare and layout remain separate
- SwiftUI receives prepared snapshots/models
- policies are explicit and safe by default
- Pretext drift is checked where layout behavior changes
- performance-sensitive behavior has tests, counters, or benchmarks
- public APIs remain general-purpose
