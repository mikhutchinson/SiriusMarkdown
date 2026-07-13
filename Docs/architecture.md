# Architecture

SiriusMarkdown is a Swift Package split into **Core**, **SwiftUI**, and **Pretext support**: semantics come from `swift-markdown`; streaming keeps immutable sealed regions plus one mutable tail; SwiftUI renders **already parsed** models and must not parse Markdown or run expensive layout from `body`.

## Modules and layout (as implemented)

```text
Sources/SiriusMarkdownCore/
  Source/MarkdownSourceBuffer.swift      — append-only UTF-8, slices, line map
  Stream/MarkdownStream.swift             — append, seal, host boundaries, snapshot
  Parser/SwiftMarkdownParser.swift        — Document parsing → render model
  Parser/MarkdownBoundaryScanner.swift   — incremental conservative seal scanning
  Model/MarkdownModel.swift               — MarkdownSnapshot, MarkdownBlock, IDs, ranges
  InlineLayout/InlineLayout.swift         — prepare/measure/layout, InlineLayoutEngine, caches
  Policy/MarkdownPolicies.swift           — link/image/HTML/code/math policy protocols
  Cache/MarkdownCaches.swift              — bounded parser / generic caches
  Diagnostics/MarkdownDiagnostics.swift    — counters, debug helpers

Sources/SiriusMarkdownSwiftUI/
  Views/MarkdownDocumentView.swift       — MarkdownDocumentView, StreamingMarkdownView
  Views/MarkdownRendererConfiguration.swift — theme, policies, highlighter/math hooks, prepared snapshot diff
  Views/MarkdownRenderSession.swift      — streaming render session, coalescing, incremental diff publishing
  Views/MarkdownCodeHighlighting.swift   — language normalization, default Highlight.js backend
  Views/MarkdownMathRendering.swift      — prepared math image, inline math pieces, baseline alignment
  Views/MarkdownMermaidRendering.swift    — Mermaid renderer, prepared SVG/ASCII
  Views/MarkdownDocumentSurface.swift     — document surface with affordances
  Views/MarkdownSourceLookup.swift       — source line/range lookup
  Views/MarkdownJavaScriptResourceLookup.swift — bundled JS resource resolution
  Blocks/MarkdownBlockView.swift         — structured block renderers
  Inline/InlineRunsView.swift            — prepared inline consumption, single-pass layout
  Inline/InlineRunView.swift             — single inline run view
  Inline/CoreTextPaintedInlineLineView.swift — CoreText CTLine paint bridge, pre-built line plans
  Inline/NativeInlineLineTextView.swift  — native text fallback for inline lines
  Theme/MarkdownTheme.swift              — typography, spacing, color tokens
  Interaction/MarkdownInteraction.swift  — selection controller, copy provider
  Interaction/MarkdownDocumentSelectionGeometry.swift — cross-block selection fragments, text-geometry-aware fragment generation for all block types
  Interaction/MarkdownNativeTextSelection.swift — platform-native text selection policy
  Interaction/MarkdownAffordanceSymbols.swift — decorative SF Symbol helpers
  Platform/MarkdownPlatformHooks.swift   — AppKit/UIKit/CoreText bridges

Sources/SiriusMarkdownMath/
  NativeMarkdownMathRenderer.swift       — SwiftMath-backed math renderer
  SwiftMathTypesetter.swift              — locked singleton, MTMathImage bridge, metric extraction

Sources/SiriusMarkdownPretextSupport/
  Golden/PretextFixture.swift             — fixture schema + golden comparator (Swift side)
  Fixtures/                               — bundled JSON resources for tests
Tools/pretext-golden/                     — Node/Bun oracle (`@chenglou/pretext`), see runbook
```

Products (see `Package.swift`): **`SiriusMarkdown`** (app-facing umbrella module that re-exports Core + SwiftUI), **`SiriusMarkdownCore`**, **`SiriusMarkdownSwiftUI`**, **`SiriusMarkdownMath`** (optional native math), **`SiriusMarkdownPretextSupport`**.

## Responsibilities

### Core

