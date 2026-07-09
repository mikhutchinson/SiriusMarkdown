import SiriusMarkdownCore
import SwiftUI

#if canImport(CoreText)
import CoreText
#endif

struct CoreTextPaintedInlineLineView: View {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var theme: MarkdownTheme
    var containerWidth: CGFloat
    var linkAction: MarkdownLinkAction?
    var dragSelectionHandler: ((CGPoint, CGPoint) -> Void)?

    static var isSupported: Bool {
        #if canImport(CoreText) && (os(macOS) || (canImport(UIKit) && !os(watchOS)))
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        #if os(macOS) && canImport(CoreText)
        CoreTextPaintedInlineLineSurface(
            prepared: prepared,
            layoutResult: layoutResult,
            fallbackAttributed: fallbackAttributed,
            textColor: theme.textColor,
            containerWidth: containerWidth,
            linkAction: linkAction,
            dragSelectionHandler: dragSelectionHandler
        )
        #elseif canImport(UIKit) && canImport(CoreText) && !os(watchOS)
        CoreTextPaintedInlineLineSurface(
            prepared: prepared,
            layoutResult: layoutResult,
            fallbackAttributed: fallbackAttributed,
            textColor: theme.textColor,
            containerWidth: containerWidth,
            linkAction: linkAction,
            dragSelectionHandler: dragSelectionHandler
        )
        #else
        EmptyView()
        #endif
    }
}

#if canImport(CoreText)
/// Cache key for the last `MarkdownCoreTextPaintedLinePlan` built in the NSView/UIView update path.
/// Guards INV-P1: if the prepared content's natural width and the current layout result are
/// unchanged since the last explicit `make()`, the existing plan is reused without recreating CTLine
/// objects in `updateNSView`/`updateUIView`.
struct CTPlanCacheKey: Equatable {
    var preparedNaturalWidth: Double
    var layout: InlineLayoutResult

    func matches(naturalWidth: Double, layout: InlineLayoutResult) -> Bool {
        preparedNaturalWidth == naturalWidth && self.layout == layout
    }
}

struct MarkdownCoreTextPaintedLinePlan: @unchecked Sendable {
    var lines: [MarkdownCoreTextPaintedLine]
    var accessibilityLabel: String
    var lineHeight: CGFloat
    var lineSpacing: CGFloat

    static let empty = MarkdownCoreTextPaintedLinePlan(
        lines: [],
        accessibilityLabel: "",
        lineHeight: 0,
        lineSpacing: 0
    )

    var linkFragments: [MarkdownCoreTextPaintedLinkFragment] {
        lines.flatMap(\.linkFragments)
    }

    static func make(
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult
    ) -> MarkdownCoreTextPaintedLinePlan {
        let naturalText = prepared.prepared.naturalText
        let runRanges = byteRanges(for: prepared.prepared.runs)
        let lineHeight = CGFloat(prepared.lineHeight)
        let lineSpacing = InlineRunsView.nativeLineSpacing(for: prepared)

        let lines = layout.lines.enumerated().map { lineIndex, line in
            makeLine(
                index: lineIndex,
                line: line,
                naturalText: naturalText,
                runRanges: runRanges,
                prepared: prepared,
                lineHeight: lineHeight,
                lineSpacing: lineSpacing
            )
        }

        return MarkdownCoreTextPaintedLinePlan(
            lines: lines,
            accessibilityLabel: String(prepared.attributed.characters),
            lineHeight: lineHeight,
            lineSpacing: lineSpacing
        )
    }

