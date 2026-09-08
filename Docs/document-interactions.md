# Document interactions

`MarkdownDocumentView` provides native Find controls on macOS. Press Cmd-F,
enter text, then use Cmd-G or Shift-Cmd-G to navigate. Escape closes the bar.
Matching uses prepared visible text, crosses inline formatting, and preserves
source offsets. It does not search hidden HTML or rasterized LaTeX source.
The index is constructed off-main on demand; ordinary rendering and resizing
do not construct it.

A host can observe/control Find without supplying its own implementation:

```swift
@StateObject private var find = MarkdownDocumentFindController()

MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
    .documentFindController(find)
```

Heading links such as `#installation` reveal the matching heading in the
self-scrolled document. Heading slugs are lowercase, Unicode-aware, and receive
numeric suffixes for duplicates. External links retain the host's link callback.
Sanitized HTML element IDs are also indexed, including empty paragraphs and
inline anchors. Anchors without selectable glyphs reveal nearby content in their
owning block or the block position without adding text or layout height.
Explicit IDs take precedence over generated heading slugs; the first duplicate
in source order wins. Fragment IDs are case-sensitive and percent-decoded.

For host-scrolled `StreamingMarkdownView`, opt into the same Find and fragment
navigation with `.documentFindController(find)`:

```swift
ScrollView {
    StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
        .documentFindController(find)
}
```

The package updates the index on demand and reveals the active source fragment
through the existing native scroller. It does not insert a nested scroll view.
Only the active result mounts a reveal marker. Find works even when ordinary
document selection is disabled. The Find bar belongs to the transcript content;
hosts can also present the reusable `MarkdownDocumentFindBar` in their own toolbar.
Without the modifier, the streaming surface retains its existing render path.
To keep a single Find bar pinned above a host-owned scroller, suppress only the
streaming view's inline controls and supply the same controller to the external
bar:

```swift
VStack(spacing: 0) {
    if find.isPresented {
        MarkdownDocumentFindBar(controller: find)
    }
    ScrollView {
        StreamingMarkdownView(preparedSnapshot: prepared, configuration: configuration)
            .documentFindController(find, showsInlineControls: false)
    }
}
```

With inline controls suppressed, the host owns presenting Find, including its
Cmd-F command (`find.isPresented = true`). The external bar supplies next,
previous and dismissal controls. Indexing, selection highlighting, fragment
links and native scroll reveal retain their existing behavior. The original
one-argument modifier continues to show the package's inline controls.

Code and table results also reveal their inner horizontal scroller. Prepared
non-wrapping code uses native font metrics shared with selection geometry.
Mounted scrolling evidence currently covers macOS; UIKit uses its native scroll
rectangle API but still requires device validation.

## Selection and clipboard

The macOS document selector preserves visual line affinity and shaped bidi caret
positions. Double-click and Option-arrow use whole prepared text leaves, so an
emergency-wrapped word remains a word. The native Edit menu supports Copy and
Select All. On macOS, selection backgrounds paint below text and above code/table
surfaces, with active and inactive system selection colors. Selected line endings
extend to their own text column; continuing adjacent prose fills paragraph gaps,
while partial ranges retain shaped glyph edges. Existing native text surfaces
share the document owner and clear stale native ranges. Paint updates reuse
prepared line geometry without adding text hosts or per-leaf observers. Color
emoji and inline image attachments retain their intrinsic colors.

Document Copy supplies exact Markdown, semantic plain text, derived HTML, and
macOS RTF. Decorations are excluded. Sanitized HTML remains semantic; approved
links retain their destinations. UIKit preserves supplied rich representations.
Programmatic callers can use `selectedPasteboardPayload(in:copyProvider:)` on
`MarkdownSelectionController`.

## Native print and PDF

On macOS, prepare a fixed pagination result outside view evaluation:

```swift
let output = try MarkdownDocumentPrintExporter.prepare(prepared)
try output.writePDF(to: destination)
let operation = try output.makePrintOperation()
// The host decides when to present/run the print operation.
```

`MarkdownDocumentPrintOptions` supplies page size, margins, title, and font size.
Ordinary text and visual table-cell text remain selectable. `pages` exposes
contiguous semantic text ranges even when an image or formula replaces its text
visually. Tables use semantic cell metadata, including nested tables, column
and row spans, multiline and empty cells. Cell borders meet without inter-row
text spacing, and ordinary table headers repeat on continuation pages. Links
retain annotations aligned to their actual glyph positions.

Prepared data-backed or authorized local-file images and math rasters draw in
the PDF, including recursive list/quote/HTML leaves and table cells. Inline
math preserves its baseline and scales to print typography. Export performs
no network requests; unresolved resources keep their semantic fallback.

`limitations` reports text fallbacks for row-span groups too tall to fit the
page, unreadable/unsupported images, unrendered math and diagrams. A spanning
header joined to body rows is not repeated independently. Creating a print
operation does not print.

## Accessibility

Painted macOS links and native table links expose enabled accessibility elements
with press actions for policy-approved destinations, including document fragments.
Denied painted destinations do not create accessibility link actions. A link that
wraps across lines remains one semantic element. Headings expose heading traits.
Native math carries a bounded semantic expression tree built from the same
SwiftMath atoms used for rasterization. Math blocks expose native children for
numerators, denominators, roots, scripts and matrix rows/cells; exact LaTeX copy
is unchanged. Inline native math attachments expose the same tree and remove
stale children when their content changes. Default prepared macOS tables expose
row/column/cell roles, spans and column-header relationships, while retaining
link actions and math structure. Custom table styles and UIKit keep their
existing accessibility behavior.

## Optional remote images

Remote loading requires both an allowing `MarkdownImagePolicy` and
`RemoteMarkdownImageResolver` in the session configuration. The default image
policy continues to deny network images. Markdown and sanitized HTML images
share this authorization and preparation path. Custom hosts can implement
`MarkdownAsyncImageResolver` to supply their own asynchronous resources.

The supplied loader permits public HTTPS resources, rejects credentials and
private network endpoints, and uses anonymous requests. It bounds redirects,
response bytes, decoded dimensions/frame counts, concurrency, pending requests,
time, and positive/negative caches. Supported encoded formats are PNG, JPEG,
GIF and WebP, subject to platform decoding support and the configured limits.

Image completion refreshes only owning prepared blocks without reparsing source
or changing block identity. Completion values survive resolver-cache eviction
while their document still owns them. Reset and session release cancel pending
work; stale completions cannot update a replacement document.

Hosts may call `session.updateImageLoadingViewport(blockIDs:)` with visible
top-level block IDs. An empty set pauses loading; `nil` enables all authorized
document images. Leaving the supplied viewport cancels pending requests but
retains already prepared images. Visibility is supplied by the host; the package
does not automatically track viewport geometry.

`waitUntilIdle()` retains its preparation-only behavior. Use
`await session.waitUntilImagesIdle()` when an export or test also needs image
completion and its resulting preparation. Network work starts in the session,
never during SwiftUI view evaluation.
