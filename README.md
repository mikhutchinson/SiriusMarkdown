# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple
platforms. It is built for chat transcripts and documents that are long,
streamed, repeatedly resized, and still need stable copy, selection, links,
tables, code, math, and host-native insertions.

The core contract is simple:

- `swift-markdown` owns Markdown semantics.
- Streaming input is immutable sealed regions plus one mutable tail.
- SwiftUI consumes prepared snapshots; it does not parse, highlight, or measure
  raw Markdown from `body`.
- CoreText owns native glyph measurement, and the default inline renderer paints
  prepared lines with CoreText.
- No WebKit renderer, no row-hosted WebViews, and no unbounded per-fragment
  overlays are part of the package path.

## Current Release

`0.6.16` fixes a JavaScriptCore lifetime violation that could crash a host
during long streamed code fences without reducing the renderer's feature surface.
Markdown semantics, tables, highlighting, math, Mermaid, links, attachments,
copy, and source-backed document selection remain enabled:

- **GC-safe JavaScript bridges:** retained functions, heap-stored arguments,
  and call results stay rooted for their complete native lifetime in both the
  Highlight.js and Mermaid runtimes. Deterministic tests force collection at
  each bridge boundary.
- **Bounded streaming regions:** the SwiftUI streaming surface groups stable
  prepared items into bounded regions, caches each sealed region's size for a
  proposal width and revision, and invalidates only the mutable tail region.
  It does not rely on `LazyVStack`'s private item-phase cache and does not
  eagerly remeasure every prior block after an append.
- **Mutable work stays mutable:** active tail blocks bypass caches intended for
  sealed values, so successive generations cannot evict stable prepared
  content or accumulate historical tail values.
- **Context-correct incremental highlighting:** plain and Highlight.js-backed
  languages process appended suffixes while a code block is active. The pinned
  Highlight.js parser continuation preserves open comment/string state; a
  full-context checkpoint runs every 16 KiB and every block is fully
  highlighted on seal. The native Swift and custom highlighters retain
  full-document semantics where no proven continuation is available.
- **Shared bounded CoreText measurements:** unchanged inline tokens reuse
  width measurements across preparation values with keys that include the
  complete font and presentation profile.
- **Measured regression:** a 179 KB document across 90 AppKit-hosted
  publications keeps mutable-tail layout at a 2.71 ms median, and the full
  release suite discovers 883 tests.

The release builds on `0.6.14`'s strict-concurrency-clean detached render pump,
`0.6.13`'s linear source mapping, `0.6.12`'s constant-time
selection/layout cache hits, and `0.6.11`'s AppKit leaf stability:

- **Linear AST source mapping:** each `swift-markdown` parse boundary builds
  one UTF-8 line-start index. Block, table-cell, and inline source locations
  resolve through that index instead of rescanning from byte zero per AST
  node, removing quadratic conversion for large mutable-tail tables.
- **Preparation stays off MainActor:** `MarkdownRenderSession` starts its
  parse/highlight/prepare pump from a detached user-initiated task. Only the
  operation drain and prepared-snapshot publication hop to MainActor.
- **Measured regression:** 8x more generated table rows now takes 8.02x parse
  time (25.63 ms for 120 rows; 205.62 ms for 960 rows). The restored pre-fix
  path did not complete the same gate after 30 seconds.

- **No content scan on a cache hit:** prepared, measured, and laid-out inline
  values carry deterministic two-lane fingerprints computed at their mutation
  boundary. SwiftUI view identity and layout/selection caches combine those
  fixed-size values instead of rehashing full text, runs, units, and line
  arrays during layout.
- **Frame-budget regression:** a release-mode AppKit-hosted 1,300-line code
  block settles at a 0.418 ms median invalidation, with a hard 16 ms gate.

- **No rebuild per layout proposal:** AppKit leaves apply their attributed
  source once per content/environment change and cache measured sizes per
  proposed width, so long list/quote documents no longer compound SwiftUI
  size negotiation into multi-second main-thread stalls.
- **Constraint-safe attachment hosts:** attachment host subviews mutate only
  in `layout()`, never inside `sizeThatFits`, avoiding AppKit's re-entrant
  `updateConstraints` crash guard.
- **Correct CoreText color contract:** Prepared `CTLine` objects opt into the
  CGContext foreground, so source-backed document-selection mode paints
  readable semantic text in both light and dark appearances.
- **Appearance-aware native bridges:** AppKit/UIKit CoreText, AppKit selectable
  text and math fallbacks, and attachment placeholder layers resolve semantic
  colors under the active SwiftUI scheme.
- **Native selection preserved:** Bounded noneditable `NSTextView` leaves
  remain the default macOS selection, wrapping, copy, keyboard, and contextual
  menu path.
- **Cached-plan stability:** Appearance changes update native colors in place
  without reparsing, repreparing, or rebuilding cached CoreText line plans,
  including long streaming transcripts.