    private static func makeLine(
        index: Int,
        line: InlineLineRange,
        naturalText: String,
        runRanges: [(run: MarkdownInlineRun, byteRange: Range<Int>)],
        prepared: MarkdownPreparedInlineContent,
        lineHeight: CGFloat,
        lineSpacing: CGFloat
    ) -> MarkdownCoreTextPaintedLine {
        let lineText = InlineRunsView.textSlice(text: naturalText, byteRange: line.byteRange)
        let drawableText = lineText.isEmpty ? " " : lineText
        let attributed = NSMutableAttributedString(string: drawableText)
        let fullRange = NSRange(location: 0, length: attributed.length)

        if fullRange.length > 0 {
            attributed.addAttribute(
                NSAttributedString.Key(kCTFontAttributeName as String),
                value: MarkdownCoreTextFontBridge.font(
                    profile: prepared.fontProfiles.body,
                    kind: .text,
                    presentation: [],
                    size: prepared.fontSize
                ),
                range: fullRange
            )
        }

        var linkCandidates: [MarkdownCoreTextPaintedLinkCandidate] = []

        for runRange in runRanges {
            guard let intersection = intersect(runRange.byteRange, line.byteRange),
                  let nsRange = nsRange(
                    forGlobalByteRange: intersection,
                    lineByteRange: line.byteRange,
                    lineText: drawableText
                  )
            else {
                continue
            }

            attributed.addAttribute(
                NSAttributedString.Key(kCTFontAttributeName as String),
                value: MarkdownCoreTextFontBridge.font(
                    profile: prepared.fontProfiles.profile(
                        for: runRange.run.presentation,
                        kind: runRange.run.kind
                    ),
                    kind: runRange.run.kind,
                    presentation: runRange.run.presentation,
                    size: prepared.fontSize
                ),
                range: nsRange
            )

            if let destination = allowedLinkDestination(
                for: runRange.byteRange,
                in: prepared,
                naturalText: naturalText
            ) {
                attributed.addAttribute(
                    NSAttributedString.Key(kCTUnderlineStyleAttributeName as String),
                    value: CTUnderlineStyle.single.rawValue,
                    range: nsRange
                )
                linkCandidates.append(
                    MarkdownCoreTextPaintedLinkCandidate(
                        destination: destination,
                        nsRange: nsRange,
                        byteRange: intersection
                    )
                )
            }
        }

        let ctLine = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let typographicWidth = CGFloat(
            CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
        )
        let top = CGFloat(index) * (lineHeight + lineSpacing)
        let linkFragments = linkCandidates.compactMap { candidate -> MarkdownCoreTextPaintedLinkFragment? in
            let start = CGFloat(CTLineGetOffsetForStringIndex(ctLine, candidate.nsRange.location, nil))
            let endIndex = candidate.nsRange.location + candidate.nsRange.length
            let end = CGFloat(CTLineGetOffsetForStringIndex(ctLine, endIndex, nil))
            let width = end - start
            guard start.isFinite, width.isFinite, width > 0 else {
                return nil
            }
            return MarkdownCoreTextPaintedLinkFragment(
                lineIndex: index,
                destination: candidate.destination,
                byteRange: candidate.byteRange,
                rect: CGRect(
                    x: start,
                    y: top,
                    width: max(1, width),
                    height: max(1, lineHeight)
                )
            )
        }

        return MarkdownCoreTextPaintedLine(
            index: index,
            text: lineText,
            byteRange: line.byteRange,
            ctLine: ctLine,
            layoutWidth: CGFloat(line.width),
            typographicWidth: typographicWidth,
            ascent: ascent,
            descent: descent,
            leading: leading,
            linkFragments: linkFragments
        )
    }

    private static func allowedLinkDestination(
        for byteRange: Range<Int>,
        in prepared: MarkdownPreparedInlineContent,
        naturalText: String
    ) -> String? {
        let attributed = InlineRunsView.attributedSlice(
            prepared.attributed,
            text: naturalText,
            byteRange: byteRange
        )
        for run in attributed.runs {
            if let link = run.link {
                return link.absoluteString
            }
        }
        return nil
    }

    private static func byteRanges(
        for runs: [MarkdownInlineRun]
    ) -> [(run: MarkdownInlineRun, byteRange: Range<Int>)] {
        var result: [(MarkdownInlineRun, Range<Int>)] = []
        var cursor = 0
        for run in runs {
            let upper = cursor + run.text.utf8.count
            result.append((run, cursor..<upper))
            cursor = upper
        }
        return result
    }

