# SiriusMarkdown Native Renderer Plan

## Summary

Build `SiriusMarkdown`: a public Swift Package for native, streaming-first Markdown rendering on Apple platforms.

This project exists because current renderer approaches fail at least one core requirement:

- “Unbounded selection overlays can spin the main thread while the transcript is streaming.”
- “A renderer dependency can be too expensive even when parsing is cached.”
- “Do not assume an opt-in modifier is the only activation point.”
- “The current native parser should not be the final assistant Markdown renderer.”

Design goals:

- Native SwiftUI rendering, not WebKit.
- `swift-markdown` for Markdown semantics.
- Pretext-inspired `prepare()` / cheap `layout()` model.
- No parsing, syntax highlighting, or expensive layout from SwiftUI `body`.
- Stable streaming IDs with immutable sealed regions and one mutable tail.
- Zero-copy source storage where possible; bounded copies only where parser APIs require `String`.
- CoreText-backed measurement; Accelerate-assisted layout math where useful; optional Metal-backed debug/canvas experiments only after the core renderer is stable.

## Directory Structure

```text
SiriusMarkdown/
  Package.swift
  README.md
  LICENSE
  Sources/
    SiriusMarkdownCore/
      Source/
      Stream/
      Parser/
      Model/
      InlineLayout/
      Policy/
      Cache/
      Diagnostics/
    SiriusMarkdownSwiftUI/
      Views/
      Blocks/
      Inline/
      Theme/
      Interaction/
      Platform/
    SiriusMarkdownPretextSupport/
      Fixtures/
      Golden/
  Tests/
    SiriusMarkdownCoreTests/
    SiriusMarkdownSwiftUITests/
    SiriusMarkdownPretextSupportTests/
  Examples/
    MarkdownDemoApp/
    StreamingTranscriptDemo/
    DocumentReaderDemo/
  Tools/
    pretext-golden/
      package.json
      src/
      fixtures/
      snapshots/
  Docs/
    SiriusMarkdown.docc/
    architecture.md
    performance.md
    streaming.md
```

## Module Responsibilities

`SiriusMarkdownCore`

- `Source/`: append-only UTF-8 source buffer, region slices, byte offsets, line maps, source-range conversion.
- `Stream/`: `MarkdownStream`, sealed regions, mutable tail, host boundaries, safe boundary scanner.
- `Parser/`: `swift-markdown` adapter, AST-to-render-model converter, math scanner, HTML classification.
- `Model/`: public `MarkdownSnapshot`, `MarkdownBlock`, `MarkdownInlineRun`, `MarkdownBlockID`, `MarkdownSourceRange`.
- `InlineLayout/`: prepared inline content, line ranges, natural width, line stats, variable-width line walker.
- `Policy/`: link, image, raw HTML, code, and math policy protocols.
- `Cache/`: parser cache, prepared-inline cache, highlighted-code cache, measured-layout cache.
- `Diagnostics/`: counters, signposts, debug dumps, performance assertions.

`SiriusMarkdownSwiftUI`

- `Views/`: `StreamingMarkdownView`, `MarkdownDocumentView`.
- `Blocks/`: paragraphs, headings, lists, task lists, quotes, code, tables, thematic breaks, math blocks.
- `Inline/`: inline run renderer, link rendering, inline code, emphasis, strong, strikethrough, soft/hard breaks.
- `Theme/`: `MarkdownTheme`, typography, spacing, color tokens, compact chat and document presets.
- `Interaction/`: per-block selection, copy-as-Markdown, link actions, image placeholders.
- `Platform/`: CoreText/AppKit/UIKit text measurement and platform-specific pasteboard/openURL hooks.

`SiriusMarkdownPretextSupport`

- Defines a shared fixture schema for Swift and JS layout comparisons.
- Runs real `@chenglou/pretext` in `Tools/pretext-golden`.
- Compares Swift line breaking, height, natural width, CJK, RTL, emoji, code spans, hard breaks, and atomic inline items against golden fixtures.

## Performance Contract

Hard rules:

- SwiftUI `body` must never parse Markdown.
- SwiftUI `body` must never perform syntax highlighting.
- SwiftUI `body` must never prepare inline layout from raw Markdown.
- Width changes may call cheap layout only, not parse or prepare.
- Streaming append reparses only the mutable tail.
- Sealed regions are immutable and cacheable.
- Renderer identity comes from stable block IDs, not array offsets.
- No unbounded per-fragment overlays for links, attachments, or selection.
- No row-hosted WebViews.

Data strategy:

- Store source as append-only UTF-8 chunks with slice references.
- Convert to `String` only at sealed-region and tail parse boundaries because `swift-markdown` requires string input.
- Keep public render models as `Sendable` value types.
- Use content hashes plus source ranges for cache keys.
- Use arenas or compact arrays for inline runs and line layout records.

Native acceleration strategy:

- CoreText owns glyph measurement and text shaping.
- Accelerate/vDSP may be used for prefix sums, width scans, and layout-stat reductions when benchmarks prove value.
- Metal is not a v0.1 text-layout dependency. Reserve it for future debug visualization, large static-document raster experiments, or custom canvas renderers after correctness lands.

## Implementation Plan

1. Scaffold package, DocC, examples, CI, and Pretext golden tool.
2. Build `MarkdownSourceBuffer`, source slices, line map, and source-range tests.
3. Implement `MarkdownStream` with append, seal boundary, finish, and snapshot.
4. Add conservative streaming boundary scanner for fences, HTML blocks, math fences, loose-list ambiguity, blank-line stability, and host boundaries.
5. Parse sealed regions and mutable tail with `swift-markdown`.
6. Convert AST into the public render model.
7. Implement stable block identity and chunked-vs-static equivalence tests.
8. Implement inline prepare/layout contracts and native text measurement.
9. Build SwiftUI block renderer with compact chat and document themes.
10. Add code highlighting, math, link, image, and HTML policy hooks.
11. Add per-block copy/select behavior.
12. Add Pretext fixtures and golden drift tests.
13. Build demo apps for static docs and live streaming.
14. Run performance harnesses against large documents and long streaming transcripts.

## Test Plan

Core tests:

- Whole-document parse equals streamed parse across many chunk sizes.
- Stable block IDs do not churn when appending to the active tail.
- Host boundaries seal Markdown before native insertions.
- Loose ordered lists, nested lists, task lists, long fences, shorter inner fences, tables, HTML, and math fences do not seal early.
- Unsafe links/images/HTML are governed by policy.

Performance tests:

- No parsing from SwiftUI `body`.
- No O(n^2) append behavior.
- Width changes reuse prepared inline content.
- Hundreds of sealed blocks plus active tail stay within budget.
- Cache eviction remains bounded.

Renderer tests:

- Snapshot coverage for paragraphs, headings, lists, quotes, code, tables, math, links, images, dark/light themes.
- Overflow tests for wide code and tables.
- Accessibility and copy-as-Markdown tests.
- Pretext golden layout tests under Node or Bun.

## Assumptions

- Sirius remains the brand name, but the package is general-purpose.
- No private app/runtime/transcript/browser concepts appear in public APIs.
- `swift-markdown` owns Markdown parsing semantics.
- Pretext is mandatory as the layout reference model and web golden oracle.
- v0.1 optimizes correctness, stable identity, streaming performance, and native rendering before cross-block selection polish.