The release retains the measured streaming path from `0.6.0`: CTLine creation
runs during prepare, append-only sessions reuse sealed prepared content, the
opt-in source-backed selector spans every structured block type, and focused
performance tests enforce the long-transcript budgets.

On macOS, bounded noneditable `NSTextView` leaves now own selection, wrapping,
copy, keyboard behavior, and the standard AppKit contextual menu by default.
They copy continuous prose without synthetic newlines at visual wraps. The
source-backed cross-block selector remains available by setting
`documentSelection = .enabled`, which disables native leaf selection to avoid
competing selection owners. Other platforms retain the source-backed default.
`preparedNativeLines` and `systemText` remain explicit rendering fallbacks.

## Requirements

- Swift 6.0
- macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Install

```swift
dependencies: [
    .package(url: "https://github.com/mikhutchinson/SiriusMarkdown.git", from: "0.6.16")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SiriusMarkdown", package: "SiriusMarkdown")
        ]
    )
]
```

Use the narrower products when needed:

- `SiriusMarkdownCore`
- `SiriusMarkdownSwiftUI`
- `SiriusMarkdownMath`
- `SiriusMarkdownPretextSupport`

Third-party credits are in `NOTICE.md`.

## Quick Start

For streaming/chat surfaces, keep a `MarkdownRenderSession` in your model layer.
It owns the stream, configuration, caches, copy provider, prepared snapshot, and
diagnostics counters.

```swift
import SiriusMarkdown

@MainActor
final class TranscriptModel: ObservableObject {
    @Published var session = MarkdownRenderSession(configuration: .compactChat)

    func append(_ chunk: String) {
        session.append(chunk)
    }
}

StreamingMarkdownView(
    preparedSnapshot: model.session.preparedSnapshot,
    configuration: model.session.configuration
)
```

For static documents, prepare before handing data to SwiftUI:

```swift
var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: stream.snapshot())

MarkdownDocumentView(
    preparedSnapshot: prepared,
    configuration: configuration
)
```

The direct `snapshot:` view initializers are deprecated compatibility shims for
small surfaces. Production paths should pass `MarkdownPreparedSnapshot`.

## What Ships

- Native structured renderers for paragraphs, headings, block quotes, thematic
  breaks, nested lists, task lists, fenced code blocks, tables, links, images,
  math, and policy-denied HTML.
- Streaming append behavior that reparses only the mutable tail while sealed
  regions remain immutable and cacheable.
- Platform-native bounded text selection on macOS, including image-backed inline
  math through TextKit attachments, with the source-backed cross-block selector
  available explicitly for exact Markdown copy through
  `MarkdownSelectionController` and `MarkdownCopyProvider`. Other platforms keep
  source-backed document selection as their default.
- Bounded parser, prepared-inline, measured-layout, highlighted-code, Mermaid,
  and math caches.
- Safe default policies: links are scheme-gated, network images are not fetched
  by default, raw HTML is inert unless a host opts in, and math/code renderers
  are pluggable.
- Allowed images flow as atomic inline attachments — reserved box metrics
  (theme default or a cheap header probe of already-available bytes) on the
  CoreText line plan, with one SwiftUI/AppKit/UIKit host per attachment
  drawing the reserved box or resolved pixels. Denied images (the default)
  keep today's alt/`[image: reason]` text. Hosts can supply bytes
  synchronously through `MarkdownImageResolver`; SiriusMarkdown performs no
  network fetch, ImageIO probe beyond a cheap header read, or decode inside
  SwiftUI `body`. Remote fetch and multi-frame animation are separate,
  independently opt-in capabilities layered on top of these attachment
  slots — this package alone does not claim either.
- Language-aware default code highlighting where the backend is available, with
  plain rendering for plaintext, nohighlight, unlabeled, unsupported, or failed
  fences.
- Package-owned Mermaid preparation through JavaScriptCore with deterministic
  ASCII plus light/dark SVG output. Mermaid remains prepared SVG/ASCII, not a
  WebKit surface and not a second Markdown semantic engine.
- Optional native LaTeX math through `SiriusMarkdownMath`, backed by the
  vendored SwiftMath target and CoreText typesetting. Inline math aligns to the
  text baseline using display-list ascent/descent from
  `MTMathImage.LayoutInfo`, block math rasterizes at the screen's backing scale
  for sharp glyphs, and streaming math falls back to text until sealed. Host
  apps must ship `SiriusMarkdown_SwiftMath.bundle` under `Contents/Resources`.
  The core renderer stays pluggable.

## Customization

`MarkdownTheme` owns typography, colors, and metrics. `MarkdownDocumentStyle`
and its fourteen per-block style protocols (heading, paragraph, block quote,
code block, table, table cell, list item, unordered/ordered/task markers,
thematic break, math block, HTML block, Mermaid block) own chrome — borders,
backgrounds, dividers, and marker glyphs around already-prepared content.
Every protocol ships a `MarkdownDefault*Style` that reproduces the built-in
look, so restyling one block never requires forking `MarkdownBlockView`:

