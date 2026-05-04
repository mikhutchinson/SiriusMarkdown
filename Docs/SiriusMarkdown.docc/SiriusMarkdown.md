# ``SiriusMarkdown``

Native, streaming-first Markdown rendering for Apple platforms—designed for long chat transcripts and documents that stream and resize without pushing parsing or expensive layout into SwiftUI `body`.

## Overview

> Product status: the packaged chat and document presets use proposal-contained prepared-line rendering, the default code highlighter is language-aware for explicit supported fences, Mermaid fences prepare concrete-color light/dark SVG output off the SwiftUI hot path, document/code affordances are generic and source-backed, and the release gate includes strict required-group Swift-vs-Pretext fixture comparison plus AppKit render probes for document, document affordance chrome, compact chat, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, and code-highlighting output.

- **`swift-markdown`** (`Markdown` product) provides parsing semantics; SiriusMarkdown converts the AST to **`MarkdownBlock`** and **`MarkdownInlineRun`** value types.
- **`MarkdownStream`** stores append-only UTF-8, incrementally scans safe seal points, reparses only the **mutable tail**, and exposes **`MarkdownSnapshot`** plus source-backed copy slices.
- **`SiriusMarkdown`** is the app-facing umbrella module. Import **`SiriusMarkdownCore`** or **`SiriusMarkdownSwiftUI`** directly only when you need a narrower dependency.
- **`SiriusMarkdownSwiftUI`** renders prepared snapshots with **`MarkdownRenderSession`**, **`MarkdownDocumentView`**, **`MarkdownDocumentSurface`**, **`StreamingMarkdownView`**, **`MarkdownTheme`**, and **`MarkdownRendererConfiguration`** (policies, optional link/copy/export actions, pluggable language-aware code highlighting, image decisions, selection/copy, and math rendering).
- **`SiriusMarkdownMath`** is an optional product with a native math renderer. The core path remains source-preserving and renderer-agnostic.

```swift
import SiriusMarkdown

var stream = MarkdownStream()
stream.append("# Hello\n\nStreaming Markdown.")
stream.finish()

let snapshot = stream.snapshot()
let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: snapshot)
MarkdownDocumentSurface(
    title: "Hello",
    preparedSnapshot: prepared,
    configuration: configuration
)
```

For live updates, append to the stream (or rebuild snapshots from your pipeline) and pass the latest snapshot into **`StreamingMarkdownView`** or **`MarkdownDocumentView`**.

In production paths, prefer **`MarkdownRenderSession`** or keep **`MarkdownRendererConfiguration`** alive in your model layer and call **`prepare(snapshot:)`** before SwiftUI evaluates renderer bodies. Prepared snapshots carry policy-gated inline text, measured inline content, image decisions, highlighted code, rendered math, HTML policy decisions, table cells, list items, selection/copy source ranges, and host-boundary ordering. The compatibility `snapshot:` view initializers are deprecated because they hide this work at the view boundary.

The default `MarkdownCodeHighlighter` normalizes info strings such as `language-swift`, `py`, `js`, `ts`, `yml`, `objc`, and `cpp` before calling the embedded grammar backend. Supported explicit languages are highlighted during render preparation, while plaintext, nohighlight, unlabeled, or unsupported fences stay plain. Code blocks render generic language-label, copy, export, and collapse affordances by default; hosts can hide or tune those affordances through `MarkdownTheme.codeBlockAffordances`. Hosts can keep the same injection point and pass `PlainMarkdownCodeHighlighter` or any custom highlighter through `MarkdownRendererConfiguration`.

`MarkdownDocumentSurface` is the package-owned document chrome for static reader surfaces. It wraps already-prepared content with optional copy, export/download, and collapse controls. `MarkdownCopyProvider` can expose exact full-document Markdown in addition to range slices, and `MarkdownAffordanceActionHandler` lets host apps replace pasteboard/export behavior without changing the renderer model or moving work into view bodies.

Markdown tables are rendered as native SwiftUI structure, not as raw pipe text. Prepared table cells keep stable source-range identities and measured inline layout, while **`MarkdownTheme`** exposes table background, header, alternate-row, border, accent, corner-radius, and padding tokens so host apps can make tables visually distinct without replacing the parser or renderer.

Heading typography is configured through **`MarkdownTheme.headings`** for H1 through H6, similar to CSS `h1`...`h6` styling. Each **`MarkdownTextStyle`** carries the SwiftUI **`Font`** used for visible rendering plus the `fontSize`, `lineHeight`, and **`MarkdownInlineFontProfiles`** used by CoreText measurement during render preparation. Do not rely on SiriusMarkdown to infer measurement profiles from arbitrary SwiftUI fonts; pass matching profiles when using custom fonts.

