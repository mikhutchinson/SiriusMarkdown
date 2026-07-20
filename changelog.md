# Changelog

## Unreleased

## 0.6.19 - 2026-07-20

- Fixed prepared table text gaining additional wrapped lines after a shorter
  row height had already entered the cross-publication measurement cache.
  Table preparation now resolves a minimum header/body-row height from the
  final cell widths, theme padding, prepared line metrics, and atomic inline
  layout before SwiftUI measures the row. Stable history reuses those heights
  incrementally, while unprepared/custom-style rows stay on uncached natural
  measurement. Pixel coverage exercises painted, prepared-native, system-text,
  and AppKit-selection modes, and the exact user-bubble stress table is now a
  prepared-height regression and a manually inspectable demo case.

## 0.6.18 - 2026-07-19

- Corrected the default task-list square's prepared optical baseline by half a
  point so it remains centered on capital text on both 1x GitHub runners and
  2x Retina displays. The pixel regression now renders compact, document, and
  larger type across CoreText-painted, SwiftUI system-text, and native AppKit
  selection modes at both backing scales instead of inheriting the host
  display's scale.

## 0.6.17 - 2026-07-19

- Fixed ordered-list numerals sitting above their first text line by carrying
  each prepared renderer's real baseline through style erasure and aligning
  default marker/content rows on that baseline. CoreText and macOS TextKit now
  share explicit line-box and attachment ascent/descent geometry, and multiline
  table dividers stretch to the full row height. Default task squares use the
  paragraph font's cap-height center as their optical guide instead of a fixed
  top offset. Pixel regressions cover compact, document, and larger type metrics
  in painted, system-text, and native-selection modes. Marker and fallback-text
  typography guides are cached with renderer configuration/prepared inline
  content, keeping CoreText font construction out of list-row `body` evaluation.
- Fixed resolved favicon bitmaps hanging below the link text even though their
  generic fallback glyphs were centered. Decoration preparation now derives the
  bitmap ascent/descent from the configured fallback glyph's CoreText image
  bounds, and the AppKit selectable-text host reconstructs the true baseline
  from TextKit's box-bottom location plus the prepared descent. Pixel coverage
  checks prepared-native and CoreText-painted rendering with native selection
  both enabled and disabled; the demo's real SEC, Companies House, GitHub,
  Wikipedia, and OpenAI icons were also inspected in the bundled app.
- Fixed native AppKit selection flattening HTML subscript and superscript back
  onto the ordinary text baseline. Prepared script runs now restore their
  scaled TextKit font and signed baseline offset after AppKit attribute-scope
  conversion, while a precomputed flag keeps the common no-script text-leaf
  path free of attributed-run inspection.
- Fixed live GFM tables rebuilding every accumulated cell, rescanning all
  natural widths from `MarkdownBlockView.body`, and repeatedly remeasuring the
  full SwiftUI row stack while one tail cell grew. Prepared tables now retain
  source-stable row/cell IDs, reuse every completed row plus unchanged tail
  cells, update monotonic column maxima from only changed cells, and use
  bounded 64-point streaming width buckets before one exact sealed width pass.
- Added a bounded cross-publication table-row measurement cache owned by the
  existing render-preparation cache. In the 120-row AppKit host regression,
  240 visible partial-row publications required 586 fresh row measurements
  with 88,464 cache hits; late-stream main-thread settle measured 0.62 ms.
- Added partial-cell visibility, streamed-versus-static equivalence, alignment,
  link/source-selection, ragged-row, malformed delimiter, finish/reset, stable
  identity, 120x6, and 500x6 scaling regressions. Completed history is retained
  without gating visibility on row-ending newlines or weakening host cadence.
- Made the RenderProbe and clean-consumer release gates resolve the local
  package by explicit identity, so required checks also run from isolated
  worktrees whose directory names differ from `SiriusMarkdown`.
- Added standards-aware, sanitized native rendering for authorized inline and
  block HTML through SwiftSoup. Supported headings, paragraphs, quotes, lists,
  preformatted code, tables, inline emphasis/code/subscript/superscript,
  anchors, breaks, and policy-governed images now convert into SiriusMarkdown's
  source-mapped native models; scripts, embedded browsing/plugin content,
  active controls, and unsafe resource behavior are dropped or governed by the
  existing policies. Static and streamed conversion share the same path.
- Added package-owned decorated links for Markdown links and HTML anchors. An
  atomic globe glyph is available at first paint, while the default replaceable
  resolver asynchronously discovers declared HTTPS site icons, conventional
  favicon/touch-icon resources, and bounded square social artwork as a final
  declared fallback, validates native image bytes and dimensions, and
  republishes only affected prepared decorations. Hosts can disable decoration,
  disable remote metadata, or supply their own resolver.
- Hardened favicon discovery with anonymous ephemeral requests, stripped
  ambient credentials/cookies/referrers, navigation-scoped in-memory cookies
  issued only during the same anonymous redirect chain, per-hop policy and DNS
  checks,
  validation of the actual contacted socket endpoint, IANA special-purpose
  IPv4/IPv6 rejection (including mapped and NAT64 forms), bounded document/icon
  payloads, redirect and candidate limits, square-artwork qualification, native
  image validation, in-flight coalescing, LRU positive/negative caching, and
  generation-safe cache clears. Anonymous top-level navigation metadata,
  bounded public 4xx HTML declarations, and standard Apple touch-icon paths
  cover sites that do not expose a root favicon without weakening endpoint or
  payload validation.
- Preserved source-backed selection, plain copy, accessibility text, link hit
  regions, and semantic font runs by treating link decorations as measured but
  non-source, non-copying attachments within the link's single activation
  range. Rich-HTML child blocks publish precise selection geometry using the
  owning Markdown block identity.
- Wired the bundled Markdown demo through `MarkdownRenderSession` so its live
  SEC and Companies House examples visibly replace the first-paint globe with
  the resolved site icon. Fully decorated link leaves use the icon as their
  non-color cue and omit redundant label underlines; mixed leaves containing
  any undecorated destination retain conventional underlines.
- Added an exhaustive supported-element gallery and a safety/media boundary to
  the bundled demo. Together they show every documented native HTML element,
  allowed and denied image-policy outcomes, decorated anchors, sanitizer
  diagnostics, and inert script/style/embed/video/audio/canvas/SVG/control
  input without implying browser media execution.
- Added focused semantic, sanitization, source-entity mapping, streamed-versus-
  one-shot, resolver security/cache, decorated-link rendering, and scaling
  regressions, plus a reusable runtime favicon audit executable for large and
  curated public-domain corpora. The combined release gate now discovers `937` Swift
  tests.

## 0.6.16 - 2026-07-13

- Fixed a JavaScriptCore lifetime violation in the Highlight.js incremental
  bridge that could crash a host with `EXC_BAD_ACCESS` in
  `JSRopeString::resolveToBuffer` during a long streamed code fence. Function,
  argument, and result values are now protected before they cross another JSC
  allocation or enter Swift heap storage, and are unprotected only after the
  bridge finishes consuming them. The Mermaid bridge follows the same rule.
- Added deterministic Highlight.js and Mermaid regressions that force JSC
  garbage collection at every protected bridge boundary, including runtime
  initialization, function invocation, and result conversion.

## 0.6.15 - 2026-07-13

- Replaced the streaming SwiftUI surface's `LazyVStack` item-phase dependency
  with bounded stable regions. Sealed regions cache their size by proposal
  width and revision; only the region containing the mutable tail invalidates
  while a generation grows. Geometry publication is asynchronous and
  coalesced, avoiding synchronous whole-document fitting loops.
- Prevented active, unsealed inline/code/math/Mermaid values from occupying
  caches intended for stable prepared content. The active code tail now keeps
  one rolling highlighter state instead of retaining historical generations.
- Made plain and Highlight.js-backed code highlighting append-aware during an
  active stream. The pinned Highlight.js wrapper now forwards its real parser
  continuation, preserving lexical context across open comments and strings;
  full-context checkpoints run every 16 KiB and a full-document highlight is
  mandatory when the code block seals. The native Swift and arbitrary custom
  highlighters retain full-document semantics where no proven continuation is
  available.
- Added a bounded, thread-safe CoreText measurement cache shared by preparation
  values, keyed by the complete font/presentation profile and text. Unchanged
  tail tokens therefore reuse glyph widths across publications.
- Added diagnostics for highlighted byte volume plus AppKit-hosted regressions
  covering 90 rapid publications of a 179 KB document, persistent hosting-root
  replacement, bounded region invalidation, incremental highlighting, and
  cross-measurer CoreText reuse. Mutable-tail layout measured a 2.71 ms median.
- Preserved the complete rendering surface: Markdown semantics, tables,
  highlighting, math, Mermaid, links, attachments, copy, and native or
  source-backed selection are unchanged.

## 0.6.14 - 2026-07-13

- Kept `MarkdownRenderSession` preparation on the detached executor while
  making the MainActor handoff compile under the older Swift 6 strict-
  concurrency checker used by the macOS 15 GitHub runner. The detached task
  now strongly captures the globally isolated session for one bounded drain
  and calls explicit MainActor batch/publication methods, instead of sending a
  task-isolated weak reference into nested `MainActor.run` closures. The task
  clears its stored handle before returning, breaking the temporary retain
  cycle deterministically.

## 0.6.13 - 2026-07-13

- Fixed AST source-range conversion rescanning the mutable-tail source from
  byte zero for every block, table cell, and inline `SourceLocation`. Large
  streamed tables therefore paid quadratic conversion cost even though
  `swift-markdown` parsing and sealed-region reuse were working correctly.
  Each parse boundary now builds one UTF-8 line-start index shared by the
  block and inline converters.
- Fixed `MarkdownRenderSession` creating its pipeline pump with an inherited
  `Task`. Because the session is MainActor-isolated, expensive parse,
  highlighting, and preparation work could inherit the caller's actor/task
  context. The pump now starts detached on the user-initiated global executor;
  only pending-operation drain and prepared-value publication use MainActor.
- Added a mutable-tail table scaling regression: 120 rows parse in 25.63 ms
  and 960 rows in 205.62 ms (8.02x for 8x data). A controlled replay of the
  pre-fix converter did not complete the same test after 30 seconds. Added a
  task-local/highlighter regression that fails under inherited `Task` and
  proves preparation runs outside the caller context and main thread.

## 0.6.12 - 2026-07-13

- Fixed source-backed document selection and prepared inline layout cache hits
  rescanning the full prepared text, inline runs, measured units, and line
  ranges from SwiftUI layout evaluation. Long generated code blocks could
  therefore hold a host app's main thread at 100% CPU even though every cache
  lookup ultimately hit.
- Added deterministic two-lane content fingerprints that are computed when
  prepared, measured, and laid-out values are created or mutated. Layout,
  view-identity, and selection cache keys now combine a constant number of
  machine words while retaining source metadata, measurement-profile, font,
  width, and geometry invalidation boundaries.
