# MarkdownDemoApp

Static-document SwiftUI demo packaged as a local SwiftPM executable.

The app is a native macOS workbench for the public `SiriusMarkdown` renderer. It uses the same design language as the other demos: a sidebar of examples, a rendered document surface, and an inspector that reports coverage and pipeline counters.

Demonstrated cases:

- Overview document with task lists, quotes, code, and a contract table.
- Inline policy matrix for safe links, unsafe links, remote images, emphasis, strikethrough, and inline code.
- Table stress cases for dense rows, alignment, long cells, multilingual values, and horizontal containment.
- Wide blocks with long code and wide table values.
- Multilingual layout with CJK, RTL, emoji, hard breaks, and inline code.
- Math and raw-HTML policy behavior.
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

The demo imports the public `SiriusMarkdown` umbrella module, parses each sample with `MarkdownStream`, prepares snapshots through `MarkdownRendererConfiguration`, and renders with `MarkdownDocumentView`.
