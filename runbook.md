# Runbook

This runbook is the local release authority for `SiriusMarkdown`. For the current public package release, use `0.6.6` as the tag and do not publish unless every release blocker below is clear.

## Build

Before changing architecture or renderer behavior, review `Docs/architecture.md` and `AGENTS.md` (if present locally).

```sh
swift build
```

## Test

```sh
swift test
```

Current status: `swift test` must pass with strict Swift-vs-Pretext comparison enabled across the required product fixture groups. Missing groups, duplicate fixture names/groups, absent required layout metadata (`font`, `lineHeight`, `whiteSpace`, `wordBreak`), invalid/nonzero `letterSpacing`, or known-drift allowlists are release blockers.
The release-gate discovery floor for this slice is `850` Swift tests.

Count the Swift test functions reported by the runner and keep the release-gate discovery floor current:

```sh
swift test list
```

Parser acceptance for the current slice:

- `SwiftMarkdownParser` must parse sealed regions and the mutable tail through `swift-markdown`; no line-based Markdown classifier should decide Markdown semantics.
- `MarkdownBlock` IDs must be stable while appending to the active tail and after sealing. Do not include mutable upper bounds or content hashes in the identity. Use `contentHash` for cache keys.
- The render model must expose parser-owned structure for task states, ordered-list starts, nested list items, table cells, table alignments, code info strings, HTML blocks, math blocks, and inline destinations.
- Whole-document parse and streamed parse must match for block IDs, kinds, and text across the chunk matrix.
- Boundary scanner changes must preserve conservative handling for code fences, math fences, HTML blocks, reference-link ambiguity, loose-list ambiguity, blank-line stability, and CRLF-vs-LF equivalence.
- Reference-style links must keep `swift-markdown` as semantic owner. Streaming may track labels to decide when sealing is safe and may pass sealed reference definitions into later slice parses, but it must not classify final link semantics outside the parser. Do not carry raw `[label]: ...` text forward from fenced code, HTML, or other parsed non-definition content.
- Code-fence close candidates must match CommonMark closer shape: no tabs or more than three leading spaces before the marker, at least the opening marker length, and only whitespace after the marker run. Trailing text or four-space-indented marker content inside a fence must not seal the stream.
- Display math may be recovered after `swift-markdown` parsing when standalone `\[ ... \]` or `$$ ... $$` delimiter lines appear inside a paragraph, but the parser must split that paragraph into source-backed text/math/text blocks rather than moving math work into SwiftUI. Bare `[` / `]` display delimiter recovery is allowed only for standalone delimiter lines whose enclosed content has clear TeX signals; ordinary bracketed prose and reference labels must stay prose.

Layout and renderer acceptance for the current slice:

