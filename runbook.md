# Runbook

This runbook is the local release authority for `SiriusMarkdown`. For the current public package release, use `0.4.14` as the tag and do not publish unless every release blocker below is clear.

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

Count the Swift test functions reported by the runner:

```sh
swift test list | wc -l
```

Parser acceptance for the current slice:

- `SwiftMarkdownParser` must parse sealed regions and the mutable tail through `swift-markdown`; no line-based Markdown classifier should decide Markdown semantics.
- `MarkdownBlock` IDs must be stable while appending to the active tail and after sealing. Do not include mutable upper bounds or content hashes in the identity. Use `contentHash` for cache keys.
- The render model must expose parser-owned structure for task states, ordered-list starts, nested list items, table cells, table alignments, code info strings, HTML blocks, math blocks, and inline destinations.
- Whole-document parse and streamed parse must match for block IDs, kinds, and text across the chunk matrix.
- Boundary scanner changes must preserve conservative handling for code fences, math fences, HTML blocks, loose-list ambiguity, and blank-line stability.

Layout and renderer acceptance for the current slice:

- Inline layout must keep the Pretext-shaped contract: call `prepare` to tokenize and measure, then call cheap `layout` for width changes. Tests should prove `layout(MeasuredInlineContent, ...)` does not call the measurer again.
- Renderer preparation must not eagerly populate per-character unit measurements. Unit fallback measurement is only allowed for explicit overwide fallback paths, and SwiftUI view-time layout must be able to refuse that fallback.
- SwiftUI `body` must not parse Markdown, syntax highlight, or run custom per-inline measurement/wrapping. `InlineRunsView` should consume prepared inline content with measured segments instead of installing a custom SwiftUI `Layout`.
- Use `MarkdownRenderSession` or `MarkdownRendererConfiguration.prepare(snapshot:)` in model/controller code and pass `MarkdownPreparedSnapshot` into `MarkdownDocumentView` or `StreamingMarkdownView`. Deprecated direct `snapshot:` view initializers are compatibility shims, not the streaming/document path.
- Renderer configuration must be protocol-driven for link, image, HTML, code, math, code highlighting, and math rendering hooks.
- Default code highlighting must stay language-aware, pluggable, and conservative: explicit supported languages may be highlighted; plaintext, nohighlight, unlabeled, and unsupported fences should render plainly.
- Document and code affordances must stay generic, source-backed, and replaceable. `MarkdownDocumentSurface` may own copy/export/collapse chrome, `MarkdownCodeBlockAffordances` may own code chrome visibility, and `MarkdownAffordanceActionHandler` may own platform actions; none of these APIs may hardcode private Sirius app concepts. Shared affordance icons are decorative SF Symbols; accessibility labels and help text belong on the enclosing buttons.
- Mermaid rendering must stay package-owned and prepared before SwiftUI body evaluation. `DefaultMarkdownMermaidRenderer` may produce ASCII plus concrete-color SVG and prepared root geometry; `MarkdownBlockView` may render the prepared image in a bounded pan/zoom viewport with controls from `MarkdownTheme.mermaidAffordances`. Mermaid zoom/fit/reset buttons must keep explicit accessibility labels while their decorative SF Symbol images stay hidden from accessibility synthesis. Do not add WebKit, app-private Mermaid wrappers, or a second Mermaid semantic engine.
- Heading typography must resolve H1-H6 through `MarkdownTheme.headings`. Visual SwiftUI `Font` and prepared-line CoreText measurement inputs (`fontSize`, `lineHeight`, `MarkdownInlineFontProfiles`) must come from the same `MarkdownTextStyle`; do not infer measurement profiles from arbitrary SwiftUI fonts.
- Inline math detection must remain source-preserving and must not rewrite code spans, fenced code, or Markdown source before `swift-markdown` parsing.
- Image handling must produce prepared decisions and placeholders by default; no network image fetch is allowed without an explicit host resolver.
- Selection/copy must stay block/range bounded and source-backed. Do not add per-fragment overlays for links, images, or selection.
- Native text selection must stay bounded to stable text leaves. Keep
  `MarkdownRendererConfiguration.nativeTextSelection` defaulted to `.disabled`
  for conservative package adoption. On macOS, `.enabled` must work by using
  package-owned selectable AppKit text leaves instead of SwiftUI's private
  `SelectionOverlay`; on other Apple platforms, the SwiftUI selection helper
  remains bounded. Selection must avoid document, scroll, stack, custom
  leading-layout containers, table-grid containers, toolbar, Mermaid-control,
  and host containers, while list, quote, and table cell text leaves stay
  selectable. The product gate's enabled-selection AppKit probe must keep
  passing and must observe selectable AppKit text leaves before a host opts in.
  SwiftUI tests must prove list/quote/table leaves mount selectable
  `NSTextView`s and that a hosted list leaf can select and copy through the
  AppKit pasteboard path.
  If a Sirius-style hang returns, sample the process and check for
  `GraphHost.flushTransactions` ->
  `SelectionOverlay.updateNSView` -> AppKit `NSTextField setFont:` /
  `_invalidateEffectiveFont` / `updateCell`.
- Lists, task lists, tables, code blocks, math blocks, and HTML blocks must keep structured render paths. Do not collapse them back to `Text(block.text)` except as an explicit policy-denied or missing-structure fallback.
- Renderer tests must assert behavior through render plans, prepared snapshots, inline payload helpers, diagnostics counters, and large-transcript prepared item identity. `Tools/RenderProbe` owns the `MarkdownDocumentView` AppKit pixel check so Swift Testing helper crashes do not excuse dropping document-render coverage.
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

The script first runs `Tools/RenderProbe`, which renders representative document, document-affordance, compact-chat, transcript-wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, wide-to-narrow resize, Mermaid diagram pan/zoom, and code-highlighting cases through AppKit and rejects blank/trivial/collapsed/clipped/misleading output. It then runs Swift tests, including AppKit-hosted transcript command clipping regressions, test count, root build, macOS demo app bundling (`Examples/scripts/bundle-macos-demos.sh`), Pretext install/test, symbol graph generation, and warning-clean DocC conversion. Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
If this script fails, treat it as a real release blocker. Do not bypass the Pretext fixture comparison or the AppKit render probe to make a release check look green.

## Product Checks

```sh
bash Tools/product-check.sh
```

Run this before claiming native-renderer product quality. It wraps the release gate and adds focused checks for `MarkdownRenderSession`, bounded selection, long-transcript resize behavior, and render-probe output. The gate proves SiriusMarkdown behavior directly; it has no competitor dependency.

## Public Release Checklist

Use this checklist for `0.4.14`.

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
   git commit -m "Prepare SiriusMarkdown 0.4.14 release"
   ```

6. Tag and push:

   ```sh
   git tag -a 0.4.14 -m "SiriusMarkdown 0.4.14"
   git push origin HEAD
   git push origin 0.4.14
   ```

7. After pushing, create the public release notes from `changelog.md`. The release notes must keep the claim precise: native SwiftUI block rendering, prepared-line inline rendering, streaming snapshots, safe policies, language-aware default code highlighting, package-owned Mermaid pan/zoom over prepared SVG/ASCII, explicit accessibility labels for package-owned affordance controls, Pretext-backed layout gate, and demo/product probes. Do not claim a custom glyph renderer, a new Mermaid semantic engine, or a WebKit renderer.

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
- Explicit `MarkdownRendererConfiguration(inlineRenderingMode: .systemText)` only as a compatibility fallback.

The consumer handoff is not part of the package release tag. It is a downstream integration check that should verify the app does not parse, highlight, or prepare raw Markdown from SwiftUI `body`.