- **Source**: `MarkdownSourceBuffer` holds append-only chunks; `MarkdownSourceSlice` bridges to `String` at parse boundaries for `swift-markdown`.
- **Stream**: `MarkdownStream.append`, automatic `sealBoundaryIfPossible()`, `appendHostBoundary(id:)`, `finish()`, `snapshot()`, and source-backed `markdown(in:)`. Sealed ranges are parsed once and stored; the tail is reparsed while streaming. `MarkdownBoundaryScanState` prevents cumulative rescans of long active tails, tracks reference labels only to decide when sealing is safe, clears local unmatched-bracket ambiguity at block boundaries, and `MarkdownParserCache` keys sealed parses by source range, content hash, and reference-definition context when needed.
- **Parser**: `SwiftMarkdownParser` drives `Document(parsing:)` and converts the AST to `MarkdownBlock` / `MarkdownInlineRun` with block kinds (paragraph, heading, lists, task lists, quotes, code, tables, thematic breaks, math, HTML, blank). One UTF-8 line-start index is built per parse boundary and shared by block/inline converters so AST `SourceLocation` mapping does not rescan the source prefix per node. Reference-link semantics remain parser-owned; streaming passes prior sealed reference definitions into later slice parses instead of classifying links by string rules, and raw definition-looking lines inside parsed code/HTML content are excluded from that carry-forward context. Inline math recovery stays source-preserving while treating common currency/reward amounts and compact ISO currency-code amounts as prose; conservative bare-TeX recovery routes generated formula families to math renderers without taking over Markdown semantics from `swift-markdown`.
- **Model**: `MarkdownSnapshot` exposes `blocks`, ordered `items` (blocks interleaved with `MarkdownHostBoundary`), `generation`, `sourceLength`, `isFinished`. Identity for rendering uses `MarkdownBlock.id`, not array position.
- **Inline layout**: `PreparedInlineContent`, `VariableWidthLineWalker`, `InlineLayoutEngine` with bounded caches for prepared, measured, and laid-out inline results; `CoreTextInlineMeasurer` where CoreText is available. This is the Pretext-style **prepare** vs **layout** split for measurements that must not live in SwiftUI `body`.
- **Policy**: protocols (`MarkdownLinkPolicy`, `MarkdownImagePolicy`, etc.) and `DefaultMarkdownPolicy` (safe schemes for links; images and raw HTML denied by default).
- **Diagnostics**: `MarkdownDiagnosticsRecorder` / `MarkdownDiagnosticsCounters` (parse, tail vs sealed parse, boundary scan work, render preparation, highlighting/math, prepare, layout, width relayout, cache hits/misses) plus signpost helpers.

### SwiftUI

