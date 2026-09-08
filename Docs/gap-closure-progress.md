# Gap closure goal

Active goal: close the gaps in pre-ship-review-2026-09-07.md and validate before release.

## Work management

At most three sub-agents. Each has a bounded non-overlapping assignment, no nested
agents, no builds, and concise completion reports. Parent owns serial validation,
integration, evidence, and release gates. Finished assignments stop before another
is dispatched. No publication is authorized.

## First wave

- Selection agent: wrapped-line affinity and leaf-wide word boundaries.
- Clipboard agent: semantic HTML/RTF payload plus UIKit representation support.
- Document agent: prepared Find and heading-anchor index/controller.
- Parent: stable native view identity/performance, integration and accessibility.

## Performance experiment

Replacing generation-based SwiftUI view identity with stable item IDs while
retaining content-based region measurement revisions reduced local debug stress
late table update median from 796.09 ms to 68.60 ms. Row body evaluations fell
from 2177 to 287. Large-document late updates fell from 1340.31 ms to 1131.82 ms.
These are same-fixture local observations, not release or WebKit benchmarks.

The first experiment exposed a counter assertion requiring all row comparisons
to succeed, which excluded genuine changed-row comparisons. The replacement
assertion tightens actual row body evaluations from below5000 to below1200 and
requires most comparisons to reuse. Full contract/stale-content checks pending.
Log: /tmp/siriusmarkdown-stable-identity-performance.log.

## Remaining work

RTL/bidi navigation; semantic accessibility and math expression structure;
Find/anchor UI integration including HTML IDs; rich clipboard integration;
pagination/print/PDF; optional policy-controlled async images; further large-
document profiling; focused and complete release/product gates and artifacts.

## Integration batch

Implemented and awaiting combined validation: visual RTL/wrap/whole-word
selection; prepared Find and heading anchors with document UI; semantic HTML/RTF
clipboard; native text pagination/PDF/print API; painted link actions, heading
traits, and bounded semantic math trees. Agents are idle while parent integrates.

Print currently reports fallbacks for tables as tab-separated text, images as
alternative text, and formulas/diagrams as source; this is not visual export
parity yet. Streaming views expose reusable Find APIs but still need built-in
host-scroller integration. Inline math accessibility and semantic table roles
remain integration work. HTML-ID anchors and optional async images remain open.

Selection snapshot updates now avoid no-op Published notifications when there
is no selection. A regression proves zero notifications and continued index
updates; timing verification pending in the combined batch.

## Validated integration evidence

- Combined run: 46 tests across eight suites; one mounted math AX failure was
  corrected with a native accessibility host and rechecked successfully.
- Broad run: 1037 tests (seven scaling tests excluded), with only three stale
  contract tests failing. Updated exact-source/semantic-label/rich-copy checks
  passed in a focused rerun. This is not yet a complete passing final suite.
- Latest measured table late update: 71.12 ms and 287 row body evaluations;
  large-document late update: 1140.57 ms. Large-document latency remains open.
- Inline math semantic accessibility compiles and the existing eight selected
  math/attachment checks pass. A new mounted tree/pruning regression is pending.
- Pretext and math-corpus JavaScript checks pass for this batch.

The next bounded batch adds disjoint bidi link hit geometry, semantic table AX,
and sanitized HTML-ID anchors. Parent additionally fixes same-generation
replacement selection invalidation and captures Find/PDF artifacts. All builds
remain serial and agent-owned builds are prohibited.

## Second wave result

All agents are stopped. The combined focused run passed 31 tests in 4.302 s:
HTML-ID preservation/navigation, disjoint bidi links, mounted native table AX,
inline/block math AX, same-generation document reset selection, Find and text
pagination. Log: /tmp/siriusmarkdown-gap-wave-two.log. The compiler required an
explicit main-thread bridge for synchronous Objective-C AX overrides; those
callbacks now assert the actor boundary before accessing native UI state.