    private static func intersect(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Range<Int>? {
        let lower = max(lhs.lowerBound, rhs.lowerBound)
        let upper = min(lhs.upperBound, rhs.upperBound)
        guard lower < upper else {
            return nil
        }
        return lower..<upper
    }

    private static func nsRange(
        forGlobalByteRange byteRange: Range<Int>,
        lineByteRange: Range<Int>,
        lineText: String
    ) -> NSRange? {
        let localRange = (byteRange.lowerBound - lineByteRange.lowerBound)..<(byteRange.upperBound - lineByteRange.lowerBound)
        guard localRange.lowerBound >= 0,
              localRange.upperBound <= lineText.utf8.count,
              let stringRange = InlineRunsView.stringRange(forUTF8Range: localRange, in: lineText),
              let lower = stringRange.lowerBound.samePosition(in: lineText.utf16),
              let upper = stringRange.upperBound.samePosition(in: lineText.utf16)
        else {
            return nil
        }
        let location = lineText.utf16.distance(from: lineText.utf16.startIndex, to: lower)
        let upperLocation = lineText.utf16.distance(from: lineText.utf16.startIndex, to: upper)
        return NSRange(location: location, length: max(0, upperLocation - location))
    }
}

struct MarkdownCoreTextPaintedLine: @unchecked Sendable {
    var index: Int
    var text: String
    var byteRange: Range<Int>
    var ctLine: CTLine
    var layoutWidth: CGFloat
    var typographicWidth: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
    var leading: CGFloat
    var linkFragments: [MarkdownCoreTextPaintedLinkFragment]
}

struct MarkdownCoreTextPaintedLinkFragment: Identifiable, Hashable {
    var lineIndex: Int
    var destination: String
    var byteRange: Range<Int>
    var rect: CGRect

    var id: String {
        "\(lineIndex):\(byteRange.lowerBound)-\(byteRange.upperBound):\(destination)"
    }
}

private struct MarkdownCoreTextPaintedLinkCandidate {
    var destination: String
    var nsRange: NSRange
    var byteRange: Range<Int>
}

struct MarkdownCoreTextPaintedLinkClickTracker: Equatable {
    static let defaultActivationDistance: CGFloat = 4

    var activationDistance: CGFloat = Self.defaultActivationDistance
    private var pendingFragment: MarkdownCoreTextPaintedLinkFragment?
    private var startPoint: CGPoint?

    var hasPendingClick: Bool {
        pendingFragment != nil
    }

    mutating func begin(
        at point: CGPoint,
        fragments: [MarkdownCoreTextPaintedLinkFragment],
        hitSlop: CGFloat
    ) -> Bool {
        guard let fragment = Self.hitFragment(at: point, fragments: fragments, hitSlop: hitSlop) else {
            cancel()
            return false
        }

        pendingFragment = fragment
        startPoint = point
        return true
    }

    mutating func updateDrag(to point: CGPoint) {
        guard let startPoint,
              hasExceededActivationDistance(from: startPoint, to: point)
        else {
            return
        }
        cancel()
    }

    mutating func finish(
        at point: CGPoint,
        fragments: [MarkdownCoreTextPaintedLinkFragment],
        hitSlop: CGFloat
    ) -> String? {
        defer { cancel() }
        guard let pendingFragment,
              let startPoint,
              !hasExceededActivationDistance(from: startPoint, to: point),
              let currentFragment = Self.hitFragment(at: point, fragments: fragments, hitSlop: hitSlop),
              currentFragment.id == pendingFragment.id
        else {
            return nil
        }
        return currentFragment.destination
    }

    mutating func cancel() {
        pendingFragment = nil
        startPoint = nil
    }

    private func hasExceededActivationDistance(from start: CGPoint, to current: CGPoint) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return dx * dx + dy * dy >= activationDistance * activationDistance
    }

    private static func hitFragment(
        at point: CGPoint,
        fragments: [MarkdownCoreTextPaintedLinkFragment],
        hitSlop: CGFloat
    ) -> MarkdownCoreTextPaintedLinkFragment? {
        fragments.first { fragment in
            fragment.rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
        }
    }
}

