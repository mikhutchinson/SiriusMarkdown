# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple platforms. It targets chat and document workloads where content is long, streamed, and resized often—without moving parsing or expensive layout into SwiftUI `body`.

The package is built around three principles:

- `swift-markdown` owns Markdown semantics.
- Streaming input is represented as immutable sealed regions plus one mutable tail.
- SwiftUI rendering consumes prepared snapshots; it does not parse Markdown from `body`.

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

## Products

- **`SiriusMarkdown`**: umbrella library (`SiriusMarkdownCore` + `SiriusMarkdownSwiftUI`).
- **`SiriusMarkdownCore`**: source storage, streaming, parsing, render model, layout contracts, caches, policies, and diagnostics.
- **`SiriusMarkdownSwiftUI`**: native SwiftUI block rendering, themes, interaction hooks, and platform pasteboard/openURL helpers.
- **`SiriusMarkdownPretextSupport`**: fixture schema and comparison helpers for Pretext golden layout tests.

## Quick start

```swift
import SiriusMarkdown

var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let snapshot = stream.snapshot()
MarkdownDocumentView(snapshot: snapshot)
```

For live tail updates, update the stream and drive a view such as `StreamingMarkdownView` with the latest `snapshot()`.

For heavier render paths, prepare once outside SwiftUI body evaluation:

```swift
let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: snapshot)
MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
```

## Documentation

- DocC catalog: `Docs/SiriusMarkdown.docc`
- Topic notes: `Docs/architecture.md`, `Docs/streaming.md`, `Docs/performance.md`

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

See `runbook.md` for Pretext golden checks (`Tools/pretext-golden`) and release expectations.

## Examples

```sh
swift build --package-path Examples/MarkdownDemoApp
swift build --package-path Examples/StreamingTranscriptDemo
swift build --package-path Examples/DocumentReaderDemo
```

Run the full local release gate with:

```sh
bash Tools/release-check.sh
```
