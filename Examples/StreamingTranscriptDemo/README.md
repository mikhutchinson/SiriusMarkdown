# StreamingTranscriptDemo

Streaming SwiftUI demo packaged as a local SwiftPM executable.

This app is the streaming lab. It keeps the transcript surface primary, uses
toolbar controls for restart/pause/step/burst, shows subtle sealed-tail state
inside the stream surface, and keeps diagnostics behind an optional inspector.
The sidebar, status pills, icon buttons, metric rows, transcript surface, and
inspector chrome come from the shared `Examples/DemoSupport` design language.

For a **macOS `.app`**:

```sh
Examples/scripts/bundle-macos-demos.sh StreamingTranscriptDemo
open Examples/MacOSArtifacts/StreamingTranscriptDemo.app
```

Debug-run from the repo:

```sh
swift run --package-path Examples/StreamingTranscriptDemo
```

The demo appends timed chunks, including a Mermaid fence, into `MarkdownStream`,
renders prepared snapshots with `StreamingMarkdownView`, and uses shared demo
controls from `Examples/DemoSupport`.
