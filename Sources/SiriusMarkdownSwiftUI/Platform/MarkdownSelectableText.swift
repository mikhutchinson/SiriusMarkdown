import SiriusMarkdownCore
import SwiftUI

struct MarkdownSelectableText: View {
    var attributed: AttributedString
    var font: Font
    var fontSize: Double
    var lineHeight: Double
    var fontProfile: MarkdownFontProfile
    var textColor: Color
    var linkAction: MarkdownLinkAction?
    var nativeTextSelection: MarkdownNativeTextSelection
    var lineSpacing: CGFloat = 0
    var wraps: Bool = true
    var selectionInlineLayout: MarkdownPreparedInlineContent?
    var preparedInlineContent: MarkdownPreparedInlineContent? = nil
    var mathTextPieces: [MarkdownInlineMathPiece]? = nil

    @Environment(\.markdownDocumentSelectionContext) private var documentSelectionContext

    @ViewBuilder
    var body: some View {
        if selectionInlineLayout != nil, documentSelectionContext != nil {
            selectableContent
                .background(selectionFragmentPreference)
        } else {
            selectableContent
        }
    }

    @ViewBuilder
    private var selectableContent: some View {
        #if os(macOS)
        if nativeTextSelection == .enabled {
            MarkdownAppKitSelectableTextView(
                attributed: attributed,
                fallbackFontSize: fontSize,
                fallbackLineHeight: lineHeight,
                fallbackFontProfile: fontProfile,
                textColor: textColor,
                linkAction: linkAction,
                lineSpacing: lineSpacing,
                wraps: wraps,
                preparedInlineContent: preparedInlineContent,
                mathTextPieces: mathTextPieces
            )
        } else {
            swiftUIText
        }
        #else
        swiftUIText
        #endif
    }

    private var swiftUIText: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(textColor)
            .lineSpacing(lineSpacing)
            .markdownNativeTextSelection(nativeTextSelection)
            .environment(\.openURL, markdownOpenURLAction(linkAction: linkAction))
    }

    private var selectionFragmentPreference: some View {
        GeometryReader { proxy in
            let rect = selectionPreferenceRect(from: proxy)
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: selectionFragments(rect: rect)
            )
        }
        .allowsHitTesting(false)
    }

    private func selectionPreferenceRect(from proxy: GeometryProxy) -> CGRect {
        selectionInlineLayout?.layoutCache.recordSelectionPreferenceBodyEvaluation()
        selectionInlineLayout?.layoutCache.recordSelectionFrameQuery()
        return proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
    }

    private func selectionFragments(rect: CGRect) -> [MarkdownDocumentSelectionFragment] {
        guard let documentSelectionContext,
              let selectionInlineLayout,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0
        else {
            return []
        }

        let layoutWidth: Double
        if wraps {
            layoutWidth = InlineRunsView.nativeLineLayoutWidth(
                for: selectionInlineLayout,
                containerWidth: Double(rect.width)
            )
        } else {
            layoutWidth = max(Double(rect.width), selectionInlineLayout.measured.naturalWidth)
        }

        return MarkdownDocumentSelectionFragment.inlineLineFragments(
            blockID: documentSelectionContext.blockID,
            prepared: selectionInlineLayout,
            layout: selectionInlineLayout.layout(
                containerWidth: layoutWidth,
                allowsOverwideFallback: wraps
            ),
            rect: rect,
            idPrefix: "selectable-text"
        )
    }
}

#if os(macOS)
import AppKit

