# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple platforms. It targets chat and document workloads where content is long, streamed, and resized often—without moving parsing or expensive layout into SwiftUI `body`.

The package is built around three principles:

- `swift-markdown` owns Markdown semantics.
- Streaming input is represented as immutable sealed regions plus one mutable tail.
- SwiftUI rendering consumes prepared snapshots; it does not parse Markdown from `body`.

## Status

This checkout is the `0.4.7` public package release. The release gate is strict Swift-vs-Pretext layout comparison, required Pretext product fixture groups, AppKit render probes for document, compact chat, transcript wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, wide-to-narrow resize, document affordance chrome, Mermaid diagram pan/zoom, and language-aware code highlighting output, plus AppKit-hosted transcript command clipping regressions. Fixture drift, missing groups, duplicate fixture names/groups, and trivial render output are release blockers.

The current product claim is native SwiftUI Markdown rendering with prepared-line layout, streaming snapshots, bounded caches, safe default policies, language-aware default code highlighting, built-in Mermaid diagram rendering with package-owned inline pan/zoom controls and deterministic plain-code fallback, generic document/code affordances with explicit accessibility labels, public chat/document presets, first-class H1-H6 heading typography through `MarkdownTheme.headings`, and containment-stable prepared native lines for transcript-style paths, commands, URLs, long identifiers, nested lists, quotes, table cells, and glyph-bound paint drift. It is not a custom glyph renderer: `preparedNativeLines` slices prepared attributed line ranges and renders them with SwiftUI `Text(AttributedString)`.

## Requirements

- Swift 6.0 (`swift-tools-version: 6.0`)
- Deployment: macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Adding the package

In `Package.swift` (adjust the package URL to the published repository):

```swift
dependencies: [
    .package(url: "https://github.com/mikhutchinson/SiriusMarkdown.git", from: "0.4.7")
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

Runtime dependency: [swift-markdown](https://github.com/swiftlang/swift-markdown) (Markdown semantics). Third-party credits, including the Pretext golden oracle and the vendored JavaScript Unicode line-breaking oracle used by `Tools/pretext-golden`, are listed in `NOTICE.md`.

For local development from a sibling checkout, use a path dependency instead:

```swift
.package(path: "../SiriusMarkdown")
```

## Renderer surface

The default SwiftUI renderer includes native structured blocks for paragraphs, headings, quotes, lists, task lists, code blocks, built-in Mermaid diagram fences, math/HTML policy paths, and Markdown tables. Mermaid fences are recognized from ```` ```mermaid ```` info strings during preparation, rendered through a bundled JavaScript runtime off the SwiftUI hot path, and can be disabled by setting `MarkdownRendererConfiguration(mermaidRenderer: nil)` to fall back to plain code blocks. The default renderer produces ASCII text plus raster-compatible light and dark SVG strings in `MarkdownPreparedMermaidDiagram.svg` and `.darkSVG`, along with prepared root SVG geometry when available; the SVG colors and local font fallback are resolved during preparation so AppKit/UIKit image decoding does not depend on runtime CSS variable support or network font imports. `MarkdownBlockView` selects the prepared variant for the active color scheme and renders diagrams in a bounded two-axis pan/zoom viewport with package-owned zoom out, zoom in, fit, and reset controls from `MarkdownTheme.mermaidAffordances`. Those package-owned control buttons provide explicit accessibility labels/help text, while their decorative SF Symbol images are hidden from accessibility synthesis so hosts do not pay for localized symbol-description resolution during view updates. This is still prepared SVG/ASCII from the bundled Mermaid renderer, not a new Mermaid semantic engine and not WebKit. Tables are first-class renderer output: cells are prepared from the AST, column widths are derived from prepared inline measurements, wide tables stay horizontally contained, and visual treatment is controlled through `MarkdownTheme` table tokens rather than demo-only styling.

Inline rendering has an explicit boundary. The packaged chat and document presets, `MarkdownRendererConfiguration.compactChat` and `.document`, use `MarkdownInlineRenderingMode.preparedNativeLines`: cached prepared layout results slice the attributed payload into proposal-contained prepared lines before SwiftUI renders them with `Text(AttributedString)`. Direct custom `MarkdownRendererConfiguration(...)` construction keeps `MarkdownInlineRenderingMode.systemText` as a compatibility fallback. Neither path parses, prepares policy/code/math work, or measures inline content in SwiftUI body.

Production CoreText measurement defaults to system-profile font measurement and caches include the measurement profile. Pretext golden fixtures still pin explicit named font profiles, usually Helvetica, so the oracle stays stable. Hosts that render custom fonts should pass matching `MarkdownInlineFontProfiles` through `MarkdownTheme`.

Heading typography is a first-class theme contract. Configure H1 through H6 with `MarkdownTheme.headings`, similar to CSS `h1`...`h6` rules. Each `MarkdownTextStyle` carries both the SwiftUI `Font` used for visible rendering and the CoreText measurement inputs used during prepared inline layout, so custom fonts must provide matching `fontProfiles`.