- Inline layout must keep the Pretext-shaped contract: call `prepare` to tokenize and measure, then call cheap `layout` for width changes. Tests should prove `layout(MeasuredInlineContent, ...)` does not call the measurer again.
- Renderer preparation must not eagerly populate per-character unit measurements. Unit fallback measurement is only allowed for explicit overwide fallback paths, and SwiftUI view-time layout must be able to refuse that fallback.
- SwiftUI `body` must not parse Markdown, syntax highlight, or run custom per-inline measurement/wrapping. `InlineRunsView` should consume prepared inline content with measured segments instead of installing a custom SwiftUI `Layout`.
- Use `MarkdownRenderSession` or `MarkdownRendererConfiguration.prepare(snapshot:)` in model/controller code and pass `MarkdownPreparedSnapshot` into `MarkdownDocumentView` or `StreamingMarkdownView`. Deprecated direct `snapshot:` view initializers are compatibility shims, not the streaming/document path; they may enforce cheap safety policy decisions but must not run full highlighting, math rendering, or inline preparation synchronously.
- Renderer configuration must be protocol-driven for link, image, HTML, code, math, code highlighting, and math rendering hooks.
- Default code highlighting must stay language-aware, pluggable, and conservative: explicit supported languages may be highlighted through the JavaScriptCore/highlight.js backend where available; plaintext, nohighlight, unlabeled, unsupported, unavailable-runtime, and failed-backend fences should render plainly.
- Document and code affordances must stay generic, source-backed, and replaceable. `MarkdownDocumentSurface` may own copy/export/collapse chrome, `MarkdownCodeBlockAffordances` may own code chrome visibility, and `MarkdownAffordanceActionHandler` may own platform actions; none of these APIs may hardcode private host-app concepts. Shared affordance icons are decorative SF Symbols; accessibility labels and help text belong on the enclosing buttons.
- Mermaid rendering must stay package-owned and prepared before SwiftUI body evaluation. `DefaultMarkdownMermaidRenderer` may produce ASCII plus concrete-color SVG and prepared root geometry; `MarkdownBlockView` may render the prepared image in a bounded pan/zoom viewport with controls from `MarkdownTheme.mermaidAffordances`. Mermaid zoom/fit/reset buttons must keep explicit accessibility labels while their decorative SF Symbol images stay hidden from accessibility synthesis. Do not add WebKit, app-private Mermaid wrappers, or a second Mermaid semantic engine.
- Heading typography must resolve H1-H6 through `MarkdownTheme.headings`. Visual SwiftUI `Font` and prepared-line CoreText measurement inputs (`fontSize`, `lineHeight`, `MarkdownInlineFontProfiles`) must come from the same `MarkdownTextStyle`; do not infer measurement profiles from arbitrary SwiftUI fonts.
- Block chrome customization must resolve through the fourteen per-block style
  protocols without moving parse, highlighting, math, or inline preparation
  into `body`. Per-slot environment overrides win over aggregate environment
  styles, which win over `MarkdownRendererConfiguration.documentStyle`, which
  wins over package defaults. Style changes must not alter prepared cache keys,
  sealed block IDs, or the `.compactChat` / `.document` defaults. The
  GitHub-inspired preset remains explicit opt-in through
  `MarkdownRendererConfiguration.gitHub`.
- Inline math detection must remain source-preserving and must not rewrite code spans, fenced code, or Markdown source before `swift-markdown` parsing. Dollar-delimited inline math must not consume common currency/reward amounts such as `$100 - $5,500`, `$108,500`, or compact ISO currency-code amounts; compact currency-code coverage should derive from Foundation's `Locale.Currency.isoCurrencies` rather than a hand-maintained code list. Bare-TeX recovery is only a conservative routing layer for generated math; it must keep code spans, paths, unknown commands, escaped Markdown, and prose out of math while preserving whole generated formula families as source-backed math runs.
- Image handling must produce prepared decisions and placeholders by default; no network image fetch is allowed without an explicit host resolver.
- Allowed images (an explicit `MarkdownImagePolicy` `.allow` decision) must become prepared inline attachments — reserved `pointWidth`/`pointHeight`/`ascent`/`descent` box metrics on the atomic image segment, a `CTRunDelegate`-backed gap on the CoreText line plan, and exactly one host view per attachment ID (`hosts.count == attachmentGaps.count`, INV-IA6). Denied images (the default) must keep the existing alt/`[image: reason]` text-atomic path unchanged. Width-only relayout must not re-invoke the image resolver or re-probe bytes. No `URLSession` call or full-frame `CGImageSourceCreate*` decode may live in a host's `body`/`updateNSView`/`updateUIView`; a cheap header-only size probe of already-resolved `Data`/local-file bytes during prepare is the one sanctioned exception. Do not add a parallel image rendering path (e.g. a `Text`-composition bypass) for the allowed box path — CoreText line gaps are the only paint path for allowed images.
- Document selection must default on through
  `MarkdownRendererConfiguration.documentSelection` for `compactChat`,
  `document`, `MarkdownDocumentView`, `StreamingMarkdownView`, and
  `MarkdownDocumentSurface`. If no host controller is supplied, the views must
  create an internal `MarkdownSelectionController` and still support drag
  selection, highlights, and Cmd-C source copy.