private struct MarkdownAppKitSelectableTextView: NSViewRepresentable {
    var attributed: AttributedString
    var fallbackFontSize: Double
    var fallbackLineHeight: Double
    var fallbackFontProfile: MarkdownFontProfile
    var textColor: Color
    var linkAction: MarkdownLinkAction?
    var lineSpacing: CGFloat
    var wraps: Bool
    var preparedInlineContent: MarkdownPreparedInlineContent?
    var mathTextPieces: [MarkdownInlineMathPiece]?

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(linkAction: linkAction)
    }

    func makeNSView(context: Context) -> MarkdownAppKitNativeSelectableContainerView {
        let container = MarkdownAppKitNativeSelectableContainerView(frame: .zero)
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindPanel = false
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        configure(textView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: MarkdownAppKitNativeSelectableContainerView, context: Context) {
        context.coordinator.linkAction = linkAction
        configure(container.textView, coordinator: context.coordinator)
        container.needsLayout = true
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView container: MarkdownAppKitNativeSelectableContainerView,
        context: Context
    ) -> CGSize? {
        let textView = container.textView
        configure(textView, coordinator: context.coordinator)
        return measuredSize(for: textView, proposedWidth: proposal.width)
    }

    private func configure(
        _ textView: MarkdownAppKitNativeSelectableTextView,
        coordinator: Coordinator
    ) {
        let resolvedTextColor = MarkdownPlatformColorResolver.appKitColor(
            textColor,
            colorScheme: colorScheme
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = !wraps
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = wraps
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        textView.colorScheme = colorScheme
        textView.textColor = resolvedTextColor
        textView.font = fallbackFont

        let next = attributedStringWithFallbackAttributes(
            coordinator: coordinator,
            resolvedTextColor: resolvedTextColor
        )
        let nextAttributed = next.attributed
        if textView.textStorage?.string != nextAttributed.string ||
            textView.textStorage?.length != nextAttributed.length ||
            textView.textStorage.map({ !$0.isEqual(to: nextAttributed) }) == true {
            let selectedSemanticRanges = textView.selectedRanges.compactMap { value in
                textView.semanticRange(for: value.rangeValue)
            }
            textView.textStorage?.setAttributedString(nextAttributed)
            let restoredRanges = selectedSemanticRanges.map { range in
                NSValue(range: textView.storageRange(forSemanticRange: range))
            }
            textView.setSelectedRanges(
                restoredRanges.isEmpty
                    ? [NSValue(range: NSRange(location: 0, length: 0))]
                    : restoredRanges,
                affinity: textView.selectionAffinity,
                stillSelecting: false
            )
        }
        textView.nativeAttachmentCacheCount = coordinator.retainNativeTextAttachments(
            ids: Set(next.attachments.map(\.id))
        )
        textView.nativeMathAttachmentCacheCount = coordinator.retainNativeMathAttachments(
            keys: next.mathAttachmentKeys
        )
        textView.preparedAttachments = next.attachments
        if textView.accessibilityValue() != next.plainText {
            textView.setAccessibilityValue(next.plainText)
        }
        textView.reconcilePreparedAttachmentHosts()
    }

    private func measuredSize(for textView: NSTextView, proposedWidth: CGFloat?) -> CGSize {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            return CGSize(width: proposedWidth ?? 0, height: CGFloat(fallbackLineHeight))
        }

        let finiteProposedWidth = proposedWidth.flatMap { width in
            width.isFinite && width > 0 ? width : nil
        }
        let naturalWidth = max(1, ceil(textView.textStorage?.size().width ?? 1) + 1)
        let targetWidth = wraps ? (finiteProposedWidth ?? naturalWidth) : naturalWidth

        if wraps {
            textView.frame.size.width = targetWidth
        }
        textContainer.containerSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        if let nativeTextView = textView as? MarkdownAppKitNativeSelectableTextView {
            nativeTextView.reconcilePreparedAttachmentHosts()
        }
        let usedRect = layoutManager.usedRect(for: textContainer)
        let measuredWidth = wraps ? (finiteProposedWidth ?? ceil(usedRect.width)) : ceil(usedRect.width)
        let measuredHeight = max(CGFloat(fallbackLineHeight), ceil(usedRect.height))
        return CGSize(width: max(1, measuredWidth), height: measuredHeight)
    }

    private func attributedStringWithFallbackAttributes(
        coordinator: Coordinator,
        resolvedTextColor: NSColor
    ) -> (
        attributed: NSAttributedString,
        attachments: [MarkdownAppKitNativeAttachmentPlacement],
        mathAttachmentKeys: Set<MarkdownAppKitMathAttachmentKey>,
        plainText: String
    ) {
        let source = appKitAttributedSource(
            coordinator: coordinator,
            resolvedTextColor: resolvedTextColor
        )
        let nsAttributed = source.attributed
        let fullRange = NSRange(location: 0, length: nsAttributed.length)
        guard fullRange.length > 0 else {
            return (nsAttributed, [], source.mathAttachmentKeys, source.plainText)
        }

        nsAttributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard !(value is NSFont) else {
                return
            }
            nsAttributed.addAttribute(.font, value: fallbackFont, range: range)
        }

        nsAttributed.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard value == nil else {
                return
            }
            nsAttributed.addAttribute(.foregroundColor, value: resolvedTextColor, range: range)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        nsAttributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        let attachments: [MarkdownAppKitNativeAttachmentPlacement]
        if mathTextPieces == nil {
            attachments = applyPreparedAttachments(to: nsAttributed, coordinator: coordinator)
        } else {
            attachments = source.attachments
        }
        return (
            nsAttributed,
            attachments,
            source.mathAttachmentKeys,
            source.plainText
        )
    }

    private func appKitAttributedSource(
        coordinator: Coordinator,
        resolvedTextColor: NSColor
    ) -> (
        attributed: NSMutableAttributedString,
        attachments: [MarkdownAppKitNativeAttachmentPlacement],
        mathAttachmentKeys: Set<MarkdownAppKitMathAttachmentKey>,
        plainText: String
    ) {
        let fallback = (try? NSMutableAttributedString(attributed, including: \.appKit)) ??
            NSMutableAttributedString(string: String(attributed.characters))
        guard let mathTextPieces, !mathTextPieces.isEmpty else {
            return (fallback, [], [], fallback.string)
        }

        let result = NSMutableAttributedString()
        var preparedOffset = 0
        let orderedAttachments = preparedInlineContent?.prepared.runs.compactMap { run -> (
            offset: Int,
            length: Int,
            record: MarkdownPreparedAttachment
        )? in
            let runLength = (run.text as NSString).length
            defer { preparedOffset += runLength }
            guard let id = run.attachmentMetrics?.id,
                  let record = preparedInlineContent?.attachments[id]
            else {
                return nil
            }
            return (preparedOffset, runLength, record)
        } ?? []
        var nextAttachmentIndex = 0
        var sourceOffset = 0
        var placements: [MarkdownAppKitNativeAttachmentPlacement] = []
        var mathAttachmentKeys: Set<MarkdownAppKitMathAttachmentKey> = []
        var mathOccurrence = 0

        for piece in mathTextPieces {
            switch piece {
            case let .text(text):
                let expectedLength = (String(text.characters) as NSString).length
                let segment: NSMutableAttributedString
                if expectedLength > 0, sourceOffset + expectedLength <= fallback.length {
                    segment = NSMutableAttributedString(
                        attributedString: fallback.attributedSubstring(
                            from: NSRange(location: sourceOffset, length: expectedLength)
                        )
                    )
                } else {
                    segment = (try? NSMutableAttributedString(text, including: \.appKit)) ??
                        NSMutableAttributedString(string: String(text.characters))
                }

                var segmentOffsetAdjustment = 0
                while nextAttachmentIndex < orderedAttachments.count {
                    let preparedAttachment = orderedAttachments[nextAttachmentIndex]
                    if preparedAttachment.offset < sourceOffset {
                        nextAttachmentIndex += 1
                        continue
                    }
                    guard preparedAttachment.offset < sourceOffset + expectedLength else {
                        break
                    }
                    let placeholderRange = NSRange(
                        location: preparedAttachment.offset - sourceOffset + segmentOffsetAdjustment,
                        length: preparedAttachment.length
                    )
                    guard placeholderRange.length > 0,
                          NSMaxRange(placeholderRange) <= segment.length
                    else {
                        nextAttachmentIndex += 1
                        continue
                    }
                    let record = preparedAttachment.record
                    let attachment = coordinator.nativeTextAttachment(for: record)
                    segment.replaceCharacters(in: placeholderRange, with: "\u{FFFC}")
                    segmentOffsetAdjustment += 1 - preparedAttachment.length
                    let attachmentRange = NSRange(location: placeholderRange.location, length: 1)
                    segment.addAttributes(
                        [
                            .attachment: attachment,
                            .markdownNativePlainText: record.image.altText ?? record.image.source,
                        ],
                        range: attachmentRange
                    )
                    placements.append(
                        MarkdownAppKitNativeAttachmentPlacement(
                            id: record.id,
                            characterRange: NSRange(
                                location: result.length + placeholderRange.location,
                                length: attachmentRange.length
                            ),
                            record: record
                        )
                    )
                    nextAttachmentIndex += 1
                }
                result.append(segment)
                sourceOffset += expectedLength

            case let .math(image):
                let fallbackLength = (image.latex as NSString).length
                var attributes: [NSAttributedString.Key: Any] = [:]
                if fallbackLength > 0, sourceOffset < fallback.length {
                    attributes = fallback.attributes(at: sourceOffset, effectiveRange: nil)
                }
                let attachmentKey = MarkdownAppKitMathAttachmentKey(
                    image: image,
                    occurrence: mathOccurrence
                )
                mathOccurrence += 1
                if let attachment = coordinator.nativeMathTextAttachment(
                    for: image,
                    key: attachmentKey,
                    color: resolvedTextColor
                ) {
                    attributes[.attachment] = attachment
                    attributes[.markdownNativePlainText] = image.latex
                    result.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                    mathAttachmentKeys.insert(attachmentKey)
                } else if fallbackLength > 0, sourceOffset + fallbackLength <= fallback.length {
                    result.append(
                        fallback.attributedSubstring(
                            from: NSRange(location: sourceOffset, length: fallbackLength)
                        )
                    )
                } else {
                    result.append(NSAttributedString(string: image.latex, attributes: attributes))
                }
                sourceOffset += fallbackLength
            }
        }
        let plainText = MarkdownAppKitNativeSelectableTextView.plainTextRepresentation(
            in: NSRange(location: 0, length: result.length),
            textStorage: result
        )
        return (result, placements, mathAttachmentKeys, plainText)
    }

    private func applyPreparedAttachments(
        to attributed: NSMutableAttributedString,
        coordinator: Coordinator
    ) -> [MarkdownAppKitNativeAttachmentPlacement] {
        guard let preparedInlineContent, !preparedInlineContent.attachments.isEmpty else {
            return []
        }

        var placements: [MarkdownAppKitNativeAttachmentPlacement] = []
        var utf16Offset = 0
        for run in preparedInlineContent.prepared.runs {
            let runLength = (run.text as NSString).length
            defer { utf16Offset += runLength }
            guard let metrics = run.attachmentMetrics,
                  let record = preparedInlineContent.attachments[metrics.id],
                  runLength > 0,
                  utf16Offset >= 0,
                  utf16Offset + runLength <= attributed.length
            else {
                continue
            }

            let range = NSRange(location: utf16Offset, length: runLength)
            attributed.replaceCharacters(in: range, with: "\u{FFFC}")
            let attachmentRange = NSRange(location: utf16Offset, length: 1)
            let attachment = coordinator.nativeTextAttachment(for: record)
            attributed.addAttributes(
                [
                    .attachment: attachment,
                    .markdownNativePlainText: record.image.altText ?? record.image.source,
                ],
                range: attachmentRange
            )
            placements.append(
                MarkdownAppKitNativeAttachmentPlacement(
                    id: record.id,
                    characterRange: attachmentRange,
                    record: record
                )
            )
            utf16Offset += 1 - runLength
        }
        return placements
    }

    private var fallbackFont: NSFont {
        MarkdownAppKitTextFont.font(profile: fallbackFontProfile, size: fallbackFontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var linkAction: MarkdownLinkAction?
        private var attachmentCache: [MarkdownAttachmentID: (MarkdownPreparedAttachment, NSTextAttachment)] = [:]
        private var mathAttachmentCache: [
            MarkdownAppKitMathAttachmentKey: (
                MarkdownPreparedMathImage,
                NSColor,
                NSTextAttachment,
                MarkdownAppKitMathAttachmentCell
            )
        ] = [:]

        init(linkAction: MarkdownLinkAction?) {
            self.linkAction = linkAction
        }

        @MainActor
        func nativeTextAttachment(for record: MarkdownPreparedAttachment) -> NSTextAttachment {
            if let cached = attachmentCache[record.id], cached.0 == record {
                return cached.1
            }

            let size = NSSize(width: record.pointWidth, height: record.pointHeight)
            let transparentImage = NSImage(size: size)
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: transparentImage)
            attachmentCache[record.id] = (record, attachment)
            return attachment
        }

        @discardableResult
        func retainNativeTextAttachments(ids: Set<MarkdownAttachmentID>) -> Int {
            attachmentCache = attachmentCache.filter { ids.contains($0.key) }
            return attachmentCache.count
        }

        @MainActor
        func nativeMathTextAttachment(
            for image: MarkdownPreparedMathImage,
            key: MarkdownAppKitMathAttachmentKey,
            color: NSColor
        ) -> NSTextAttachment? {
            if let cached = mathAttachmentCache[key],
               cached.0 == image,
               cached.1.isEqual(color) {
                return cached.2
            }

            let size = NSSize(width: image.renderPointWidth, height: image.renderPointHeight)
            guard size.width > 0,
                  size.height > 0,
                  let sourceImage = NSImage(data: image.imageData)
            else {
                return nil
            }
            sourceImage.size = size
            let tintedImage = NSImage(size: size, flipped: false) { rect in
                color.setFill()
                rect.fill()
                sourceImage.draw(
                    in: rect,
                    from: .zero,
                    operation: .destinationIn,
                    fraction: 1
                )
                return true
            }
            // `NSTextAttachment(data:ofType:)` can replace or clear a custom
            // attachment cell when TextKit inserts the attributed string on
            // newer macOS runners. The image and bounds survive that
            // normalization and provide stable geometry across AppKit versions.
            let attachment = NSTextAttachment()
            attachment.image = tintedImage
            attachment.bounds = NSRect(
                x: 0,
                y: -image.renderDescent,
                width: size.width,
                height: size.height
            )
            let attachmentCell = MarkdownAppKitMathAttachmentCell(
                image: tintedImage,
                size: size,
                descent: image.renderDescent
            )
            attachment.attachmentCell = attachmentCell
            // Newer AppKit releases may copy the attachment during TextKit
            // insertion and omit its legacy cell. `image` plus baseline-adjusted
            // `bounds` are therefore the portable drawing/layout contract;
            // retain the custom cell beside the bounded cache for older AppKit.
            mathAttachmentCache[key] = (image, color, attachment, attachmentCell)
            return attachment
        }

        @discardableResult
        func retainNativeMathAttachments(keys: Set<MarkdownAppKitMathAttachmentKey>) -> Int {
            mathAttachmentCache = mathAttachmentCache.filter { keys.contains($0.key) }
            return mathAttachmentCache.count
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let destination: String
            if let url = link as? URL {
                destination = url.absoluteString
            } else {
                destination = String(describing: link)
            }

            if let linkAction {
                linkAction.open(destination)
            } else {
                Task { @MainActor in
                    MarkdownURLOpener.open(destination)
                }
            }
            return true
        }
    }
}