Discovery is 1058 tests; the gate floor, named regressions and docs are synced.
The follow-up Find/document consistency run passed 16 tests in 2.593 s. Light
Find capture and PDF page were visually inspected. The initial mixed-appearance
offscreen Find capture was unsuitable evidence; an explicit matching AppKit and
SwiftUI appearance produces legible native controls.

Remaining: optional policy-controlled async image lifecycle; host-scrolled
Find/reveal integration; visual PDF fidelity for tables/images/formulas;
large-document latency; complete final release/product gates and fresh renderer
artifacts. Custom table styles/UIKit retain their existing accessibility path.
No claim of complete WebKit parity or shipping readiness is made.

Explicit light and dark Find captures are now both visually inspected and
legible; the mounted Find regression passes after each appearance transition.
Artifacts: /tmp/siriusmarkdown-gap-find.png,
/tmp/siriusmarkdown-gap-find.png.dark.png, /tmp/siriusmarkdown-gap-print.pdf.


## Host-scrolled Find

The previous goal turn made verified progress (source changes, mounted tests and
visual artifacts). This pass used no sub-agents. StreamingMarkdownView now opts
into shared package navigation with documentFindController. A single active
native marker reveals through the existing ancestor scrollers; no nested scroll
view is added. The mounted regression verifies first/last matches, heading
navigation, one marker, one scroller, and operation with document selection
disabled. Navigation plus document consistency: 19 tests passed in 5.640 s.
Log: /tmp/siriusmarkdown-host-find-final.log. Discovery floor is 1059.

UIKit has an equivalent native reveal implementation, but device validation is
still outstanding. The native Find bar remains within transcript content;
custom toolbar placement is available through the reusable bar/controller.

Remaining Find edge: the document-level reveal marker reaches the host scroller,
but horizontal results inside independently scrolling code/table blocks require
leaf-level reveal routing. Do not infer that coverage from the vertical test.

Host-Find root integration scaling check passed both stress tests (72.405 s).
Large-document late update median: 1175.25 ms; table late update: 73.48 ms,
287 row bodies. These remain close to the previous measurements; no additional
speedup is claimed. Log: /tmp/siriusmarkdown-host-find-scaling.log.


## Horizontal Find and code metrics

This turn made source and verification progress without sub-agents. Active
code/table matches now mount an inner reveal marker using existing selection
geometry. Reveals visit the enclosing scroll views. Lookup skips line fragments
that share the source range but contain no visible part of the match.

The mounted code regression exposed a real font mismatch: SwiftUI semantic body
code rendered narrower than the explicit prepared metrics. Prepared non-wrapping
code now uses the native text path, aligning display, selection and reveal.
The regression proves horizontal reveal of a distant code token, return to the
left for a second-line match, and reveal of the last column in a wide table.
52 navigation/native-selection/interaction tests passed in 12.415 s.
Log: /tmp/siriusmarkdown-overflow-find-final.log. Discovery floor: 1060.

The overflow Find screenshot was visually inspected: the final table column and
its highlighted match are visible, with code overflow contained above it.
Artifact: /tmp/siriusmarkdown-overflow-find.png. The 15 document consistency
checks pass. The latest code-native change still needs the final scaling/release
pass; do not reuse the prior SwiftUI-code timing as current proof.

## Optional asynchronous images

One narrowly scoped Core agent implemented the shared safe transport and bounded
remote loader; the parent implemented session scheduling, owner-only refresh,
viewport gating and cancellation. All agents are stopped. No agent ran builds.

The focused image/favicon/metadata pass passed 34 tests in 2.239 s
(/tmp/siriusmarkdown-async-images-viewport.log). Session-release cancellation
and document consistency then passed with the image suites: 21 tests in 0.986 s
(/tmp/siriusmarkdown-async-images-final.log). Discovery is 1066 tests.
Completion is tested with a resolver that caches nothing, including Markdown
and HTML owners, unchanged parse counts and stable block identities.