- Selection/copy must stay range bounded and source-backed. Contiguous
  selections copy one exact source slice; non-contiguous selections copy
  ordered source slices deterministically; prepared plain text is only a
  fallback when source is unavailable. Do not add unbounded per-fragment
  overlays for links, images, or selection.
- Document-selection highlight geometry must come from rendered text leaves,
  not parent block/list/table rectangles. Prepared-line fragments should carry
  text-leaf coordinates, and first/last-line highlights must clip through
  CoreText-backed string offsets so gutters, table grids, and trailing blank row
  width are not painted as selected text. All block types with inline content
  (paragraphs, headings, block quotes, list items, table cells, code blocks,
  math blocks, HTML blocks) must publish text-geometry-aware selection
  fragments from prepared inline layout, not rect-based fallbacks.
  `MarkdownCrossBlockSelectionTests` must pass in the release gate.
- `MarkdownDocumentSelectionFragment.fragments(for:preparedContent:rect:)` must
  check `selectionInlineLayout` after `inlineLayout`. Code blocks, math blocks,
  and any block that prepares only `selectionInlineLayout` (not `inlineLayout`)
  must produce text-geometry-aware fragments via the `selectionInlineLayout`
  path. Do not fall through to the rect-based block fragment when
  `selectionInlineLayout` is available (INV-S3).
- `MarkdownPreparedBlockContent.emitsTextLeafSelectionFragments` must return
  true for every block type that will produce text-leaf fragments via
  `fragments(for:preparedContent:rect:)`. For tables, this check must inspect
  whether any cell has `inlineLayout` or `selectionInlineLayout`, not just the
  block-level `inlineLayout`. For list items, this check must inspect each
  item's `inlineLayout` or `selectionInlineLayout` recursively including nested
  items. Do not allow `emitsTextLeafSelectionFragments` to return false for any
  block that will in practice emit text-leaf fragments (INV-S3).
- Prepared-line selection fragments must map visible byte offsets back through
  source runs before forming source ranges. Styled inline Markdown such as
  emphasis, strong, links, images, and math may have visible text shorter than
  its source delimiters, and full-line selection must preserve the full
  source-backed Markdown range while clipping highlight paint to glyph bounds.
- Prepared-line selection geometry must not rebuild rich per-line text geometry
  just because a host invalidates or moves the SwiftUI view graph. After warmup,
  repeated same-rect resolution, rect-only movement, and host-app-style hosted
  layout storms must record zero new inline line-fragment builds, selection text
  geometry initializations, source-run mappings, CoreText line builds, and
  selection fingerprint builds. Keep
  `MarkdownSelectionPerformanceTests` in the release gate when changing
  document selection, prepared native lines, preference publication, or inline
  layout cache keys.
- **Inter-block drag continuity:** Document selection drag must resolve
  continuously across paragraph → list → code block transitions. When the
  pointer is in vertical theme-spacing gutters between fragments, the
  nearest-fragment fallback must resolve to the nearest fragment within
  the inter-block gutter threshold (hitSlop × 8 ≈ 32 pt). Pointers in
  large empty regions beyond the document content still resolve to nil.
  Source-backed endpoints must remain valid (INV-NS1). No per-glyph
  overlays added (INV-NS2). `MarkdownDocumentSelectionAffinityTests` must
  pass in the release gate.
- **Scrollable selection contexts:** Activating code-block or table selection
  must clear document multi-block selection and vice versa. A drag entirely
  within a code/table block activates `.scrollableRegion`; a drag crossing
  block boundaries activates `.document`. `MarkdownSelectionContextTests`
  must pass in the release gate.