- Added direct and AppKit-hosted 1,300-line selection performance regressions.
  On the release build, 40 repeated layout/selection cache hits fell from a
  353.9 ms pre-fix baseline to 0.214 ms, and hosted post-warm invalidations
  measured a 0.418 ms median against a 16 ms release budget.

## 0.6.11 - 2026-07-12

- Fixed the macOS AppKit selectable text leaves rebuilding their full
  attributed source, re-enumerating attributes, and re-applying attachments on
  every SwiftUI layout proposal. Under long nested list/quote documents,
  SwiftUI's repeated size negotiation compounded that into multi-second
  main-thread stalls in host apps. `configure` now short-circuits behind an
  equatable content/environment key, and measured sizes are cached per
  proposed width until the key changes.
- AppKit selectable leaves no longer add or remove attachment host subviews
  during SwiftUI size negotiation. `sizeThatFits` can run inside the window's
  `updateConstraints` traversal, where view-hierarchy mutation re-enters
  `_postWindowNeedsUpdateConstraints` and AppKit converts its guard exception
  into a deliberate crash. Host reconciliation now happens only in `layout()`.
- Added a hosted streaming scaling gate proving per-append main-thread cost
  stays bounded as a document grows in the Core Text painted-line +
  document-selection configuration, plus a regression test that fails if
  stable-content layout passes rebuild AppKit leaf content.

## 0.6.10 - 2026-07-12

- Fixed semantic theme colors such as `Color.primary` being converted to
  fixed AppKit/UIKit/Core Graphics colors without the active SwiftUI
  appearance. Core Text line plans now also carry the foreground-from-context
  attribute required for `CTLineDraw` to honor the resolved CGContext fill
  color. Core Text-painted lines, AppKit selectable text and math fallbacks,
  and attachment placeholder layers update in place when the scheme changes
  without rebuilding cached line plans.

## 0.6.9 - 2026-07-11

- Fixed image-backed inline math losing its custom baseline attachment cell on
  the newer AppKit version used by GitHub's macOS runner. Math attachments now
  assign the prepared image, baseline-adjusted bounds, and package-owned cell
  explicitly instead of relying on `NSTextAttachment(data:ofType:)`
  initialization behavior. The image and bounds are the portable layout
  contract; the bounded cache also retains the legacy cell for older AppKit
  versions that use it.
- `0.6.8` remains an immutable historical tag. `0.6.9` carries the same native
  macOS selection/menu release with the cross-AppKit attachment construction
  fix and a release regression that requires the preserved image and geometry.

## 0.6.8 - 2026-07-11

- macOS selection now defaults to bounded noneditable `NSTextView` leaves, so
  AppKit owns glyph-backed highlights, word/drag/keyboard selection, continuous
  prose wrapping and copy, and the standard contextual menu.
- Removed the per-block SwiftUI context menu that intercepted secondary clicks
  with only “Copy Markdown.” Exact-source cross-block selection remains an
  explicit mode and disables native leaf selection while active.
- Closed the remaining default-selection hole for paragraphs containing
  image-backed inline math. Prepared equations now become baseline-aligned
  TextKit attachments inside the same bounded AppKit leaf, preserve links and
  semantic plain-text copy/accessibility, coexist with prepared image
  attachments, and do not mount SwiftUI's private `SelectionOverlay`.
- Kept the AppKit selection owner stable while a streamed tail transitions
  between text fallback and prepared math imagery, and made the release gate
  require the default menu, streaming-selection, inline-math, and attachment
  cache regressions that define the macOS product contract.

## 0.6.7 - 2026-07-09

- Fixed a clean-checkout GitHub Actions compiler failure in vendored SwiftMath.
  The GitHub macOS runner's Swift toolchain could not type-check the chained
  lazy `filter`/`map`/`min` expression used to restore a preferred registered
  LaTeX symbol name, even though the release compiler accepted it locally.
  The lookup is now an explicit single-pass loop with the same deterministic
  rule (shortest name, then lexicographically first), avoiding compiler
  complexity without changing runtime behavior.
- `0.6.6` remains an immutable historical tag. `0.6.7` carries the same block
  styles, atomic attachments, math corpus, cache correctness, serializer, and
  concurrency hardening with the compiler-portable registry implementation.

## 0.6.6 - 2026-07-09

### Block Style Protocols (Parts 01–03)

- **Style protocol surface (Part 01):** Fourteen `@MainActor` per-block
  style protocols (`MarkdownHeadingBlockStyle`, `MarkdownParagraphBlockStyle`,
  `MarkdownBlockQuoteStyle`, `MarkdownCodeBlockStyle`, `MarkdownTableBlockStyle`,
  `MarkdownTableCellStyle`, `MarkdownListItemStyle`,
  `MarkdownUnorderedListMarkerStyle`, `MarkdownOrderedListMarkerStyle`,
  `MarkdownTaskListMarkerStyle`, `MarkdownThematicBreakStyle`,
  `MarkdownMathBlockStyle`, `MarkdownHTMLBlockStyle`,
  `MarkdownMermaidBlockStyle`) replace `MarkdownBlockView`'s hardcoded chrome.
  Each `makeBody(configuration:)` receives an already-prepared
  `MarkdownBlockStyleLabel` plus metadata (theme, block ID, indentation level,
  and slot-specific fields such as `headingLevel` or `languageHint`) — styles
  never parse, highlight, or run inline layout (INV-BS2). `MarkdownDefault*Style`
  implementations reproduce pre-protocol chrome exactly (INV-BS3), and the
  aggregate `MarkdownDocumentStyle` protocol bundles all fourteen slots with a
  `MarkdownDefaultDocumentStyle` / `.default` convenience.
- **Environment + configuration injection (Part 02):**
  `MarkdownRendererConfiguration.documentStyle` (default `nil`) carries a
  session-default style bundle, and a new `.markdown` namespace
  (`View+Markdown.swift`) exposes per-slot modifiers
  (`.markdown.headingStyle(_:)`, `.markdown.codeBlockStyle(_:)`, …) plus an
  aggregate `.markdown.documentStyle(_:)`. Effective style per slot resolves as
  `environment override ?? environment aggregate slot ?? configuration.documentStyle
  slot ?? MarkdownDefault*Style` (INV-BS9) — a per-block modifier always wins over
  an aggregate document style regardless of which is applied first, avoiding
  Textual's aggregate-clobber footgun. Style resolution never reparses Markdown,
  never changes prepare/layout cache identity, and never churns sealed block IDs
  (INV-BS1, INV-BS6) — `MarkdownTheme` remains the sole prepare/layout cache
  identity core.
- **GitHub-inspired preset (Part 03):** Opt-in `MarkdownTheme.gitHub`
  (heading sizes 32/24/20/16/14/14pt with matching line heights, denser table
  padding, GitHub-flavored borders/zebra rows) pairs with
  `MarkdownGitHubDocumentStyle` / `.gitHub` (semibold headings with an H1/H2
  divider underlay and tertiary H6 color, a GitHub-bordered block-quote bar,
  denser code-block padding, and hierarchical disc/circle/square unordered
  markers) via the `MarkdownRendererConfiguration.gitHub` convenience. Neither
  `.compactChat` nor `.document` is affected — GitHub is never the default
  (INV-BS4), and it approximates Textual's `.gitHub`, not github.com's exact
  CSS (Part 03 §3.3.3).
- 27 new tests cover default-style parity (geometry constants locked for
  block-quote bar, code corner radius, list marker widths, thematic break,
  and heading pass-through), merge-order precedence (including
  order-independence of override vs. aggregate modifiers),
  configuration-vs-environment precedence, custom style invocation,
  cache/streaming safety under style changes, GitHub theme metrics, GitHub
  opt-in status, GitHub slot overrides, hierarchical markers, and nested-list
  indentation with custom marker widths.

### Inline Attachments (Parts 01–04)

- **Model + prepare (Part 01):** Allowed images (`MarkdownImagePolicy` `.allow`)
  now flow as prepared `MarkdownPreparedAttachment` records with reserved
  `pointWidth`/`pointHeight`/`ascent`/`descent` box metrics instead of
  alt-text-measured display runs. `MarkdownInlineRun`/`PreparedInlineSegment`
  carry an optional `attachmentMetrics` field; `CoreTextInlineMeasurer` uses
  `pointWidth` for atomic image segments instead of measuring text.
  `MarkdownTheme.attachmentPlaceholder` is the new default reserved-box size
  token. A cheap ImageIO header probe of resolver-supplied `.data`/`.localFile`
  bytes yields `.intrinsicHint` sizing (clamped to the theme's max width,
  preserving aspect ratio); otherwise sizing falls back to
  `.themeDefault`. Denied images are unaffected — they keep today's
  alt/`[image: reason]` text-atomic path (INV-IA1, INV-IA4).
- **CoreText atomic placement (Part 02):** `MarkdownCoreTextPaintedLinePlan`
  attaches a `CTRunDelegate` to each attachment's placeholder-character
  range so line wrap and painted advance use box metrics, and records a
  `MarkdownCoreTextPaintedAttachmentGap` per attachment. Wide attachments in
  narrow containers wrap as a whole atomic box, never split into
  per-character sub-lines. A link-wrapped allowed image
  (`[![alt](img)](url)`) still produces a clickable `MarkdownCoreTextPaintedLinkFragment`
  over the attachment's own box — becoming an attachment does not drop the
  outer link's hit region (§3.2.7). `MarkdownDocumentSelectionGeometry`
  applies the same `CTRunDelegate` shape to its local selection `CTLine`, so
  drag/hit-test x-mapping is box-precise instead of proportional to the
  placeholder glyph's own advance (INV-IA5), while atomic snapping still
  resolves any partial hit to the whole image source range.
- **SwiftUI/AppKit/UIKit hosts (Part 03):** One `MarkdownAttachmentHostNSView`/
  `UIView` exists per attachment ID, reconciled by identity from the
  CoreText line plan's gaps (INV-IA6); removing an attachment tears its host
  down (detaches from the view hierarchy), it does not just drop out of the
  count. Hosts draw already-resolved `Data` through `NSImageView`/
  `UIImageView` or quiet reserved-box chrome for pending/placeholder
  attachments, with an alt-text-first, generic-fallback accessibility label
  (§3.2.6); no `URLSession` call or body-time `CGImageSourceCreate*` decode
  exists in a host's `body`/`updateNSView`/`updateUIView` (INV-IA3). Hosts do
  not intercept drag-selection or link hit-testing — decorative image
  content passes hit-testing through to the CoreText surface underneath.
- **Policy + cache (Part 04):** Default `evaluateImage` stays deny
  (INV-IA1); the resolver is only ever consulted on `.allow`. Prepared
  inline cache identity now includes an `attachmentMetricsVersion` token and
  the theme's `attachmentPlaceholder` fingerprint whenever allowed
  attachments exist, so changing the default box size invalidates stale
  cached box metrics.
