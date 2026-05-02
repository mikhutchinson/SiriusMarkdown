# Prepared Inline Rendering Post-Mortem

## Summary

The prompt was:

```text
fix-> prepared inline layout exists and is tested, but actual text drawing still goes through SwiftUI `Text(AttributedString)`.
```

The concern was valid. SiriusMarkdown had a prepared inline layout pipeline, counters, layout caches, and tests proving width changes used cheap layout. But the visible inline text path still delegated final glyph drawing and wrapping to SwiftUI `Text(AttributedString)`.

The response was wrong. I treated that caveat as permission to replace the visible inline renderer immediately with a custom native drawing bridge. The result technically consumed `MeasuredInlineContent` and `InlineLayoutResult`, but it was visually unacceptable: word spacing collapsed, list rows looked broken, font matching was poor, and product demos regressed even while tests and the product gate still passed.

The failed custom drawing bridge was removed. The current product fix is narrower and safer: `MarkdownInlineRenderingMode.preparedNativeLines` consumes `InlineLayoutResult`, slices the prepared attributed inline payload into prepared lines, and renders each line with SwiftUI `Text(AttributedString)`. That keeps the prepare/layout contract visible in the renderer without pretending SiriusMarkdown owns final glyph drawing.

## What We Set Out To Fix

The real product gap was this:

- Prepared inline content existed.
- Prepared layout results existed.
- Resize tests proved layout counters moved without parse, prepare, highlight, or math-render counters.
- SwiftUI still performed the final text rendering through `Text(AttributedString)`.

That meant SiriusMarkdown could honestly claim a prepared layout pipeline, but not that prepared layout was the authoritative on-screen glyph placement engine.

The desired end state is still valid:

- SwiftUI should consume prepared inline models.
- Width changes should use cheap layout.
- Hit testing and selection metadata should come from prepared runs/layout records.
- Native text rendering should respect the prepared line model.
- Visual quality must remain at least as good as SwiftUI `Text`.

## What Went Wrong

### 1. I Confused "Prepared Layout Owns Wrapping" With "Draw Every Token Manually"

The failed implementation drew individual prepared segments at hand-computed x/y positions. That was the wrong abstraction.

Prepared segments are useful for measurement, line breaking, source mapping, link metadata, and selection. They are not automatically a good drawing unit. Drawing token by token breaks typography because text shaping, whitespace, kerning, ligatures, baselines, font fallback, and bidirectional text are line-level or run-level concerns.

The implementation should not have jumped from "SwiftUI still draws text" to "draw each measured segment manually."

### 2. The Renderer Broke Typography While Satisfying A Narrow Architectural Checklist

The replacement path consumed `MeasuredInlineContent` and `InlineLayoutResult`, but that was not enough. It produced visible regressions:

- Missing or weak spacing between words.
- Bad spacing around inline math and code.
- Poor relationship between task/list markers and text.
- Full-width inline views that made list rows feel disconnected.
- Font weight and size mismatches against the surrounding UI.

That is a product failure. Passing through the right model types does not matter if the output looks worse than the old path.

### 3. I Trusted A Non-Visual Product Gate For A Visual Change

`Tools/product-check.sh` passed while the demos looked bad.

That exposed a weakness in the gate:

- The AppKit render probe verifies nonblank/nontrivial rendering, not visual quality.
- Pixel bucket counts do not catch collapsed spacing or bad list alignment.
- Accessibility output can describe content correctly while the visible UI is wrong.
- Unit tests can prove line metadata and link hit testing without proving typography.

For renderer changes, "the gate passed" is not sufficient unless the gate includes targeted visual assertions for the affected UI.

### 4. I Did Not Stop After The First Visual Regression

The first visual pass showed broken spacing. Instead of reverting immediately, I tried to salvage the custom drawing path by moving from token drawing to line drawing. That improved paragraphs but still broke list layout and text/marker alignment.

That was a process failure. Once a renderer rewrite visibly degraded product surfaces, the correct move was to revert and document the gap, not continue iterating inside a live user flow.

### 5. I Mixed A Legitimate Copy Cleanup With A Risky Renderer Rewrite

The direct "Textual replacement" language cleanup was a separate, low-risk docs task. The native inline renderer change was high-risk code.

Bundling them in one dirty worktree made rollback too broad. Restoring to the good commit removed both the bad renderer changes and the good copy cleanup, which then had to be re-applied.

Those should have been separate commits or at least separate patches.

### 6. The Direct Snapshot Initializer Cleanup Was Pulled Into The Wrong Thread

Making direct `snapshot:` view initializers unavailable before 1.0 was directionally reasonable, but it was not the user's requested fix at that moment. It also expanded the change surface while the renderer was already risky.

The right order was:

1. Preserve visual quality.
2. Fix or document the prepared inline caveat.
3. Separately tighten public API affordances.

### 7. The New Test Proved Metadata, Not Product Rendering

The added test checked that a prepared render plan had multiple lines, preserved text, and could hit-test a link destination. That is useful, but it did not test:

- Visual spacing.
- Baseline alignment.
- List marker alignment.
- Font parity with existing themes.
- Paragraph/list/table integration.
- CJK, RTL, emoji, or mixed styled runs in the actual renderer.

It proved a data structure, not the user-facing renderer.

## Technical Root Causes

### Segment Measurement Is Not Enough For Drawing

