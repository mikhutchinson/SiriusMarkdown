# ``SiriusMarkdown``

Native, streaming-first Markdown rendering for Apple platforms.

## Overview

Use `SiriusMarkdownCore` to build snapshots from streamed Markdown source and `SiriusMarkdownSwiftUI` to render those snapshots natively.

```swift
var stream = MarkdownStream()
stream.append("# Hello")
stream.finish()
let snapshot = stream.snapshot()
```

