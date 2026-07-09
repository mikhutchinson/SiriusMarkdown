import SiriusMarkdownCore
import Foundation

#if canImport(CoreText)
import CoreText

/// Shared `CTRunDelegate` construction for reserved attachment box metrics
/// (Inline Attachments Part 02 §2.2.2, Strategy A). Both the CoreText paint
/// path (`CoreTextPaintedInlineLineView`) and the document-selection local
/// `CTLine` (`MarkdownDocumentSelectionGeometry`) attach the same delegate
/// shape to an attachment run's `NSRange` so glyph advance/ascent/descent
/// come from prepared metrics instead of the placeholder character's own
/// (irrelevant) font metrics — that is what keeps wrap/selection x-mapping
/// box-precise (INV-IA2, INV-IA5) instead of alt-text-width-precise.
enum MarkdownAttachmentRunDelegate {
    static func make(_ metrics: MarkdownInlineAttachmentMetrics) -> CTRunDelegate? {
        let boxRef = Unmanaged.passRetained(MarkdownAttachmentRunDelegateBox(metrics))
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { refCon in
                Unmanaged<MarkdownAttachmentRunDelegateBox>.fromOpaque(refCon).release()
            },
            getAscent: { refCon in
                CGFloat(Unmanaged<MarkdownAttachmentRunDelegateBox>.fromOpaque(refCon).takeUnretainedValue().metrics.ascent)
            },
            getDescent: { refCon in
                CGFloat(Unmanaged<MarkdownAttachmentRunDelegateBox>.fromOpaque(refCon).takeUnretainedValue().metrics.descent)
            },
            getWidth: { refCon in
                CGFloat(Unmanaged<MarkdownAttachmentRunDelegateBox>.fromOpaque(refCon).takeUnretainedValue().metrics.pointWidth)
            }
        )
        // `CTRunDelegateCreate` retains `refCon` itself once it succeeds
        // (released later via the `dealloc` callback above); on the
        // (practically unreachable, but not impossible) failure path it
        // never takes ownership, so the `passRetained` box must be
        // released here or it leaks.
        guard let delegate = CTRunDelegateCreate(&callbacks, boxRef.toOpaque()) else {
            boxRef.release()
            return nil
        }
        return delegate
    }
}

private final class MarkdownAttachmentRunDelegateBox {
    let metrics: MarkdownInlineAttachmentMetrics

    init(_ metrics: MarkdownInlineAttachmentMetrics) {
        self.metrics = metrics
    }
}
#endif
