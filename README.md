# SiriusMarkdown

SiriusMarkdown is a native, streaming-first Markdown renderer for Apple platforms. It targets chat and document workloads where content is long, streamed, and resized often—without moving parsing or expensive layout into SwiftUI `body`.

The package is built around three principles:

- `swift-markdown` owns Markdown semantics.
- Streaming input is represented as immutable sealed regions plus one mutable tail.
- SwiftUI rendering consumes prepared snapshots; it does not parse Markdown from `body`.

## Status

This checkout is the `0.5.0` public package release. The release gate is strict Swift-vs-Pretext layout comparison, required Pretext product fixture groups, AppKit render probes for document, compact chat, transcript wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, finite-column containment, wide-to-narrow resize, document affordance chrome, Mermaid diagram pan/zoom, enabled native text selection, default-on document selection, document-selection invalidation-storm counters, and language-aware code highlighting output, plus AppKit-hosted transcript command clipping regressions and a clean local SwiftPM consumer build. Fixture drift, missing groups, duplicate fixture names/groups, missing required tests, and trivial render output are release blockers.

The current product claim is native SwiftUI Markdown rendering with prepared-line layout, streaming snapshots, bounded caches, safe default policies, language-aware default code highlighting, built-in Mermaid diagram rendering with package-owned inline pan/zoom controls and deterministic plain-code fallback, generic document/code affordances with explicit accessibility labels, public chat/document presets, first-class H1-H6 heading typography through `MarkdownTheme.headings`, containment-stable prepared native lines for transcript-style paths, commands, URLs, long identifiers, nested lists, quotes, table cells, and glyph-bound paint, plus default-on source-backed document selection for cross-block drag highlights and Cmd-C. Document selection paint is emitted by rendered text leaves and clipped through prepared-line/CoreText offsets; it is not a parent row or block rectangle overlay. `nativeTextSelection` remains a separate macOS leaf-level compatibility opt-in that uses bounded AppKit text leaves instead of SwiftUI's private `SelectionOverlay`; it is not required for document selection. It is not a custom glyph renderer: `preparedNativeLines` slices prepared attributed line ranges and renders them natively while CoreText owns measurement.

## Requirements

- Swift 6.0 (`swift-tools-version: 6.0`)
- Deployment: macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1

## Adding the package

In `Package.swift` (adjust the package URL to the published repository):

```swift
dependencies: [
    .package(url: "https://github.com/mikhutchinson/SiriusMarkdown.git", from: "0.5.0")
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

The default SwiftUI renderer includes native structured blocks for paragraphs, headings, quotes, lists, task lists, code blocks, built-in Mermaid diagram fences, math/HTML policy paths, and Markdown tables. Reference-style links are resolved by `swift-markdown` semantics even when definitions are discovered in earlier sealed streaming regions; unresolved reference candidates stay in the mutable tail until they are safe to seal, and definition-looking text inside code/HTML content is not carried forward as a global definition. Mermaid fences are recognized from ```` ```mermaid ```` info strings during preparation, rendered through a bundled JavaScript runtime off the SwiftUI hot path, and can be disabled by setting `MarkdownRendererConfiguration(mermaidRenderer: nil)` to fall back to plain code blocks. The default renderer produces ASCII text plus raster-compatible light and dark SVG strings in `MarkdownPreparedMermaidDiagram.svg` and `.darkSVG`, along with prepared root SVG geometry when available; the SVG colors and local font fallback are resolved during preparation so AppKit/UIKit image decoding does not depend on runtime CSS variable support or network font imports. `MarkdownBlockView` selects the prepared variant for the active color scheme and renders diagrams in a bounded two-axis pan/zoom viewport with package-owned zoom out, zoom in, fit, and reset controls from `MarkdownTheme.mermaidAffordances`. Those package-owned control buttons provide explicit accessibility labels/help text, while their decorative SF Symbol images are hidden from accessibility synthesis so hosts do not pay for localized symbol-description resolution during view updates. This is still prepared SVG/ASCII from the bundled Mermaid renderer, not a new Mermaid semantic engine and not WebKit. Tables are first-class renderer output: cells are prepared from the AST, column widths are derived from prepared inline measurements, wide tables stay horizontally contained, and visual treatment is controlled through `MarkdownTheme` table tokens rather than demo-only styling.

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

