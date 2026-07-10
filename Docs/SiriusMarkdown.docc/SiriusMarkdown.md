# ``SiriusMarkdown``

Native, streaming-first Markdown rendering for Apple platforms—designed for long chat transcripts and documents that stream and resize without pushing parsing or expensive layout into SwiftUI `body`.

## Overview

> Product status: the packaged chat and document presets, plus direct custom configuration, default to CoreText-painted prepared-line rendering. SiriusMarkdown also ships default-on source-backed document selection, reference-style links resolved through `swift-markdown` across sealed streaming regions, source-preserving dollar inline math that does not consume currency/reward prose, language-aware default code highlighting where the backend is available, Mermaid preparation off the SwiftUI hot path, package-owned document/code/Mermaid affordances with explicit accessibility labels, and a release gate covering strict Swift-vs-Pretext fixture comparison, the shared native/KaTeX/MathJax math corpus, required test discovery, clean local SwiftPM consumer build, demo builds, DocC, and product probes. AppKit render probes remain available as an explicit `SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1` opt-in.

- **`swift-markdown`** (`Markdown` product) provides parsing semantics; SiriusMarkdown converts the AST to **`MarkdownBlock`** and **`MarkdownInlineRun`** value types.
- **`MarkdownStream`** stores append-only UTF-8, incrementally scans safe seal points, reparses only the **mutable tail**, preserves sealed reference definitions for later reference-link resolution without carrying definitions out of code/HTML content, and exposes **`MarkdownSnapshot`** plus source-backed copy slices.
- **`SiriusMarkdown`** is the app-facing umbrella module. Import **`SiriusMarkdownCore`** or **`SiriusMarkdownSwiftUI`** directly only when you need a narrower dependency.
- **`SiriusMarkdownSwiftUI`** renders prepared snapshots with **`MarkdownRenderSession`**, **`MarkdownDocumentView`**, **`MarkdownDocumentSurface`**, **`StreamingMarkdownView`**, **`MarkdownTheme`**, and **`MarkdownRendererConfiguration`** (policies, optional link/copy/export actions, pluggable language-aware code highlighting, image decisions, default-on document selection/copy, leaf-level native text selection compatibility, and math rendering).
- **`SiriusMarkdownMath`** is an optional product with a native math renderer. The core path remains source-preserving and renderer-agnostic. Dollar-delimited inline math detection leaves common currency/reward amounts and compact ISO currency-code amounts as text; chat-style single-line display math and conservative bare-TeX recovery route common generated equations to the configured math renderer without rewriting code spans, paths, escaped Markdown, or adjacent prose. Generated formulas using `\operatorname`, `\mathbb`, `cases`, `align*`, `equation`, angle-bracket pairs, Greek/font-style commands, and relation operators stay source-backed, with SwiftMath compatibility handled during math preparation rather than in SwiftUI body evaluation. Exact formula source participates in math-cache identity, platform image geometry is bounded before publication, and vendored SwiftMath shared registries are synchronized for concurrent preparation.

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

In production paths, prefer **`MarkdownRenderSession`** or keep **`MarkdownRendererConfiguration`** alive in your model layer and call **`prepare(snapshot:)`** before SwiftUI evaluates renderer bodies. Prepared snapshots carry policy-gated inline text, measured inline content, image decisions, highlighted code, rendered math, HTML policy decisions, table cells, list items, selection/copy source ranges, and host-boundary ordering. The compatibility `snapshot:` view initializers are deprecated because they skip full preparation and are only suitable for small compatibility surfaces; they still enforce cheap code, math, and HTML policy denials.

The default `MarkdownCodeHighlighter` normalizes info strings such as `language-swift`, `py`, `js`, `ts`, `yml`, `objc`, and `cpp` before calling the embedded JavaScriptCore/highlight.js backend where available. Supported explicit languages are highlighted during render preparation, while plaintext, nohighlight, unlabeled, unsupported, unavailable-runtime, or failed-backend fences stay plain. Code blocks render generic language-label, copy, export, and collapse affordances by default; hosts can hide or tune those affordances through `MarkdownTheme.codeBlockAffordances`. Hosts can keep the same injection point and pass `PlainMarkdownCodeHighlighter` or any custom highlighter through `MarkdownRendererConfiguration`.

Mermaid fences are prepared by `MarkdownMermaidRenderer` before SwiftUI body evaluation. The default renderer still uses the bundled DOM-free `beautiful-mermaid` runtime through JavaScriptCore and produces deterministic ASCII fallback plus light/dark SVG strings; it also extracts root SVG geometry and strips remote font imports during preparation. `MarkdownBlockView` renders the prepared SVG as a platform image inside a bounded two-axis pan/zoom viewport with package-owned zoom out, zoom in, fit, and reset controls. Tune those controls with `MarkdownTheme.mermaidAffordances` or disable Mermaid rendering entirely with `MarkdownRendererConfiguration(mermaidRenderer: nil)`. The diagram, document, and code control buttons carry explicit accessibility labels/help text; their decorative SF Symbol images are hidden from accessibility synthesis to avoid redundant localized symbol-description resolution in host updates. This is not a new Mermaid semantic engine and not a WebKit surface.

