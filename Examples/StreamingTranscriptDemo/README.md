# StreamingTranscriptDemo

Streaming SwiftUI demo packaged as a local SwiftPM executable.

For a **macOS `.app`**:

```sh
Examples/scripts/bundle-macos-demos.sh StreamingTranscriptDemo
open Examples/MacOSArtifacts/StreamingTranscriptDemo.app
```

Debug-run from the repo:

```sh
swift run --package-path Examples/StreamingTranscriptDemo
```

The demo appends timed chunks into `MarkdownStream` and renders snapshots with `StreamingMarkdownView`.