- This is the placement layer only: no network fetch, no multi-frame decode,
  and no animation ships in this release. Future loaders can provide bytes or
  frames through the same attachment slots without adding a second inline
  layout path.

### Native Math, Layout, and Cache Correctness

- Added a shared 50-case math/LaTeX corpus consumed by both Swift and the
  JavaScript parity tool. Native coverage requires 48 SwiftMath-backed image
  cases, preserves original LaTeX for copy/accessibility, checks display-list
  metrics and visual golden bands, records `mathFallbackCount`, and proves
  bounded math-cache reuse. The web subset is checked against current KaTeX
  and MathJax 4; Sirius-only aliases and intentionally invalid diagnostics are
  explicit rather than silently skipped.
- Expanded generated-formula compatibility for fractions/binomials, relations,
  arrows, arrays and small matrices while keeping original source untouched.
  Compatibility replacement now respects complete command boundaries,
  preserves nondigit script groups such as `x^{n+1}` and `y_{ij}`, and leaves
  escaped script markers and escaped Unicode commands unchanged.
- Corrected prepared cache identity across the renderer. Measured inline cache
  hits now rebind visual metrics to the requesting run metadata; measured-layout
  keys include the actual supplied measurements; code highlighting includes the
  complete fence info string; Mermaid keys include render-relevant colors and
  fonts; block math hashes exact source rather than trusting a caller-provided
  stale `contentHash`; and attachment keys include placeholder colors, metrics,
  and sizing inputs.
- Allowed attachment placeholder chrome now reaches the AppKit/UIKit hosts, and
  all placeholder width, height, and corner-radius values are finite, positive,
  and bounded before entering CoreText, SwiftUI, or layer geometry.
- CoreText measurement now uses real fallback shaping for missing glyphs and
  applies semantic italic/monospace traits consistently. Selection geometry
  uses the same font resolver as painting, so nested strong/emphasis/code
  presentation no longer measures with different glyph metrics.
- Custom math renderers can no longer inject nonfinite, negative, or enormous
  image dimensions into SwiftUI/AppKit/UIKit frame calculations. Raster size,
  scale, point geometry, and ascent/descent are sanitized before publication.

### Vendored SwiftMath Safety and Serialization

- Replaced lazy mutable reverse lookup and inter-element spacing tables with
  immutable initialization. Font/math-table access, display-support state, and
  the custom LaTeX symbol registry now synchronize shared mutable state; custom
  symbol overrides remove stale reverse mappings and restore the canonical
  built-in mapping when an override moves to a new nucleus.
- Hardened public mutable atom models. Copies dispatch by runtime subclass,
  canonicalize impossible type/storage combinations before copying scripts,
  drop scripts from no-script atom classes, and make malformed composite atoms
  fail closed instead of trapping in enum-driven force casts.
- Fixed `MTMathTable.finalized` mutating temporary row copies instead of the
  returned table's cells. Numeric fusion and operator normalization now apply
  recursively inside table cells, and negative public row/column indices are
  ignored safely.
- Reworked `MTMathListBuilder.mathListToString` into a non-mutating serializer.
  Matrix/alignment helper atoms are skipped through array slices instead of
  being deleted from caller-owned cells; `color`, `textcolor`, and `colorbox`
  atoms retain their contents; incomplete fractions/inner lists and unknown
  custom operators degrade to valid bounded output instead of force-unwrapping;
  and a stale duplicate command parser with unsafe color handling was removed.
- Added adversarial regressions for concurrent symbol/font-table access,
  malformed public models, serializer purity and color round trips, table-cell
  finalization, exact cache invalidation, Unicode fallback shaping, attachment
  geometry, and custom renderer dimensions.

## 0.6.5 - 2026-07-09

### Native Selection Feel (Parts 01–04)

- **Continuous drag affinity (Part 01):** Inter-block drag selection no longer freezes
  when the pointer sits in vertical spacing between fragments. `hitFragment` now has
  a nearest-fragment fallback within the inter-block gutter threshold (hitSlop × 8),
  resolving nil hits in theme-spacing gutters between paragraphs, lists, and code
  blocks. Gutter ties break via `MarkdownDocumentSelectionAffinity` (`.upstream` /
  `.downstream`) derived from drag direction. The drag layer now passes affinity hints
  derived from movement direction. Source-backed endpoints remain correct (INV-NS1);
  no per-glyph overlays are added (INV-NS2).

- **Scrollable selection contexts (Part 02):** `MarkdownSelectionController` now
  tracks an `activeContext: MarkdownSelectionContextKind` (`.document` or
  `.scrollableRegion(MarkdownScrollableSelectionRegionID)`). Activating one context
  clears the other — matching Textual's documented rule that selecting inside a
  scrollable code/table region clears document multi-block selection and vice versa.
  Document drag that crosses block boundaries activates `.document` and clears region
  clamp. New types: `MarkdownScrollableSelectionRegionID`, `MarkdownSelectionContextKind`.

- **Pasteboard richness (Part 03):** `MarkdownPasteboard` now writes
  multi-representation payloads via `MarkdownPasteboard.copy(MarkdownPasteboardPayload)`.
  On macOS, one `NSPasteboardItem` carries `.string` = visible plain text,
  `net.siriusmarkdown.markdown` = exact Markdown source (INV-NS1), and optional `.rtf`
  / `.html` when present. On iOS/iPadOS, plain text and the custom Markdown type are
  written. Document Cmd-C routes through `affordanceActionHandler.copyPayload` only;
  the default `copyPayload` implementation calls `MarkdownPasteboard.copy(_ payload:)`.
  Single-string affordance copy (code block copy, etc.) still uses `copyString`.

  **Breaking change for hosts reading the pasteboard:** `NSPasteboard.string(forType: .string)`
  now contains **plain text** (visible rendered text), not Markdown source. Hosts that
  previously assumed `.string` was Markdown source must now read
  `NSPasteboard.data(forType: NSPasteboardType("net.siriusmarkdown.markdown"))`.
  In-process `selectedMarkdown` and `MarkdownCopyProvider` APIs are unchanged.
  `MarkdownPasteboard.markdownPasteboardType` exposes the type constant.

  **Breaking change for hosts overriding affordance handlers:** document selection
  Cmd-C invokes `copyPayload`, not `copyString`. Hosts that hooked `copyString` for
  document-copy toasts or side effects must move that logic to `copyPayload`.

  New types: `MarkdownPasteboardPayload`.

- **`MarkdownAffordanceActionHandler` promoted to `final class`:** Previously a struct
  with two `@MainActor @Sendable` closure fields; the struct was extended to three
  fields during pasteboard richness work, triggering a SIGBUS in the Swift runtime's
  memmove path during default-argument evaluation. The type is now a
  `public final class @unchecked Sendable`, which eliminates the memmove and restores
  `copyPayload` as a first-class stored closure. `copySelection` now routes through
  `copyPayload` only; the temporary `copyString` call after the pasteboard write is
  removed, closing the semantic mismatch where the handler saw Markdown but `.string`
  had plain text.

- **Text.Layout bridge (Part 04, evaluated and rejected):** Parts 01–03 close the
  feel gap on the default `coreTextPaintedLines` path. A `Text.Layout` bridge for
  cross-view Markdown selection is not warranted on the CoreText default path and
  would risk the `SelectionOverlay` hang class documented in `runbook.md`.
  `nativeTextSelection` remains opt-in and disabled by default. No bridge code
  shipped; `INV-NS3` upheld.

- Completed math-quality metrics: `SwiftMathTypesetter` now consumes vendored
  SwiftMath `MTMathImage.LayoutInfo` (`MTMathListDisplay` ascent/descent)
  instead of the interim atom-tree fraction estimator, keeping `-descent`
  baseline alignment and `ascent + descent == pointHeight` after mapping
  through SwiftMath's `fontSize/2` vertical-layout formula. Compact glyphs
  grow the image to at least `fontSize/2` so the baseline stays inside the
  bitmap. Cache identity bumps to `compat5-layoutinfo`.
- Added LayoutInfo parity, baseline, tall-equation line-height, compact-glyph,
  and `.interpolation(.medium)` source-guard tests, plus streaming coverage
  that open inline `\(...\)` does not invent math blocks or block fences.
- Updated `Docs/performance.md`, the native-renderer scorecard, and bugfix
  math-quality wording to describe display-list metrics and packaged-app
  `SiriusMarkdown_SwiftMath.bundle` requirements.

## 0.6.4 - 2026-07-07

- Fixed a packaged-macOS-app crash that re-appeared under macOS 26.5.x where
  inline LaTeX math rendering trapped with `EXC_BREAKPOINT` inside SwiftPM's
  generated `Bundle.module` accessor (`fatalError("could not load resource
  bundle: from ... or ...")`) during `MarkdownRendererConfiguration.prepare`.
  `0.6.2`/`0.6.3` patched `MTFont.fontBundle` to locate
  `SiriusMarkdown_SwiftMath.bundle` via
  `Bundle.main.url(forResource:withExtension:)` and only fall back to
  `Bundle.module` for SwiftPM test/command-line contexts. That relied on
  `Bundle.url(forResource:withExtension:)` returning a nested `.bundle`
  directory from a signed app's `Contents/Resources`. A macOS 26.5.x Foundation
  change stopped returning wrapped-bundle directories from that API, so every
  candidate missed, the `Bundle.module` fallback fired, and its accessor
  fatals because it only checks `Bundle.main.bundleURL/<name>.bundle` (the
  `.app` root) and a build-time path baked in at compile time — never
  `Contents/Resources`. `MTFont.fontBundle` now resolves the inner
  `mathFonts.bundle` by a direct **filesystem probe**
  (`MTFont.mathFontsBundleURL(mainBundleURL:fileExists:)`) of
  `Contents/Resources`, the `.app` root, and the owning bundle's resource URL,
  and loads it with `Bundle(url:)`. The `Bundle.module` fallback is now
  reached only when `Bundle.main` is not a packaged `.app` (SwiftPM
  test/`swift run` contexts where the build-time candidate is valid), so the
  fatal landmine can never fire in a signed `.app`. `canEnterSwiftMath` uses
  the same resolver so the entry guard and the loader agree: a packaged app
  enters SwiftMath only when the inner `mathFonts.bundle` is actually
  loadable, and falls back to text otherwise.
- Hardened the vendored `MathBundle` (`MathFont`/`BundleManager`) path against
  the same `Bundle.module` fatal: `registerCGFont`/`registerMathTable` resolve
  `mathFonts.bundle` via `MTFont.mathFontsBundleURL` instead of
  `Bundle.module.url(forResource:withExtension:)`, so the alternative
  `MTFontV2`/`MathFont` API no longer traps in a signed `.app`.