- **Pasteboard richness:** Document Cmd-C must write a multi-representation
  `NSPasteboardItem` (macOS): `.string` = plain text, `net.siriusmarkdown.markdown`
  = exact Markdown source, optional `.rtf`/`.html`. Do not produce network fetches
  or WebKit HTML generation on copy. `MarkdownPasteboardTests` must pass in
  the release gate.
- **Text.Layout bridge:** Enabling `nativeTextSelection` by default or switching
  the default-path selection authority to `Text.Layout` are out of bounds.
  The Part 04 evaluation (2026-07-09) concluded: Parts 01–03 close the feel
  gap on the CoreText default path; a `Text.Layout` bridge is not warranted
  and risks the `SelectionOverlay` hang class. Reject recorded; INV-NS3 upheld.
- Native text selection must stay a separate compatibility knob bounded to
  stable text leaves. Keep `MarkdownRendererConfiguration.nativeTextSelection`
  defaulted to `.disabled`. On macOS, `.enabled` must work by using
  package-owned selectable AppKit text leaves instead of SwiftUI's private
  `SelectionOverlay`; on other Apple platforms, the SwiftUI selection helper
  remains bounded. Native text selection must avoid document, scroll, stack,
  custom leading-layout containers, table-grid containers, toolbar,
  Mermaid-control, and host containers, while list, quote, and table cell text
  leaves stay selectable. The product gate's enabled-selection AppKit probe
  must keep passing and must observe selectable AppKit text leaves before a
  host opts in.
  SwiftUI tests must prove list/quote/table leaves mount selectable
  `NSTextView`s and that a hosted list leaf can select and copy through the
  AppKit pasteboard path.
- Lists, task lists, tables, code blocks, math blocks, and HTML blocks must keep structured render paths. Do not collapse them back to `Text(block.text)` except as an explicit policy-denied or missing-structure fallback.
- Renderer tests must assert behavior through render plans, prepared snapshots, lightweight prepared render identities, source-backed selection copy contexts, inline payload helpers, diagnostics counters, and large-transcript prepared item identity. `Tools/RenderProbe` owns the opt-in `MarkdownDocumentView` AppKit pixel check so Swift Testing helper crashes do not excuse dropping document-render coverage.
- The full Swift suite runs serially in `Tools/release-check.sh` because the renderer tests host real SwiftUI/AppKit views and text views. `Tools/RenderProbe` is opt-in through `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` for pixel-level offscreen AppKit coverage instead of forcing those artifact checks through every default release run.
- Repeated preparation of the same snapshot should reuse inline/code/math caches and record cache hits without incrementing prepare, highlighting, or math-render counters.
- CTLine creation must not run in `updateNSView`/`updateUIView`; it must run in `prepare(snapshot:)` (INV-P1). The representable assigns a pre-built `MarkdownCoreTextPaintedLinePlan` when the layout result matches the initial pre-computed layout.
- `PreparedInlineTextView` must render content on first appearance without waiting for the width preference (INV-P2). The initial layout is pre-computed at a default width during preparation.
- `MarkdownRenderSession` must publish a `MarkdownPreparedSnapshotDiff` alongside the full snapshot (INV-P3). Only changed/new items trigger preparation; sealed blocks hit the reuse path.
- Selection fragment geometry must be cached; repeated same-rect resolution must record zero new builds after warmup (INV-P4). `onPreferenceChange` must skip sorting and storage when fragments are unchanged.
- Performance benchmarks must pass in release mode with defined frame budgets (INV-P8). See `MarkdownPerformanceBenchmarkTests.swift`.
- `MarkdownPreparedMathImage` must carry real ascent/descent estimated from the parsed atom tree, not `pointHeight`/`0` (INV-M2). Inline math baseline alignment uses `-descent`, not a heuristic.
- Math rasterization scale must match the screen's backing scale (min 2.0), not a fixed 3.0. `MarkdownMathImageView` must use `.interpolation(.medium)`.
- Math and attachment render geometry must be finite, positive, and bounded
  before entering CoreText, SwiftUI, AppKit/UIKit frames, or layer corner
  radii. Math cache identity must hash exact formula source; code highlighting
  must include the complete fence info string; Mermaid and attachment cache
  identity must include every render-relevant theme/style field.
