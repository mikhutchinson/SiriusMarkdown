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
- SwiftUI `body` must not parse Markdown, syntax highlight, or run custom per-inline measurement/wrapping. `InlineRunsView` should consume inline runs as an attributed payload instead of installing a custom SwiftUI `Layout`.
- Renderer configuration must be protocol-driven for link, image, HTML, code, math, code highlighting, and math rendering hooks.
- Lists, task lists, tables, code blocks, math blocks, and HTML blocks must keep structured render paths. Do not collapse them back to `Text(block.text)` except as an explicit policy-denied or missing-structure fallback.
- Renderer tests must assert behavior through render plans and inline payload helpers, not only instantiate views.

## Pretext Golden Tool

```sh
cd Tools/pretext-golden
npm ci
npm test
```

The Pretext tool is the JavaScript golden oracle for layout drift. It uses real `@chenglou/pretext` with `@napi-rs/canvas` providing a Node measurement context. Swift fixtures live in `Sources/SiriusMarkdownPretextSupport/Fixtures`; JS fixtures live in `Tools/pretext-golden/fixtures`.
Run `npm ci` and `npm test` sequentially; running them in parallel can race while `node_modules` is being replaced.

## Release Checks

```sh
swift test
swift test list | wc -l
swift build
swift build --package-path Examples/MarkdownDemoApp
npm --prefix Tools/pretext-golden ci
npm --prefix Tools/pretext-golden test
swift package dump-symbol-graph
xcrun docc convert Docs/SiriusMarkdown.docc \
  --additional-symbol-graph-dir .build/arm64-apple-macosx/symbolgraph \
  --fallback-display-name SiriusMarkdown \
  --fallback-bundle-identifier com.sirius.markdown \
  --fallback-bundle-version 0.1.0 \
  --output-path /tmp/SiriusMarkdown.doccarchive
```

Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
