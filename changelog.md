# Changelog

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

- Fixed a Sirius transcript layout storm where a live sample of the host app spent the main thread under SwiftUI `GraphHost.flushTransactions`, `LayoutChildGeometries`, nested stack/flex-frame layout, and `ForEachState` while copying `MarkdownPreparedSnapshotItem` / `MarkdownBlockID` values during prepared Markdown rendering.
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

- Fixed the remaining native-selection hang path reproduced in Sirius' right-panel DiffTree Markdown preview. A live sample showed SwiftUI back in `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` -> AppKit `NSTextField` font invalidation with `MarkdownLeadingContentLayout` and prepared snapshot frames in the same graph.
- Kept `MarkdownRendererConfiguration(nativeTextSelection: .enabled)` available for stable Markdown text leaves, but prevents SwiftUI native selection from mounting inside custom leading layouts and composite table grids where the private selection overlay can re-enter layout.
- Filled prepared native-line separator and blank-line glyphs with explicit font attributes so selectable attributed payloads do not contain unowned font runs.

## 0.4.11 - 2026-05-13

- Fixed `MarkdownRendererConfiguration(nativeTextSelection: .enabled)` so SwiftUI native selection is mounted only on bounded Markdown text leaves instead of document, scroll, stack, table-row, toolbar, Mermaid-control, or host containers.
- Kept the public default `.disabled` for conservative package adoption while proving the opt-in path with an AppKit render-probe stress case covering streaming appends, width changes, tables, links, code, and prepared native lines.
- Strengthened static guards so the only direct `.textSelection(.enabled)` call remains inside the package-owned helper and renderer roots cannot reintroduce selection overlays.

## 0.4.10 - 2026-05-13

- Documented the SwiftUI native text-selection hang as unresolved rather than fixed. The current mitigation keeps `MarkdownRendererConfiguration.nativeTextSelection` defaulted to `.disabled` so SiriusMarkdown does not mount SwiftUI's private `SelectionOverlay` path by default.
- Added public doc and doc-comment breadcrumbs for future debugging: sample Sirius and look for `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` -> `NSTextField setFont:` / `_invalidateEffectiveFont` if the hang returns.
- Clarified that this mitigation only controls SwiftUI's explicit native-selection overlay. Source-backed copy affordances, `MarkdownSelectionController`, and any host/AppKit selection behavior outside that overlay are separate.

## 0.4.9 - 2026-05-13

- Mitigated the follow-up Sirius hang sample where root-scoping `.textSelection(.enabled)` was still enough to drive SwiftUI's private `SelectionOverlay.updateNSView` loop through AppKit `NSTextField` font and intrinsic-size invalidation.
- Changed `MarkdownRendererConfiguration.nativeTextSelection` to default to `.disabled`, keeping source-backed copy affordances and `MarkdownSelectionController` available without mounting SwiftUI's private selection overlay in host views.
- Kept `.enabled` as an explicit host opt-in for consumers that can tolerate SwiftUI's native selection overlay on their target macOS/runtime mix.
- Updated regression coverage so packaged presets and raw configurations use the safe selection policy by default while still proving the opt-in remains available.

## 0.4.8 - 2026-05-13

- Bounded the first observed Sirius host hang profile where the main thread spun in SwiftUI's private `SelectionOverlay.updateNSView` path and AppKit repeatedly invalidated `NSTextField` font/layout state while flushing `GraphHost` transactions.
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
- Fixed a Sirius host hang profile dominated by SwiftUI `GraphHost` layout, `LayoutChildGeometries`, `StackLayout`, and `_FlexFrameLayout` while rendering prepared native lines. The renderer now joins prepared attributed line slices into one fixed-height `Text(AttributedString)` payload instead of building a `VStack`/`ForEach` child tree with one `Text` per prepared line, preserving the prepared-line contract while reducing SwiftUI layout work.
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

- Fixed prepared native-line width observation so split-view and right-panel resizing relayouts against the current proposed width instead of a stale rendered line frame.
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