enum MarkdownCoreTextFontBridge {
    static func font(
        profile: MarkdownFontProfile,
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation,
        size: Double
    ) -> CTFont {
        let pointSize = CGFloat(size)
        let base: CTFont
        var symbolicTraits: CTFontSymbolicTraits

        switch profile {
        case let .named(name, weight):
            base = CTFontCreateWithName(name as CFString, pointSize, nil)
            symbolicTraits = []
            return apply(
                weight: weight,
                symbolicTraits: symbolicTraits.union(semanticTraits(kind: kind, presentation: presentation)),
                to: base,
                size: pointSize
            )
        case let .monospacedSystem(weight):
            base = CTFontCreateUIFontForLanguage(.system, pointSize, nil) ??
                CTFontCreateWithName("Menlo" as CFString, pointSize, nil)
            symbolicTraits = .traitMonoSpace
            return apply(
                weight: weight,
                symbolicTraits: symbolicTraits.union(semanticTraits(kind: kind, presentation: presentation)),
                to: base,
                size: pointSize
            )
        case let .system(weight, design):
            base = systemFont(design: design, size: pointSize)
            symbolicTraits = fontSymbolicTraits(for: design)
            return apply(
                weight: weight,
                symbolicTraits: symbolicTraits.union(semanticTraits(kind: kind, presentation: presentation)),
                to: base,
                size: pointSize
            )
        }
    }

    private static func apply(
        weight: MarkdownFontWeight,
        symbolicTraits: CTFontSymbolicTraits,
        to font: CTFont,
        size: CGFloat
    ) -> CTFont {
        var traits: [CFString: Any] = [:]
        if let weightValue = fontWeightValue(for: weight) {
            traits[kCTFontWeightTrait] = weightValue
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: traits
        ] as CFDictionary)
        let weighted = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)
        guard !symbolicTraits.isEmpty else {
            return weighted
        }
        return CTFontCreateCopyWithSymbolicTraits(
            weighted,
            size,
            nil,
            symbolicTraits,
            symbolicTraits
        ) ?? weighted
    }

    private static func systemFont(design: MarkdownFontDesign, size: CGFloat) -> CTFont {
        switch design {
        case .serif:
            return CTFontCreateWithName("Times" as CFString, size, nil)
        case .monospaced:
            return CTFontCreateUIFontForLanguage(.system, size, nil) ??
                CTFontCreateWithName("Menlo" as CFString, size, nil)
        case .default, .rounded:
            return CTFontCreateUIFontForLanguage(.system, size, nil) ??
                CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
    }

    private static func semanticTraits(
        kind: MarkdownInlineKind,
        presentation: MarkdownInlinePresentation
    ) -> CTFontSymbolicTraits {
        var traits: CTFontSymbolicTraits = []
        if kind == .emphasis || presentation.contains(.emphasis) {
            traits.insert(.traitItalic)
        }
        if kind == .code || kind == .math ||
            presentation.contains(.code) || presentation.contains(.math) {
            traits.insert(.traitMonoSpace)
        }
        return traits
    }

    private static func fontSymbolicTraits(for design: MarkdownFontDesign) -> CTFontSymbolicTraits {
        switch design {
        case .monospaced:
            return .traitMonoSpace
        case .default, .serif, .rounded:
            return []
        }
    }

    private static func fontWeightValue(for weight: MarkdownFontWeight) -> CGFloat? {
        switch weight {
        case .regular:
            return nil
        case .medium:
            return 0.23
        case .semibold:
            return 0.3
        case .bold:
            return 0.4
        }
    }
}
#endif

#if os(macOS) && canImport(CoreText)
import AppKit

private struct CoreTextPaintedInlineLineSurface: NSViewRepresentable {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var textColor: Color
    var containerWidth: CGFloat
    var linkAction: MarkdownLinkAction?
    var dragSelectionHandler: ((CGPoint, CGPoint) -> Void)?

