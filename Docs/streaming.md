# Streaming

## Model

`MarkdownStream` keeps **append-only UTF-8** in `MarkdownSourceBuffer`. Parsed output is split into:

1. **Sealed blocks** — immutable once sealed; parses are cached in `MarkdownParserCache`.
2. **Mutable tail** — from `sealedUpperBound` to `source.byteCount`; reparsed on each `snapshot()` while the stream is unfinished.

Calling **`finish()`** seals any remaining tail through the end of source and marks the stream finished so further **`append`** is invalid.

## API sketch

```swift
var stream = MarkdownStream()
stream.append("# Hi\n\nStill typing…")
// Optional: stream.sealBoundaryIfPossible()  // also invoked from append
let partial = stream.snapshot()

stream.append(" Done.\n")
stream.finish()
let final = stream.snapshot()
```

- **`sourceLength`** — current byte length of buffered source.
- **`diagnosticsCounters`** — parse/cache counters from the stream’s diagnostics recorder.

## Sealing

After each **`append`**, **`sealBoundaryIfPossible()`** runs. It asks **`MarkdownBoundaryScanner.safeSealUpperBound(in:after:)`** for a byte offset strictly greater than the current seal point. If present, Core parses **`[sealedUpperBound, upperBound)`**, appends blocks to **`sealedBlocks`**, and advances **`sealedUpperBound`**.

The scanner is **conservative**: it must not seal inside constructs that later bytes could extend or invalidate.

Current rules (see `MarkdownBoundaryScanner.swift`):

- **Fenced code** — opening ` ``` ` / `~~~` tracks depth until a closing line with enough matching markers.
- **Math** — `$$` toggles an open math fence until a closing `$$`.
- **HTML blocks** — heuristic open/close for comments and several block tags (`script`, `style`, `pre`, `table`, `div`, etc.) until the closing token appears.
- **Blank lines** — a candidate seal ends after a blank line **unless** the scanner is inside fence/HTML/math.
- **Loose ordered lists** — after a **list-like** non-blank line, a **single** trailing blank line does **not** yield a seal candidate (avoids sealing early before continuation lines); **two** consecutive blanks still allow a candidate.

If any fence/HTML/math remains open at EOF-of-scan, **no** seal is returned for that scan.

## Host boundaries

**`appendHostBoundary(id: MarkdownHostBoundaryID? = nil)`** forces Markdown and native insertions to align:

- If there is buffered tail past **`sealedUpperBound`**, it **seals up to `source.byteCount`** first.
- Then a **`MarkdownHostBoundary`** is recorded at the current source offset (optional stable **`id`**).

**`snapshot()`** builds **`MarkdownSnapshot.items`**: blocks and **`hostBoundary`** entries ordered by source offsets so hosts can render native chrome between Markdown regions. Default **`MarkdownSnapshot`** initialization can derive **`items`** from **`blocks`** alone when you omit custom ordering.

## Snapshots

**`MarkdownSnapshot`** includes:

- **`blocks`** — sealed blocks plus tail blocks (tail empty when caught up or finished).
- **`items`** — optional interleaving with host boundaries.
- **`generation`** — bumps on append, seal steps, host boundaries, and finish (useful for view identity).
- **`isFinished`** — whether **`finish()`** was called.

Semantics always come from **`swift-markdown`** on each parsed slice; the scanner only chooses slice boundaries.

## Related docs

- `Docs/architecture.md` — module map and responsibilities.
- `Docs/performance.md` — tail vs sealed parse counts and caches.
- `plan.md` — full streaming and test expectations.