Viewport IDs are host supplied. A mounted async-image visual check and the full
current release/product gate remain outstanding. Visual PDF fidelity and
large-document latency remain open; these image tests do not close those gaps.

## Full suite and mounted image evidence (September 8)

The full serial suite passed all 1066 tests in 40 suites, 153.014 s, with no
compiler warnings or test failures: /tmp/siriusmarkdown-full-1066.log. Current
large-document late total is 1156.78 ms (pipeline/graph 1151.37 ms, explicit
layout 5.56 ms). Streaming table late total is 71.85 ms with 287 row bodies.
This includes the latest native non-wrapping code path. Large-document latency
remains open. The full release/product scripts have not yet been completed.

After that run, the existing async completion regression gained a mounted
observable session host and a pixel assertion. The initial test fixture used
named colors unsupported by its bitmap color space; explicit device-RGB colors
fixed that fixture. No production code changed after the full suite. The image
and documentation suites passed again: 21 tests in 2.435 s, no warnings,
/tmp/siriusmarkdown-async-image-mounted.log. Visually inspected the 1280x600
Retina-scale artifact /tmp/siriusmarkdown-async-image.png: both Markdown and
HTML image owners display the completed two-color image. No network was used
by this mounted fixture. End-to-end live public-network image validation and
UIKit device validation are not claimed.

All subagents remain stopped. Goal remains active: visual PDF fidelity, large
document latency and final release/product validation still need work.

## Prepared block publication boundary

The previous turn was progress: complete serial suite plus mounted async-image
evidence. This turn used one narrowly scoped exporter agent and parent-owned
profiling/integration. The five-second sample of the unchanged fixture shows
SwiftUI graph work dominating the main thread, including unchanged block and
selection subtree evaluation. Profile: /tmp/siriusmarkdown-latency.sample.txt.

An explicit streaming block equality boundary now compares source model,
prepared-value revision, configuration revision, and selection-controller
identity. Copies preserve revisions; all public prepared/configuration field
mutations invalidate them. The mounted regression verifies body reuse and
invalidations, including nested writeback and callback replacement.

Three focused tests passed in 41.963 s. The same 178960-byte fixture improved
1154.28 -> 729.83 ms (about 37 percent), with no native surface remount on width
change and correct narrow wrapping. Interaction follow-up: 28 tests passed in
9.499 s. Exporter work is still in progress and was not covered by those tests.

The Pretext oracle imports unicode-trie/base64-js from its vendored linebreak
module. These dependencies were absent from the root test-tool manifest, so a
clean install could lose the manually installed copies. They are now declared
and locked at the vendored module's versions. A fresh npm ci followed by all
Pretext goldens passed. The existing twelve vendor-file deletions remain intact.

## Visual PDF preparation and current renderer probe

The exporter now substitutes prepared visual runs while preserving public
semantic page ranges. Supported top-level table rows draw native cell text,
header fills, borders and PDF link annotations. Prepared inline images/math
work through recursive list/quote/HTML leaves. Authored image matching excludes
decorative icons and preserves missing-resource slots. Inline formulas retain
scaled ascent/descent and print-font sizing rather than lifting their full
bitmap above the sentence baseline.

Pixel fixtures and a real native formula export caught and corrected bitmap
fixture color conversion and baseline issues. The focused export/real-math/doc
suites passed 25 tests in 1.101 s, no compiler warnings:
/tmp/siriusmarkdown-pdf-visual.log. Inspected formula PDF PNG and quoted image
PDF PNG at /tmp/siriusmarkdown-formula.pdf.png and
/tmp/siriusmarkdown-print-visual-quoted.png. Formula baseline and authored red
image are visibly correct; ordinary PDF text remains selectable in tests.

The current RenderProbe rebuilt and exited successfully:
/tmp/siriusmarkdown-boundary-render.log. Visually inspected
/tmp/siriusmarkdown-boundary-render.png and
/tmp/siriusmarkdown-boundary-selection.png. Native selection stress reports
13 selectable AppKit text leaves and 4 inline math attachments.

