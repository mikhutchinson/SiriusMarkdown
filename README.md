# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple platforms.

The package is built around three principles:

- `swift-markdown` owns Markdown semantics.
- Streaming input is represented as immutable sealed regions plus one mutable tail.
- SwiftUI rendering consumes prepared snapshots; it does not parse Markdown from `body`.

## Products

- `SiriusMarkdownCore`: source storage, streaming, parsing, render model, layout contracts, caches, policies, and diagnostics.
- `SiriusMarkdownSwiftUI`: native SwiftUI block rendering, themes, interaction hooks, and platform pasteboard/openURL helpers.
- `SiriusMarkdownPretextSupport`: fixture schema and comparison helpers for Pretext golden layout tests.

## Quick Start

```swift
import SiriusMarkdownCore

var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let snapshot = stream.snapshot()
```

```swift
import SiriusMarkdownSwiftUI

MarkdownDocumentView(snapshot: snapshot)
```

## Project Tracking

- `plan.md` contains the binding SiriusMarkdown Native Renderer Plan verbatim.
- `changelog.md` tracks implementation slices.
- `runbook.md` contains build, test, and golden-oracle commands.
- `bugfix.md` records defects found and fixed during implementation.