    func makeNSView(context _: Context) -> MarkdownCoreTextPaintedNSView {
        let view = MarkdownCoreTextPaintedNSView(frame: .zero)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: MarkdownCoreTextPaintedNSView, context _: Context) {
        if let prebuilt = prepared.coreTextLinePlan,
           let initialLayout = prepared.initialLayoutResult,
           initialLayout == layoutResult
        {
            view.plan = prebuilt
            view.cachedLinePlanKey = nil
        } else if view.cachedLinePlanKey?.matches(
            naturalWidth: prepared.measured.naturalWidth,
            layout: layoutResult
        ) == true {
            // Same content+layout since last explicit make() — reuse existing plan (INV-P1).
        } else {
            // The prebuilt plan from `prepare(snapshot:)` was built at a
            // width that doesn't match this view's real layout — this is
            // the residual INV-P1 gap: CTLine creation runs here, in the
            // SwiftUI update path, instead of during prepare. Recorded so
            // it's measured, not assumed away (INV-P8); should trend to
            // zero for blocks prepared after the real width is known
            // (Streaming Performance Part 01/02 gap fix).
            prepared.layoutCache.recordCoreTextLinePlanRebuiltInBody()
            view.plan = MarkdownCoreTextPaintedLinePlan.make(
                prepared: prepared,
                layout: layoutResult
            )
            view.cachedLinePlanKey = CTPlanCacheKey(
                preparedNaturalWidth: prepared.measured.naturalWidth,
                layout: layoutResult
            )
        }
        view.textColor = resolvedCGColor(textColor)
        view.linkAction = linkAction
        view.dragSelectionHandler = dragSelectionHandler
        view.frame.size.width = containerWidth
        view.needsDisplay = true
        view.resetCursorRects()
        view.setAccessibilityLabel(String(fallbackAttributed.characters))
    }

    private func resolvedCGColor(_ color: Color) -> CGColor {
        let resolved = NSColor(color)
        return resolved.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.labelColor.cgColor
    }
}

private final class MarkdownCoreTextPaintedNSView: NSView {
    var plan = MarkdownCoreTextPaintedLinePlan.empty
    var textColor: CGColor = NSColor.labelColor.cgColor
    var linkAction: MarkdownLinkAction?
    var dragSelectionHandler: ((CGPoint, CGPoint) -> Void)?
    /// Cached key from the last explicit `MarkdownCoreTextPaintedLinePlan.make()` call so
    /// repeated `updateNSView` calls with identical content+layout skip `make()` (INV-P1).
    var cachedLinePlanKey: CTPlanCacheKey?
    private var linkClickTracker = MarkdownCoreTextPaintedLinkClickTracker()
    private var dragStartPoint: CGPoint?

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.setFillColor(textColor)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        for line in plan.lines {
            let baselineY = bounds.height - baselineFromTop(for: line)
            context.textPosition = CGPoint(x: 0, y: baselineY)
            CTLineDraw(line.ctLine, context)
        }

        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        linkClickTracker.begin(at: point, fragments: plan.linkFragments, hitSlop: 2)
        dragStartPoint = point
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        linkClickTracker.updateDrag(to: point)
        if let dragStartPoint,
           !linkClickTracker.hasPendingClick,
           let dragSelectionHandler
        {
            dragSelectionHandler(dragStartPoint, point)
            self.dragStartPoint = nil
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let destination = linkClickTracker.finish(at: point, fragments: plan.linkFragments, hitSlop: 2) {
            open(destination)
            return
        }
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for fragment in plan.linkFragments {
            addCursorRect(fragment.rect.insetBy(dx: -2, dy: -2), cursor: .pointingHand)
        }
    }

    override func accessibilityLabel() -> String? {
        plan.accessibilityLabel
    }

    private func open(_ destination: String) {
        if let linkAction {
            linkAction.open(destination)
        } else {
            MarkdownURLOpener.open(destination)
        }
    }

    private func baselineFromTop(for line: MarkdownCoreTextPaintedLine) -> CGFloat {
        let lineStride = plan.lineHeight + plan.lineSpacing
        let top = CGFloat(line.index) * lineStride
        let typographicHeight = line.ascent + line.descent + line.leading
        let verticalInset = max(0, (plan.lineHeight - typographicHeight) / 2)
        return top + verticalInset + line.ascent
    }
}
#endif

#if canImport(UIKit) && canImport(CoreText) && !os(macOS) && !os(watchOS)
import UIKit

