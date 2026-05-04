# Contributing

SiriusMarkdown accepts contributions that improve the package without weakening the documented architecture. Before opening a pull request, read `Docs/architecture.md` and `Docs/native-renderer-scorecard.md` so your change lands in the right module with the right contract.

## Architecture constraints

These are not guidelines. They are load-bearing design decisions.

- `swift-markdown` owns Markdown semantics. Do not replace it with string classifiers.
- Streaming keeps immutable sealed regions plus one mutable tail. Sealed regions must stay immutable and cacheable.
- SwiftUI `body` must not parse Markdown, run syntax highlighting, prepare inline layout, or rebuild the document model. If a change moves expensive work into view evaluation, it will be rejected.
- Stable block identity comes from `MarkdownBlockID`, not array offsets.
- Source storage is append-only UTF-8 chunks with slice references. Avoid O(n²) append or scan behavior.
- Inline layout follows the prepare/layout split: measure once during preparation, then compute line ranges cheaply on width changes.
- Default policies must be safe for a public package: no remote image fetch, no arbitrary URL schemes, no raw HTML rendering by default.
- Public APIs stay general-purpose. Do not introduce private app concepts, hardcoded routes, or host-specific affordances.

## Where changes belong

| Change | Module |
| --- | --- |
| Source buffer, streaming, parsing, render model, policies, caches, diagnostics, inline layout | `SiriusMarkdownCore` |
| SwiftUI views, themes, interaction, platform hooks, render sessions, prepared snapshots | `SiriusMarkdownSwiftUI` |
| Pretext fixture schema, golden comparison helpers | `SiriusMarkdownPretextSupport` |
| Optional math renderer | `SiriusMarkdownMath` |

Core must produce `Sendable` value models. SwiftUI consumes them. Do not move rendering concerns into Core or parsing concerns into SwiftUI.

## Before you open a PR

1. Run the full product gate from the repository root:

   ```sh
   bash Tools/product-check.sh
   ```

   This wraps `swift test`, `Tools/RenderProbe`, Pretext golden fixture comparison, DocC conversion, and demo app bundling. A failing gate is a blocking issue.

2. Run the Pretext golden tool if your change touches inline layout, measurement, or fixture data:

   ```sh
   cd Tools/pretext-golden
   npm ci
   npm test
   ```

   Do not whitelist known drift. Fix the layout path or the fixture contract.

3. Confirm no whitespace errors:

   ```sh
   git diff --check
   ```

## Writing tests

Tests must prove contracts, not just construct objects.

- Parser changes: whole-document parse must equal streamed parse across chunk sizes. Block IDs must survive tail-to-sealed transitions.
- Inline layout changes: prepared content must be reused across width changes. Width changes must not call the measurer again.
- Renderer changes: assert through prepared snapshots, diagnostics counters, and inline payload helpers. `Tools/RenderProbe` owns the AppKit pixel check for `MarkdownDocumentView`.
- Cache changes: repeated preparation of the same snapshot must hit caches and record diagnostics without incrementing work counters.
- New Pretext fixtures must include required group metadata and must not duplicate existing fixture names or groups.

A test that only constructs a SwiftUI view is not a renderer test.

## Code style

- Swift 6.0, strict concurrency.
- Type hints throughout; no untyped `Any` or `object` unless required by platform interop.
- Use `logging` patterns from `MarkdownDiagnosticsRecorder`, not `print()`.
- No hardcoded values — use configuration, theme tokens, or policy protocols.
- Follow the existing file and module layout. If you are unsure where something belongs, check `Docs/architecture.md`.

## Commit discipline

- Each commit should be self-contained. No partial implementations that leave the product gate failing.
- Update `changelog.md` with a precise description of what changed and why.
- Record defects in `bugfix.md` if the change fixes a regression or architectural violation.
- Keep `NOTICE.md` current if you add or update a vendored dependency.

## Licensing

Contributions are made under the MIT License (`LICENSE`). By submitting a pull request, you agree that your contribution is licensed under those terms.

Third-party dependencies must be credited in `NOTICE.md` with their license type and the path to the bundled license file. Do not vendor a dependency without recording it.
