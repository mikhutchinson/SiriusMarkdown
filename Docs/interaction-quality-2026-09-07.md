# Selection, links, and math quality pass

This follow-up preserves the earlier bug-hunt changes and intentionally changes
macOS configuration defaults from native per-leaf selection to document selection.
Explicit `nativeTextSelection: .enabled` remains supported.

## Changes

- One document-scoped AppKit event bridge supports cross-block dragging,
  double-click word and triple-click paragraph selection, Shift-click extension,
  arrow/Shift/Option/Command navigation, Escape, Cmd-A, Cmd-C, and drag
  autoscrolling. Returning to the drag origin updates the caret, Option-arrows
  use directional word boundaries, document replacement invalidates stale
  carets, and Escape cancels active drag/autoscroll state. A consumed drag also consumes its release so a link cannot open
  when the pointer returns to the starting position. Paragraph selection uses
  the prepared leaf's source range, not the enclosing list/table's range.
- Native Open Link and Copy Link Address menus cover Markdown/HTML links in
  painted, system-text, prepared-native, and math-containing paragraphs. They
  retain the host's link action and the prepared policy-approved destination.
- Math is rasterized from vector display lists directly at the requested scale.
  TextKit tinting now applies the pixel-to-point transform; previously a formula
  could occupy only a fraction of its correctly reserved attachment box.
- Prepared native line source maps account for inserted newlines, trimmed
  whitespace, Unicode, and decoration attachments. Disabled document selection
  no longer mounts unnecessary native-leaf selection geometry readers.

## Evidence

- Regression discovery: 1008 tests; all 392 required named release regressions
  resolve in current discovery. The discovery floor and standing count documents
  are synchronized.
- Focused selection performance and link/math checks: 24 tests passed.
- New selection and high-resolution tint checks: 5 tests passed, including three
  raster scales and a mounted native event bridge.
- Pretext goldens passed. Math corpus passed: 50 cases, 48 native-image cases,
  42 KaTeX/MathJax parity cases, eight intentional diagnostic/extension skips.
- Full serial `swift test --no-parallel`: **1004 tests in 28 suites passed**
  in 278.219 seconds before the final four interaction edge regressions. All seven streaming-scaling tests passed, including rapid
  publications and the live 120-row table (no skipped tests). Log:
  `/tmp/siriusmarkdown-complete-validation.log`.
- After the four final interaction fixes, 27 focused interaction, selection
  performance, link-menu, and discovery-document checks passed in 23.299 seconds.
  Log: `/tmp/siriusmarkdown-final-edge-validation.log`. The complete suite was
  not repeated after those narrowly scoped changes.
- Independent AppKit tint probe: the 73 by 66 pixel source at 2.5x contained
  934 covered pixels. The old tint output occupied only x=0...29, y=39...65
  with 426 covered pixels; corrected tint restores the original full bounds
  and 934 covered pixels. Probe: `/tmp/sirius-math-tint-probe.swift`.

- Refreshed AppKit RenderProbe passed all surfaces. The native selection stress
  artifact contains 13 selectable leaves and four math attachments; visual
  inspection confirms the formula now fills its intended box and baseline.
  Image: `/tmp/siriusmarkdown-quality-selection-final.png`; log:
  `/tmp/siriusmarkdown-quality-renderprobe-final.log`.

## Scope and review

No release, commit, or push is included. Existing unrelated vendor deletions are
preserved. Pixel evidence verifies the rendering pipeline; this is not a claim
of testing on the user's physical 4K display or comparative best-in-class parity.
The complete release/product scripts, including consumer, all demos, DocC, and
symbol-graph gates, have not been rerun as a single release certification.

Native interaction choices were checked against Apple's
[macOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos),
[accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility),
and [context-menu guidance](https://developer.apple.com/design/human-interface-guidelines/context-menus).