Code highlighting remains pluggable through `MarkdownCodeHighlighter`, but the shipped default is now language-aware where JavaScriptCore is available. `DefaultMarkdownCodeHighlighter` normalizes fence info strings and aliases, highlights explicit supported languages through a pinned embedded `highlight.js` common build, and renders plaintext, nohighlight, unlabeled, unsupported, unavailable-runtime, or failed-backend fences plainly. Mermaid fences are routed before syntax highlighting through `MarkdownMermaidRenderer`, whose shipped default uses a bundled DOM-free `beautiful-mermaid` runtime to prepare native diagram text and concrete-color SVG output without WebKit. Hosts that want Mermaid fences to stay plain can disable that path with `mermaidRenderer: nil`, and hosts that want tighter or looser diagram chrome can tune `MarkdownTheme.mermaidAffordances`. Code blocks also include generic SwiftUI chrome for the normalized language label, copy, export, and collapse controls; hosts can hide or tune those affordances through `MarkdownTheme.codeBlockAffordances`. All package-owned icon affordances keep labels on the enclosing button rather than asking SwiftUI to synthesize accessibility text from the SF Symbol image. Hosts that want no highlighting can still inject `PlainMarkdownCodeHighlighter`.

Document chrome and selection are generic and source-backed. `MarkdownDocumentSurface` wraps prepared document content with optional copy, export/download, and collapse controls while keeping parsing, highlighting, and layout preparation outside SwiftUI body evaluation. `MarkdownRendererConfiguration.documentSelection` defaults to `.enabled`, so `MarkdownDocumentView`, `StreamingMarkdownView`, and `MarkdownDocumentSurface` install SiriusMarkdown's document selection layer even when hosts do not provide a `MarkdownSelectionController`. Hosts can inject a controller for observation/control or set `documentSelection: .disabled` for hostile embeds. Source comes from `MarkdownCopyProvider`, and behavior is replaceable through `MarkdownAffordanceActionHandler`:

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

Use the optional native math renderer for beautiful, native LaTeX without taking over the pluggable hook:

```swift
import SiriusMarkdownMath

let configuration = MarkdownRendererConfiguration(
    theme: .document,
    mathRenderer: NativeMarkdownMathRenderer()
)
```

`NativeMarkdownMathRenderer` typesets math with CoreText (via SwiftMath) — real glyphs, no WebView, no SVG, no network. It recognizes display math (`$$ ... $$` and `\[ ... \]`), inline math (`$ ... $` and `\( ... \)`), and `\begin{...} ... \end{...}` environments. Equations are typeset once during preparation and cached; display blocks render centered with horizontal-scroll overflow, and inline math composes natively so it wraps with surrounding text. The dependency is linked only into `SiriusMarkdownMath`, so `SiriusMarkdownCore` and `SiriusMarkdownSwiftUI` stay dependency-free; hosts that ship their own engine can conform to `MarkdownMathRenderer` (implement `preparedMath(_:isBlock:fontSize:)` for typeset output, or just `renderedMath(_:isBlock:)` for text).

The direct `snapshot:` view initializers remain for small compatibility cases, but they are deprecated because they skip full preparation at the view boundary. They still enforce cheap code, math, and HTML policy denials; applications that stream or resize long content should keep full preparation in their model layer.

## Source navigation and reveal

SiriusMarkdown resolves which rendered block corresponds to a source line or range. Host apps own scrolling because `StreamingMarkdownView` does not wrap a `ScrollView`; `MarkdownDocumentView` owns its own internal scroll surface.

Pass `MarkdownBlockID` to `ScrollViewReader.scrollTo(_:anchor:)`. That matches `MarkdownBlockView.id(block.id)`. Do not pass `MarkdownPreparedSnapshotRenderItem.id` (`"block:<raw>"` strings used only for lightweight `ForEach` identity).

```swift
ScrollViewReader { proxy in
    StreamingMarkdownView(
        preparedSnapshot: session.preparedSnapshot,
        configuration: session.configuration,
        selectionController: selectionController
    )
    .onChange(of: outlineLine) { line in
        guard let line else { return }
        if let blockID = session.blockID(containingSourceLine: line) {
            selectionController.selectSourceLine(line, in: session.preparedSnapshot)
            proxy.scrollTo(blockID, anchor: .top)
        }
    }
}
```

