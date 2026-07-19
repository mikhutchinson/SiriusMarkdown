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
- **`diagnosticsCounters`** — parse/cache/boundary-scan counters from the stream’s diagnostics recorder.
- **`markdown(in:)`** — returns a bounded source slice for a `MarkdownSourceRange`, used by copy-as-Markdown flows without materializing unrelated source.

## Sealing

After each **`append`**, **`sealBoundaryIfPossible()`** runs. `MarkdownStream` keeps **`MarkdownBoundaryScanState`** for the active tail, so newly appended complete lines are scanned once instead of rescanning the whole unsealed suffix. If the scanner returns a byte offset strictly greater than the current seal point, Core parses **`[sealedUpperBound, upperBound)`**, appends blocks to **`sealedBlocks`**, records any reference definitions from that sealed slice, resets scanner state to the new seal point, and advances **`sealedUpperBound`**.

The scanner is **conservative**: it must not seal inside constructs that later bytes could extend or invalidate.

Current rules (see `MarkdownBoundaryScanner.swift`):

- **Fenced code** — opening ` ``` ` / `~~~` tracks depth until a closing line with enough matching markers.
- **Math** — `$$` toggles an open math fence until a closing `$$`.
- **HTML blocks** — heuristic open/close for comments and several block tags (`script`, `style`, `pre`, `table`, `div`, etc.) until the closing token appears.
- **Reference links** — unresolved full, collapsed, or shortcut reference labels keep the region mutable. Matching definitions make the region sealable; definitions sealed earlier are included when later slices are parsed so `swift-markdown` resolves the links. Reference-looking lines inside parsed code/HTML content are not carried forward as definitions.
- **Blank lines** — a candidate seal ends after a blank line **unless** the scanner is inside fence/HTML/math.
- **Loose ordered lists** — after a **list-like** non-blank line, a **single** trailing blank line does **not** yield a seal candidate (avoids sealing early before continuation lines); **two** consecutive blanks still allow a candidate.

If any fence/HTML/math remains open, or if unresolved reference labels remain ambiguous at EOF-of-scan, **no** seal is returned for that scan. Literal unmatched bracket text recovers at blank-line block boundaries so one malformed paragraph does not pin the rest of a long stream in the mutable tail.

## Host boundaries

**`appendHostBoundary(id: MarkdownHostBoundaryID? = nil)`** forces Markdown and native insertions to align:

- If there is buffered tail past **`sealedUpperBound`**, it **seals up to `source.byteCount`** first.
- Then a **`MarkdownHostBoundary`** is recorded at the current source offset (optional stable **`id`**).

**`snapshot()`** builds **`MarkdownSnapshot.items`**: blocks and **`hostBoundary`** entries ordered by source offsets so hosts can render native chrome between Markdown regions. Default **`MarkdownSnapshot`** initialization can derive **`items`** from **`blocks`** alone when you omit custom ordering. `MarkdownDocumentView` and `StreamingMarkdownView` can render prepared snapshot items with a host-boundary closure; their default host-boundary renderer is empty.

Host applications should prepare snapshots before crossing into SwiftUI:

```swift
let configuration = MarkdownRendererConfiguration.compactChat
let prepared = configuration.prepare(snapshot: stream.snapshot())
StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
```

Keeping the configuration alive lets the render-preparation cache reuse inline, highlighted-code, and rendered-math work as the mutable tail changes.

`StreamingMarkdownView` groups prepared render items into stable regions of at
most 16 items. A region identity includes the prepared item revisions it owns.
The custom non-lazy region layout caches each settled size by identity,
revision, and proposal width, so an append normally remeasures only the final
region containing the mutable tail. Region geometry reports are quantized,
asynchronous, and coalesced before they invalidate the parent. This keeps the
full feature-complete SwiftUI hierarchy mounted without relying on
`LazyVStack`'s private item-phase cache or synchronously fitting the whole
document after every publication.

## Snapshots

**`MarkdownSnapshot`** includes:

- **`blocks`** — sealed blocks plus tail blocks (tail empty when caught up or finished).
- **`items`** — optional interleaving with host boundaries.
- **`generation`** — bumps on append, seal steps, host boundaries, and finish (useful for view identity).
- **`isFinished`** — whether **`finish()`** was called.

**`MarkdownPreparedSnapshot`** includes:

- **`items`** — prepared block content and host boundaries.
- **`renderItems`** — stable render item identifiers for `ForEach`.
- **`diff`** — **`MarkdownPreparedSnapshotDiff`** identifying changed, new, and removed item IDs since the last published snapshot. The diff is computed during `prepare(snapshot:reusing:)` as a byproduct of the existing reuse detection — reused items are unchanged, freshly prepared items are changed or new.

**`MarkdownRenderSession`** publishes both the full `MarkdownPreparedSnapshot` and the `MarkdownPreparedSnapshotDiff` via `@Published`. Views can consume the diff to minimize `ForEach` churn; unchanged sealed blocks do not trigger view re-evaluation during streaming appends.

The render pump starts with `Task.detached(priority: .userInitiated)`. It
drains queued operations and publishes prepared values through narrow
MainActor hops, while parsing, AST conversion, highlighting, math/Mermaid
preparation, and inline preparation execute outside the caller's actor and
task-local context.

Active, unsealed prepared values do not enter the stable inline, code, math, or
Mermaid caches. Plain and Highlight.js-backed highlighting keeps one rolling
state for the active block and highlights append-only suffixes between 16 KiB
full-context checkpoints. The pinned Highlight.js wrapper forwards the
parser's opaque continuation so multiline comments and strings retain exact
lexical context. Every block receives a full highlight when it seals. The
native Swift and custom highlighters continue to receive the full document on
every publication because no equivalent continuation contract is available.

### Mutable streaming tables

A GFM table remains one mutable parser block until it seals, but its prepared
renderer state is incremental below that block boundary. Row and cell IDs use
the stable block/source start plus structural role and column; mutable source
upper bounds and content hashes are revisions, never renderer identity.

`prepare(snapshot:reusing:)` retains the completed row prefix as persistent
prepared values, compares/prepares only the prior tail row and newly appended
rows, and reuses unchanged prepared cell inline measurements. Column natural
widths are monotonic during streaming and inspect only changed cells. Effective
widths grow through bounded 64-point buckets, preventing every token in one
cell from resizing all historical rows; sealing performs one exact-width pass
so a finished streamed table matches one-shot preparation.

SwiftUI consumes the prepared widths directly. A bounded row-size cache keyed
by stable row fingerprint and column-width revision survives prepared-root
publication, so only changed rows or a genuine width revision call into row
`sizeThatFits`. None of this gates source publication: partial cells, links,
and URLs remain visible before their row-ending newline.

Semantics always come from **`swift-markdown`** on each parsed slice; the scanner only chooses slice boundaries. The scanner's reference-label tracking is a sealing guard, not a Markdown parser.

## Related docs

- `Docs/architecture.md` — module map and responsibilities.
- `Docs/performance.md` — tail vs sealed parse counts and caches.
- `Docs/native-renderer-scorecard.md` — product quality bar.