- `MTFont.mathFontsBundleURL(_:)` is now `public` so host apps and the
  `SiriusMarkdownMath` guard share one source of truth for the packaged-app
  resource layout. Host build scripts that copy
  `SiriusMarkdown_SwiftMath.bundle` into `Contents/Resources` are unchanged.

## 0.6.3 - 2026-07-05

- Fixed a SwiftPM resolver blocker that made `0.6.2` unusable from any
  stable-version requirement (`from:` or `exact:`). `0.6.2` vendored SwiftMath
  via `.package(path: "Vendor/SwiftMath")`; path packages carry no version, so
  SwiftPM assigned it `0.0.0` (unstable), tripping the
  "stable-version requirement cannot depend on an unstable-version package"
  rule for every consumer. SwiftMath is now vendored as an inline **target** in
  the SiriusMarkdown manifest (`Sources/SwiftMath`), eliminating the package
  dependency edge entirely. The package is still clean-checkout safe with no
  external SwiftMath fetch; the only remaining package dependency is
  `swift-markdown`.
- Resource-bundle rename: because SwiftMath is now a target of the
  SiriusMarkdown package, SwiftPM names its resource bundle
  `SiriusMarkdown_SwiftMath.bundle` (the `<Package>_<Target>` convention)
  instead of `0.6.2`'s `SwiftMath_SwiftMath.bundle`. `MTFont.fontBundle` and
  `canEnterSwiftMath` look for the new name, and the
  `swiftMathTypesetterRejectsPackagedAppOnlyWhenResourcePathsAreMissing`
  regression asserts the new layout. Host build scripts that copy the bundle
  into `Contents/Resources` must copy `SiriusMarkdown_SwiftMath.bundle`.
- Compiled the vendored SwiftMath target under Swift 5 language mode
  (`swiftSettings: [.swiftLanguageMode(.v5)]`) because upstream SwiftMath is
  not Swift 6 strict-concurrency clean (non-Sendable mutable globals). The rest
  of the package remains Swift 6.
- Native LaTeX math glyphs still render in signed packaged macOS apps via the
  patched `MTFont.fontBundle` that searches `Bundle.main.url(forResource:)` and
  `Bundle(for:).url(forResource:)` before the `.app` root and the SwiftPM
  build-time fallback, so the signed-`.app` `Contents/Resources` layout loads
  without breaking `codesign`.

## 0.6.2 - 2026-07-05

- Restored native LaTeX math glyphs in signed packaged macOS apps. `0.6.0`
  trapped and `0.6.1` fell back to text because SwiftMath's generated
  `Bundle.module` accessor (built from a `swift-tools-version: 5.7` manifest,
  and still emitted by current toolchains for 6.0 manifests) only checks
  `Bundle.main.bundleURL`'s root and a build-time path; it never searches
  `Contents/Resources`, which is the only location a signed versioned `.app`
  may keep resources. A host-side copy to the `.app` root was confirmed
  unviable (`codesign` rejects unsealed bundle-root contents).
- Vendored SwiftMath as a local in-tree package at `Vendor/SwiftMath` (MIT,
  attribution in `NOTICE.md`) and dropped the external
  `mgriebling/SwiftMath.git` dependency. The vendored fork patches
  `MTFont.fontBundle` to search `Bundle.main.url(forResource:)` and
  `Bundle(for:).url(forResource:)` (which find `SwiftMath_SwiftMath.bundle`
  under `Contents/Resources`) before the `.app` root and the SwiftPM build-time
  fallback. Native math now renders in packaged apps without breaking the
  signed bundle layout, and the package is clean-checkout safe (no external
  SwiftMath fetch).
- Reverted the `0.6.1` `canEnterSwiftMath` restriction. The guard again accepts
  the `Contents/Resources/SwiftMath_SwiftMath.bundle/mathFonts.bundle` layout
  because the patched `MTFont.fontBundle` can now load it; the
  `swiftMathTypesetterRejectsPackagedAppOnlyWhenResourcePathsAreMissing`
  regression now asserts that layout enters SwiftMath.
- The resource bundle name (`SwiftMath_SwiftMath.bundle`) is unchanged, so
  host-app build scripts that copy the bundle into `Contents/Resources` keep
  working.

## 0.6.1 - 2026-07-05

- Fixed a packaged-macOS-app crash introduced in `0.5.12` and shipped in
  `0.6.0`, where `SiriusMarkdownMath`'s SwiftMath entry guard accepted
  `Contents/Resources/SwiftMath_SwiftMath.bundle` as a valid resource path but
  SwiftMath's generated `Bundle.module` accessor (built from a
  `swift-tools-version: 5.7` package) only checks `Bundle.main.bundleURL`'s
  root and a build-time path. In a standard signed `.app` the bundle lives
  under `Contents/Resources`, so the guard passed, `MTFont.fontBundle` entered
  SwiftMath, and `Bundle.module` trapped with `EXC_BREAKPOINT` inside
  `MarkdownRendererConfiguration.prepare(block:)`. The guard now mirrors
  `Bundle.module`'s actual candidates and falls back to text rendering when the
  loadable path is absent, restoring the safe `0.5.7` behavior. A regression
  test guards that a `Contents/Resources`-only layout does not enter SwiftMath.
- Updated the SwiftMath entry-guard regression to reject the
  `Contents/Resources`-only path that previously crashed packaged apps and to
  accept the `.app` root path that `Bundle.module` actually loads.

## 0.6.0 - 2026-07-04

- Consolidated streaming performance, cross-block selection consistency, and
  native math rendering quality into a measured release. The improvements below
  were delivered across `0.5.13`–`0.5.14` and are now the documented product
  state for `0.6.0`.
- Moved CTLine creation from the SwiftUI update path into the prepare phase,
  eliminating expensive CoreText work in `updateNSView`/`updateUIView`.
  Prepared line plans (`MarkdownCoreTextPaintedLinePlan`) are cached by content
  identity and width bucket (INV-P1).
- Eliminated two-pass layout latency in `PreparedInlineTextView`. New and changed
  blocks render content on first appearance without waiting for a width
  preference pass (INV-P2).
- Added incremental snapshot publishing. `MarkdownRenderSession` publishes a
  `MarkdownPreparedSnapshotDiff` alongside the full snapshot so only
  changed/new/removed items trigger SwiftUI view updates (INV-P3).
- Cached selection fragment geometry by prepared content identity and rect
  fingerprint. Repeated same-rect resolution records zero new builds after
  warmup (INV-P4).
- Unified cross-block selection consistency. Table cells, list items, code
  blocks, and math blocks now publish text-geometry-aware selection fragments
  from `inlineLayout` or `selectionInlineLayout`, eliminating rect-based
  fallbacks (INV-S1).
- Improved inline math baseline alignment by extracting real ascent/descent
  from the parsed `MTMathList` atom tree, replacing the `0.32` heuristic
  (INV-M2).
- Matched math rasterization scale to screen backing scale (min 2.0) and
  switched to `.interpolation(.medium)` for sharper glyph edges.
- Hardened streaming math detection for `\begin{...}...\end{...}` LaTeX
  environments so they do not seal early during streaming.
- Added measured performance benchmarks with defined frame budgets: <16ms per
  append for 100+ blocks, <4ms per width-change relayout, zero CTLine creation
  in SwiftUI body after preparation (INV-P8).
- Added streaming math detection tests for partial delimiters, multi-line
  equations, math inside containers, and `\begin{...}` environment tracking.
- Added cross-block selection tests covering table cells, list items (including
  nested and task lists), code blocks, math blocks, HTML blocks, and
  mixed-document fragment generation.
- Added math quality tests covering metric extraction, baseline alignment,
  rendering sharpness, inline math flow, streaming fallback, and cache identity.
- Updated documentation to reflect the current product state, removing stale
  workaround language and hang-history references. Added documentation
  consistency tests covering version alignment, stale-reference scanning, and
  historical preservation. The release gate now discovers `643` Swift tests.

## 0.5.14 - 2026-07-04

- Improved native LaTeX math rendering quality: `MarkdownPreparedMathImage` now carries real typographic ascent/descent estimated from the parsed `MTMathList` atom tree (detecting subscripts, fraction denominators, radical degrees, and large-operator limits) instead of the prior `ascent = pointHeight, descent = 0` placeholder. `InlineMathTextView.baselineOffset(for:)` uses `-descent` to align the equation's typographic baseline with the surrounding text baseline, replacing the `−overshoot × 0.32` heuristic.
- Matched math rasterization scale to the screen's backing scale (min 2.0) instead of a fixed 3.0, ensuring sharp glyphs on both 2x Retina and 3x Pro displays. `MarkdownMathImageView` now uses `.interpolation(.medium)` for sharper glyph edges on template images.
- Fixed streaming boundary scanner gap where `\begin{equation}...\end{equation}` and other `\begin{...}...\end{...}` LaTeX environments could seal early during streaming because the scanner did not track open environments. The scanner now keeps the region mutable until `\end{...}` arrives, matching the existing `$$` and `\[...\]` fence tracking behavior. Self-closing environments on a single line are handled correctly.
- Added streaming math detection tests covering partial `$$`, partial `\[...\]`, partial `\begin{...}`, math inside block quotes and list items, math adjacent to code fences, multi-line equations, and boundary scanner direct tests for the new `\begin{...}` environment tracking.
- Added math quality tests covering metric extraction (`ascent + descent == pointHeight`, `ascent < pointHeight` for descenders), baseline alignment, rendering sharpness, inline math flow, streaming fallback, and cache identity. The release gate now discovers `630` Swift tests.
- Updated `Docs/performance.md` with a math rendering quality section documenting real typographic metrics, baseline alignment, screen-matched rasterization, interpolation, and streaming detection.

## 0.5.13 - 2026-07-04

- Fixed cross-block selection consistency so all block types with inline content (paragraphs, headings, block quotes, list items, table cells, code blocks, math blocks, HTML blocks) publish text-geometry-aware selection fragments from prepared inline layout instead of rect-based fallbacks. Previously table cells and list items used rect-based fragments without `textGeometry`, code blocks with `selectionInlineLayout` were skipped by `fragments(for:preparedContent:rect:)`, and list/table blocks' block-level `inlineLayout` intercepted before per-item/per-cell fragment paths.
- Added `selectionInlineLayout` to `MarkdownPreparedListItem` and `MarkdownPreparedTableCell` so items/cells without `inlineLayout` still get text-geometry-aware fragments. Updated `emitsTextLeafSelectionFragments` to check `selectionInlineLayout` for list items and table cells (INV-S3).
- Reordered `fragments(for:preparedContent:rect:)` to check list items and table cells before block-level `inlineLayout`, preventing concatenated block-level inline content from intercepting per-item/per-cell fragment generation.
- Added 27 cross-block selection tests covering table cells, list items (including nested and task lists), code blocks (including policy-denied), math blocks (including `\[...\]` and policy-denied), HTML blocks, and mixed-document fragment generation. The release gate now discovers `594` Swift tests.