private struct CoreTextPaintedInlineLineSurface: UIViewRepresentable {
    var prepared: MarkdownPreparedInlineContent
    var layoutResult: InlineLayoutResult
    var fallbackAttributed: AttributedString
    var textColor: Color
    var containerWidth: CGFloat
    var linkAction: MarkdownLinkAction?

    func makeUIView(context _: Context) -> MarkdownCoreTextPaintedUIView {
        let view = MarkdownCoreTextPaintedUIView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = true
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: MarkdownCoreTextPaintedUIView, context _: Context) {
        if let prebuilt = prepared.coreTextLinePlan,
           let initialLayout = prepared.initialLayoutResult,
           initialLayout == layoutResult
        {
            view.plan = prebuilt
            view.cachedLinePlanKey = nil
        } else if view.cachedLinePlanKey?.matches(
            naturalWidth: prepared.measured.naturalWidth,
            layout: layoutResult
        ) == true {
            // Same content+layout since last explicit make() — reuse existing plan (INV-P1).
        } else {
            // See the matching NSViewRepresentable branch above: residual
            // INV-P1 gap, recorded so it's measured, not assumed away.
            prepared.layoutCache.recordCoreTextLinePlanRebuiltInBody()
            view.plan = MarkdownCoreTextPaintedLinePlan.make(
                prepared: prepared,
                layout: layoutResult
            )
            view.cachedLinePlanKey = CTPlanCacheKey(
                preparedNaturalWidth: prepared.measured.naturalWidth,
                layout: layoutResult
            )
        }
        view.textColor = resolvedCGColor(textColor)
        view.linkAction = linkAction
        view.frame.size.width = containerWidth
        view.accessibilityLabel = String(fallbackAttributed.characters)
        view.setNeedsDisplay()
    }

    private func resolvedCGColor(_ color: Color) -> CGColor {
        UIColor(color).cgColor
    }
}

private final class MarkdownCoreTextPaintedUIView: UIView {
    var plan = MarkdownCoreTextPaintedLinePlan(
        lines: [],
        accessibilityLabel: "",
        lineHeight: 0,
        lineSpacing: 0
    )
    var textColor: CGColor = UIColor.label.cgColor
    var linkAction: MarkdownLinkAction?
    /// Cached key from the last explicit `MarkdownCoreTextPaintedLinePlan.make()` call so
    /// repeated `updateUIView` calls with identical content+layout skip `make()` (INV-P1).
    var cachedLinePlanKey: CTPlanCacheKey?
    private var linkClickTracker = MarkdownCoreTextPaintedLinkClickTracker()

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.setFillColor(textColor)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        for line in plan.lines {
            let baselineY = bounds.height - baselineFromTop(for: line)
            context.textPosition = CGPoint(x: 0, y: baselineY)
            CTLineDraw(line.ctLine, context)
        }

        context.restoreGState()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self),
              linkClickTracker.begin(at: point, fragments: plan.linkFragments, hitSlop: 8)
        else {
            super.touchesBegan(touches, with: event)
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard linkClickTracker.hasPendingClick else {
            super.touchesMoved(touches, with: event)
            return
        }

        if let point = touches.first?.location(in: self) {
            linkClickTracker.updateDrag(to: point)
        }
        if !linkClickTracker.hasPendingClick {
            super.touchesMoved(touches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self),
              let destination = linkClickTracker.finish(at: point, fragments: plan.linkFragments, hitSlop: 8)
        else {
            super.touchesEnded(touches, with: event)
            return
        }

        open(destination)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        linkClickTracker.cancel()
        super.touchesCancelled(touches, with: event)
    }

    private func open(_ destination: String) {
        if let linkAction {
            linkAction.open(destination)
        } else {
            MarkdownURLOpener.open(destination)
        }
    }

    private func baselineFromTop(for line: MarkdownCoreTextPaintedLine) -> CGFloat {
        let lineStride = plan.lineHeight + plan.lineSpacing
        let top = CGFloat(line.index) * lineStride
        let typographicHeight = line.ascent + line.descent + line.leading
        let verticalInset = max(0, (plan.lineHeight - typographicHeight) / 2)
        return top + verticalInset + line.ascent
    }
}
#endif
