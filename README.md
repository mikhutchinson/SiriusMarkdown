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

`0.5.8` fixes long-generation render-session slowdown by batching fast append
bursts, skipping reset-superseded work before parsing or highlighting, and
reusing exact-match prepared block content across append-only streaming
snapshots. `0.5.7` hardened packaged-app native math fallback, and `0.5.5`
shipped
`MarkdownInlineRenderingMode.coreTextPaintedLines` as the default
for `MarkdownRendererConfiguration()`, `.compactChat`, and `.document`.
Prepared line ranges come from SiriusMarkdown's layout engine; AppKit/UIKit
bridges paint each line through CoreText `CTLineDraw`; links use bounded hit
regions derived from already policy-filtered prepared attributes.

The current line also hardens shipped-app resource lookup for bundled HighlightJS
and Mermaid preparation, and tightens source-backed document selection/copy
across code, math, HTML, tables, lists, styled Markdown, and streamed appends.

`preparedNativeLines` and `systemText` remain explicit compatibility fallbacks.
`nativeTextSelection` is a separate disabled-by-default compatibility mode. When
enabled, it uses selectable native text leaves instead of the CoreText paint path
so host apps can opt into platform text selection without making document
selection depend on SwiftUI's private selection overlay.

## Requirements

- Swift 6.0
- macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Install

```swift
dependencies: [
    .package(url: "https://github.com/mikhutchinson/SiriusMarkdown.git", from: "0.5.8")
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
- Source-backed document selection enabled by default, with exact Markdown copy
  through `MarkdownSelectionController` and `MarkdownCopyProvider`.
- Bounded parser, prepared-inline, measured-layout, highlighted-code, Mermaid,
  and math caches.
- Safe default policies: links are scheme-gated, network images are not fetched
  by default, raw HTML is inert unless a host opts in, and math/code renderers
  are pluggable.
- Language-aware default code highlighting where the backend is available, with
  plain rendering for plaintext, nohighlight, unlabeled, unsupported, or failed
  fences.
- Package-owned Mermaid preparation through JavaScriptCore with deterministic
  ASCII plus light/dark SVG output. Mermaid remains prepared SVG/ASCII, not a
  WebKit surface and not a second Markdown semantic engine.
- Optional native LaTeX math through `SiriusMarkdownMath`, backed by SwiftMath
  and CoreText typesetting. The core renderer stays pluggable.

## CoreText Inline Rendering

Inline work follows the Pretext-style split:

1. Prepare once: normalize inline runs, apply policies, build attributed payloads,
   measure segments, compute natural width, and cache prepared content.
2. Layout cheaply: consume prepared measurements for a container width and
   produce line ranges without reparsing or remeasuring from raw Markdown.
3. Paint: the default mode draws each prepared line with CoreText on supported
   AppKit/UIKit platforms.

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

The gate runs the AppKit render probe, full Swift suite, required test discovery,
root build, clean local SwiftPM consumer build, bundled demo builds, Pretext
golden tests, symbol graph generation, DocC conversion, focused product tests,
and final render probe.

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
- Third-party credits: `NOTICE.md`

## Release

`0.5.8` is ready only when the docs describe the current public package surface,
`bash Tools/product-check.sh` passes from the repository root, `git diff --check`
is clean, the public remote is correct, and the release commit is tagged and
pushed as `0.5.8`.
