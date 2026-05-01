# ``SiriusMarkdown``

Native, streaming-first Markdown rendering for Apple platforms—designed for long chat transcripts and documents that stream and resize without pushing parsing or expensive layout into SwiftUI `body`.

## Overview

> Beta status: this checkout is not v0.1 beta-ready. Strict Swift-vs-Pretext fixture comparison currently fails for emoji/CJK, multilingual, and RTL layout drift; the failure is intentional until the native layout path matches the oracle.

- **`swift-markdown`** (`Markdown` product) provides parsing semantics; SiriusMarkdown converts the AST to **`MarkdownBlock`** and **`MarkdownInlineRun`** value types.
- **`MarkdownStream`** stores append-only UTF-8, incrementally scans safe seal points, reparses only the **mutable tail**, and exposes **`MarkdownSnapshot`** plus source-backed copy slices.
- **`SiriusMarkdown`** is the app-facing umbrella module. Import **`SiriusMarkdownCore`** or **`SiriusMarkdownSwiftUI`** directly only when you need a narrower dependency.
- **`SiriusMarkdownSwiftUI`** renders prepared snapshots with **`MarkdownDocumentView`** and **`StreamingMarkdownView`**, **`MarkdownTheme`**, and **`MarkdownRendererConfiguration`** (policies, optional link/copy actions, pluggable code highlighting and math rendering).

```swift
import SiriusMarkdown

var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let snapshot = stream.snapshot()
let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: snapshot)
MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
```

For live updates, append to the stream (or rebuild snapshots from your pipeline) and pass the latest snapshot into **`StreamingMarkdownView`** or **`MarkdownDocumentView`**.

In production paths, keep **`MarkdownRendererConfiguration`** alive in your model layer and call **`prepare(snapshot:)`** before SwiftUI evaluates renderer bodies. Prepared snapshots carry policy-gated inline text, measured inline content, highlighted code, rendered math, HTML policy decisions, table cells, list items, and host-boundary ordering. The compatibility `snapshot:` view initializers are deprecated because they hide this work at the view boundary.

```swift
@MainActor
final class TranscriptModel: ObservableObject {
    @Published var preparedSnapshot: MarkdownPreparedSnapshot

    private var stream = MarkdownStream()
    private let configuration = MarkdownRendererConfiguration.compactChat

    init() {
        preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
    }

    func append(_ chunk: String) {
        stream.append(chunk)
        preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
    }
}
```

SiriusMarkdown's default tests assert this contract through renderer preparation, diagnostics, native SwiftUI pixel checks, an AppKit `MarkdownDocumentView` render probe, and strict Pretext comparison: large streaming transcripts must keep stable prepared item IDs, repeated preparation must hit inline/code/math caches, width changes must reuse measured inline content, and Pretext drift must fail instead of being hidden as a passing known issue.

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
- ``SiriusMarkdownSwiftUI/MarkdownPreparedSnapshot``
- ``SiriusMarkdownSwiftUI/MarkdownPreparedBlockContent``
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
- ``SiriusMarkdownSwiftUI/MarkdownCopyProvider``
