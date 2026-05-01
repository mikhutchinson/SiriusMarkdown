# Streaming

`MarkdownStream` stores append-only UTF-8 source chunks and exposes snapshots made from immutable sealed blocks plus one mutable tail.

The conservative boundary scanner only seals once Markdown is unlikely to be invalidated by future chunks. Host boundaries can force-seal the current tail before a native insertion.

Current implementation status:

- Code and math fences are protected from early sealing.
- Blank lines are safe seal candidates outside fences.
- Host boundaries are explicit through `appendHostBoundary()`.

