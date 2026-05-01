# Changelog

## Unreleased

- Created the SiriusMarkdown package scaffold as a public MIT Swift package.
- Added the verbatim renderer plan at `plan.md` for implementation tracking.
- Added initial core source-buffer, streaming, parser, model, policy, cache, diagnostics, inline-layout, SwiftUI-renderer, and Pretext-support surfaces.
- Added a working Pretext golden smoke harness backed by `@chenglou/pretext` and a Node canvas shim.
- Expanded Swift coverage to 108 runner-counted tests plus parameterized edge cases for streaming equivalence, stable block IDs, source byte/line maps, conservative boundary scanning, block and inline classification, structured AST conversion, policy handling, cache eviction, diagnostics, and deterministic inline layout.
- Fixed stable block identity so active-tail block IDs survive sealing.
- Fixed conservative boundary scanning so a single trailing newline does not seal a block or split multi-line blockquotes during streaming.
- Reworked parsing so `swift-markdown` owns Markdown semantics and the package converts the AST into the public render model.
- Added structured render-model data for task/list items, nested list items, ordered-list starts, table cells, table column alignments, and deterministic block content hashes.
- Switched source slices to segment-backed storage and made the boundary scanner iterate source lines without copying the full tail.
- Tightened default link/image policy and added a renderer configuration surface for policy and link handling.
- Made CI's Pretext golden step clean-checkout safe with `npm ci`.