Use `MarkdownSourceRevealPolicy.exactOnly` when a source line must lie inside a block range. The default `.nearestRenderedBlock` resolves blank-line gaps and inter-block separators to the following rendered block (or the preceding block at end-of-document).

`selectSourceLine` selects the resolved block with coherent block-level source ranges so copy and highlight stay aligned. For byte-accurate partial-line selection, call `selectSourceRanges(_:selectedBlockIDs:)` with explicit ranges from your source buffer.

## What the tests prove

The release and product gates cover more than construction smoke tests:

- streamed parse output matches whole-document parse output across chunk sizes;
- block identity survives active-tail appends and tail-to-sealed transitions;
- source-line and source-range lookup resolves stable `MarkdownBlockID` scroll targets with optional nearest-block fallback for blank-line gaps, without parsing or re-preparing in lookup paths;
- conservative sealing avoids open fences, math, HTML, true reference-link ambiguity, and loose-list ambiguity while allowing literal unmatched bracket prose to seal at paragraph boundaries;
- SwiftUI renderer inputs are prepared outside block bodies, including inline layout, language-aware code highlighting, built-in Mermaid rendering, math rendering, and policy decisions;
- `MarkdownRenderSession` keeps streaming, copy, cache, and prepared-snapshot state out of SwiftUI view bodies;
- inline math is detected source-preservingly while code spans and fences remain excluded;
- image runs produce prepared placeholder/resolution decisions, with no remote image loading by default;
- document selection defaults on for cross-block drag highlights and Cmd-C copy, using ordered source ranges through `MarkdownSelectionController` and `MarkdownCopyProvider`;
- exact Markdown source copy wins for whole-block, partial-line, contiguous multi-block, and deterministic non-contiguous selection; prepared plain text is only a fallback when source is unavailable;
- document selection highlights are generated from text-leaf prepared line fragments and clipped with CoreText-backed string offsets for partial first/last lines, so list gutters, quote gutters, table grids, and trailing row width are not painted as selected text;
- Native text selection remains a separate explicit leaf-level opt-in through
  `MarkdownRendererConfiguration.nativeTextSelection`. It defaults to
  `.disabled`. On macOS, `.enabled` now
  mounts package-owned selectable AppKit text leaves instead of SwiftUI's
  private `SelectionOverlay`; on other Apple platforms the SwiftUI selection
  helper remains bounded to stable text leaves. Native text selection is still kept off
  document, scroll, stack, custom leading-layout containers, table-grid
  containers, toolbar, Mermaid-control, and host containers, while list, quote,
  and table cell text leaves remain selectable. The AppKit render probe
  stress-renders `.enabled` through streaming appends, width changes, tables,
  links, code, and prepared native lines with a watchdog and verifies selectable
  AppKit text leaves are present; SwiftUI tests also select and copy from a
  hosted list text leaf through the actual `NSTextView` pasteboard path.
  If a regression returns, sample the host and look for
  `GraphHost.flushTransactions` -> `SelectionOverlay.updateNSView` ->
  `NSTextField setFont:` / `_invalidateEffectiveFont` / `updateCell`.
- renderer preparation does not eagerly populate per-character fallback measurements;
- repeated preparation reuses inline/code/mermaid/math caches and records diagnostics;
- large transcripts keep stable prepared item IDs for 10,000 sealed blocks plus one active tail;
- `Tools/release-check.sh` asserts the Swift test discovery floor, required regression tests, root build, clean local SwiftPM consumer resolve/build, demo bundling, Pretext golden tests, symbol graphs, DocC, and render probes;
- `Tools/RenderProbe` renders document, compact-chat, transcript-wrapping, multilingual, inline-attribute, overflow, hard-break, long-word, Mermaid diagram pan/zoom, enabled native text selection, and code-highlighting cases through AppKit and rejects blank, trivial, collapsed-spacing, clipped-wide, stalled, or misleading plain-fence output;
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

`0.5.0` is ready to publish only when:

- `README.md`, DocC, `Docs/architecture.md`, `Docs/native-renderer-scorecard.md`, `NOTICE.md`, `changelog.md`, `bugfix.md`, and `runbook.md` describe the current public package surface;
- `bash Tools/product-check.sh` passes from the repository root;
- `git diff --check` reports no whitespace errors;
- `git remote -v` points at the intended public repository;
- the release commit is tagged as `0.5.0` and pushed with tags.

Recommended release commands are documented in `runbook.md`.