Allowed images (an explicit `MarkdownImagePolicy` `.allow` decision) flow as prepared inline attachments instead of alt text. `MarkdownPreparedAttachment` carries reserved `pointWidth`/`pointHeight`/`ascent`/`descent` box metrics — from a cheap ImageIO header probe of resolver-supplied bytes when available, otherwise `MarkdownTheme.attachmentPlaceholder`'s default box — and the CoreText line plan reserves a gap for that box via a `CTRunDelegate` instead of measuring alt text. One AppKit/UIKit host view exists per attachment instance, drawing either the resolved bytes or quiet reserved-box chrome; width-only relayout never re-invokes the resolver. Denied images (the default) are unaffected and keep rendering alt/`[image: reason]` text. This is the placement layer only: SiriusMarkdown does not fetch images over the network or decode/animate multi-frame formats on its own — those are separate, independently opt-in capabilities that mount inside these same attachment slots.

`MarkdownDocumentSurface` is the package-owned document chrome for static reader surfaces. It wraps already-prepared content with optional copy, export/download, collapse controls, and default-on source-backed document selection. `MarkdownRendererConfiguration.documentSelection` defaults to `.enabled`; when hosts do not inject a `MarkdownSelectionController`, document and streaming views create one internally and still support cross-block drag highlights and Cmd-C copy. `nativeTextSelection` remains a separate disabled-by-default compatibility knob for bounded text leaves and is not required for document selection. `MarkdownCopyProvider` can expose exact full-document Markdown in addition to range slices, and `MarkdownAffordanceActionHandler` lets host apps replace pasteboard/export behavior without changing the renderer model or moving work into view bodies.

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

SiriusMarkdown's default tests assert this contract through renderer preparation, diagnostics, exact source-backed selection copy tests, CRLF streaming equivalence, protocol-relative link denial, currency-safe dollar inline math detection, single-call math/HTML render-plan policy checks, and strict Pretext comparison: large streaming transcripts must keep stable prepared item IDs, repeated preparation must hit inline/code/math caches, width changes must reuse measured inline content, document collapse must preserve prepared identity, and Pretext drift must fail instead of being hidden as a passing known issue. AppKit `MarkdownDocumentView` and `MarkdownDocumentSurface` render probes are opt-in visual checks.

`MarkdownRendererConfiguration.compactChat`, `.document`, and direct custom configuration select `MarkdownInlineRenderingMode.coreTextPaintedLines` by default, so chat and document views paint prepared line slices inside the finite proposal supplied by the host. `MarkdownInlineRenderingMode.preparedNativeLines` and `.systemText` remain explicit compatibility fallbacks.

### Block styles

**`MarkdownTheme`** owns typography, colors, and metrics — and stays the prepare/layout cache identity core. **`MarkdownDocumentStyle`** and its fourteen per-block protocols (**`MarkdownHeadingBlockStyle`**, **`MarkdownParagraphBlockStyle`**, **`MarkdownBlockQuoteStyle`**, **`MarkdownCodeBlockStyle`**, **`MarkdownTableBlockStyle`**, **`MarkdownTableCellStyle`**, **`MarkdownListItemStyle`**, **`MarkdownUnorderedListMarkerStyle`**, **`MarkdownOrderedListMarkerStyle`**, **`MarkdownTaskListMarkerStyle`**, **`MarkdownThematicBreakStyle`**, **`MarkdownMathBlockStyle`**, **`MarkdownHTMLBlockStyle`**, **`MarkdownMermaidBlockStyle`**) own chrome — borders, backgrounds, dividers, and marker glyphs around already-prepared content. `makeBody(configuration:)` receives a prepared `MarkdownBlockStyleLabel` plus metadata; implementations must not parse Markdown, run inline layout, or perform CoreText prepare. Every protocol ships a `MarkdownDefault*Style` that reproduces the pre-protocol look.

Override one block without forking `MarkdownBlockView`:

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

Restyle every slot at once with a custom `MarkdownDocumentStyle` — unspecified slots fall back to their own default:

```swift
struct ReaderStyle: MarkdownDocumentStyle {
    var headingStyle: some MarkdownHeadingBlockStyle { UnderlineH1() }
}

MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
    .markdown.documentStyle(ReaderStyle())
```

Effective style per slot resolves as `.markdown.<slot>Style(_:)` override, then `.markdown.documentStyle(_:)` aggregate, then `MarkdownRendererConfiguration.documentStyle`, then `MarkdownDefault*Style` — a per-block override always wins over an aggregate document style regardless of which modifier is applied first. Chrome-only style changes never reparse Markdown, never change prepare/layout cache identity, and never churn sealed block IDs.