```swift
let compactHeading = MarkdownTextStyle(
    font: .system(size: 12, weight: .semibold),
    fontSize: 12,
    lineHeight: 16,
    fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .semibold))
)

let compactTheme = MarkdownTheme(headings: .uniform(compactHeading))

let documentTheme = MarkdownTheme(
    headings: MarkdownHeadingStyles(
        h1: MarkdownTextStyle(font: .system(size: 34, weight: .bold), fontSize: 34, lineHeight: 42, fontProfiles: .headingDefault),
        h2: MarkdownTextStyle(font: .system(size: 28, weight: .bold), fontSize: 28, lineHeight: 36, fontProfiles: .headingDefault),
        h3: MarkdownTextStyle(font: .system(size: 22, weight: .bold), fontSize: 22, lineHeight: 30, fontProfiles: .headingDefault),
        h4: MarkdownTextStyle(font: .system(size: 18, weight: .bold), fontSize: 18, lineHeight: 24, fontProfiles: .headingDefault),
        h5: MarkdownTextStyle(font: .system(size: 16, weight: .bold), fontSize: 16, lineHeight: 22, fontProfiles: .headingDefault),
        h6: MarkdownTextStyle(font: .system(size: 14, weight: .bold), fontSize: 14, lineHeight: 20, fontProfiles: .headingDefault)
    )
)
```

```swift
@MainActor
final class TranscriptModel: ObservableObject {
    @Published var session = MarkdownRenderSession(configuration: .compactChat)

    func append(_ chunk: String) {
        session.append(chunk)
    }
}
```

SiriusMarkdown's default tests assert this contract through renderer preparation, diagnostics, AppKit `MarkdownDocumentView` and `MarkdownDocumentSurface` render probes, and strict Pretext comparison: large streaming transcripts must keep stable prepared item IDs, repeated preparation must hit inline/code/math caches, width changes must reuse measured inline content, document collapse must preserve prepared identity, and Pretext drift must fail instead of being hidden as a passing known issue.

`MarkdownRendererConfiguration.compactChat` and `.document` select `MarkdownInlineRenderingMode.preparedNativeLines`, so chat and document views render prepared attributed line slices inside the finite proposal supplied by the host. Direct custom configuration still defaults to `.systemText` as a compatibility fallback.

Production CoreText measurement defaults to system-profile font measurement, and measured/layout caches include the measurement profile. Pretext golden fixtures use explicit named profiles such as Helvetica, and hosts with custom fonts can align measurement by providing `MarkdownInlineFontProfiles` through `MarkdownTheme`. `preparedNativeLines` still renders through SwiftUI `Text(AttributedString)`; it is not a custom glyph renderer.

### Products

| Product | Role |
| --- | --- |
| `SiriusMarkdown` | Umbrella: Core + SwiftUI |
| `SiriusMarkdownCore` | Source buffer, stream, parser adapter, model, inline layout engine, policies, caches, diagnostics |
| `SiriusMarkdownSwiftUI` | SwiftUI views, theme, configuration, interaction helpers |
| `SiriusMarkdownMath` | Optional native math renderer for hosts and demos |
| `SiriusMarkdownPretextSupport` | Fixture types and golden comparison helpers; JS oracle lives under `Tools/pretext-golden` |

Platform availability matches **`Package.swift`** (e.g. macOS 13, iOS 16).

### Further reading (repository)

Conceptual articles shipped beside this catalog:

- `Docs/architecture.md` — module layout and boundaries
- `Docs/streaming.md` — sealing algorithm and host boundaries
- `Docs/performance.md` — caches, diagnostics, prepare/layout contract

Architecture rules and the product quality bar are documented in `Docs/architecture.md` and `Docs/native-renderer-scorecard.md`.

## Topics

### Essentials

- ``SiriusMarkdownCore/MarkdownBlock``
- ``SiriusMarkdownCore/MarkdownBlockKind``
- ``SiriusMarkdownCore/MarkdownSnapshot``
- ``SiriusMarkdownCore/MarkdownBlockID``
- ``SiriusMarkdownCore/MarkdownStream``
- ``SiriusMarkdownCore/MarkdownHostBoundary``
- ``SiriusMarkdownSwiftUI/MarkdownDocumentView``
- ``SiriusMarkdownSwiftUI/MarkdownDocumentSurface``
- ``SiriusMarkdownSwiftUI/StreamingMarkdownView``
- ``SiriusMarkdownSwiftUI/MarkdownRenderSession``
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
- ``SiriusMarkdownSwiftUI/MarkdownDocumentAffordances``
- ``SiriusMarkdownSwiftUI/MarkdownCodeBlockAffordances``
- ``SiriusMarkdownSwiftUI/MarkdownAffordanceActionHandler``
- ``SiriusMarkdownSwiftUI/MarkdownSelectionController``
- ``SiriusMarkdownSwiftUI/MarkdownPreparedImage``
