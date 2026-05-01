# Performance

The v0.1 performance contract is enforced by architecture and tests:

- Appends only reparse the mutable tail.
- Sealed regions are immutable and cacheable.
- Width changes operate on prepared inline content.
- Renderer identity comes from stable `MarkdownBlockID` values.
- SwiftUI `body` renders snapshots only.

CoreText is the measurement backend for native text shaping. Accelerate and Metal remain future optimization or visualization tracks until correctness and streaming behavior are stable.