private extension NSAttributedString.Key {
    static let markdownNativePlainText = NSAttributedString.Key(
        "net.siriusmarkdown.native-selection.plain-text"
    )
}

private extension NSRange {
    func clamped(toUTF16Length length: Int) -> NSRange? {
        guard location != NSNotFound else {
            return nil
        }
        let lowerBound = min(max(0, location), length)
        let upperBound = min(max(lowerBound, location + self.length), length)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }
}

struct MarkdownAppKitNativeAttachmentPlacement: Equatable {
    var id: MarkdownAttachmentID
    var characterRange: NSRange
    var record: MarkdownPreparedAttachment
}

struct MarkdownAppKitMathAttachmentKey: Hashable {
    var occurrence: Int
    var latex: String
    var scale: Double
    var pointWidth: Double
    var pointHeight: Double
    var ascent: Double
    var descent: Double
    var imageByteCount: Int

    init(image: MarkdownPreparedMathImage, occurrence: Int) {
        self.occurrence = occurrence
        self.latex = image.latex
        self.scale = Self.finite(image.scale)
        self.pointWidth = Self.finite(image.pointWidth)
        self.pointHeight = Self.finite(image.pointHeight)
        self.ascent = Self.finite(image.ascent)
        self.descent = Self.finite(image.descent)
        self.imageByteCount = image.imageData.count
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}

final class MarkdownAppKitNativeSelectableTextView: NSTextView {
    var nativeAttachmentCacheCount = 0
    var nativeMathAttachmentCacheCount = 0
    var colorScheme: ColorScheme = .light
    var preparedAttachments: [MarkdownAppKitNativeAttachmentPlacement] = [] {
        didSet {
            guard preparedAttachments != oldValue else { return }
            needsLayout = true
        }
    }
    private var attachmentHostsByID: [MarkdownAttachmentID: MarkdownAttachmentHostNSView] = [:]