## 0.5.12 - 2026-06-26

- Fixed bug-sweep regressions for same-offset host-boundary ordering, host-heavy snapshot item assembly, duplicate host-boundary render IDs, EOF nearest source reveal, plain-text fallback copy for blocks without inline runs, empty source-buffer appends, prepared native-line semantic layout identity, overwide atomic inline presentation measurement, styled-link document-selection geometry, duplicate sourceless image display text, Mermaid theme cache identity, Mermaid custom-renderer geometry validation and toolbar visibility, Pretext fixture metadata validation, SwiftMath packaged-app resource lookup, macOS demo resource packaging, CoreText measurement hardening, image-backed display-math selection fragments, source-range-aware and field-bounded inline cache keys, field-bounded font/theme/render-preparation namespaces, seal-state-only prepared snapshot reuse, visual-probe release/docs gating, and public native-selection incident wording.
- Hardened public input boundaries for caches, source-buffer ranges, table/theme/font metrics, and selection limits so invalid host configuration degrades to bounded defaults instead of trapping or producing unstable SwiftUI layout.
- RenderProbe remains opt-in but now renders through an offscreen AppKit host instead of ordering its window on screen, so artifact-producing visual checks can run without flashing probe windows.
- Added parser, native-math-renderer, and negative code/path regressions for generated formula families, Windows-style paths, code spans, unknown commands, escaped Markdown, empty source appends, source-range-aware and field-bounded inline cache keys, font/theme/render-preparation namespace boundaries, image-backed display-math selection geometry, Mermaid invalid-geometry toolbar gating, seal-state-only prepared snapshot reuse, and fixed-width prepared layout identity changes. The release gate now discovers `557` Swift tests and requires the new math recovery, renderer, host-boundary, source-lookup, fallback-copy, inline-layout, image-preparation, Mermaid-cache/geometry, Pretext fixture-comparison, source-buffer, demo-resource-packaging, visual-probe-gating, and selection-geometry regressions.

## 0.5.11 - 2026-06-21

- Fixed generated bare-TeX recovery so chat/math output such as score formulas, `\operatorname`, `\mathbb`, `\partial`, `\nabla`, `cases`, `align*`, `equation`, angle-bracket pairs, Greek/font-style commands, and common relation operators stay together as one source-backed math run instead of splitting at each command.
- Hardened `SiriusMarkdownMath`'s SwiftMath bridge for common generated LaTeX by normalizing `\operatorname` / `\operatorname*`, one-column `cases` shorthand, wrapper environments such as `equation` / `displaymath`, and `align` / `align*` / `multline` aliases before typesetting while preserving the original LaTeX source on prepared math images.
- Added parser, native-math-renderer, and negative code/path regressions for generated formula families, Windows-style paths, code spans, unknown commands, and escaped Markdown. The release gate now discovers `522` Swift tests and requires the new math recovery and renderer regressions.

## 0.5.10 - 2026-06-16

- Fixed chat-style LaTeX recovery for single-line display math inside prose paragraphs. Lines such as `$$...$$` and `\[...\]` now split into source-backed paragraph/math/paragraph blocks instead of leaking literal delimiters through the renderer.
- Added conservative bare-TeX inline recovery for common math commands such as `Z \approx 0`, `\sqrt{t}`, and `\sigma \sqrt{t}` so configured math renderers receive real math runs even when model output omits `$...$` or `\(...\)` delimiters. The recovery stays out of code spans and preserves paths, unknown commands, escaped Markdown punctuation, currency amounts, and adjacent prose.
- Added Core parser and SwiftUI render-preparation regressions for the recovered LaTeX shapes.

## 0.5.9 - 2026-06-16

- Fixed wide code blocks stretching constrained transcript/document columns. Prepared code content now keeps its natural width inside the horizontal scroll view while the code block itself remains bound to the host column, preserving inspectable long lines without inflating the surrounding SwiftUI layout.
- Added hosted AppKit regression coverage for plaintext-style wide code blocks in a 320-point transcript column, including width and height assertions so the block neither stretches nor collapses.
- Hardened `Tools/RenderProbe` overflow coverage so it now asserts the hosted fitting width stays contained, not just that wide pixels render. The release gate now discovers `512` Swift tests and requires the new wide-code containment regression.

## 0.5.8 - 2026-06-14

- Fixed long-generation render-session slowdown where rapid append bursts queued obsolete snapshot preparation work. `MarkdownRenderSession` now drains pending operations in batches, coalesces consecutive appends, preserves host-boundary ordering, and drops queued work superseded by reset before parsing or preparing it.
- Reused prepared block content across append-only streaming snapshots. Stable blocks from the prior prepared snapshot are now reused by exact block identity/content match, so appending one paragraph to a long transcript prepares the changed/new tail instead of walking back through hundreds of sealed blocks after the render-preparation cache capacity is exceeded.
- Added render-session performance regressions covering append-burst coalescing, reset skipping stale highlighter work, host-boundary ordering through coalesced batches, and a 320-block transcript append that must prepare exactly one new block. A release-mode probe measured a 320-block append dropping from 321 preparations and about 257 ms on the full-snapshot path to 1 preparation and about 1.6 ms through `MarkdownRenderSession`.
- Updated the release gate for `511` Swift tests and made the new render-session long-generation regressions required release checks.

## 0.5.7 - 2026-06-10

- Fixed native math rendering in signed packaged apps where SwiftMath's generated `Bundle.module` accessor would fatal if `SwiftMath_SwiftMath.bundle` was not present at the app bundle root. `SiriusMarkdownMath` now checks the generated accessor's required packaged-app resource path before entering SwiftMath and falls back to text rendering when that path is unavailable, preserving the signed app bundle layout under `Contents/Resources`.
- Added a regression covering packaged `.app` bundle lookup versus SwiftPM test contexts so consuming apps do not need to fork or repin SwiftMath to avoid the crash.

## 0.5.5 - 2026-06-06

- Fixed shipped-app JavaScript resource lookup for bundled HighlightJS and Mermaid runtimes by searching the main app bundle, SwiftPM resource bundles, framework bundles, and adjacent resource directories before disabling preparation.
- Hardened default document selection so code blocks, text-rendered math, image-backed inline math, allowed HTML, table cells, list rows, and styled Markdown map visible drags back to precise source ranges.
- Added Cmd-A and context-menu Select All support for package-owned document selection, with full-document selections tracking streamed appends instead of being clipped by the configured block-selection cap.
- Fixed fallback plain-text copy without a `MarkdownCopyProvider` so partial and non-contiguous source selections copy only the selected visible text instead of whole selected blocks.
- Fixed multi-chunk UTF-8 source slices and line decoding so source-backed selection/copy remains byte-accurate across chunk boundaries and multibyte scalars.
- Expanded AppKit selection, controller, parser, source-buffer, product, and performance regressions; the release gate now discovers `485` Swift tests.

## 0.5.4 - 2026-06-04

- Made CoreText-painted prepared-line inline rendering the default for `MarkdownRendererConfiguration()`, `.compactChat`, and `.document`.
- Added AppKit/UIKit CoreText line painting with bounded link hit regions derived from policy-filtered prepared link attributes.
- Preserved explicit native text selection by routing `nativeTextSelection: .enabled` through selectable native text leaves instead of the CoreText paint path.
- Hardened tvOS/watchOS platform guards and expanded release coverage across iOS, tvOS, watchOS, visionOS, and Mac Catalyst builds.
- Updated the release gate and docs for the `472`-test floor, product check, Pretext golden coverage, demo builds, DocC, and CoreText-default public claim.

## 0.5.3 - 2026-06-03

- Fixed dollar-delimited inline math detection so currency and reward amounts such as `$100 - $5,500`, `$108,500`, and screenshot-shaped reward tables stay literal while real inline math continues to parse.
- Switched compact currency-code detection to Foundation's `Locale.Currency.isoCurrencies` instead of a package-maintained suffix list.
- Added parser and SwiftUI preparation regressions for table currency amounts, styled and linked currency contexts, numeric-leading math, code spans, `\(...\)` fallback parsing, and every Foundation ISO currency identifier; the release gate now discovers and requires `466` Swift tests.

## 0.5.2 - 2026-06-03

- Hardened streaming boundary scanning and sealed-reference carry-forward across generated stream-vs-one-shot matrices covering reference definitions, inline reference ambiguity, container fences, display math, raw HTML, list continuations, tables, and host boundaries.
- Tightened default public link policy handling for HTTP(S), `mailto:`, relative destinations, and HTML-character-reference decoded links. The default policy now rejects additional Foundation-normalized and percent-decoded delimiter/header-smuggling cases, including encoded `mailto:` query separators inside allowed `subject` values.
- Improved display-math recovery and native math behavior in block quotes, list items, linked inline contexts, image-backed inline math, selection geometry, and render preparation so math remains source-backed, policy-routed, and cacheable without extra renderer invocations.
- Replaced the crash-prone default Swift highlighting path with a package-owned lexical Swift highlighter that handles long strings, nested interpolation strings, embedded NULs, and modern Swift keywords.
- Strengthened prepared inline/image/math cache identities and policy short-circuit behavior so denied content does not invoke host resolvers/renderers and allowed content does not reuse stale policy-dependent output.
- Expanded release evidence with `456` Swift tests, required named regressions, AppKit RenderProbe coverage, Pretext golden checks, a clean local SwiftPM consumer build, DocC/symbol graph generation, and bundled macOS demo app smoke coverage.

## 0.5.1 - 2026-05-29

- Hardened display-math recovery for chat-style output where models omit blank lines around `\[ ... \]` blocks or upstream text has degraded the delimiters to bare `[` / `]` lines. The parser now splits paragraph-embedded standalone display math into source-backed text/math/text blocks, preserves reference-link resolution in adjacent text, and only treats bare bracket delimiters as math when the enclosed content is clearly TeX, leaving ordinary bracketed prose and reference labels as prose.

## 0.5.0 - 2026-05-29

