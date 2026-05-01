# Runbook

## Build

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

## Pretext Golden Tool

```sh
cd Tools/pretext-golden
npm ci
npm test
```

The Pretext tool is the JavaScript golden oracle for layout drift. It uses real `@chenglou/pretext` with `@napi-rs/canvas` providing a Node measurement context. Swift fixtures live in `Sources/SiriusMarkdownPretextSupport/Fixtures`; JS fixtures live in `Tools/pretext-golden/fixtures`.

## Release Checks

```sh
swift test
swift test list | wc -l
npm --prefix Tools/pretext-golden ci
npm --prefix Tools/pretext-golden test
```

Before cutting a release, update `changelog.md` and confirm `bugfix.md` records any defects found during the slice.