- Vendored SwiftMath public-model paths must fail closed. Runtime subclass and
  atom type must be canonicalized before copying/finalizing; table cells must
  finalize recursively; `mathListToString` must not mutate caller-owned cells
  and must preserve color atoms; shared font tables and custom symbol maps must
  remain synchronized under concurrent reads and writes.
- Streaming math detection must track open `$$`, `\[...\]`, and `\begin{...}...\end{...}` environments to prevent early sealing (INV-M5).

## Pretext Golden Tool

```sh
cd Tools/pretext-golden
npm ci
npm test
```

The Pretext tool is the JavaScript golden oracle for layout drift. It uses real `@chenglou/pretext` with `@napi-rs/canvas` providing a Node measurement context. Transcript/path wrapping fixtures also validate line opportunities against the vendored MIT `linebreak` UAX #14 implementation under `Tools/pretext-golden/vendor/linebreak`, using package-owned generic paths instead of local machine paths. Swift fixtures live in `Sources/SiriusMarkdownPretextSupport/Fixtures`; JS fixtures live in `Tools/pretext-golden/fixtures`. `npm test` validates every fixture, rejects duplicate names/groups, verifies all required product groups, and checks Swift-resource/JS mirror parity.
Run `npm ci` and `npm test` sequentially; running them in parallel can race while `node_modules` is being replaced.
The Swift fixture comparison must not whitelist known drift. A failing Pretext fixture is a release blocker until the native layout path or fixture contract is corrected.
Third-party credits for Pretext, the Node canvas shim, the vendored Unicode line-break oracle, and `swift-markdown` are tracked in `NOTICE.md`.

## Release Checks

```sh
bash Tools/release-check.sh
```

By default the script skips `Tools/RenderProbe`; set `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` when pixel-level AppKit output is intentionally part of the release pass. The opt-in probe renders representative document, document-affordance, compact-chat, transcript-wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, wide-to-narrow resize, Mermaid diagram pan/zoom, and code-highlighting cases through an offscreen AppKit host and rejects blank/trivial/collapsed/clipped/misleading output. The default script runs Swift tests, asserts the discovered test floor and required named regressions, runs the root build, resolves/builds a clean temporary SwiftPM consumer against the local package path, bundles macOS demos (`Examples/scripts/bundle-macos-demos.sh`), runs Pretext install/test, generates symbol graphs, and performs warning-clean DocC conversion. Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
If this script fails, treat it as a real release blocker. Do not bypass the Pretext fixture comparison, and do not report opt-in AppKit render-probe coverage as passing unless `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` was actually run.

## Product Checks

```sh
bash Tools/product-check.sh
```

Run this before claiming native-renderer product quality. It wraps the release gate and adds focused checks for `MarkdownRenderSession`, bounded selection, and long-transcript resize behavior. Set `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` when product validation intentionally includes RenderProbe output. The gate proves SiriusMarkdown behavior directly; it has no competitor dependency.

## Public Release Checklist

Use this checklist for `0.6.6`.

1. Confirm public hygiene:

   Review README, DocC, runbook, changelog, notices, package manifests, source, tests, examples, and tool metadata for stale internal references, stale dependency names, and unreleased implementation claims. Package-name references to SiriusMarkdown are expected.

   Reconcile local and live release state before choosing a version:

   ```sh
   git fetch origin --prune --tags
   git describe --tags --always --dirty
   git ls-remote --heads --tags origin
   gh release list --repo mikhutchinson/SiriusMarkdown --limit 100
   ```

   Historical tags are immutable. Every public release tag should have a
   matching GitHub Release record; backfill a missing record from the matching
   changelog section instead of moving or deleting the tag. The new version is
   valid only when neither a local/remote tag nor a GitHub Release already uses
   it.

