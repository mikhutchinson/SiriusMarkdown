# ``SiriusMarkdown``

Native, streaming-first Markdown rendering for Apple platforms—designed for long chat transcripts and documents that stream and resize without pushing parsing or expensive layout into SwiftUI `body`.

## Overview

- **`swift-markdown`** (`Markdown` product) provides parsing semantics; SiriusMarkdown converts the AST to **`MarkdownBlock`** and **`MarkdownInlineRun`** value types.
- **`MarkdownStream`** stores append-only UTF-8, seals safe prefixes, reparses only the **mutable tail**, and exposes **`MarkdownSnapshot`** for views.
- **`SiriusMarkdown`** is the app-facing umbrella module. Import **`SiriusMarkdownCore`** or **`SiriusMarkdownSwiftUI`** directly only when you need a narrower dependency.
- **`SiriusMarkdownSwiftUI`** renders snapshots with **`MarkdownDocumentView`** and **`StreamingMarkdownView`**, **`MarkdownTheme`**, and **`MarkdownRendererConfiguration`** (policies, optional link actions, pluggable code highlighting and math rendering).

```swift
import SiriusMarkdown

var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let snapshot = stream.snapshot()
MarkdownDocumentView(snapshot: snapshot)
```

For live updates, append to the stream (or rebuild snapshots from your pipeline) and pass the latest snapshot into **`StreamingMarkdownView`** or **`MarkdownDocumentView`**.

### Products

| Product | Role |
| --- | --- |
| `SiriusMarkdown` | Umbrella: Core + SwiftUI |
| `SiriusMarkdownCore` | Source buffer, stream, parser adapter, model, inline layout engine, policies, caches, diagnostics |
| `SiriusMarkdownSwiftUI` | SwiftUI views, theme, configuration, interaction helpers |
| `SiriusMarkdownPretextSupport` | Fixture types and golden comparison helpers; JS oracle lives under `Tools/pretext-golden` |

Platform availability matches **`Package.swift`** (e.g. macOS 13, iOS 16).

### Further reading (repository)

Conceptual articles shipped beside this catalog:

- `Docs/architecture.md` — module layout and boundaries vs `plan.md` / `AGENTS.md`
- `Docs/streaming.md` — sealing algorithm and host boundaries
- `Docs/performance.md` — caches, diagnostics, prepare/layout contract

The binding renderer plan and contributor rules live in **`plan.md`** and **`AGENTS.md`** at the repository root.

## Topics

### Essentials

- ``SiriusMarkdownCore/MarkdownBlock``
- ``SiriusMarkdownCore/MarkdownBlockKind``
- ``SiriusMarkdownCore/MarkdownSnapshot``
- ``SiriusMarkdownCore/MarkdownBlockID``
- ``SiriusMarkdownCore/MarkdownStream``
- ``SiriusMarkdownCore/MarkdownHostBoundary``
- ``SiriusMarkdownSwiftUI/MarkdownDocumentView``
- ``SiriusMarkdownSwiftUI/StreamingMarkdownView``
- ``SiriusMarkdownSwiftUI/MarkdownRendererConfiguration``
- ``SiriusMarkdownSwiftUI/MarkdownTheme``

### Layout and measurement

- ``SiriusMarkdownCore/PreparedInlineContent``
- ``SiriusMarkdownCore/InlineLayoutEngine``
- ``SiriusMarkdownCore/TextMeasurer``
- ``SiriusMarkdownCore/CoreTextInlineMeasurer``
- ``SiriusMarkdownPretextSupport/PretextFixture``
- ``SiriusMarkdownPretextSupport/PretextGoldenComparator``

### Policies and safety

- ``SiriusMarkdownCore/MarkdownLinkPolicy``
- ``SiriusMarkdownCore/MarkdownImagePolicy``
- ``SiriusMarkdownCore/MarkdownHTMLPolicy``
- ``SiriusMarkdownCore/MarkdownCodePolicy``
- ``SiriusMarkdownCore/MarkdownMathPolicy``
- ``SiriusMarkdownCore/DefaultMarkdownPolicy``
