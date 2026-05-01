# MarkdownDemoApp

Static-document SwiftUI demo packaged as a local SwiftPM executable.

```sh
swift build --package-path Examples/MarkdownDemoApp
```

The demo imports the public `SiriusMarkdown` umbrella module, parses sample Markdown into a `MarkdownSnapshot`, and renders it with `MarkdownDocumentView`.