- **`MarkdownDocumentView`** (default theme `.document`) and **`StreamingMarkdownView`** (default `.compactChat`) should be driven with precomputed `MarkdownPreparedSnapshot` values. Direct `snapshot:` initializers remain as deprecated compatibility shims only; they enforce cheap code/math/HTML safety policy decisions but skip full highlighting/rendering/layout preparation, so long or streaming content should prepare in the host model layer.
- **`MarkdownRendererConfiguration`** wires `MarkdownTheme`, policies, optional `MarkdownLinkAction`, `MarkdownCopyProvider`, `MarkdownCodeHighlighter`, and `MarkdownMathRenderer` (`DefaultMarkdownCodeHighlighter` and `PlainMarkdownMathRenderer` ship as defaults; `PlainMarkdownCodeHighlighter` remains available for opt-out). Its `prepare(block:)` / `prepare(snapshot:)` methods move inline attributed text, measured inline content, link/image policy decisions, code highlighting, math rendering, and HTML policy decisions out of block `body` evaluation, with `MarkdownRenderPreparationCache` bounding inline/highlighted-code/rendered-math reuse.
- **`MarkdownMermaidRenderer`** / **`DefaultMarkdownMermaidRenderer`** prepares Mermaid diagrams through a bundled DOM-free `beautiful-mermaid` JavaScript runtime executed in JavaScriptCore. The default renderer produces ASCII text plus concrete-color light and dark SVG output in `MarkdownPreparedMermaidDiagram`; it also extracts root SVG geometry during preparation so SwiftUI does not parse SVG from `body`. The JavaScriptCore environment is shimmed with `self`/`window`/`global`/`setTimeout` so the embedded ELK layout engine resolves its global object correctly. SVG CSS variables are resolved and root-level Google-font imports are stripped during preparation for AppKit/UIKit image decoding. `MarkdownBlockView` selects the prepared color-scheme variant without rerendering Mermaid in SwiftUI `body` and renders diagrams in a bounded two-axis pan/zoom viewport with zoom out, zoom in, fit, and reset controls governed by `MarkdownTheme.mermaidAffordances`. Package-owned document, code, and Mermaid control icons are decorative SF Symbols hidden from accessibility synthesis; the enclosing buttons own the explicit labels and help text. This remains prepared SVG/ASCII from the bundled Mermaid renderer, not a new Mermaid semantic engine and not WebKit. Hosts can disable Mermaid rendering with `mermaidRenderer: nil`.
- **`MarkdownCodeLanguage`** normalizes fence info strings and aliases before highlighting. The default highlighter only highlights explicit supported languages through the embedded Highlight.js backend and renders plaintext, nohighlight, unlabeled, unsupported, or backend-failed fences plainly.
- **`MarkdownTheme`** owns `MarkdownSyntaxHighlightingPalette`, so default token colors are theme-owned and included in highlighted-code cache identity instead of being hidden inside SwiftUI body work.
- **`MarkdownBlockView`** branches on `MarkdownBlockKind` for structured blocks and consumes `MarkdownPreparedBlockContent` for inline text, lists, nested lists, tables, code, math, and HTML. List and table rendering uses prepared source-range IDs rather than array offsets. Tables use prepared cell inline layouts and measured natural widths to choose bounded adaptive columns in SwiftUI; the view layer does not reparse table Markdown or measure raw source.
- **`MarkdownTheme`** owns renderer-level table presentation tokens (`tableBackground`, header/alternate-row backgrounds, border/accent colors, corner radius, and cell padding). This keeps table styling part of the public renderer surface instead of a demo-only skin.

### Block styles (`Theme/Styles/`)

- `MarkdownBlockView` dispatches rendering through fourteen `@MainActor`
  per-block style protocols (`MarkdownHeadingBlockStyle`,
  `MarkdownParagraphBlockStyle`, `MarkdownBlockQuoteStyle`,
  `MarkdownCodeBlockStyle`, `MarkdownTableBlockStyle`,
  `MarkdownTableCellStyle`, `MarkdownListItemStyle`,
  `MarkdownUnorderedListMarkerStyle`, `MarkdownOrderedListMarkerStyle`,
  `MarkdownTaskListMarkerStyle`, `MarkdownThematicBreakStyle`,
  `MarkdownMathBlockStyle`, `MarkdownHTMLBlockStyle`,
  `MarkdownMermaidBlockStyle`) rather than owning chrome geometry inline.
  Each `makeBody(configuration:)` receives an already-prepared
  `MarkdownBlockStyleLabel` (a type-erased `View`) plus metadata (theme,
  block ID, indentation level, slot-specific fields) built by
  `MarkdownBlockView` from `MarkdownPreparedBlockContent` — styles never
  call `configuration.prepare(...)`, parse Markdown, run inline layout, or
  perform CoreText prepare. `MarkdownTheme` remains the sole prepare/layout
  cache identity core (`renderCacheIdentity`); style protocol types are not
  `Hashable` and are never part of a cache key. `MarkdownDefault*Style`
  (one per protocol) reproduces the pre-protocol hardcoded chrome exactly.
  The aggregate `MarkdownDocumentStyle` protocol bundles all fourteen
  slots behind a single conformance, with `MarkdownDefaultDocumentStyle` /
  `.default` as the all-defaults bundle.
