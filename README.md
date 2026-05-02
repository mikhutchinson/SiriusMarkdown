# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple platforms. It targets chat and document workloads where content is long, streamed, and resized often—without moving parsing or expensive layout into SwiftUI `body`.

The package is built around three principles:

- `swift-markdown` owns Markdown semantics.
- Streaming input is represented as immutable sealed regions plus one mutable tail.
- SwiftUI rendering consumes prepared snapshots; it does not parse Markdown from `body`.

## Status

This checkout is gated for Sirius use through strict Swift-vs-Pretext layout comparison, required Pretext product fixture groups, and AppKit render probes for document, compact chat, multilingual, inline-attribute, overflow, hard-break, and long-word rendering. Fixture drift, missing groups, duplicate fixture names/groups, and trivial render output are release blockers.

## Requirements

- Swift 6.0 (`swift-tools-version: 6.0`)
- Deployment: macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Adding the package

In `Package.swift` (adjust the package reference to your checkout or published URL):

```swift
dependencies: [
    .package(path: "../SiriusMarkdown") // or .package(url: "...", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SiriusMarkdown", package: "SiriusMarkdown")
            // Or depend on `SiriusMarkdownCore` / `SiriusMarkdownSwiftUI` alone.
            // Pretext golden helpers: `SiriusMarkdownPretextSupport`
        ]
    )
]
```

Runtime dependency: [swift-markdown](https://github.com/swiftlang/swift-markdown) (Markdown semantics).

## Renderer surface

The default SwiftUI renderer includes native structured blocks for paragraphs, headings, quotes, lists, task lists, code blocks, math/HTML policy paths, and Markdown tables. Tables are first-class renderer output: cells are prepared from the AST, column widths are derived from prepared inline measurements, wide tables stay horizontally contained, and visual treatment is controlled through `MarkdownTheme` table tokens rather than demo-only styling.

Inline rendering has an explicit boundary. The Sirius-ready presets, `MarkdownRendererConfiguration.compactChat` and `.document`, use `MarkdownInlineRenderingMode.preparedNativeLines`: cached prepared layout results slice the attributed payload into prepared lines before SwiftUI renders them with `Text(AttributedString)`. Direct custom `MarkdownRendererConfiguration(...)` construction keeps `MarkdownInlineRenderingMode.systemText` as a compatibility fallback. Neither path parses, prepares policy/code/math work, or measures inline content in SwiftUI body.

## Products

- **`SiriusMarkdown`**: umbrella library (`SiriusMarkdownCore` + `SiriusMarkdownSwiftUI`).
- **`SiriusMarkdownCore`**: source storage, streaming, parsing, render model, layout contracts, caches, policies, and diagnostics.
- **`SiriusMarkdownSwiftUI`**: native SwiftUI block rendering, render sessions, themes, interaction hooks, and platform pasteboard/openURL helpers.
- **`SiriusMarkdownMath`**: optional native math renderer used by demos; the core renderer stays pluggable and does not depend on this product.
- **`SiriusMarkdownPretextSupport`**: fixture schema and comparison helpers for Pretext golden layout tests.

## Quick start

For streaming or long content, keep a `MarkdownRenderSession` in your model layer. It owns the stream, long-lived renderer configuration, source-backed copy provider, render caches, prepared snapshot, and diagnostics counters:

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

For static documents, preparing snapshots outside SwiftUI body evaluation is still the direct path:

```swift
var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: stream.snapshot())
MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
```

Use the optional native math renderer when a host wants built-in math presentation without taking over the pluggable hook:

```swift
import SiriusMarkdownMath

let configuration = MarkdownRendererConfiguration(
    theme: .document,
    mathRenderer: NativeMarkdownMathRenderer()
)
```

The direct `snapshot:` view initializers remain for small compatibility cases, but they are deprecated because they hide preparation at the view boundary. Applications that stream or resize long content should keep preparation in their model layer.

## What the tests prove

The default test suite covers more than construction smoke tests:

- streamed parse output matches whole-document parse output across chunk sizes;
- block identity survives active-tail appends and tail-to-sealed transitions;
- conservative sealing avoids open fences, math, HTML, and loose-list ambiguity;
- SwiftUI renderer inputs are prepared outside block bodies, including inline layout, code highlighting, math rendering, and policy decisions;
- `MarkdownRenderSession` keeps streaming, copy, cache, and prepared-snapshot state out of SwiftUI view bodies;
- inline math is detected source-preservingly while code spans and fences remain excluded;
- image runs produce prepared placeholder/resolution decisions, with no remote image loading by default;
- selection/copy is bounded at the block level instead of using unbounded per-fragment overlays;
- renderer preparation does not eagerly populate per-character fallback measurements;
- repeated preparation reuses inline/code/math caches and records diagnostics;
- large transcripts keep stable prepared item IDs for 10,000 sealed blocks plus one active tail;
- `Tools/RenderProbe` renders document, compact-chat, multilingual, inline-attribute, overflow, hard-break, and long-word cases through AppKit and rejects blank, trivial, collapsed-spacing, or clipped-wide output;
- strict Pretext golden fixtures compare Swift layout metrics against the JavaScript oracle with no known-drift whitelist, no duplicate fixture names/groups, and all required product groups present.

## Documentation

- DocC catalog: `Docs/SiriusMarkdown.docc`
- Topic notes: `Docs/architecture.md`, `Docs/streaming.md`, `Docs/performance.md`
- Native-renderer product gate: `Docs/native-renderer-scorecard.md`

## Project tracking

- `plan.md` — binding SiriusMarkdown Native Renderer Plan.
- `AGENTS.md` — contributor and agent guardrails (architecture and testing expectations).
- `changelog.md` — implementation slices.
- `runbook.md` — build, test, and Pretext golden commands.
- `bugfix.md` — defects recorded during implementation.

## Developing

```sh
swift build
swift test
```

See `runbook.md` for the AppKit render probe, Pretext golden checks (`Tools/pretext-golden`), and release expectations.

## Examples

SwiftPM examples are SwiftUI `@main` apps, but plain `swift build` / `swift run` produces a bare Mach-O executable. For double-clickable macOS apps (not tied to the launching terminal), bundle them:

```sh
Examples/scripts/bundle-macos-demos.sh
open Examples/MacOSArtifacts/MarkdownDemoApp.app
```

The bundled demos have distinct jobs:

- `MarkdownDemoApp` is the renderer workbench: example navigation, coverage summaries, cache/pipeline counters, and stress cases.
- `DocumentReaderDemo` is the reader product surface: a single prepared document with library navigation, reading metadata, source-copy actions, and reading-width controls.
- `StreamingTranscriptDemo` exercises the streaming append model.

Build a single demo as an app by name:

```sh
Examples/scripts/bundle-macos-demos.sh StreamingTranscriptDemo
```

For a quick command-line launch (debug build, process bound to that shell session unless disowned):

```sh
swift run --package-path Examples/MarkdownDemoApp
```

Run the full local release gate with:

```sh
bash Tools/release-check.sh
```

Run the product gate before claiming native-renderer product quality:

```sh
bash Tools/product-check.sh
```