```swift
let compactHeading = MarkdownTextStyle(
    font: .system(size: 12, weight: .semibold),
    fontSize: 12,
    lineHeight: 16,
    fontProfiles: MarkdownInlineFontProfiles(uniform: .system(weight: .semibold))
)

let compactTheme = MarkdownTheme(
    headings: .uniform(compactHeading)
)

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

Code highlighting remains pluggable through `MarkdownCodeHighlighter`, but the shipped default is now language-aware on Apple platforms with JavaScriptCore. `DefaultMarkdownCodeHighlighter` normalizes fence info strings and aliases, highlights explicit supported languages through a pinned embedded `highlight.js` common build, and renders plaintext, nohighlight, unlabeled, or unsupported fences plainly. Mermaid fences are routed before syntax highlighting through `MarkdownMermaidRenderer`, whose shipped default uses a bundled DOM-free `beautiful-mermaid` runtime to prepare native diagram text and concrete-color SVG output without WebKit. Hosts that want Mermaid fences to stay plain can disable that path with `mermaidRenderer: nil`, and hosts that want tighter or looser diagram chrome can tune `MarkdownTheme.mermaidAffordances`. Code blocks also include generic SwiftUI chrome for the normalized language label, copy, export, and collapse controls; hosts can hide or tune those affordances through `MarkdownTheme.codeBlockAffordances`. All package-owned icon affordances keep labels on the enclosing button rather than asking SwiftUI to synthesize accessibility text from the SF Symbol image. Hosts that want no highlighting can still inject `PlainMarkdownCodeHighlighter`.

Document chrome is generic and source-backed. `MarkdownDocumentSurface` wraps prepared document content with optional copy, export/download, and collapse controls while keeping parsing, highlighting, and layout preparation outside SwiftUI body evaluation. Source comes from `MarkdownCopyProvider`, and behavior is replaceable through `MarkdownAffordanceActionHandler`:

```swift
let copyProvider = MarkdownCopyProvider(markdownSource: markdown)
let configuration = MarkdownRendererConfiguration.document
var configured = configuration
configured.copyProvider = copyProvider

MarkdownDocumentSurface(
    title: "Field Guide",
    subtitle: "Prepared native Markdown with source-backed actions.",
    suggestedFilename: "FieldGuide.md",
    preparedSnapshot: prepared,
    configuration: configured
)
```

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

The release and product gates cover more than construction smoke tests:

- streamed parse output matches whole-document parse output across chunk sizes;
- block identity survives active-tail appends and tail-to-sealed transitions;
- conservative sealing avoids open fences, math, HTML, and loose-list ambiguity;
- SwiftUI renderer inputs are prepared outside block bodies, including inline layout, language-aware code highlighting, built-in Mermaid rendering, math rendering, and policy decisions;
- `MarkdownRenderSession` keeps streaming, copy, cache, and prepared-snapshot state out of SwiftUI view bodies;
- inline math is detected source-preservingly while code spans and fences remain excluded;
- image runs produce prepared placeholder/resolution decisions, with no remote image loading by default;
- selection/copy is bounded at the block level instead of using unbounded per-fragment overlays;
- renderer preparation does not eagerly populate per-character fallback measurements;
- repeated preparation reuses inline/code/mermaid/math caches and records diagnostics;
- large transcripts keep stable prepared item IDs for 10,000 sealed blocks plus one active tail;
- `Tools/RenderProbe` renders document, compact-chat, transcript-wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, Mermaid diagram pan/zoom, and code-highlighting cases through AppKit and rejects blank, trivial, collapsed-spacing, clipped-wide, or misleading plain-fence output;
- strict Pretext golden fixtures compare Swift layout metrics against the JavaScript oracle with no known-drift whitelist, no duplicate fixture names/groups, and all required product groups present.

Before a public tag, run:

```sh
bash Tools/product-check.sh
```

That wraps the release gate, Swift tests, Pretext golden parity, DocC conversion, demo app bundling, focused product tests, and AppKit render probes.

## Documentation

- DocC catalog: `Docs/SiriusMarkdown.docc`
- Topic notes: `Docs/architecture.md`, `Docs/streaming.md`, `Docs/performance.md`
- Native-renderer product gate: `Docs/native-renderer-scorecard.md`
- Third-party credits: `NOTICE.md`
- Contributing: `CONTRIBUTING.md`
- Security policy: `SECURITY.md`

## Project tracking

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

- `MarkdownDemoApp` is the renderer workbench: example navigation, package-owned document/code affordances, coverage summaries, optional diagnostics, and stress cases.
- `DocumentReaderDemo` is the reader product surface: a single prepared document with library navigation, reading metadata, top-right document actions, optional inspector, and reading-width controls.
- `StreamingTranscriptDemo` is the streaming lab: live compact-chat rendering, pause/step/burst controls, subtle sealed-tail state, host-boundary markers, and optional diagnostics.

All three demos share `Examples/DemoSupport` for macOS tokens, surfaces, sidebar rows, metric rows, icon buttons, affordance bars, and empty/error states so demo polish does not drift across apps.

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

## Release

`0.4.7` is ready to publish only when:

- `README.md`, DocC, `Docs/architecture.md`, `Docs/native-renderer-scorecard.md`, `NOTICE.md`, `changelog.md`, `bugfix.md`, and `runbook.md` describe the current public package surface;
- `bash Tools/product-check.sh` passes from the repository root;
- `git diff --check` reports no whitespace errors;
- `git remote -v` points at the intended public repository;
- the release commit is tagged as `0.4.7` and pushed with tags.

Recommended release commands are documented in `runbook.md`.
