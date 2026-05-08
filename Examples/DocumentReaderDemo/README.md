# DocumentReaderDemo

Document-reader SwiftUI demo packaged as a local SwiftPM executable.

This app is intentionally not another renderer dashboard. `MarkdownDemoApp` is
the static-document workbench for coverage and pipeline counters; this demo is a
reader product surface that presents one prepared Markdown document as native
long-form reading material.

Reader-focused behavior:

- Library-style sidebar with current-document summary, contents, and reading metadata.
- `MarkdownDocumentSurface` document chrome with source-backed copy, export, and collapse controls.
- Toolbar actions for returning to the document top, toggling the inspector, and switching reading measure.
- Calm page surface that keeps diagnostics out of the reading flow unless the inspector is opened.
- Shared `DemoSupport` tokens, sidebar rows, icon buttons, metrics, and inspector surfaces used by the other bundled demos.
- Reader sample content that still exercises links, denied images, task lists, multilingual text, code, Mermaid diagrams, tables, math, and raw-HTML policy behavior.

For a **macOS `.app`**:

```sh
Examples/scripts/bundle-macos-demos.sh DocumentReaderDemo
open Examples/MacOSArtifacts/DocumentReaderDemo.app
```

Debug-run from the repo:

```sh
swift run --package-path Examples/DocumentReaderDemo
```

The demo imports the public `SiriusMarkdown` umbrella module, prepares a static
document through `MarkdownRendererConfiguration`, and renders prepared blocks
inside the package-owned document surface.