`PreparedInlineSegment` records are intentionally compact and layout-oriented. They are not a complete text shaping model. Native drawing needs at least line-level attributed strings or CoreText lines built from prepared runs.

A viable future approach should draw each prepared line as a shaped native line, not as isolated tokens.

### Whitespace Is A Special Case In Both Measurement And Drawing

The failed path exposed how fragile whitespace handling is. CoreText typographic bounds can exclude trailing whitespace. But changing the core measurer to always include trailing whitespace broke Pretext golden comparisons because fixture natural widths drifted.

That showed the boundary:

- Layout metrics must stay aligned with the Pretext oracle.
- Drawing may need line-level text construction that preserves whitespace visually without changing layout metrics.

Changing the core measurement contract to make a renderer hack look better was the wrong layer.

### Theme Fonts Were Not A Drawing Contract

`MarkdownTheme` carries SwiftUI `Font` values and numeric font metrics. A custom AppKit/UIKit drawing path cannot faithfully reconstruct every SwiftUI font, weight, dynamic type behavior, or environment trait from that alone.

Before a native drawing bridge can be product quality, the package needs a real platform font resolution contract.

### List Rows Need Layout Integration, Not Just Inline Rendering

Replacing inline text with a platform view changed how list rows sized and aligned. The marker and text relationship is part of block layout, not only inline drawing.

A native inline renderer must be tested inside paragraphs, headings, task lists, nested lists, tables, and quotes before it can replace `Text`.

## Process Root Causes

### I Treated An Honest Caveat As A One-Turn Implementation Target

The caveat was not small. Moving from SwiftUI `Text` to authoritative native drawing is a renderer subsystem, not a patch.

The correct response should have been:

- Confirm the caveat.
- Split the fix into staged work.
- Land a non-visual render-plan/hit-test layer first if useful.
- Keep the visible text path unchanged until visual parity is proven.

### I Let Architecture Language Outrun Product Evidence

The architecture wants prepared inline layout to become authoritative. That does not justify replacing a visually correct path with an immature one.

For this project, architecture exists to prevent the known streaming and SwiftUI hot-path failures. It does not excuse bad UI.

### I Failed To Use The Demo As The Primary Acceptance Test

The user explicitly had me launch demos to make an honest assessment. A renderer change should have been judged first against those demos. The broken UI was visible immediately.

The demos are not decoration. For renderer work, they are product acceptance surfaces.

## What Was Correct Before The Failed Change

The pre-failure state had a real, defensible boundary:

- Expensive preparation was outside SwiftUI block bodies.
- Prepared inline content and layout results existed.
- Width changes could exercise cheap layout.
- SwiftUI `Text(AttributedString)` still handled final text shaping and typography.

That state was not the final architecture, but it was product-safer than the failed native drawing bridge.

The honest claim should remain:

> SiriusMarkdown has prepared inline layout and uses it for caching, diagnostics, width-change layout, and metadata. The default visible inline path still uses SwiftUI `Text(AttributedString)`. The opt-in `preparedNativeLines` path uses prepared layout to slice line text first, then also renders those lines with SwiftUI `Text(AttributedString)`. It is not a fully custom glyph renderer.

## Correct Remediation Plan

### Short Term

- Keep `Text(AttributedString)` as the visible inline renderer.
- Keep `preparedNativeLines` opt-in as prepared-line slicing rendered through SwiftUI text.
- Keep prepared inline layout as the source for counters, cached layout, source ranges, and future hit-testing.
- Do not claim native glyph placement ownership.
- Keep the caveat explicit in the scorecard, performance docs, and README.

### Medium Term

Build a native inline rendering prototype behind an internal feature flag:

- Construct attributed strings per prepared line.
- Let CoreText/AppKit/UIKit shape each line as a line, not token by token.
- Preserve prepared line breaks from `InlineLayoutResult`.
- Resolve platform fonts from `MarkdownTheme` through an explicit font bridge.
- Keep link hit regions and selection metadata bounded by prepared run metadata.
- Test the renderer inside real block contexts, especially task lists and tables.

### Required Visual Gates Before Enabling

Add screenshot or pixel-structure probes for:

- Paragraphs with normal spaces.
- Headings.
- Task lists with checked and unchecked markers.
- Nested lists.
- Inline strong/emphasis/code/link/math combinations.
- CJK, RTL, emoji, and mixed scripts.
- Tables with wrapped cells.
- Block quotes.
- Long streaming transcript rows.

The probe must catch collapsed words, broken marker alignment, clipped baselines, and obvious font mismatches. Nonblank pixel counts are not enough.

### Release Claim Rule

Do not say prepared inline layout owns on-screen glyph placement until:

- The native path is visually at parity with the current SwiftUI `Text` path.
- The renderer actually owns shaped glyph drawing instead of rendering prepared line slices through SwiftUI `Text`.
- The product gate includes visual checks that would have caught this regression.
- Demos are inspected after building the exact app bundles users will run.
- The old path remains available until the new path is proven under chat and document workloads.

## Non-Goals

This post-mortem does not argue for:

- WebKit.
- Row-hosted WebViews.
- Parsing or measuring in SwiftUI `body`.
- Unbounded per-fragment overlays.
- Abandoning the prepared inline architecture.

It argues that the visible native renderer must be earned with typography, layout integration, and visual gates, not asserted because the data model exists.