- Added native LaTeX math rendering through `SiriusMarkdownMath`'s `NativeMarkdownMathRenderer`, backed by SwiftMath's CoreText typesetting. Display and inline equations render as real glyphs (Latin Modern Math) with no WebView, SVG rasterization, or network access. The dependency is linked only into `SiriusMarkdownMath` on iOS/macOS/visionOS; the core renderer stays dependency-free and pluggable.
- Extended math detection so `\[ ... \]` display delimiters, `\( ... \)` inline delimiters, and `\begin{...} ... \end{...}` environments are recognized alongside `$$ ... $$` and `$ ... $`. Detection stays source-preserving and does not rewrite code spans before `swift-markdown` parsing.
- Taught the streaming boundary scanner to treat an unclosed `\[` display block as an open fence so equations never seal mid-expression; streamed and whole-document parses stay equivalent across chunk sizes.
- Evolved `MarkdownMathRenderer` with `preparedMath(_:isBlock:fontSize:)` returning `MarkdownPreparedMath` (`.text` or typeset `.image`). The new method has a default that wraps the existing `renderedMath(_:isBlock:)`, so external conformers keep working without changes.
- Rendered typeset math blocks centered with horizontal-scroll overflow containment and theme-tinted template images; inline math composes natively with SwiftUI `Text` so it wraps with surrounding prose. Equation bitmaps are rasterized once during preparation and reused through the bounded math preparation cache.
- Added `MarkdownBlockRenderPlan.mathRendered`, `MarkdownPreparedBlockContent.mathRender`, `MarkdownPreparedMath`, `MarkdownPreparedMathImage`, and `MarkdownInlineMathPiece` to the public SwiftUI surface, and improved the math block accessibility label to include the LaTeX source.
- Fell back to plain text for streamed/partial LaTeX until it parses and seals, then typeset once; invalid LaTeX renders inertly as its source.
- Added a "Native LaTeX Math" showcase to the demo app and broadened Core/Math test coverage for delimiter detection, streaming equivalence, typeset output, caching, render plans, and inline composition.

## 0.4.21 - 2026-05-26

- Fixed streamed reference-style links so unresolved labels keep their region in the mutable tail, matching reference definitions allow sealing once safe, and later streamed regions can resolve links against definitions already sealed in earlier regions.
- Fixed streamed reference-definition carry-forward so raw `[label]: ...` text inside fenced code or HTML blocks is not treated as a global definition for later chunks. `swift-markdown` remains the semantic owner; streaming only reuses definitions that are safe to carry across sealed-region parse boundaries.
- Fixed literal unmatched `[` text in completed paragraphs no longer pinning the rest of a long stream in the mutable tail. Reference ambiguity is cleared at block boundaries while true unresolved reference labels still prevent early sealing.
- Fixed deprecated direct SwiftUI snapshot/block compatibility initializers so their unprepared path still enforces code, math, and HTML policies without doing code highlighting, math rendering, or full inline preparation synchronously.
- Included sealed reference-definition context in parser/cache namespaces so `swift-markdown` still owns link semantics while source offsets and stable block IDs remain valid for the parsed slice.
- Preserved nested inline presentation through links, including strong, emphasis, strikethrough, code, math, and image presentation metadata, instead of flattening linked children into a single plain run.
- Fixed structured child extraction inside block quotes and list items so nested code blocks, tables, lists, and loose-list paragraph breaks are represented in inline/list metadata instead of being silently dropped.
- Hardened the conservative boundary scanner for `1)` ordered-list markers, non-tag HTML blocks such as processing instructions, declarations, and CDATA, broader CommonMark HTML container tags, and reference-link ambiguity.
- Fixed stale queued append publication after `MarkdownRenderSession.reset()` so an old async append cannot overwrite the reset session's prepared snapshot.
- Updated the bundled demos to exercise reference-style links in the static workbench, streaming lab, and reader product surface before cutting the patch release.

## 0.4.20 - 2026-05-21

- Added source-line and source-range lookup helpers on `MarkdownSnapshot`, `MarkdownPreparedSnapshot`, and `MarkdownRenderSession` so host apps can resolve stable `MarkdownBlockID` scroll targets without open-coding block scans. Lookup is side-effect free and uses existing 1-based, half-open `MarkdownSourceRange.lineRange` semantics.
- Added `MarkdownSourceRevealPolicy` with `.exactOnly` and `.nearestRenderedBlock` fallback for blank-line gaps and ranges that start between rendered blocks. Preview-friendly defaults use nearest-block resolution for line and top-scroll target lookup.
- Added `MarkdownSelectionController.selectSourceLine(_:in:policy:)` and `selectSourceRange(_:in:policy:)` convenience over snapshots and prepared snapshots so preview reveal and highlight state stay package-owned.
- Documented that `ScrollViewReader.scrollTo` must use `MarkdownBlockID` (matching `MarkdownBlockView.id(block.id)`), not `MarkdownPreparedSnapshotRenderItem.id` `"block:<raw>"` ForEach strings. `StreamingMarkdownView` remains scroll-container agnostic; host apps own scrolling.
- Added Core, SwiftUI, and umbrella regression tests for CRLF input, multiline blocks, lists, code fences, tables, blank-line gaps, active-tail ID stability, session append/reset, and selection convenience.
- Tightened `selectSourceLine` to use coherent block-level selection ranges, added byte-offset nearest fallback when line metadata is empty, and aligned release metadata and DocC symbol links for `0.4.20`.

## 0.4.19 - 2026-05-21

- Hardened default document-selection geometry against host layout invalidation storms. Prepared native-line selection now caches per-line source geometry/fingerprints by prepared content and layout identity, so repeated parent invalidations or rect-only movement can still publish preferences without rebuilding rich text geometry.
- Added strict selection-performance diagnostics and SwiftUI/AppKit regression tests covering disabled-selection negative control, enabled-selection host layout storms, invalidation-count scaling, distinct-width cache invalidation, rect-only movement, and repeated same-rect preference resolution.

## 0.4.18 - 2026-05-20

- Fixed streaming fence sealing so code-fence closer candidates must have at most three leading spaces, enough matching backticks or tildes, and only whitespace after the marker run. Lines such as ` ``` not a closer` or four-space-indented marker content no longer seal a streamed code block early.
- Fixed source-backed document-selection highlights for styled inline Markdown. Prepared-line fragments now map visible offsets through source runs, so full-line selections over emphasis, strong, links, and other delimiter-backed runs keep the full Markdown source range while clipping highlight paint to the rendered glyph span.

## 0.4.17 - 2026-05-17

- Fixed a host-app transcript layout storm where a live sample spent the main thread under SwiftUI `GraphHost.flushTransactions`, `LayoutChildGeometries`, nested stack/flex-frame layout, and `ForEachState` while copying `MarkdownPreparedSnapshotItem` / `MarkdownBlockID` values during prepared Markdown rendering.
- Added lightweight `MarkdownPreparedSnapshotRenderItem` identities so `MarkdownDocumentView` and `StreamingMarkdownView` iterate small stable render records instead of using heavyweight prepared snapshot items as SwiftUI `ForEach` data.
- Reduced default document-selection preference churn by giving selection text geometry a cached equality fingerprint, so SwiftUI preference comparisons do not repeatedly walk prepared source/font-run arrays during layout.
- Fixed the document-selection Cmd-C AppKit bridge lifecycle by replacing the retained SwiftUI method closure with an explicit copy context and teardown hook, keeping `Tools/RenderProbe` stable with document selection still default-on.

## 0.4.16 - 2026-05-15

- Fixed document-selection highlight geometry so rendered text leaves emit prepared-line fragments, drag endpoints map through CoreText/string offsets, and partial-line highlights no longer paint list gutters, quote gutters, table containers, parent rows, or trailing blank row width as selected text.

## 0.4.15 - 2026-05-14

- Added default-on SiriusMarkdown document selection through `MarkdownRendererConfiguration.documentSelection`, with internal controller creation for `MarkdownDocumentView`, `StreamingMarkdownView`, and `MarkdownDocumentSurface` when hosts do not inject a `MarkdownSelectionController`.
- Extended `MarkdownSelectionController` with ordered source ranges and exact source-backed copy for whole-block, partial-line, contiguous multi-block, and deterministic non-contiguous selections. `nativeTextSelection` remains a separate disabled-by-default leaf compatibility knob.
- Fixed CRLF streaming boundary handling for blank lines, code fences, math fences, and HTML blocks, and added streamed-vs-static CRLF equivalence coverage.
- Denied protocol-relative `//host/path` links by default while preserving safe schemes, true relative links, and fragments.
- Fixed `MarkdownBlockView.renderPlan` to evaluate math and HTML policies once per render-plan call.
- Strengthened `Tools/release-check.sh` with required test discovery checks and a clean temporary SwiftPM consumer resolve/build against the local package path.

## 0.4.14 - 2026-05-13

- Fixed the `0.4.13` route-level selection gap where list rows, block quotes, and table cells still passed `.disabled` into their text leaves, making large structured Markdown previews effectively non-selectable even though the AppKit leaf implementation existed.
- Kept selection off the custom leading-layout and table-grid containers themselves, but now forwards `MarkdownRendererConfiguration.nativeTextSelection` to the bounded text leaves inside those composite structures.
- Added serialized AppKit SwiftUI tests that verify enabled selection reaches list, nested-list, quote, and table text leaves and that a hosted list `NSTextView` can select and copy through the real pasteboard path.

## 0.4.13 - 2026-05-13

- Replaced the macOS `.enabled` native-selection implementation with package-owned selectable AppKit text leaves, so SiriusMarkdown no longer mounts SwiftUI's private `SelectionOverlay` on macOS Markdown text during host view transitions.
- Kept the public `MarkdownRendererConfiguration(nativeTextSelection: .enabled)` API source-compatible while routing prepared inline text, fallback inline text, code, math/HTML, and policy-denial text through bounded non-editable `NSTextView` leaves on macOS.
- Extended tests and the AppKit render probe to prove `.textSelection(.enabled)` remains isolated to the non-macOS helper branch and that enabled-selection stress rendering actually mounts selectable AppKit text leaves.

## 0.4.12 - 2026-05-13

- Fixed the remaining native-selection hang path reproduced in a host-side Markdown preview pane. A live sample showed SwiftUI back in `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` -> AppKit `NSTextField` font invalidation with `MarkdownLeadingContentLayout` and prepared snapshot frames in the same graph.
- Kept `MarkdownRendererConfiguration(nativeTextSelection: .enabled)` available for stable Markdown text leaves, but prevents SwiftUI native selection from mounting inside custom leading layouts and composite table grids where the private selection overlay can re-enter layout.
- Filled prepared native-line separator and blank-line glyphs with explicit font attributes so selectable attributed payloads do not contain unowned font runs.

## 0.4.11 - 2026-05-13

- Fixed `MarkdownRendererConfiguration(nativeTextSelection: .enabled)` so SwiftUI native selection is mounted only on bounded Markdown text leaves instead of document, scroll, stack, table-row, toolbar, Mermaid-control, or host containers.
- Kept the public default `.disabled` for conservative package adoption while proving the opt-in path with an AppKit render-probe stress case covering streaming appends, width changes, tables, links, code, and prepared native lines.
- Strengthened static guards so the only direct `.textSelection(.enabled)` call remains inside the package-owned helper and renderer roots cannot reintroduce selection overlays.

## 0.4.10 - 2026-05-13

- Documented the SwiftUI native text-selection hang as unresolved rather than fixed. The current mitigation keeps `MarkdownRendererConfiguration.nativeTextSelection` defaulted to `.disabled` so SiriusMarkdown does not mount SwiftUI's private `SelectionOverlay` path by default.
- Added public doc and doc-comment breadcrumbs for future debugging: sample the host app and look for `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` -> `NSTextField setFont:` / `_invalidateEffectiveFont` if the hang returns.
- Clarified that this mitigation only controls SwiftUI's explicit native-selection overlay. Source-backed copy affordances, `MarkdownSelectionController`, and any host/AppKit selection behavior outside that overlay are separate.

