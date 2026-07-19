# MarkdownDemoApp

Static-document SwiftUI demo packaged as a local SwiftPM executable.

The app is a native macOS workbench for the public `SiriusMarkdown` renderer. It uses shared `Examples/DemoSupport` tokens, surfaces, sidebar rows, metric rows, icon buttons, and affordance bars; package-owned document/code affordances; a sidebar of examples; and an optional inspector for coverage and pipeline counters.

Demonstrated cases:

- Overview document with task lists, quotes, code, Mermaid diagrams, and a contract table.
- Native rich-HTML overview with HTML5 recovery, source-mapped structure, and decorated HTML anchors.
- Exhaustive HTML element gallery covering h1-h6, every documented inline semantic, containers, quotes, lists, tables, preformatted code, thematic breaks, and both allowed and denied image-policy outcomes.
- HTML safety and media boundary showing dropped scripts, styles, embeds, video, audio, canvas, SVG, and controls alongside inert URL/image fallbacks and sanitizer diagnostics.
- Inline policy matrix for safe links, unsafe links, reference-style links, remote images, emphasis, strikethrough, and inline code.
- Table stress cases for dense rows, alignment, long cells, multilingual values, and horizontal containment.
- Wide blocks with long code and wide table values.
- Multilingual layout with CJK, RTL, emoji, hard breaks, and inline code.
- Native LaTeX math rendered through the package math hook.
- Long-form document rhythm with nested structure and cache evidence.

For a **macOS `.app`** (Finder / Dock, not tied to the terminal process):

```sh
Examples/scripts/bundle-macos-demos.sh MarkdownDemoApp
open Examples/MacOSArtifacts/MarkdownDemoApp.app
```

Debug-run from the repo as a plain executable:

```sh
swift run --package-path Examples/MarkdownDemoApp
```

The demo imports the public `SiriusMarkdown` umbrella module, parses each sample with `MarkdownStream`, prepares snapshots through `MarkdownRendererConfiguration`, and renders with `MarkdownDocumentSurface`.
