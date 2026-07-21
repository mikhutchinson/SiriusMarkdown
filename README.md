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

`0.6.20` reduces retained work while a GFM table grows and strengthens the
tests that enforce the renderer boundary:

- **Bounded table conversion:** unchanged table-cell render models are reused
  across mutable-tail reparses from a bounded cache with explicit conversion
  and hit diagnostics.
- **Prepared table leaves:** default cells enter SwiftUI with exact
  width-specific line layouts, CoreText plans, and row heights. Stable bounded
  row groups avoid triangular body evaluation and measurement work as rows
  accumulate.
- **Serializable native attachments:** transparent image placeholders and
  tinted math images now use concrete bounded bitmap representations, avoiding
  ImageIO serialization failures during TextKit copy and normalization.
- **Honest renderer coverage:** construction-only and unconditional-success
  tests were replaced with mounted AppKit rendering, pixel output, controlled
  state changes, exact pasteboard representations, and end-to-end streaming
  timing assertions.
- **Release validation:** the serial release suite discovers 941 tests, and the
  full gate also builds a clean external consumer, bundles all three demos,
  compares every Pretext fixture, checks the math corpus, builds DocC, and runs
  the opt-in AppKit renderer probes.

The release retains the sanitized native rich HTML, bounded decorated-link
resolver, baseline corrections, bounded streaming, native selection, syntax
highlighting, math, Mermaid, attachment, and Pretext-backed layout contracts
from earlier releases.

## Requirements

- Swift 6.0
- macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Install

```swift
dependencies: [
    .package(url: "https://github.com/mikhutchinson/SiriusMarkdown.git", from: "0.6.20")
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
  math, and sanitized native rich HTML. Supported HTML is converted through an
  HTML5 tree into the same source-mapped block and inline models as Markdown;
  active content is removed rather than executed or displayed as raw tags.
- Streaming append behavior that reparses only the mutable tail while sealed
  regions remain immutable and cacheable.
- Platform-native bounded text selection on macOS, including image-backed inline
  math through TextKit attachments, with the source-backed cross-block selector
  available explicitly for exact Markdown copy through
  `MarkdownSelectionController` and `MarkdownCopyProvider`. Other platforms keep
  source-backed document selection as their default.
- Bounded parser, prepared-inline, measured-layout, highlighted-code, Mermaid,
  math, and origin-scoped link-metadata/icon caches.
- Safe default policies: links are scheme-gated, network images are not fetched
  by default, the documented native HTML subset is sanitized, active HTML and
  unsafe destinations are removed or denied, and math/code renderers are
  pluggable.
- Decorated website links work without a host-owned favicon bundle. Every
  allowed HTTP(S) link receives an immediate atomic globe glyph; the
  package-owned resolver then
  discovers the destination's declared public HTTPS icon, bounded square social
  artwork, or conventional favicon/touch-icon paths, validates it, and
  refreshes only that prepared decoration. Requests are
  anonymous and ephemeral, private/special network endpoints and unsafe
  redirects are rejected, concurrent origins, payloads, and decoded dimensions
  are capped, and positive/negative results are bounded and coalesced per
  origin. Set
  `linkMetadataResolver` to `nil`, use `.disabled` link decoration, or inject a
  custom `MarkdownLinkMetadataResolver` to change this behavior.
- Allowed images flow as atomic inline attachments — reserved box metrics
  (theme default or a cheap header probe of already-available bytes) on the
  CoreText line plan, with one SwiftUI/AppKit/UIKit host per attachment
  drawing the reserved box or resolved pixels. Denied images (the default)
  keep today's alt/`[image: reason]` text. Hosts can supply bytes
  synchronously through `MarkdownImageResolver`; SiriusMarkdown performs no
  content-image network fetch, ImageIO probe beyond a cheap header read, or
  decode inside SwiftUI `body`. Remote content-image fetch and multi-frame
  animation are separate,
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
- Current release notes: `release-notes/0.6.20.md`
- Third-party credits: `NOTICE.md`

## Release

`0.6.20` is ready only when the docs describe the current public package surface,
`bash Tools/product-check.sh` passes from the repository root, `git diff --check`
is clean, the public remote is correct, and the release commit is tagged and
pushed as `0.6.20` with a matching published GitHub Release.