## 0.4.9 - 2026-05-13

- Mitigated the follow-up host-app hang sample where root-scoping `.textSelection(.enabled)` was still enough to drive SwiftUI's private `SelectionOverlay.updateNSView` loop through AppKit `NSTextField` font and intrinsic-size invalidation.
- Changed `MarkdownRendererConfiguration.nativeTextSelection` to default to `.disabled`, keeping source-backed copy affordances and `MarkdownSelectionController` available without mounting SwiftUI's private selection overlay in host views.
- Kept `.enabled` as an explicit host opt-in for consumers that can tolerate SwiftUI's native selection overlay on their target macOS/runtime mix.
- Updated regression coverage so packaged presets and raw configurations use the safe selection policy by default while still proving the opt-in remains available.

## 0.4.8 - 2026-05-13

- Bounded the first observed host-app hang profile where the main thread spun in SwiftUI's private `SelectionOverlay.updateNSView` path and AppKit repeatedly invalidated `NSTextField` font/layout state while flushing `GraphHost` transactions.
- Kept native text selection enabled by default, but bounded the SwiftUI selection modifier to renderer roots (`MarkdownDocumentView`, `StreamingMarkdownView`, and `MarkdownDocumentSurface`) instead of attaching `.textSelection(.enabled)` to every paragraph, list item, table cell, code block, math block, HTML fallback, policy denial, and Mermaid ASCII fallback.
- Added `MarkdownNativeTextSelection` and `MarkdownRendererConfiguration.nativeTextSelection` so hosts can explicitly opt out where needed without changing the default selectable Markdown behavior.
- Added regression coverage that rejects per-block selection modifiers and proves the renderer roots remain the only SwiftUI native-selection activation points.

## 0.4.7 - 2026-05-08

- Added prepared Mermaid SVG geometry to `MarkdownPreparedMermaidDiagram` with public `MarkdownMermaidDiagramGeometry` and `MarkdownMermaidViewBox` types. Geometry is extracted during Mermaid preparation from root SVG dimensions or viewBox data, so SwiftUI does not parse SVG from `body`.
- Added `MarkdownMermaidDiagramAffordances` and `MarkdownTheme.mermaidAffordances` so package-owned Mermaid controls can be tuned by hosts. The compact chat preset caps Mermaid viewport height lower, while the document preset allows taller diagram surfaces.
- Replaced the inline Mermaid image branch with a dedicated bounded pan/zoom diagram view. SVG diagrams now render in a two-axis scroll viewport with zoom out, zoom in, fit, and reset controls, while ASCII fallback remains deterministic when SVG is unavailable or image decoding fails.
- Kept Mermaid rendering on the existing bundled JavaScriptCore preparation path. This release does not replace `beautiful-mermaid`, does not add WebKit, and does not introduce a new Mermaid semantic engine.
- Hardened prepared SVG output by stripping root-level Google-font imports, resolving light/dark CSS variables, and forcing local Apple/system font fallback before AppKit/UIKit image decoding.
- Expanded unit and product coverage for Mermaid geometry parsing, cache reuse, render-plan controls, affordance opt-out, and nil-renderer fallback, and added an AppKit render probe for Mermaid diagram containment and toolbar pixels.
- Hid decorative SF Symbol images inside package-owned Markdown affordance buttons from accessibility synthesis while preserving each button's explicit accessibility label and help text. This avoids forcing SwiftUI/AppKit to localize symbol descriptions for copy/export/collapse and Mermaid zoom controls during host updates.
- Fixed a host-app hang profile dominated by SwiftUI `GraphHost` layout, `LayoutChildGeometries`, `StackLayout`, and `_FlexFrameLayout` while rendering prepared native lines. The renderer now joins prepared attributed line slices into one fixed-height `Text(AttributedString)` payload instead of building a `VStack`/`ForEach` child tree with one `Text` per prepared line, preserving the prepared-line contract while reducing SwiftUI layout work.
- Debounced Mermaid diagram width preference updates so unchanged geometry does not trigger redundant SwiftUI state writes during layout passes.

## 0.4.6 - 2026-05-06

- Fixed prepared native-line clipping where CoreText line measurement and SwiftUI `Text(AttributedString)` painting could drift by a few pixels, causing the final glyph of transcript-style inline code to be sheared by the containment clip.
- Native prepared lines now apply explicit per-run SwiftUI font attributes derived from the same `MarkdownInlineFontProfiles` used for CoreText measurement, including body, emphasis, strong, inline code, math, and image placeholder runs.
- Aligned system monospaced CoreText measurement with SwiftUI's system-monospaced rendering intent instead of hard-coding Menlo for `.monospacedSystem`.
- Replaced the fixed native-line safety inset with a font-scaled paint guard used during prepared layout, preserving clipping as containment instead of normal fit behavior.
- Prepared native-line views now size their rendered surface from the offered parent width and computed line height before overlaying native text, preventing stale wide line frames from polluting later width reads during host resizing.
- Added screenshot-shaped transcript command regressions for line layout, actual AppKit-hosted line width, width-narrowing relayout reuse, and a rendered bitmap resize check that catches visible right-edge clipping.

## 0.4.5 - 2026-05-04

- Fixed stale prepared-inline layout reuse when SwiftUI kept a view alive at the same width but swapped in different prepared content. `PreparedInlineTextView` now invalidates its cached layout when the prepared payload identity changes, so the first visible pass no longer depends on a later resize to recompute line layout.
- Fixed `MarkdownDemoApp` and `StreamingTranscriptDemo` case switching to reset the rendered document/stream subtree identity when the selected example changes, preventing stale SwiftUI subtree reuse across different prepared documents or stream cases.
- Fixed task-list checkbox alignment in the shared SwiftUI renderer by sizing task markers from paragraph metrics and placing them inside a paragraph line-height box, so checklist rows align consistently with the first text line in document-style rendering.
- Expanded SwiftUI regression coverage for the initial-layout bug class with hosted AppKit tests that verify first-pass paragraph visibility and prepared-inline recomputation when prepared content changes at a fixed width.

## 0.4.4 - 2026-05-04

- Fixed Mermaid SVG rendering failing in JavaScriptCore by shimming `self`, `window`, `global`, `setTimeout`, and `clearTimeout` onto `globalThis` before the bundled `beautiful-mermaid` runtime evaluates. The ELK layout engine embedded in the bundle resolves its global-object reference (`A`) from `window`, `global`, or `self`; none of these exist in bare JavaScriptCore, so `A.Math.max(...)` crashed with a `TypeError`. ASCII rendering was unaffected because it uses its own layout engine.
- Added SVG output to `DefaultMarkdownMermaidRenderer`: `MarkdownPreparedMermaidDiagram.svg` is now populated alongside the existing ASCII representation when the bundled runtime succeeds. The SVG render function is loaded and cached alongside the ASCII function, so both results are produced in a single runtime initialization.
- Hardened the JavaScriptCore environment shim with `Error.stackTraceLimit` lockdown and a relaxed `Buffer.toString()` signature to match the bundle's actual calling convention.
- Fixed a JavaScriptCore crash (`EXC_BAD_ACCESS` in `JSRopeString::resolveToBuffer`) caused by the highlight and mermaid runtimes sharing the default JSC VM group. Under concurrent Swift Testing execution, both runtimes' `JSGlobalContextCreate(nil)` calls placed their contexts in the same VM, and simultaneous JS evaluation from different threads corrupted internal rope-string state. Both runtimes now create an isolated `JSContextGroupRef` with `JSContextGroupCreate()` and use `JSGlobalContextCreateInGroup` to prevent cross-runtime VM contention.
- Fixed `MarkdownBlockView` rendering Mermaid diagrams as ASCII box-drawing text instead of SVG. The block view now renders `MarkdownPreparedMermaidDiagram.svg` as a native platform image (`NSImage` on macOS, `UIImage` on iOS) when SVG output is available, with ASCII as the fallback when SVG is absent.
- Fixed Mermaid SVG visibility on dark SwiftUI/AppKit surfaces by resolving SVG CSS variables into concrete light and dark color palettes during render preparation. `MarkdownPreparedMermaidDiagram` now carries `svg` and `darkSVG`, and `MarkdownBlockView` selects the correct prepared variant from `colorScheme` without reparsing or rerendering Mermaid in `body`.
- Fixed small Mermaid diagrams being visually blown up inside transcript/code blocks by rendering SVG platform images at intrinsic size inside horizontal overflow containment instead of making every diagram resizable-to-fill.

## 0.4.3 - 2026-05-03

- Added built-in Mermaid fence rendering through a bundled DOM-free JavaScript runtime executed with JavaScriptCore, keeping diagram preparation out of SwiftUI `body`.
- Added deterministic Mermaid fallback behavior: hosts can disable Mermaid rendering through `MarkdownRendererConfiguration(mermaidRenderer: nil)`, and failed Mermaid preparation falls back to plain code blocks.
- Added Mermaid preparation caching, diagnostics counters, native SwiftUI rendering coverage, and product/unit tests for default rendering, opt-out behavior, and cache reuse.

## 0.4.2 - 2026-05-03

- Fixed prepared native-line containment for transcript-style inline code paths, shell commands, URLs, long identifiers, nested lists, block quotes, and table cells so visible prepared-line layout stays within the effective host column.
- Added package-owned transcript/path wrapping fixtures and a vendored MIT `linebreak` UAX #14 JavaScript oracle for Pretext golden validation, avoiding local-machine or private-project path data in public fixtures.
- Added focused Swift tests and an AppKit transcript-wrapping render probe that reject overwide fitting widths and right-edge overflow for compact transcript content.

## 0.4.1 - 2026-05-03

- Added controlled-collapse overloads for `MarkdownDocumentSurface`, letting host apps bind document collapse state and observe collapse changes while preserving the existing local-state initializers.

## 0.4.0 - 2026-05-03

- Added `MarkdownDocumentSurface`, `MarkdownDocumentAffordances`, `MarkdownAffordanceActionHandler`, and full-document `MarkdownCopyProvider` support so static document surfaces can show generic copy, export, and collapse chrome without app-private concepts.
- Expanded `MarkdownCodeBlockAffordances` with export and collapse controls while keeping language labels and copy-code behavior configurable through `MarkdownTheme`.
- Added render-plan tests and an AppKit render probe for document-affordance chrome, including collapsed document state preserving prepared snapshot identity.
- Added shared `Examples/DemoSupport` UI components and reworked the bundled demos into clearer product surfaces: renderer workbench, reader flagship, and streaming lab.
- Centralized affordance SF Symbol rendering around `square.on.square`, `square.and.arrow.down.on.square`, and chevron collapse/expand icons so document and code chrome share optical alignment.