An opt-in, GitHub-inspired preset pairs a matching theme with matching chrome — apply both together, since heading sizes are a theme (prepare/measurement) concern:

```swift
MarkdownDocumentView(preparedSnapshot: prepared, configuration: .gitHub)
```

`MarkdownRendererConfiguration.gitHub` approximates common README rendering; it is not a pixel match for github.com's CSS, and it is never the default — `.compactChat` and `.document` are unaffected.

### Source navigation and reveal

SiriusMarkdown resolves which rendered block corresponds to a source line or range. Host apps own scrolling: ``SiriusMarkdownSwiftUI/StreamingMarkdownView`` does not wrap a `ScrollView`, while ``SiriusMarkdownSwiftUI/MarkdownDocumentView`` owns its own internal scroll surface.

Pass ``SiriusMarkdownCore/MarkdownBlockID`` to `ScrollViewReader.scrollTo(_:anchor:)`. That matches ``SiriusMarkdownSwiftUI/MarkdownBlockView``'s `.id(block.id)`. Do not pass ``SiriusMarkdownSwiftUI/MarkdownPreparedSnapshotRenderItem`` `.id` values (`"block:<raw>"` strings are for lightweight `ForEach` identity only).

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

Use ``SiriusMarkdownCore/MarkdownSourceRevealPolicy/exactOnly`` when a source line must lie inside a block range. The default ``SiriusMarkdownCore/MarkdownSourceRevealPolicy/nearestRenderedBlock`` resolves blank-line gaps and inter-block separators to the following rendered block (or the preceding block at end-of-document).

`MarkdownSelectionController.selectSourceLine(_:in:policy:)` selects the resolved block with coherent block-level source ranges so copy and highlight stay aligned. For byte-accurate partial-line selection, call `MarkdownSelectionController.selectSourceRanges(_:selectedBlockIDs:)` with explicit ranges from your source buffer.

Production CoreText measurement defaults to system-profile font measurement, and measured/layout caches include the measurement profile. Pretext golden fixtures use explicit named profiles such as Helvetica, and hosts with custom fonts can align measurement by providing `MarkdownInlineFontProfiles` through `MarkdownTheme`. The default `coreTextPaintedLines` mode paints whole prepared lines with CoreText `CTLineDraw`, derives fonts from the same font profiles, and keeps link hit regions tied to policy-filtered prepared link attributes.

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
- ``SiriusMarkdownCore/MarkdownSourceRange``
- ``SiriusMarkdownCore/MarkdownSourceRevealPolicy``
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
- ``SiriusMarkdownSwiftUI/MarkdownMermaidDiagramAffordances``
- ``SiriusMarkdownSwiftUI/MarkdownMermaidDiagramGeometry``
- ``SiriusMarkdownSwiftUI/MarkdownMermaidViewBox``

### Block styles

- ``SiriusMarkdownSwiftUI/MarkdownDocumentStyle``
- ``SiriusMarkdownSwiftUI/MarkdownHeadingBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownParagraphBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownBlockQuoteStyle``
- ``SiriusMarkdownSwiftUI/MarkdownCodeBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownTableBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownTableCellStyle``
- ``SiriusMarkdownSwiftUI/MarkdownListItemStyle``
- ``SiriusMarkdownSwiftUI/MarkdownUnorderedListMarkerStyle``
- ``SiriusMarkdownSwiftUI/MarkdownOrderedListMarkerStyle``
- ``SiriusMarkdownSwiftUI/MarkdownTaskListMarkerStyle``
- ``SiriusMarkdownSwiftUI/MarkdownThematicBreakStyle``
- ``SiriusMarkdownSwiftUI/MarkdownMathBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownHTMLBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownMermaidBlockStyle``
- ``SiriusMarkdownSwiftUI/MarkdownBlockStyleLabel``
- ``SiriusMarkdownSwiftUI/MarkdownGitHubDocumentStyle``

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
- ``SiriusMarkdownSwiftUI/MarkdownMermaidRenderer``
- ``SiriusMarkdownSwiftUI/DefaultMarkdownMermaidRenderer``
- ``SiriusMarkdownSwiftUI/MarkdownPreparedMermaidDiagram``
- ``SiriusMarkdownSwiftUI/MarkdownAffordanceActionHandler``
- ``SiriusMarkdownSwiftUI/MarkdownSelectionController``
- ``SiriusMarkdownSwiftUI/MarkdownPreparedImage``
- ``SiriusMarkdownSwiftUI/MarkdownPreparedAttachment``
- ``SiriusMarkdownSwiftUI/MarkdownAttachmentPlaceholderStyle``
- ``SiriusMarkdownCore/MarkdownAttachmentID``
- ``SiriusMarkdownCore/MarkdownInlineAttachmentMetrics``
- ``SiriusMarkdownCore/MarkdownAttachmentSizingSource``