    override func layout() {
        super.layout()
        reconcilePreparedAttachmentHosts()
    }

    override func copy(_ sender: Any?) {
        let selected = selectedRange()
        let plainText = plainTextRepresentation(in: selected)
        super.copy(sender)
        if !plainText.isEmpty {
            NSPasteboard.general.setString(plainText, forType: .string)
        }
    }

    func plainTextRepresentation(in range: NSRange) -> String {
        guard let textStorage else {
            return ""
        }
        return Self.plainTextRepresentation(in: range, textStorage: textStorage)
    }

    func semanticRange(for storageRange: NSRange) -> NSRange? {
        guard let textStorage,
              let clamped = storageRange.clamped(toUTF16Length: textStorage.length)
        else {
            return nil
        }
        let lower = Self.semanticOffset(forStorageOffset: clamped.location, in: textStorage)
        let upper = Self.semanticOffset(forStorageOffset: NSMaxRange(clamped), in: textStorage)
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    func storageRange(forSemanticRange semanticRange: NSRange) -> NSRange {
        guard let textStorage else {
            return NSRange(location: 0, length: 0)
        }
        let lower = Self.storageOffset(
            forSemanticOffset: semanticRange.location,
            edge: .lower,
            in: textStorage
        )
        let upper = Self.storageOffset(
            forSemanticOffset: NSMaxRange(semanticRange),
            edge: .upper,
            in: textStorage
        )
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func plainTextRepresentation(
        in range: NSRange,
        textStorage: NSAttributedString
    ) -> String {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= textStorage.length
        else {
            return ""
        }

        var result = ""
        textStorage.enumerateAttributes(in: range) { attributes, effectiveRange, _ in
            if let replacement = attributes[.markdownNativePlainText] as? String {
                result += replacement
            } else {
                result += (textStorage.string as NSString).substring(with: effectiveRange)
            }
        }
        return result
    }

    private enum SemanticSelectionEdge: Equatable {
        case lower
        case upper
    }

    private static func semanticOffset(
        forStorageOffset requestedOffset: Int,
        in textStorage: NSAttributedString
    ) -> Int {
        let target = min(max(0, requestedOffset), textStorage.length)
        var semanticCursor = 0
        var resolved: Int?
        textStorage.enumerateAttributes(
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { attributes, range, stop in
            let replacementLength = (attributes[.markdownNativePlainText] as? String).map {
                ($0 as NSString).length
            }
            let semanticLength = replacementLength ?? range.length
            if target <= NSMaxRange(range) {
                if replacementLength != nil {
                    resolved = target <= range.location ? semanticCursor : semanticCursor + semanticLength
                } else {
                    resolved = semanticCursor + max(0, target - range.location)
                }
                stop.pointee = true
                return
            }
            semanticCursor += semanticLength
        }
        return resolved ?? semanticCursor
    }

    private static func storageOffset(
        forSemanticOffset requestedOffset: Int,
        edge: SemanticSelectionEdge,
        in textStorage: NSAttributedString
    ) -> Int {
        let target = max(0, requestedOffset)
        var semanticCursor = 0
        var resolved: Int?
        textStorage.enumerateAttributes(
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { attributes, range, stop in
            let replacementLength = (attributes[.markdownNativePlainText] as? String).map {
                ($0 as NSString).length
            }
            let semanticLength = replacementLength ?? range.length
            let semanticEnd = semanticCursor + semanticLength
            guard target <= semanticEnd else {
                semanticCursor = semanticEnd
                return
            }

            if replacementLength != nil {
                if target <= semanticCursor {
                    resolved = range.location
                } else if target >= semanticEnd {
                    resolved = NSMaxRange(range)
                } else {
                    resolved = edge == .lower ? range.location : NSMaxRange(range)
                }
            } else {
                resolved = range.location + min(max(0, target - semanticCursor), range.length)
            }
            stop.pointee = true
        }
        return resolved ?? textStorage.length
    }

    func reconcilePreparedAttachmentHosts() {
        guard let layoutManager, let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)

        var stillPresent: Set<MarkdownAttachmentID> = []
        for placement in preparedAttachments {
            stillPresent.insert(placement.id)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: placement.characterRange,
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textContainerInset.width
            rect.origin.y += textContainerInset.height
            rect.size.width = CGFloat(placement.record.pointWidth)
            rect.size.height = CGFloat(placement.record.pointHeight)

            let host: MarkdownAttachmentHostNSView
            if let existing = attachmentHostsByID[placement.id] {
                host = existing
            } else {
                host = MarkdownAttachmentHostNSView()
                addSubview(host)
                attachmentHostsByID[placement.id] = host
            }
            host.frame = rect
            host.colorScheme = colorScheme
            host.record = placement.record
        }

        let staleIDs = attachmentHostsByID.keys.filter { !stillPresent.contains($0) }
        for id in staleIDs {
            attachmentHostsByID[id]?.removeFromSuperview()
            attachmentHostsByID.removeValue(forKey: id)
        }
    }
}

final class MarkdownAppKitMathAttachmentCell: NSTextAttachmentCell {
    private let measuredSize: NSSize
    private let measuredDescent: CGFloat

    init(image: NSImage, size: NSSize, descent: CGFloat) {
        self.measuredSize = size
        self.measuredDescent = min(max(0, descent), size.height)
        super.init(imageCell: image)
    }

    required init(coder: NSCoder) {
        self.measuredSize = .zero
        self.measuredDescent = 0
        super.init(coder: coder)
    }

    override var cellSize: NSSize {
        get { measuredSize }
        set {}
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -measuredDescent)
    }

    override func wantsToTrackMouse() -> Bool {
        false
    }
}

private final class MarkdownAppKitNativeSelectableContainerView: NSView {
    let textView = MarkdownAppKitNativeSelectableTextView(frame: .zero)

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(textView)
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        textView.reconcilePreparedAttachmentHosts()
    }
}

private enum MarkdownAppKitTextFont {
    static func font(profile: MarkdownFontProfile, size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        switch profile {
        case let .named(name, weight):
            let base = NSFont(name: name, size: pointSize) ??
                NSFont.systemFont(ofSize: pointSize, weight: appKitWeight(weight))
            return weightedFont(base, weight: weight, size: pointSize)
        case let .monospacedSystem(weight):
            return NSFont.monospacedSystemFont(ofSize: pointSize, weight: appKitWeight(weight))
        case let .system(weight, design):
            let base = NSFont.systemFont(ofSize: pointSize, weight: appKitWeight(weight))
            guard let systemDesign = appKitDesign(design),
                  let descriptor = base.fontDescriptor.withDesign(systemDesign),
                  let designed = NSFont(descriptor: descriptor, size: pointSize)
            else {
                return base
            }
            return designed
        }
    }

    private static func weightedFont(_ font: NSFont, weight: MarkdownFontWeight, size: CGFloat) -> NSFont {
        guard weight != .regular else {
            return font
        }
        let descriptor = font.fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: appKitWeight(weight).rawValue]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    private static func appKitWeight(_ weight: MarkdownFontWeight) -> NSFont.Weight {
        switch weight {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }

    private static func appKitDesign(_ design: MarkdownFontDesign) -> NSFontDescriptor.SystemDesign? {
        switch design {
        case .default:
            return nil
        case .serif:
            return .serif
        case .rounded:
            return .rounded
        case .monospaced:
            return .monospaced
        }
    }
}
#endif
