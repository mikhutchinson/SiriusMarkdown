# Runbook

This runbook is the local release authority for `SiriusMarkdown`. For the current public package release, use `0.5.5` as the tag and do not publish unless every release blocker below is clear.

## Build

Before changing architecture or renderer behavior, review `Docs/architecture.md` and `AGENTS.md` (if present locally).

```sh
swift build
```

## Test

```sh
swift test
```

Current status: `swift test` must pass with strict Swift-vs-Pretext comparison enabled across the required product fixture groups. Missing groups, duplicate fixture names/groups, absent fixture metadata, or known-drift allowlists are release blockers.
The release-gate discovery floor for this slice is `485` Swift tests.

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
- Document and code affordances must stay generic, source-backed, and replaceable. `MarkdownDocumentSurface` may own copy/export/collapse chrome, `MarkdownCodeBlockAffordances` may own code chrome visibility, and `MarkdownAffordanceActionHandler` may own platform actions; none of these APIs may hardcode private Sirius app concepts. Shared affordance icons are decorative SF Symbols; accessibility labels and help text belong on the enclosing buttons.
- Mermaid rendering must stay package-owned and prepared before SwiftUI body evaluation. `DefaultMarkdownMermaidRenderer` may produce ASCII plus concrete-color SVG and prepared root geometry; `MarkdownBlockView` may render the prepared image in a bounded pan/zoom viewport with controls from `MarkdownTheme.mermaidAffordances`. Mermaid zoom/fit/reset buttons must keep explicit accessibility labels while their decorative SF Symbol images stay hidden from accessibility synthesis. Do not add WebKit, app-private Mermaid wrappers, or a second Mermaid semantic engine.
- Heading typography must resolve H1-H6 through `MarkdownTheme.headings`. Visual SwiftUI `Font` and prepared-line CoreText measurement inputs (`fontSize`, `lineHeight`, `MarkdownInlineFontProfiles`) must come from the same `MarkdownTextStyle`; do not infer measurement profiles from arbitrary SwiftUI fonts.
- Inline math detection must remain source-preserving and must not rewrite code spans, fenced code, or Markdown source before `swift-markdown` parsing. Dollar-delimited inline math must not consume common currency/reward amounts such as `$100 - $5,500`, `$108,500`, or compact ISO currency-code amounts; compact currency-code coverage should derive from Foundation's `Locale.Currency.isoCurrencies` rather than a hand-maintained code list.
- Image handling must produce prepared decisions and placeholders by default; no network image fetch is allowed without an explicit host resolver.
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
  width are not painted as selected text.
- Prepared-line selection fragments must map visible byte offsets back through
  source runs before forming source ranges. Styled inline Markdown such as
  emphasis, strong, links, images, and math may have visible text shorter than
  its source delimiters, and full-line selection must preserve the full
  source-backed Markdown range while clipping highlight paint to glyph bounds.
- Prepared-line selection geometry must not rebuild rich per-line text geometry
  just because a host invalidates or moves the SwiftUI view graph. After warmup,
  repeated same-rect resolution, rect-only movement, and Sirius-style hosted
  layout storms must record zero new inline line-fragment builds, selection text
  geometry initializations, source-run mappings, CoreText line builds, and
  selection fingerprint builds. Keep
  `MarkdownSelectionPerformanceTests` in the release gate when changing
  document selection, prepared native lines, preference publication, or inline
  layout cache keys.
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
  If a Sirius-style hang returns, sample the process and check for
  `GraphHost.flushTransactions` ->
  `SelectionOverlay.updateNSView` -> AppKit `NSTextField setFont:` /
  `_invalidateEffectiveFont` / `updateCell`.