Unfinished PDF fidelity: nested/spanning/multiline/oversize tables, repeated
headers, table-cell visual assets, non-data images and nested display math
without inline math flags. These remain explicit fallbacks. The full current
1071-test suite is running; final release/product scripts remain outstanding.
No new subagents were spawned; the one reused exporter agent is now stopped.

The table PDF artifact /tmp/siriusmarkdown-print-visual-table.png was also
inspected. Its cell text/borders/header fill render, but CoreText's inter-row
line descent leaves a visible gap between the row rectangles. Close that row
spacing gap with the remaining table export work; pixel presence alone is not
a claim of polished table fidelity.

The full current serial suite completed: 1071 tests in 41 suites passed in
136.211 s, no compiler warnings or failures. Log:
/tmp/siriusmarkdown-full-1071.log. Late large-document median is 773.60 ms
(pipeline/graph 768.70 ms, explicit layout 5.76 ms), about 33 percent lower
than the previous full-suite 1156.78 ms. The isolated before/after fixture
showed about 37 percent; use the full-suite value when reporting this run.

No processes or agents remain active from this pass. No commit/push/release.
Goal remains active. Next coherent work: complete table/PDF fidelity (including
inter-row spacing observed in the artifact) and then run final release/product
scripts. Source edits during this pass were validated by the full current suite.

## Structured PDF tables and quoted display math (September 8)

Previous turn classified as progress: full 1071-test suite and real visual
artifacts. This pass used no subagents. The semantic rich-copy pass now carries
internal table-cell locations, retaining empty cells and nested/multiline
structure without delimiter reconstruction. PDF layout consumes those locations
for native spans, cell assets, contiguous borders and repeating ordinary
headers. It preserves selectable text and original semantic page ranges.

Visual verification exposed and fixed two errors beyond the original spacing
issue: CoreText line origins are relative to frame paths, so nested graphic and
link-annotation placement must include the path origin; and standalone dollar
math inside an AST block quote retained later-line quote markers. That parser
path now strips exactly the AST-owned quote depth, preserving comparison signs
and the original source ranges. CR/LF/CRLF regressions pass.

Nineteen export/clipboard/real-formula tests passed in 1.107 s; eleven targeted
quoted-math/CR tests passed in 0.159 s. Logs:
/tmp/siriusmarkdown-structured-pdf.log and
/tmp/siriusmarkdown-quoted-math-fix.log. Refreshed artifacts inspected:
/tmp/siriusmarkdown-structured-print-table.png,
/tmp/siriusmarkdown-structured-print-nested-spans.png, and
/tmp/siriusmarkdown-nested-formula.pdf.png. Table borders meet, math appears in
quoted content/table cells, and the formula contains no Markdown quote marks.

Discovery is 1074 tests; required named cases and public documentation are
synchronized. Tools/product-check.sh is running with visual probes enabled,
log /tmp/siriusmarkdown-product-gate.log. No source edits during that gate.
Explicit export constraints remain: groups joined by rowspan that exceed page
height use semantic text fallback; a spanning header joined to body rows is not
repeated independently; unresolved resources and diagrams retain source/alt
representations. These are reported by the export API, not hidden failures.

Final validation: the same visual-enabled product command completed with exit
0. Its nested release gate passed the clean 1074 tests, discovery, consumer,
three release demos, math corpus, Pretext goldens, symbol graphs and DocC.
Focused render-session/selection/product runs passed 2/39/31 tests and final
RenderProbe checks passed. The current mounted 178,960-byte debug fixture
measured 753.21 ms late total, with 5.37 ms explicit layout. Final artifacts
were inspected; the requirement matrix and explicit evidence limits are in
Docs/pre-ship-validation-2026-09-08.md. No commit, push or publication occurred.
