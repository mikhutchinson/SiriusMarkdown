# Native Renderer Product Scorecard

SiriusMarkdown should be chosen when the current checkout proves the product bar below without weakening the documented architecture.

The goal is a native, streaming-first Markdown renderer for Apple applications: `swift-markdown` owns semantics, source storage stays append-only, sealed regions are immutable and cacheable, SwiftUI consumes prepared snapshots, width changes perform cheap layout only, and interaction remains bounded under long chat and document workloads.

## Required Wins

- Semantics: Markdown structure comes from `swift-markdown`, not string-rule parsing.
- Streaming: appends reparse only the mutable tail; sealed regions stay immutable and cacheable.
- Resize: width changes perform cheap prepared layout only.
- Rendering: paragraphs, headings, nested/task lists, quotes, code, Mermaid diagrams, tables, math, inline/reference links, images, and host boundaries have structured native render paths.
- Inline rendering: packaged chat and document presets plus direct custom configurations use `MarkdownInlineRenderingMode.coreTextPaintedLines` by default, so visible wrapping is driven by cached prepared line ranges and whole-line CoreText painting contained to the finite proposal. CTLine creation runs in the prepare phase, not in the SwiftUI update path. `MarkdownInlineRenderingMode.preparedNativeLines` and `.systemText` remain explicit compatibility fallbacks.
- Single-pass layout: new blocks render content on first appearance without waiting for a width preference pass. `MarkdownRenderSession` publishes a `MarkdownPreparedSnapshotDiff` so only changed blocks trigger view updates.
- Measured performance: benchmarks enforce <16ms per append for 100+ blocks, <4ms per width-change relayout, and zero CTLine creation in SwiftUI body after preparation.
- Selection consistency: source-backed document selection is consistent across all block types — paragraphs, headings, block quotes, lists, task lists, nested lists, code blocks, tables, math blocks, and HTML blocks. Selection fragment geometry is cached; repeated same-rect resolution records zero new builds after warmup.
- Math quality: native LaTeX math through `SiriusMarkdownMath` renders with
  display-list typographic metrics from vendored SwiftMath
  `MTMathImage.LayoutInfo` (not atom-tree heuristics), proper baseline alignment
  using `-descent`, screen-matched rasterization scale, and reliable streaming
  detection for `$$`, `\[...\]`, and `\begin{...}...\end{...}` environments.
- Font measurement: production CoreText measurement defaults to system-profile fonts and includes font profiles in cache identity; Pretext fixtures pin explicit named fonts for oracle stability.
- Safety: links, images, HTML, code, and math stay policy controlled, with no remote image fetch by default.
- Link cues: automatic decoration is a font-relative decorative template symbol
  that shares one reserved box with a resolved untinted favicon; decoration and
  the first label token cannot wrap onto separate lines.
- Interaction: macOS defaults to bounded noneditable `NSTextView` leaves, giving selection and secondary-click menus to AppKit while avoiding an unbounded transcript-wide selection overlay. Visual wraps do not become copied newline characters, image-backed inline math stays selectable as a baseline-aligned TextKit attachment, semantic ranges survive streamed fallback/image transitions, and the standard Copy/Speech/services menu is not replaced by a package-only “Copy Markdown” item. Exact-source cross-block selection remains explicit and has one document-level context-menu owner: it resolves continuously through inter-block gutters, mutually excludes code/table scrollers through `MarkdownSelectionContextKind`, and writes plain text plus the Markdown UTI on Cmd-C without network or WebKit work. Package-owned document/code/Mermaid controls retain explicit accessibility labels and decorative SF Symbols.
- Product surfaces: demos show clean transcript and reader behavior first, with diagnostics available as inspection rather than primary UI.

## Product Gate

Run:

```sh
bash Tools/product-check.sh
```

The gate wraps the release check and adds focused product checks for render sessions, selection, long transcript behavior, resize discipline, required Pretext fixture groups, and AppKit-rendered document/chat/overflow/multilingual/finite-column containment, document-affordance, Mermaid pan/zoom, code-highlighting output, and the default CoreText-painted prepared-line path.

## Release Claim

The public product claim is CoreText-painted prepared-line rendering: layout ranges come from SiriusMarkdown's prepared layout engine, and the default presets own shaped line drawing through `coreTextPaintedLines`. Do not claim a WebKit renderer, a new Markdown semantic engine, or per-fragment overlay selection.

Do not claim native-renderer product quality unless the product gate passes and at least one consuming app path uses only public SiriusMarkdown APIs with no parsing, highlighting, or raw Markdown layout in SwiftUI `body`.
