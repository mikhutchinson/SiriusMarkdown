# DocumentReaderDemo

Document-reader SwiftUI demo packaged as a local SwiftPM executable.

For a **macOS `.app`**:

```sh
Examples/scripts/bundle-macos-demos.sh DocumentReaderDemo
open Examples/MacOSArtifacts/DocumentReaderDemo.app
```

Debug-run from the repo:

```sh
swift run --package-path Examples/DocumentReaderDemo
```

The demo stresses static documents, inline styling, safe and unsafe links, denied image loading, quotes, hard breaks, nested and ordered lists, multilingual text, wide code blocks, tables, math blocks, raw HTML policy behavior, and document-theme rendering.
