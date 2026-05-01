# MarkdownDemoApp

Static-document SwiftUI demo packaged as a local SwiftPM executable.

For a **macOS `.app`** (Finder / Dock, not tied to the terminal process):

```sh
Examples/scripts/bundle-macos-demos.sh MarkdownDemoApp
open Examples/MacOSArtifacts/MarkdownDemoApp.app
```

Debug-run from the repo as a plain executable:

```sh
swift run --package-path Examples/MarkdownDemoApp
```

The demo imports the public `SiriusMarkdown` umbrella module, parses sample Markdown into a `MarkdownSnapshot`, and renders it with `MarkdownDocumentView`.
