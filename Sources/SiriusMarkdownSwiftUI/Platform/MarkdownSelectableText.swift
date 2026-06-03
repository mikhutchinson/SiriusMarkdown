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

    var body: some View {
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
                wraps: wraps
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

    func makeCoordinator() -> Coordinator {
        Coordinator(linkAction: linkAction)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
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
        configure(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.linkAction = linkAction
        configure(textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        configure(textView)
        return measuredSize(for: textView, proposedWidth: proposal.width)
    }

    private func configure(_ textView: NSTextView) {
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = !wraps
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = wraps
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        textView.textColor = NSColor(textColor)
        textView.font = fallbackFont

        let nextAttributed = attributedStringWithFallbackAttributes()
        if textView.textStorage?.string != nextAttributed.string ||
            textView.textStorage?.length != nextAttributed.length ||
            textView.textStorage.map({ !$0.isEqual(to: nextAttributed) }) == true {
            textView.textStorage?.setAttributedString(nextAttributed)
        }
    }

    private func measuredSize(for textView: NSTextView, proposedWidth: CGFloat?) -> CGSize {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            return CGSize(width: proposedWidth ?? 0, height: CGFloat(fallbackLineHeight))
        }

        let targetWidth: CGFloat
        if wraps {
            targetWidth = max(1, proposedWidth ?? textView.intrinsicContentSize.width)
        } else {
            targetWidth = CGFloat.greatestFiniteMagnitude / 4
        }

        textContainer.containerSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let measuredWidth = wraps ? (proposedWidth ?? ceil(usedRect.width)) : ceil(usedRect.width)
        let measuredHeight = max(CGFloat(fallbackLineHeight), ceil(usedRect.height))
        return CGSize(width: max(1, measuredWidth), height: measuredHeight)
    }

    private func attributedStringWithFallbackAttributes() -> NSAttributedString {
        let nsAttributed = (try? NSMutableAttributedString(attributed, including: \.appKit)) ??
            NSMutableAttributedString(string: String(attributed.characters))
        let fullRange = NSRange(location: 0, length: nsAttributed.length)
        guard fullRange.length > 0 else {
            return nsAttributed
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
            nsAttributed.addAttribute(.foregroundColor, value: NSColor(textColor), range: range)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        nsAttributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        return nsAttributed
    }

    private var fallbackFont: NSFont {
        MarkdownAppKitTextFont.font(profile: fallbackFontProfile, size: fallbackFontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var linkAction: MarkdownLinkAction?

        init(linkAction: MarkdownLinkAction?) {
            self.linkAction = linkAction
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
