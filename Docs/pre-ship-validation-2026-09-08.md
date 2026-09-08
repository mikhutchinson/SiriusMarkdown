# Pre-ship validation, September 8

The September 7 review is a historical defect inventory. This audit records
current implementation and evidence; it does not claim universal browser parity
or zero remaining bugs. The published baseline remains 0.6.26, verified against
the GitHub release during this pass. No commit, push or publication occurred.

| Requirement | Current implementation | Evidence |
| --- | --- | --- |
| RTL and wrapped selection | Shaped visual caret movement, line affinity, leaf-wide word navigation and native document event bridge | `MarkdownDocumentSelectionInteractionTests`: RTL/mixed bidi emoji, wrapped commands, emergency word wraps, mounted drag/autoscroll and native menu actions |
| Semantic accessibility | Native actionable links, heading traits, table row/column/header/span relationships, bounded math expression children | Mounted semantic link/table/math accessibility suites, including replacement/pruning and link press actions |
| Find and anchors | On-demand prepared index, visible-text search, Unicode headings, explicit sanitized IDs, package and host-scrolled reveal | Find/navigation/explicit-anchor suites; mounted horizontal code/table reveal and vertical host scrolling; Find artifacts |
| Rich clipboard | Semantic HTML and native RTF alongside exact Markdown/plain representations | RichCopy and Pasteboard suites, including formatting/link round-trip and denied content |
| Print/PDF | Native pagination, selectable text/cells, nested/spanning tables, repeated ordinary headers, prepared image/math drawing, annotation geometry | Exporter tests, real native formula PDF, current table/span/formula artifacts; page-range and final-content assertions |
| Optional async images | Explicit image policy plus replaceable async resolver, bounded anonymous public-HTTPS loader, coalescing/cancellation, host viewport IDs, owner-only refresh | RemoteImageLoader and AsyncImage suites; mounted completion pixels and Retina artifact; defaults initiate no image loads |
| Large-document latency | Stable view IDs, prepared/configuration revision boundaries, cached table row subtrees and width inference reuse | Same mounted 178,960-byte debug fixture: 1156.78 ms in the prior full run, 753.21 ms in the clean gate; explicit layout 5.37 ms |
| Native streaming architecture | Semantic conversion remains in Core; preparation and resource completion occur before view evaluation; width changes reuse prepared metrics | Complete Core/streaming/layout/Pretext tests, mounted resize identities and diagnostics; source changes preserve existing native ownership |
| Release/product gates | `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1 bash Tools/product-check.sh` | Passed with exit 0, including the complete release gate and final visual probes |

## Evidence and scope

The clean Swift suite passed all 1074 tests in 41 suites in 140.863 seconds.
The gate log is `/tmp/siriusmarkdown-product-gate.log`. Focused PDF/clipboard
checks and the quoted-dollar-math regression also passed before the clean run.

Visual inspection included the current contiguous table grid, nested spans,
real inline/display/quoted/table formulas, async images, native document render
and native selection stress artifacts. Tests additionally compare a PDF link's
rectangle to the PDF text's glyph bounds, not merely to page margins.

PDF export reports fallback limitations for a rowspan-connected group too tall
for a page, unreadable/unsupported resources, unrendered math and diagrams. A
header joined to body rows by rowspan is not independently repeated. These
constraints are explicit; the export is not an arbitrary CSS print engine.

Mounted interaction/accessibility evidence is macOS evidence. UIKit keeps its
native implementation and requires device validation before claiming equivalent
hardware behavior. No hands-on VoiceOver certification or comparative WebKit
benchmark is claimed. Viewport IDs for optional image loading are host-supplied.
Default policies still prevent implicit image network requests.

The original twelve vendor dependency-file deletions remain untouched. The
Pretext tool now declares its required linebreak runtime dependencies so fresh
`npm ci` no longer relies on leftover installed packages. No subagents were used
in this pass; all existing agents are stopped.

## Gate completion

The authoritative product command completed with exit 0 and printed
`SiriusMarkdown product check passed.` The nested release gate completed the
clean 1074-test run, discovery and required regressions, local consumer build,
all three bundled release demos, math corpus, Pretext goldens, symbol graphs and
DocC. Subsequent focused runs passed 2 render-session tests, 39 selection tests,
and 31 product tests. Both visual-probe passes completed successfully.

The final product artifact was visually inspected. The release demo was also
opened by its exact task-built app path and its native accessibility hierarchy
inspected; this is not a hands-on VoiceOver certification. `git diff --check`
passed. The scoped implementation and validation goal is complete with the
limits above; publication remains a separate, unauthorized action.
