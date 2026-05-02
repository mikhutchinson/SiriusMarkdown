# Runbook

## Build

Before changing architecture or renderer behavior, read `plan.md` and `AGENTS.md`. `plan.md` is the implementation source of truth; `AGENTS.md` restates the repo-local guardrails for future agents.

```sh
swift build
```

## Test

```sh
swift test
```

Current status: `swift test` must pass with strict Swift-vs-Pretext comparison enabled. The former `emoji-cjk`, `multilingual`, and `rtl` drift in `bundledPretextFixturesCompareAgainstSwiftLayout` is fixed; do not reintroduce known-drift allowlists or call construction-only smoke tests renderer coverage.

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
- Inline math detection must remain source-preserving and must not rewrite code spans, fenced code, or Markdown source before `swift-markdown` parsing.
- Image handling must produce prepared decisions and placeholders by default; no network image fetch is allowed without an explicit host resolver.
- Selection/copy must stay block/range bounded and source-backed. Do not add per-fragment overlays for links, images, or selection.
- Lists, task lists, tables, code blocks, math blocks, and HTML blocks must keep structured render paths. Do not collapse them back to `Text(block.text)` except as an explicit policy-denied or missing-structure fallback.
- Renderer tests must assert behavior through render plans, prepared snapshots, inline payload helpers, diagnostics counters, and large-transcript prepared item identity. `Tools/RenderProbe` owns the `MarkdownDocumentView` AppKit pixel check so Swift Testing helper crashes do not excuse dropping document-render coverage.
- Repeated preparation of the same snapshot should reuse inline/code/math caches and record cache hits without incrementing prepare, highlighting, or math-render counters.

## Pretext Golden Tool

```sh
cd Tools/pretext-golden
npm ci
npm test
```

The Pretext tool is the JavaScript golden oracle for layout drift. It uses real `@chenglou/pretext` with `@napi-rs/canvas` providing a Node measurement context. Swift fixtures live in `Sources/SiriusMarkdownPretextSupport/Fixtures`; JS fixtures live in `Tools/pretext-golden/fixtures`.
Run `npm ci` and `npm test` sequentially; running them in parallel can race while `node_modules` is being replaced.
The Swift fixture comparison must not whitelist known drift. A failing Pretext fixture is a release blocker until the native layout path or fixture contract is corrected.

## Release Checks

```sh
bash Tools/release-check.sh
```

The script first runs `Tools/RenderProbe`, which renders a representative `MarkdownDocumentView` through AppKit and rejects blank or trivial output. It then runs Swift tests, test count, root build, macOS demo app bundling (`Examples/scripts/bundle-macos-demos.sh`), Pretext install/test, symbol graph generation, and warning-clean DocC conversion. Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
If this script fails, treat it as a real release blocker. Do not bypass the Pretext fixture comparison or the AppKit render probe to make a release check look green.

## Product Checks

```sh
bash Tools/product-check.sh
```

Run this before claiming Textual-replacement quality. It wraps the release gate and adds focused checks for `MarkdownRenderSession`, bounded selection, long-transcript resize behavior, and render-probe output. Textual is the product bar, not a dependency of the gate.