```swift
struct UnderlineH1: MarkdownHeadingBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
            if configuration.headingLevel == 1 {
                Divider()
            }
        }
    }
}

MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
    .markdown.headingStyle(UnderlineH1())
```

Per-block `.markdown.<slot>Style(_:)` overrides always win over an aggregate
`.markdown.documentStyle(_:)`, which in turn wins over
`MarkdownRendererConfiguration.documentStyle`, which falls back to
`MarkdownDefault*Style` — regardless of modifier order. Style resolution
never reparses Markdown, never changes prepare/layout cache identity, and
never churns sealed block IDs.

An opt-in, GitHub-inspired preset pairs a matching theme with matching chrome:

```swift
MarkdownDocumentView(preparedSnapshot: prepared, configuration: .gitHub)
```

`MarkdownRendererConfiguration.gitHub` approximates common README
rendering — semibold headings with H1/H2 divider rules, a bordered
block-quote bar, denser code padding, and hierarchical unordered markers. It
is not a pixel match for github.com's CSS, and it is never the default;
`.compactChat` and `.document` are unaffected.

## CoreText Inline Rendering

Inline work follows the Pretext-style split:

1. Prepare once: normalize inline runs, apply policies, build attributed payloads,
   measure segments, compute natural width, build CTLine plans, and cache prepared
   content.
2. Layout cheaply: consume prepared measurements for a container width and
   produce line ranges without reparsing or remeasuring from raw Markdown.
3. Paint: the default mode draws each prepared line with CoreText on supported
   AppKit/UIKit platforms. CTLine creation runs in prepare, not in the SwiftUI
   update path.

New blocks render content on first appearance without waiting for a width
preference pass. Width changes adjust line breaks through the cheap `layout()`
path only.

If a platform cannot host the CoreText paint bridge, the renderer falls back to
prepared native text without changing parser, policy, or wrapping authority.
watchOS compiles through that fallback path.

## Source Navigation

SiriusMarkdown can resolve source lines and source ranges back to stable
`MarkdownBlockID` values. Host apps own scrolling for `StreamingMarkdownView`;
`MarkdownDocumentView` owns its internal scroll surface.

```swift
if let blockID = session.blockID(containingSourceLine: line) {
    selectionController.selectSourceLine(line, in: session.preparedSnapshot)
    proxy.scrollTo(blockID, anchor: .top)
}
```

Use `MarkdownSourceRevealPolicy.exactOnly` for strict line containment or
`.nearestRenderedBlock` to resolve blank-line gaps to the nearest useful block.

## Products

| Product | Role |
| --- | --- |
| `SiriusMarkdown` | Umbrella import for Core + SwiftUI |
| `SiriusMarkdownCore` | Source storage, streaming, parser adapter, model, inline layout, policies, caches, diagnostics |
| `SiriusMarkdownSwiftUI` | Views, themes, renderer configuration, document selection, copy/export actions, platform hooks |
| `SiriusMarkdownMath` | Optional native math renderer |
| `SiriusMarkdownPretextSupport` | Pretext fixture schema and golden comparison helpers |

## Demos

Build the macOS demo apps with:

```sh
Examples/scripts/bundle-macos-demos.sh
```

The bundled demos are:

- `MarkdownDemoApp`: renderer workbench and stress cases.
- `DocumentReaderDemo`: static reader surface with document actions.
- `StreamingTranscriptDemo`: live compact-chat streaming surface.

## Testing

Run the product gate before a release or before claiming renderer quality:

```sh
bash Tools/product-check.sh
```

By default the gate skips the AppKit render probe unless
`SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` is set. The default nonvisual gate runs the
full Swift suite, required test discovery, root build, clean local SwiftPM
consumer build, bundled demo builds, Pretext golden tests, symbol graph
generation, DocC conversion, and focused product tests.

For local iteration:

```sh
swift build
swift test
git diff --check
```

## Documentation

- DocC catalog: `Docs/SiriusMarkdown.docc`
- Architecture: `Docs/architecture.md`
- Streaming: `Docs/streaming.md`
- Performance: `Docs/performance.md`
- Native renderer scorecard: `Docs/native-renderer-scorecard.md`
- Release runbook: `runbook.md`
- Changelog: `changelog.md`
- Bugfix log: `bugfix.md`
- Current release notes: `release-notes/0.6.16.md`
- Third-party credits: `NOTICE.md`

## Release

`0.6.16` is ready only when the docs describe the current public package surface,
`bash Tools/product-check.sh` passes from the repository root, `git diff --check`
is clean, the public remote is correct, and the release commit is tagged and
pushed as `0.6.16` with a matching published GitHub Release and green CI.