- **Injection** (`View+Markdown.swift`): `MarkdownRendererConfiguration.documentStyle`
  (default `nil`, boxed in an internal `@unchecked Sendable`
  `MarkdownDocumentStyleBox` so the `Sendable` configuration type can carry
  a `@MainActor` existential) is the session-default style source. A
  `.markdown` namespace (`MarkdownNamespace<Base: View>`) exposes per-slot
  environment modifiers (`.markdown.headingStyle(_:)`, …) plus an aggregate
  `.markdown.documentStyle(_:)`. `MarkdownBlockView` and the private list-item
  row resolve each slot via the internal `resolvedMarkdownStyle` helper:
  `environment override ?? environment aggregate slot ?? configuration.documentStyle
  slot ?? MarkdownDefault*Style` — a per-block environment override always
  wins over an aggregate document style regardless of which modifier is
  applied first (avoiding Textual's aggregate-clobber bug). Both
  environment keys default to `nil` rather than a constructed
  `MarkdownDefault*Style`, because `EnvironmentKey.defaultValue` runs in a
  nonisolated context and cannot construct a `@MainActor`-isolated default;
  the `MarkdownDefault*Style()` fallback only happens inside
  `resolvedMarkdownStyle`, called from an already-`@MainActor` view.
  Resolving a style never reparses Markdown, never changes prepare/layout
  cache identity, and never churns sealed block IDs.
- **GitHub-inspired preset** (`Theme/Styles/GitHub/`): opt-in
  `MarkdownTheme.gitHub` (heading sizes/line heights, table padding/zebra/
  border tokens) pairs with `MarkdownGitHubDocumentStyle` / `.gitHub`
  (semibold headings with an H1/H2 divider underlay, a GitHub-bordered
  block-quote bar, denser code-block padding, hierarchical disc/circle/
  square unordered markers) through the `MarkdownRendererConfiguration.gitHub`
  convenience. `MarkdownGitHubColors` builds its palette from SwiftUI
  semantic colors (`.primary`/`.secondary`/`.blue` with opacity) rather than
  fixed sRGB values or an asset catalog, so it adapts to light/dark
  automatically. Slots the plan calls structurally identical to defaults
  (paragraph, ordered marker, list item, table, table cell, math, HTML,
  Mermaid) are left on `MarkdownDocumentStyle`'s own default extensions —
  table chrome in particular reads GitHub-flavored tokens straight from
  `MarkdownTheme.gitHub` without needing a distinct table style. Neither
  `.compactChat` nor `.document` is affected; GitHub is never the default.

- **Cross-block selection** (`MarkdownDocumentSelectionGeometry.swift`) uses a unified two-path strategy for all block types: blocks with `inlineLayout` (paragraphs, headings, block quotes) produce per-line `inlineLineFragments` from `inlineLayout`; blocks with only `selectionInlineLayout` (code blocks, math blocks) produce per-line fragments from `selectionInlineLayout`; table cells and list items use `inlineLineFragments` per cell/item when `inlineLayout ?? selectionInlineLayout` is available, falling back to a source-backed rect fragment when neither is present. `fragments(for:preparedContent:rect:)` checks `selectionInlineLayout` after `inlineLayout` so code and math blocks produce text-geometry-aware fragments without `inlineLayout` being set. `emitsTextLeafSelectionFragments` inspects table cells and list items recursively so the document-level selection layer can skip the fallback container fragment when any descendant has prepared inline content. Policy-denied blocks produce a source-backed rect fragment covering the block's source range so selection and copy remain correct even when rendering is suppressed.

- **Selection feel — drag affinity and contexts** (`MarkdownDocumentSelectionGeometry.swift`, `MarkdownInteraction.swift`, `MarkdownDocumentView.swift`):
  - *Continuous drag:* `hitFragment(at:in:hitSlop:affinityHint:)` adds a nearest-fragment fallback within the inter-block gutter threshold (hitSlop × 8) so drag selection through vertical theme-spacing gutters between blocks does not freeze. `MarkdownDocumentSelectionAffinity` (`.upstream` / `.downstream`) breaks ties using drag direction. Source byte endpoints remain correct; no per-glyph overlays are added.
  - *Selection contexts:* `MarkdownSelectionController.activeContext: MarkdownSelectionContextKind` tracks whether the active owner is `.document` or a `.scrollableRegion(MarkdownScrollableSelectionRegionID)`. `activateContext(_:)` clears all ranges when switching contexts — matching Textual's rule that selecting inside a code/table scroller clears document multi-block selection and vice versa.
  - *Pasteboard richness:* `MarkdownPasteboardPayload` carries `plainText`, `markdown` (exact source), and optional `rtf`/`html`. `MarkdownPasteboard.copy(MarkdownPasteboardPayload)` writes a multi-representation `NSPasteboardItem` on macOS (`.string` = plain text, `net.siriusmarkdown.markdown` = Markdown source) and a multi-type item on iOS. The `MarkdownPasteboard.markdownPasteboardType` constant (`"net.siriusmarkdown.markdown"`) identifies the Markdown UTI. Document Cmd-C routes through `affordanceActionHandler.copyPayload` only; single-string affordance copy still uses `copyString`. RTF/HTML must not involve network fetches or WebKit.
  - *macOS native interaction:* Bounded noneditable `NSTextView` leaves are the default macOS selection authority. AppKit owns glyph-backed highlights, word/drag/keyboard selection, continuous-prose wrapping/copy, and the contextual menu. Image-backed inline math stays inside the same stable TextKit leaf as a prepared baseline-aligned attachment; transitioning between streamed text fallback and a prepared math image does not remount the selection owner. The source-backed cross-block selector remains an explicit mode and automatically disables native leaf selection so gesture owners cannot overlap. CoreText-painted prepared lines remain its rendering/geometry authority.

### Inline Attachments (allowed images as reserved-box atomics)

- **The stack**: `MarkdownImagePolicy` decision → `MarkdownImageResolver`
  (`.data` / `.localFile` / `.remote` / `.placeholder`) → prepare builds a
  `MarkdownPreparedAttachment` (`MarkdownRendererConfiguration.swift`) with
  reserved `pointWidth`/`pointHeight`/`ascent`/`descent` → a `CoreTextInlineMeasurer`
  short-circuit makes the atomic image segment's measured width equal
  `pointWidth` instead of measuring alt text → `MarkdownCoreTextPaintedLinePlan`
  attaches a `CTRunDelegate` to the placeholder character's range so the
  painted `CTLine`'s advance/ascent/descent match the box, and records a
  `MarkdownCoreTextPaintedAttachmentGap` per attachment
  (`CoreTextPaintedInlineLineView.swift`) → the AppKit/UIKit surface
  reconciles one `MarkdownAttachmentHostNSView`/`UIView` per attachment ID
  (`MarkdownAttachmentHostView.swift`), positioned at the gap rect, drawing
  either an `NSImageView`/`UIImageView` from already-resolved `Data` or quiet
  reserved-box chrome. Host count always equals gap count; resolving bytes
  later swaps content inside the same host instance instead of remounting.
- **Denied stays text**: the default-deny path is untouched — denied images
  still render alt/`[image: reason]` text measured as an atomic text
  segment, exactly as before this stack existed. Only an explicit `.allow`
  policy decision creates a `MarkdownPreparedAttachment`.
- **No fetch/decode in `body`**: reserved metrics come from the theme's
  `attachmentPlaceholder` default box, or from a cheap ImageIO header-only
  probe (pixel dimensions, not full decode) of resolver-supplied `Data`/
  local-file bytes performed during `prepare(block:)` — never inside
  `updateNSView`/`updateUIView`/host `body`. Width-only relayout reuses the
  same prepared metrics and never re-invokes the resolver.
- **Selection stays box-precise**: `MarkdownDocumentSelectionGeometry`'s
  local selection `CTLine` attaches the same `CTRunDelegate` shape to an
  attachment's font run, so drag/hit-test x-mapping reflects `pointWidth`
  instead of the placeholder character's own glyph advance, while atomic
  snapping still resolves any partial hit to the whole image source range.
- **Future loading stays downstream**: an opt-in host loader can plug bytes or
  frames into these same attachment slots without inventing a parallel
  placement model. This package alone does not claim remote fetch, multi-frame
  decode, or animation.

### Math (`SiriusMarkdownMath`, optional)

- **`MarkdownMathRenderer`** is the pluggable seam. `preparedMath(_:isBlock:fontSize:)` returns `MarkdownPreparedMath` (`.text` or a typeset `.image`); the default implementation wraps the legacy `renderedMath(_:isBlock:)` so the core path stays text-only and dependency-free.
- **`NativeMarkdownMathRenderer`** (in the optional `SiriusMarkdownMath` product) typesets LaTeX with CoreText via SwiftMath. `SwiftMathTypesetter` is a locked, `@unchecked Sendable` singleton (mirroring the Mermaid runtime) that confines non-`Sendable` typesetting objects and yields only a `Sendable` `MarkdownPreparedMathImage` (alpha-coverage PNG plus point metrics). The SwiftMath dependency is linked only on iOS/macOS/visionOS and gated with `#if canImport(SwiftMath)`.
- **Preparation, not body**: typesetting and rasterization happen in `prepare(block:)`/`preparedInline`, keyed by the exact formula source, source range, renderer identity, font size, and backing scale in the bounded math cache. SwiftUI draws the cached image as a theme-tinted template; width changes never re-typeset. Block math renders centered with horizontal-scroll overflow; inline math composes through `MarkdownInlineMathPiece` with native `Text` so it wraps with prose. SwiftMath compatibility normalization for common generated LaTeX such as `\operatorname*`, `cases`, `equation`, and `align*` happens inside math preparation while preserving the original LaTeX source. Partial/invalid LaTeX and currency-shaped dollar text fall back to text until real math is present.
- **Vendored safety boundary**: SwiftMath's mutable symbol registry, reverse
  lookup tables, font tables, and display-support state are synchronized or
  immutable. Public atom models are canonicalized by runtime storage before
  copy/finalization, malformed composites fail closed, table cells finalize
  recursively, and `MTMathListBuilder.mathListToString` never mutates its input.
  The shared native/web math corpus and focused sanitizer tests guard this
  boundary in the release gate.

Host-native content between Markdown segments is modeled in Core via **`MarkdownSnapshot.items`** and **`appendHostBoundary`**; built-in document views now render prepared items and expose a host-boundary closure with an empty default.

### Pretext support

- **`PretextFixture`** / **`PretextExpectedLayout`** describe markdown, required product group metadata, font/spacing profile, and expected line/natural-width/height metrics.
- **`PretextGoldenComparator`** compares `InlineLayoutResult` from Swift to fixture tolerances.
- Full golden pipeline runs in **`Tools/pretext-golden`** against real Pretext output; see repository `runbook.md`.

## Boundaries (non‑negotiable)

- **`MarkdownBoundaryScanner`** only decides **when** a suffix may be sealed; it does not replace `swift-markdown` block or link classification.
- No WebKit on the core path; no row-hosted WebViews; avoid unbounded overlay fragments for links or selection.
- Public APIs stay general-purpose (no private transcript/tool/runtime concepts); prefer names like `MarkdownStream`, `MarkdownSnapshot`, `MarkdownTheme`, `MarkdownRendererConfiguration`, policies, `InlineLayoutEngine`, `TextMeasurer`.

## Verification shape

Renderer verification intentionally favors deterministic contracts over fragile UI-process snapshots:

- representative documents must prepare structured renderer inputs for headings, paragraphs, task lists, quotes, code, tables, math, and currency-shaped prose that must not become math;
- repeated preparation of the same snapshot must reuse inline, highlighted-code, and rendered-math caches and record diagnostics cache hits;
- large streaming transcripts must produce unique prepared item IDs for hundreds of sealed blocks plus the active tail;
- nested list metadata and table row/cell identities must come from the AST-backed render model, not SwiftUI offsets;
- native SwiftUI rendering must still have pixel-level coverage available through the opt-in `Tools/RenderProbe` offscreen AppKit host, which exercises `MarkdownDocumentView`, document affordances, and Mermaid pan/zoom diagrams outside Swift Testing's helper process when `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` is intentionally set;
- Pretext fixtures remain the layout oracle for line count, natural width, height, paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content. Known drift is not whitelisted, and missing required groups fail the gate.

## Related docs

- `Docs/streaming.md` — seal algorithm and host boundaries.
- `Docs/performance.md` — caches, diagnostics, measurement.
- `Docs/native-renderer-scorecard.md` — product quality bar.
