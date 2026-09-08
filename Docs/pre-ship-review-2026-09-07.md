# Pre-ship review

## Judgment

The fixes improve the renderer, but the current checkout does not establish
best-in-class interaction or a release-ready state. The remaining keyboard and
accessibility gaps deserve priority before a broad quality claim.

## Fixed in this review

- Connected document Copy and Select All to native responder-chain actions and
  menu validation. A mounted test sends the actions through `NSApp.sendAction`.
- Reused the already-built streaming region array within one view evaluation,
  removing a duplicate grouping/copy/fingerprint pass.
- Skipped table-wide inferred-column allocation/scanning when both prepared
  width arrays are supplied. Public span/column boundary normalization remains.

The two reductions remove demonstrably redundant work. Their individual speedup
has not been benchmarked; they do not prove the latency problem below is solved.

## Remaining interaction work

1. Horizontal keyboard movement follows source byte order, not shaped visual
   caret order. RTL and mixed-direction lines need directional caret affinity.
2. `fragment(containing:)` chooses the first inclusive source-range match. A
   shared wrapped-line boundary can resolve to the preceding line, affecting
   Command-arrow and vertical movement. Preserve visual line affinity.
3. Word navigation and double-click selection tokenize a rendered line. Words
   split by emergency wrapping need leaf-wide word boundaries.
4. Painted content needs stronger native accessibility structure and actions:
   heading navigation, individually actionable links, table relationships, and
   document selection exposure. Math has textual semantics but not a navigable
   mathematical expression tree.

Relevant implementation: `Interaction/MarkdownDocumentSelectionInteraction.swift`,
`Inline/NativeInlineLineTextView.swift`, and `Blocks/MarkdownBlockView.swift` under
`Sources/SiriusMarkdownSwiftUI`.

## Performance evidence

From the earlier complete passing run, not a fresh benchmark of this review:

| Workload | Observed median |
| --- | ---: |
| Small to larger document explicit append layout | 0.08 to 0.27 ms |
| Large 178,960-byte rapid-publication fixture, late total | 1,340.31 ms |
| Same fixture, pipeline and SwiftUI graph portion | 1,335.10 ms |
| Same fixture, explicit layout portion | 5.58 ms |
| Streaming table, early to late total | 51.91 to 796.09 ms |
| Streaming table, late explicit layout | 0.93 ms |

These are fully mounted debug stress fixtures, not production release timings or
cross-engine benchmarks. They pass existing thresholds but reveal poor end-to-end
latency at scale. Profile preparation/publication and SwiftUI graph invalidation
before targeting glyph measurement. Any viewport strategy must retain selection,
stable identity, and the bounded-region contract; previous LazyVStack failures
mean blindly swapping in a lazy stack is not a fix.

Log: `/tmp/siriusmarkdown-complete-validation.log`.

## Browser capability gaps

Repository inspection found no packaged document-wide Find controller, internal
heading/HTML-ID navigation index, or paginated print/PDF path. Default links go
to the OS opener, so internal anchors require host routing. Cross-block copy
produces plain text plus Markdown rather than derived HTML/RTF. Image policy
safety is deliberate, but an optional viewport-aware async image loader is not
bundled. Hosts can supply resolved images.

WKWebView exposes document [Find and other document operations](https://developer.apple.com/documentation/webkit/wkwebview).
WebKit also provides [semantic accessibility and accessible MathML](https://webkit.org/blog/3302/aria-and-accessibility-inspector/).
These are capabilities of the engine/platform, not a claim that every WebKit
Markdown wrapper configures them correctly or outperforms SiriusMarkdown.

Scripts, arbitrary CSS, embedded browsing, and uncontrolled resource loads are
intentional exclusions. They are not requirements for native Markdown parity.

## Release status

No release, commit, or push performed. The previous full suite and visual probe
are evidence for the earlier snapshot. Focused validation for this review: 15 tests passed in 0.871 seconds, including
mounted menu actions, integer boundaries, streaming region stability, and
mounted resize. Log: `/tmp/siriusmarkdown-preship-focus.log`. Discovery is 1009
tests, with all 393 required names present. Full release gates
and hands-on VoiceOver/keyboard/trackpad verification remain outstanding.