- Lists, task lists, tables, code blocks, math blocks, and HTML blocks must keep structured render paths. Do not collapse them back to `Text(block.text)` except as an explicit policy-denied or missing-structure fallback.
- Renderer tests must assert behavior through render plans, prepared snapshots, lightweight prepared render identities, source-backed selection copy contexts, inline payload helpers, diagnostics counters, and large-transcript prepared item identity. `Tools/RenderProbe` owns the `MarkdownDocumentView` AppKit pixel check so Swift Testing helper crashes do not excuse dropping document-render coverage.
- The full Swift suite runs serially in `Tools/release-check.sh` because the renderer tests host real SwiftUI/AppKit windows and text views; use `Tools/RenderProbe` for pixel-level AppKit coverage instead of forcing those windowed tests through parallel SwiftPM teardown.
- Repeated preparation of the same snapshot should reuse inline/code/math caches and record cache hits without incrementing prepare, highlighting, or math-render counters.

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

The script first runs `Tools/RenderProbe`, which renders representative document, document-affordance, compact-chat, transcript-wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, wide-to-narrow resize, Mermaid diagram pan/zoom, and code-highlighting cases through AppKit and rejects blank/trivial/collapsed/clipped/misleading output. It then runs Swift tests, asserts the discovered test floor and required named regressions, runs the root build, resolves/builds a clean temporary SwiftPM consumer against the local package path, bundles macOS demos (`Examples/scripts/bundle-macos-demos.sh`), runs Pretext install/test, generates symbol graphs, and performs warning-clean DocC conversion. Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
If this script fails, treat it as a real release blocker. Do not bypass the Pretext fixture comparison or the AppKit render probe to make a release check look green.

## Product Checks

```sh
bash Tools/product-check.sh
```

Run this before claiming native-renderer product quality. It wraps the release gate and adds focused checks for `MarkdownRenderSession`, bounded selection, long-transcript resize behavior, and render-probe output. The gate proves SiriusMarkdown behavior directly; it has no competitor dependency.

## Public Release Checklist

Use this checklist for `0.5.5`.

1. Confirm public hygiene:

   Review README, DocC, runbook, changelog, notices, package manifests, source, tests, examples, and tool metadata for stale internal references, stale dependency names, and unreleased implementation claims. Package-name references to SiriusMarkdown are expected.

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
   git add README.md runbook.md NOTICE.md changelog.md bugfix.md Docs Sources Tests Examples Tools Package.swift Package.resolved
   git commit -m "Prepare SiriusMarkdown 0.5.5 release"
   ```

6. Tag and push:

   ```sh
   git tag -a 0.5.5 -m "SiriusMarkdown 0.5.5"
   git push origin HEAD
   git push origin 0.5.5
   ```

7. After pushing, create the public release notes from `changelog.md`. The release notes must keep the claim precise: native SwiftUI block rendering, CoreText-painted prepared-line inline rendering, streaming snapshots, safe policies, language-aware default code highlighting, package-owned Mermaid pan/zoom over prepared SVG/ASCII, explicit accessibility labels for package-owned affordance controls, Pretext-backed layout gate, and demo/product probes. Do not claim a new Mermaid semantic engine or a WebKit renderer.

## Release Blockers

- `Tools/product-check.sh` fails.
- `swift test` fails or the expected Swift test count unexpectedly drops.
- Pretext fixture comparison has missing required groups, duplicate fixture names/groups, missing bundled metadata, or known-drift allowlists.
- `Tools/RenderProbe` reports blank, trivial, collapsed-spacing, clipped-wide, or insufficient-width rendering.
- `README.md`, DocC, runbook, changelog, or notices describe stale internal, stale dependency, or uncredited Pretext behavior.
- The public package surface requires non-package app concepts or a downstream app integration to function.
- `git remote -v` does not point at the intended public repository before pushing tags.

## Consumer Handoff

Consuming apps should depend on the public package product and use one of these paths:

- `MarkdownRenderSession(configuration: .compactChat)` for streaming/chat surfaces.
- `MarkdownRendererConfiguration.document` plus `prepare(snapshot:)` for document surfaces.
- Default `MarkdownRendererConfiguration(...)`, `.compactChat`, and `.document` use `MarkdownInlineRenderingMode.coreTextPaintedLines`.
- Explicit `MarkdownRendererConfiguration(inlineRenderingMode: .preparedNativeLines)` or `.systemText` only as compatibility fallbacks.

The consumer handoff is not part of the package release tag. It is a downstream integration check that should verify the app does not parse, highlight, or prepare raw Markdown from SwiftUI `body`.