2. Confirm third-party credit files:

   ```sh
   test -f LICENSE
   test -f NOTICE.md
   rg -n "@chenglou/pretext|swift-markdown|@napi-rs/canvas|linebreak" NOTICE.md README.md runbook.md
   ```

3. Run the product gate:

   ```sh
   bash Tools/product-check.sh
   ```

4. Run final repository checks:

   ```sh
   git diff --check
   git status --short
   git remote -v
   git branch --show-current
   ```

   The expected release branch is the public default branch. If the remote expects a different branch name, rename or push intentionally before tagging. If the public remote is not `https://github.com/mikhutchinson/SiriusMarkdown.git`, update the README installation snippet before tagging.

5. Commit the release candidate:

   ```sh
   git add README.md runbook.md NOTICE.md changelog.md bugfix.md release-notes Docs Sources Tests Examples Tools Package.swift Package.resolved
   git commit -m "Prepare SiriusMarkdown 0.6.6 release"
   ```

6. Tag and push:

   ```sh
   git tag -a 0.6.6 -m "SiriusMarkdown 0.6.6"
   git push origin HEAD
   git push origin 0.6.6
   ```

7. After pushing, create the public release from the matching `changelog.md`
   section and verify that GitHub marks it as Latest:

   ```sh
   gh release create 0.6.6 \
     --repo mikhutchinson/SiriusMarkdown \
     --verify-tag \
     --latest \
     --title "SiriusMarkdown 0.6.6" \
     --notes-file release-notes/0.6.6.md
   gh release view 0.6.6 \
     --repo mikhutchinson/SiriusMarkdown \
     --json tagName,name,isDraft,isPrerelease,publishedAt,url
   ```

   The release notes must keep the claim precise: native SwiftUI block
   rendering, CoreText-painted prepared-line inline rendering, streaming
   snapshots, safe policies, language-aware default code highlighting,
   package-owned Mermaid pan/zoom over prepared SVG/ASCII, explicit
   accessibility labels for package-owned affordance controls, Pretext-backed
   layout and math-corpus gates, and demo/product probes. Do not claim a new
   Mermaid semantic engine, network image loading, animated media, or a WebKit
   renderer.

## Release Blockers

- `Tools/product-check.sh` fails.
- `swift test` fails or the expected Swift test count unexpectedly drops.
- Pretext fixture comparison has missing required groups, duplicate fixture names/groups, missing bundled metadata, or known-drift allowlists.
- `Tools/RenderProbe`, when intentionally enabled, reports blank, trivial, collapsed-spacing, clipped-wide, or insufficient-width rendering.
- `README.md`, DocC, runbook, changelog, or notices describe stale internal, stale dependency, or uncredited Pretext behavior.
- Local/remote tags, the latest changelog version, README install version,
  runbook version, release-check fallback version, or GitHub Releases disagree.
- The public package surface requires non-package app concepts or a downstream app integration to function.
- `git remote -v` does not point at the intended public repository before pushing tags.

## Consumer Handoff

Consuming apps should depend on the public package product and use one of these paths:

- `MarkdownRenderSession(configuration: .compactChat)` for streaming/chat surfaces.
- `MarkdownRendererConfiguration.document` plus `prepare(snapshot:)` for document surfaces.
- Default `MarkdownRendererConfiguration(...)`, `.compactChat`, and `.document` use `MarkdownInlineRenderingMode.coreTextPaintedLines`.
- Explicit `MarkdownRendererConfiguration(inlineRenderingMode: .preparedNativeLines)` or `.systemText` only as compatibility fallbacks.

The consumer handoff is not part of the package release tag. It is a downstream integration check that should verify the app does not parse, highlight, or prepare raw Markdown from SwiftUI `body`.