## 0.3.3 - 2026-05-02

- Fixed prepared native-line width observation so split-view and side-panel resizing relayouts against the current proposed width instead of a stale rendered line frame.
- Added an AppKit wide-to-narrow resize probe that keeps the SwiftUI view alive while shrinking the host column, then asserts prepared native text stays inside the new column and fitting width remains bounded.

## 0.3.2 - 2026-05-02

- Corrected the MIT license copyright holder from generic project-contributor boilerplate to `Dr. Mikholae Hutchinson`.

## 0.3.1 - 2026-05-02

- Semver: patch release on top of `v0.3.0`, adding public code-block affordance controls without changing the renderer architecture or SwiftPM platform floor.
- Added `MarkdownCodeBlockAffordances` and `MarkdownTheme.codeBlockAffordances` so hosts can show or hide the generic code language label and copy-code button.
- Added normalized code-language display names for common fence aliases such as `language-swift`, `py`, `js`, `ts`, `objective-c`, and `c++`, while preserving conservative plain rendering for plaintext, nohighlight, unlabeled, and unsupported fences.
- Added native SwiftUI code-block chrome for language labels and copy-code actions above horizontally contained code blocks.
- Expanded render-plan and SwiftUI tests to prove code-language labels, copy visibility, copy text extraction, disabled chrome, and policy-denied code paths.

## v0.3.0 - 2026-05-02

- Semver: minor release, not `v0.2.1`, because this adds public renderer theme API (`MarkdownTextStyle`, `MarkdownHeadingStyles`, `MarkdownTheme.headings`) and deprecates the old singular H3-only compatibility fields.
- Added first-class H1-H6 heading typography to `MarkdownTheme` so visual SwiftUI fonts and CoreText measurement inputs resolve from the same `MarkdownTextStyle` source for every Markdown heading level.
- Replaced hardcoded H1/H2/H4-H6 visual fonts and prepared-line metrics with per-level `MarkdownHeadingStyles` lookup, keeping prepared-inline cache identity tied to resolved `fontSize`, `lineHeight`, and `fontProfiles`.
- Kept `headingFont`, `headingFontSize`, `headingLineHeight`, and `headingFontProfiles` as deprecated H3 compatibility aliases while documenting `MarkdownTheme.headings` as the general-purpose API.
- Added H1-H6 renderer-preparation contract tests, hardcoded-metric regression tests, heading cache-separation coverage, and a uniform compact-heading consumer-style test.

## v0.2.0 - 2026-05-02

- Replaced the default generic lexical code tokenizer with `DefaultMarkdownCodeHighlighter`, a language-aware highlighter backed by a pinned embedded `highlight.js` 11.11.1 common bundle through a synchronous JavaScriptCore wrapper on supported Apple platforms.
- Added `MarkdownCodeLanguage`, `MarkdownCodeHighlighterCacheIdentifying`, and `MarkdownSyntaxHighlightingPalette` so fence info strings are normalized, highlighter cache identities are stable, and syntax token colors belong to the theme.
- Updated code-block preparation to cache highlighted output by source hash, normalized language, theme palette identity, and highlighter identity while keeping all highlighting in render preparation.
- Made the default highlighter conservative: explicit supported languages are highlighted, while unsupported, plaintext, nohighlight, and unlabeled fences render as plain monospaced code instead of misleading lexical color.
- Added tests and product fixtures for alias normalization, supported-language semantic attributes, unsupported/plain fallback behavior, cache invalidation, width relayout reuse, and Swift/JSON/shell/YAML/diff/Markdown/plaintext/unsupported fences.
- Expanded the render probe and product gate with a code-highlighting document that verifies language-aware color variation and plain rendering for diagnostic/non-code fences.

## v0.1.1 and earlier

- Created the SiriusMarkdown package scaffold as a public MIT Swift package.
- Established the renderer plan and contributor guardrails for the project architecture.
- Added initial core source-buffer, streaming, parser, model, policy, cache, diagnostics, inline-layout, SwiftUI-renderer, and Pretext-support surfaces.
- Added a working Pretext golden smoke harness backed by `@chenglou/pretext` and a Node canvas shim.
- Expanded Swift coverage to 167 runner-counted tests plus parameterized edge cases for streaming equivalence, stable block IDs, source byte/line maps, conservative and incremental boundary scanning, block and inline classification, structured AST conversion, policy handling, cache eviction, diagnostics, renderer behavior, prepared snapshots, large-transcript prepared item identity, repeated preparation cache reuse, source-backed copy, umbrella import ergonomics, strict Pretext fixture drift, CoreText-vs-Pretext font-profile measurement, and deterministic inline layout.
- Fixed stable block identity so active-tail block IDs survive sealing.
- Fixed conservative boundary scanning so a single trailing newline does not seal a block or split multi-line blockquotes during streaming.
- Reworked parsing so `swift-markdown` owns Markdown semantics and the package converts the AST into the public render model.
- Added structured render-model data for task/list items, nested list items, ordered-list starts, table cells, table column alignments, and deterministic block content hashes.
- Switched source slices to segment-backed storage and made the boundary scanner iterate source lines without copying the full tail.
- Switched inline layout to a Pretext-shaped prepare/layout split with cached measured segments and cheap width-change layout.
- Removed SwiftUI-owned inline fragment measurement from `InlineRunsView`; inline rendering now consumes runs as one attributed payload with policy-gated links/images.
- Added structured SwiftUI render paths for lists, task lists, tables, code blocks, math blocks, and HTML blocks.
- Tightened default link/image policy and added a protocol-driven renderer configuration surface for links, images, HTML, code, math, code highlighting, and math rendering.
- Integrated parser, prepared-inline, measured-inline, and layout caches with diagnostics counters instead of leaving cache/counter types as passive scaffolding.
- Moved SwiftUI code highlighting and math rendering into explicit prepared block content with bounded reuse through `MarkdownRenderPreparationCache`, so `MarkdownBlockView.body` consumes prepared output.
- Added a real `SiriusMarkdown` umbrella target that re-exports Core and SwiftUI, plus a consumer-facing import test and DocC links for the app-facing module.
- Replaced the static-document demo placeholder with a buildable SwiftPM SwiftUI demo that imports the public `SiriusMarkdown` product.
- Added incremental active-tail boundary scanning, source-backed copy slices, prepared snapshots, host-boundary rendering hooks, broader diagnostics/signposts, lazy overwide inline fallback measurement, expanded Pretext fixtures, and buildable streaming/document reader demos.
- Added meaningful headless renderer contract tests in place of fragile default-suite AppKit bitmap snapshots, covering representative documents, large streaming transcripts, prepared identity stability, and render-preparation cache reuse.
- Count highlighted-code and rendered-math cache hits/misses in `MarkdownDiagnosticsRecorder` so repeated preparation proves cache reuse through counters, not only through highlighter/renderer call counts.
- Updated README, DocC, architecture, streaming, performance, and runbook documentation to make prepared snapshots the primary integration path and to describe the renderer/performance verification contract.
- Tightened the Pretext Swift fixture comparison so emoji/CJK, multilingual, and RTL drift now fails the test suite instead of being treated as a passing known issue.
- Fixed the native inline measurer so strict Pretext fixtures for emoji/CJK, multilingual, RTL, and long overwide words pass without fixture allowlists.
- Stopped renderer preparation from eagerly populating per-character inline unit measurements, added a view-time layout mode that refuses overwide measurement fallback, and added tests for both paths.
- Fixed boundary scanning for incomplete active-tail lines so repeated appends without a newline do not rescan the same unfinished line.
- Made `BoundedMarkdownCache` update recency on cache hits and added a real least-recently-used eviction assertion.
- Restored native pixel coverage for representative structured documents through `Tools/RenderProbe`, which renders `MarkdownDocumentView` through AppKit in its own release-gated process.
- Added `Tools/release-check.sh` and made CI call the same release gate used locally.
- Made CI's Pretext golden step clean-checkout safe with `npm ci`.
- Differentiated `DocumentReaderDemo` from the renderer workbench by turning it into a reader product surface with document metadata, outline navigation, reading-width controls, full-source copy, reader-specific sample content, and no visible pipeline counters.
- Added renderer-level table presentation tokens to `MarkdownTheme` and redesigned SwiftUI table rendering around prepared cell measurements, bounded adaptive columns, header/accent styling, row separators, and subtle banding.
- Stopped `StreamingTranscriptDemo` from publishing renderer configuration changes, avoiding unnecessary Combine copies during macOS window startup while still refreshing prepared snapshots through the model.
- Redesigned `MarkdownDemoApp` into a sidebar-driven static-document workbench with renderer coverage metrics, pipeline counters, and expanded examples for inline policy, tables, wide blocks, multilingual layout, math/HTML policy, and long-form documents.
- Added `MarkdownRenderSession` as the public streaming/document integration seam that owns stream state, long-lived renderer configuration, source-backed copy, prepared snapshots, caches, and diagnostics counters.
- Replaced SwiftUI's newline-injected prepared-inline render path with native `Text(AttributedString)` rendering while still consuming prepared `InlineLayoutResult` records for width-change diagnostics and layout reuse.
- Added `MarkdownInlineRenderingMode.preparedNativeLines`, which renders prepared attributed line slices through SwiftUI `Text(AttributedString)` and is guarded by a representative document render probe plus a word-spacing check. This is prepared-line rendering, not a fully custom glyph renderer.
- Added bounded `MarkdownSelectionController` support for block-level selection, source-backed Markdown copy, plain-text copy, and selection rendering without per-fragment overlay growth.
- Added source-preserving inline math detection outside code spans/fences, prepared image decisions with placeholder-safe defaults, a theme-aware default code highlighter, and an optional `SiriusMarkdownMath` product used by the demos.
- Added `Docs/native-renderer-scorecard.md` and `Tools/product-check.sh` to make native-renderer product quality a gate instead of a claim.
- Expanded Pretext from a nine-fixture seed to a required 25-group product corpus covering paragraph width profiles, semantic inline runs, autolinks, inline code, inline math, image placeholders, CJK, RTL, emoji, mixed scripts, combining marks, hard breaks, soft wraps, long words, punctuation/trailing whitespace, heading/code font profiles, and list/table cell inline content.
- Promoted packaged chat and document presets to `MarkdownInlineRenderingMode.preparedNativeLines` while keeping direct custom configurations on `.systemText` for compatibility.
- Expanded `Tools/RenderProbe` to cover compact chat, multilingual text, inline attributes crossing lines, code/table overflow, hard breaks, long words, width reach, color variation, and collapsed word-spacing checks.
- Added large-product stress surfaces to the demos: a generated big cached document in `MarkdownDemoApp`, a generated very-long streaming document with burst controls in `StreamingTranscriptDemo`, and a generated cached appendix in `DocumentReaderDemo`.
