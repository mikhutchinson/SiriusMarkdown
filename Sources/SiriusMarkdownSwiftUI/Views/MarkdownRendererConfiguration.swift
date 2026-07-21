import SiriusMarkdownCore
import Foundation
import SwiftUI

#if canImport(CoreText)
import CoreText
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public protocol MarkdownCodeHighlighter: Sendable {
    func highlightedCode(_ code: String, infoString: String?) -> AttributedString
}

public protocol MarkdownMathRenderer: Sendable {
    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString
    func preparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath
}

public protocol MarkdownMathRendererCacheIdentifying: Sendable {
    var mathRendererCacheIdentity: String { get }
}

/// Opt-in marker for math renderers whose `.text` prepared output means an
/// attempted native math render fell back to source text.
public protocol MarkdownMathRendererFallbackDiagnosing: Sendable {
    var recordsTextFallbackAsMathFallback: Bool { get }
}

public enum MarkdownPreparedImageSource: Sendable, Hashable {
    case placeholder(reason: String)
    case localFile(path: String)
    case data(Data, mimeType: String)
    case remote(URL)
}

public struct MarkdownPreparedImage: Sendable, Hashable {
    public var source: String
    public var altText: String?
    public var sourceRange: MarkdownSourceRange?
    public var preparedSource: MarkdownPreparedImageSource

    public init(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        preparedSource: MarkdownPreparedImageSource
    ) {
        self.source = source
        self.altText = altText
        self.sourceRange = sourceRange
        self.preparedSource = preparedSource
    }
}

/// A prepared, allowed inline attachment with reserved box metrics (Inline
/// Attachments Part 01). Only created for `.allow` image policy decisions —
/// denied images stay on the alt/`[image: reason]` text-atomic path
/// (INV-IA1, INV-IA4) and never produce a `MarkdownPreparedAttachment`.
public struct MarkdownPreparedAttachment: Sendable, Hashable {
    public var id: MarkdownAttachmentID
    public var image: MarkdownPreparedImage
    public var pointWidth: Double
    public var pointHeight: Double
    public var ascent: Double
    public var descent: Double
    public var sizingSource: MarkdownAttachmentSizingSource
    public var policyDecision: MarkdownPolicyDecision
    public var placeholderStyle: MarkdownAttachmentPlaceholderStyle
    public var isDecorative: Bool

    public init(
        id: MarkdownAttachmentID,
        image: MarkdownPreparedImage,
        pointWidth: Double,
        pointHeight: Double,
        ascent: Double,
        descent: Double,
        sizingSource: MarkdownAttachmentSizingSource,
        policyDecision: MarkdownPolicyDecision,
        placeholderStyle: MarkdownAttachmentPlaceholderStyle = .default,
        isDecorative: Bool = false
    ) {
        self.id = id
        self.image = image
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.ascent = ascent
        self.descent = descent
        self.sizingSource = sizingSource
        self.policyDecision = policyDecision
        self.placeholderStyle = placeholderStyle
        self.isDecorative = isDecorative
    }

    var metrics: MarkdownInlineAttachmentMetrics {
        MarkdownInlineAttachmentMetrics(
            id: id,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            ascent: ascent,
            descent: descent,
            sizingSource: sizingSource
        )
    }
}

public struct MarkdownLinkDecorationConfiguration: Sendable, Hashable {
    public var isEnabled: Bool
    public var fallbackGlyph: String
    public var iconPointSize: Double

    public init(
        isEnabled: Bool = true,
        fallbackGlyph: String = "🌐",
        iconPointSize: Double = 18
    ) {
        self.isEnabled = isEnabled
        self.fallbackGlyph = fallbackGlyph
        self.iconPointSize = iconPointSize.isFinite && iconPointSize > 0 ? iconPointSize : 18
    }

    public static let automatic = MarkdownLinkDecorationConfiguration()
    public static let disabled = MarkdownLinkDecorationConfiguration(isEnabled: false)
}

public protocol MarkdownImageResolver: Sendable {
    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage
}

public protocol MarkdownImageResolverCacheIdentifying: Sendable {
    var imageResolverCacheIdentity: String { get }
}

public struct PlainMarkdownCodeHighlighter: MarkdownCodeHighlighter, MarkdownCodeHighlighterCacheIdentifying {
    public init() {}

    public var codeHighlighterCacheIdentity: String {
        "siriusmarkdown.plain-code"
    }

    public func highlightedCode(_ code: String, infoString _: String?) -> AttributedString {
        var highlighted = AttributedString(code)
        highlighted.inlinePresentationIntent = .code
        return highlighted
    }
}

public struct PlainMarkdownMathRenderer: MarkdownMathRenderer, MarkdownMathRendererCacheIdentifying {
    public init() {}

    public var mathRendererCacheIdentity: String {
        "siriusmarkdown.plain-math"
    }

    public func renderedMath(_ source: String, isBlock _: Bool) -> AttributedString {
        var rendered = AttributedString(source)
        rendered.inlinePresentationIntent = .code
        return rendered
    }
}

public struct DefaultMarkdownImageResolver: MarkdownImageResolver, MarkdownImageResolverCacheIdentifying {
    public init() {}

    public var imageResolverCacheIdentity: String {
        "siriusmarkdown.default-image-resolver.v1"
    }

    public func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        let preparedSource: MarkdownPreparedImageSource
        switch policyDecision {
        case .allow:
            preparedSource = .placeholder(reason: "Image rendering requires a host image resolver.")
        case let .deny(reason):
            preparedSource = .placeholder(reason: reason)
        }

        return MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: preparedSource
        )
    }
}

struct MarkdownPreparedTypographyMetrics: Sendable, Hashable {
    var naturalTextFirstBaselineFromTop: CGFloat
    var nativeSelectableFirstTextBaselineFromTop: CGFloat
    var taskMarkerFirstTextBaselineFromTop: CGFloat

    init(
        profile: MarkdownFontProfile,
        fontSize: Double,
        lineHeight: Double
    ) {
        let safeFontSize = fontSize.isFinite && fontSize > 0 ? fontSize : 14
        let safeLineHeight = lineHeight.isFinite && lineHeight > 0
            ? CGFloat(lineHeight)
            : CGFloat(safeFontSize)
        // The SF Symbol checkbox's raster center lands half a point above the
        // capital-text center on both 1x and 2x macOS renderers. Incorporate
        // that optical correction in the prepared guide so alignment remains
        // stable without view-time font measurement.
        let taskMarkerOpticalBaselineCorrection: CGFloat = 0.5

        #if canImport(CoreText)
        let font = MarkdownCoreTextFontBridge.font(
            profile: profile,
            kind: .text,
            presentation: [],
            size: safeFontSize
        )
        naturalTextFirstBaselineFromTop =
            CTFontGetAscent(font) + max(0, CTFontGetLeading(font) / 2)
        nativeSelectableFirstTextBaselineFromTop =
            max(0, safeLineHeight - CTFontGetDescent(font))
        taskMarkerFirstTextBaselineFromTop = max(
            0,
            (safeLineHeight + CTFontGetCapHeight(font)) / 2 + taskMarkerOpticalBaselineCorrection
        )
        #else
        let approximateAscent = CGFloat(safeFontSize * 0.8)
        let approximateDescent = CGFloat(safeFontSize * 0.2)
        let approximateCapHeight = CGFloat(safeFontSize * 0.7)
        naturalTextFirstBaselineFromTop = approximateAscent
        nativeSelectableFirstTextBaselineFromTop =
            max(0, safeLineHeight - approximateDescent)
        taskMarkerFirstTextBaselineFromTop = max(
            0,
            (safeLineHeight + approximateCapHeight) / 2 + taskMarkerOpticalBaselineCorrection
        )
        #endif
    }
}

struct MarkdownListMarkerBaselineMetrics: Sendable, Hashable {
    var paragraphNaturalFirstTextBaselineFromTop: CGFloat
    var textualMarkerFirstTextBaselineFromTop: CGFloat
    var taskMarkerFirstTextBaselineFromTop: CGFloat

    init(theme: MarkdownTheme) {
        let paragraph = MarkdownPreparedTypographyMetrics(
            profile: theme.paragraphFontProfiles.body,
            fontSize: theme.paragraphFontSize,
            lineHeight: theme.paragraphLineHeight
        )
        let code = MarkdownPreparedTypographyMetrics(
            profile: theme.codeFontProfiles.body,
            fontSize: theme.codeFontSize,
            lineHeight: theme.codeLineHeight
        )
        paragraphNaturalFirstTextBaselineFromTop = paragraph.naturalTextFirstBaselineFromTop
        textualMarkerFirstTextBaselineFromTop = code.naturalTextFirstBaselineFromTop
        taskMarkerFirstTextBaselineFromTop = paragraph.taskMarkerFirstTextBaselineFromTop
    }
}

public struct MarkdownRendererConfiguration: Sendable {
    public enum DocumentSelection: Sendable, Hashable {
        /// Install SiriusMarkdown's source-backed document selection layer.
        case enabled
        /// Disable document-level drag selection and package-owned Cmd-C copy.
        case disabled

        /// The platform-appropriate default document-selection layer.
        ///
        /// macOS uses bounded AppKit text views by default, so the custom
        /// cross-block layer stays off unless a host requests it explicitly.
        /// Other platforms keep the source-backed document selector.
        public static var platformDefault: Self {
            #if os(macOS)
            .disabled
            #else
            .enabled
            #endif
        }
    }

    public var theme: MarkdownTheme {
        didSet {
            listMarkerBaselineMetrics = MarkdownListMarkerBaselineMetrics(theme: theme)
        }
    }
    var listMarkerBaselineMetrics: MarkdownListMarkerBaselineMetrics
    public var inlineRenderingMode: MarkdownInlineRenderingMode
    /// Native text leaf selection policy.
    ///
    /// On macOS this defaults to bounded AppKit text selection. Other
    /// platforms keep native leaf selection disabled by default. Cross-block
    /// source selection is controlled separately by `documentSelection`.
    public var nativeTextSelection: MarkdownNativeTextSelection {
        didSet {
            if nativeTextSelection == .enabled {
                documentSelection = .disabled
            }
        }
    }
    /// Source-backed cross-block selection owned by SiriusMarkdown.
    ///
    /// This is the default product selection path outside macOS. On macOS it
    /// is an explicit compatibility mode for hosts that require exact-source
    /// cross-block selection. It does not require `nativeTextSelection` and
    /// does not mount SwiftUI's container-level native-selection modifiers or
    /// private `SelectionOverlay` surfaces.
    public var documentSelection: DocumentSelection {
        didSet {
            if documentSelection == .enabled {
                nativeTextSelection = .disabled
            }
        }
    }
    public var linkAction: MarkdownLinkAction?
    public var copyProvider: MarkdownCopyProvider?
    public var linkPolicy: any MarkdownLinkPolicy
    public var linkMetadataResolver: (any MarkdownLinkMetadataResolver)?
    public var linkDecoration: MarkdownLinkDecorationConfiguration
    public var imagePolicy: any MarkdownImagePolicy
    public var imageResolver: any MarkdownImageResolver
    public var htmlPolicy: any MarkdownHTMLPolicy
    public var codePolicy: any MarkdownCodePolicy
    public var mathPolicy: any MarkdownMathPolicy
    public var codeHighlighter: any MarkdownCodeHighlighter
    public var mermaidRenderer: (any MarkdownMermaidRenderer)?
    public var mathRenderer: any MarkdownMathRenderer
    public var affordanceActionHandler: MarkdownAffordanceActionHandler
    public var preparationCache: MarkdownRenderPreparationCache
    public var diagnosticsRecorder: MarkdownDiagnosticsRecorder

    /// Session-default block chrome style bundle (Part 02 §2.2 Channel A).
    ///
    /// `nil` means "no configuration-level override" — `MarkdownBlockView`
    /// falls back to `.markdown` environment styles and finally to each
    /// slot's `MarkdownDefault*Style` (INV-BS9 merge order). Storing or
    /// copying this property never requires the main actor — only
    /// *invoking* `makeBody` on a resolved style does, and that already
    /// happens exclusively inside `@MainActor` `MarkdownBlockView` /
    /// `MarkdownListItemRow` call sites. Storage uses an internal
    /// `@unchecked Sendable` box so this `Sendable` configuration type can
    /// still carry the `@MainActor` `MarkdownDocumentStyle` existential
    /// (see `MarkdownDocumentStyleBox`). Prepare/cache paths never read
    /// this property (INV-BS1, INV-BS2).
    public var documentStyle: (any MarkdownDocumentStyle)? {
        get { documentStyleBox?.style }
        set { documentStyleBox = newValue.map(MarkdownDocumentStyleBox.init) }
    }

    private var documentStyleBox: MarkdownDocumentStyleBox?

    public init(
        theme: MarkdownTheme = .compactChat,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .platformDefault,
        documentSelection: DocumentSelection = .platformDefault,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        linkMetadataResolver: (any MarkdownLinkMetadataResolver)? = DefaultMarkdownLinkMetadataResolver.shared,
        linkDecoration: MarkdownLinkDecorationConfiguration = .automatic,
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        documentStyle: (any MarkdownDocumentStyle)? = nil,
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.listMarkerBaselineMetrics = MarkdownListMarkerBaselineMetrics(theme: theme)
        self.inlineRenderingMode = inlineRenderingMode
        self.nativeTextSelection = nativeTextSelection
        self.documentSelection = documentSelection
        if documentSelection == .enabled {
            self.nativeTextSelection = .disabled
        }
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.linkMetadataResolver = linkMetadataResolver
        self.linkDecoration = linkDecoration
        self.imagePolicy = imagePolicy
        self.imageResolver = imageResolver
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mermaidRenderer = mermaidRenderer
        self.mathRenderer = mathRenderer
        self.documentStyleBox = documentStyle.map(MarkdownDocumentStyleBox.init)
        self.affordanceActionHandler = affordanceActionHandler
        self.preparationCache = preparationCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public init(
        theme: MarkdownTheme = .compactChat,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        linkMetadataResolver: (any MarkdownLinkMetadataResolver)? = DefaultMarkdownLinkMetadataResolver.shared,
        linkDecoration: MarkdownLinkDecorationConfiguration = .automatic,
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        documentStyle: (any MarkdownDocumentStyle)? = nil,
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.theme = theme
        self.listMarkerBaselineMetrics = MarkdownListMarkerBaselineMetrics(theme: theme)
        self.inlineRenderingMode = .coreTextPaintedLines
        self.nativeTextSelection = .platformDefault
        self.documentSelection = .platformDefault
        self.linkAction = linkAction
        self.copyProvider = copyProvider
        self.linkPolicy = linkPolicy
        self.linkMetadataResolver = linkMetadataResolver
        self.linkDecoration = linkDecoration
        self.imagePolicy = imagePolicy
        self.imageResolver = imageResolver
        self.htmlPolicy = htmlPolicy
        self.codePolicy = codePolicy
        self.mathPolicy = mathPolicy
        self.codeHighlighter = codeHighlighter
        self.mermaidRenderer = mermaidRenderer
        self.mathRenderer = mathRenderer
        self.documentStyleBox = documentStyle.map(MarkdownDocumentStyleBox.init)
        self.affordanceActionHandler = affordanceActionHandler
        self.preparationCache = preparationCache
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    public init(
        theme: MarkdownTheme = .compactChat,
        inlineRenderingMode: MarkdownInlineRenderingMode = .coreTextPaintedLines,
        nativeTextSelection: MarkdownNativeTextSelection = .platformDefault,
        linkAction: MarkdownLinkAction? = nil,
        copyProvider: MarkdownCopyProvider? = nil,
        linkPolicy: any MarkdownLinkPolicy = DefaultMarkdownPolicy(),
        linkMetadataResolver: (any MarkdownLinkMetadataResolver)? = DefaultMarkdownLinkMetadataResolver.shared,
        linkDecoration: MarkdownLinkDecorationConfiguration = .automatic,
        imagePolicy: any MarkdownImagePolicy = DefaultMarkdownPolicy(),
        imageResolver: any MarkdownImageResolver = DefaultMarkdownImageResolver(),
        htmlPolicy: any MarkdownHTMLPolicy = DefaultMarkdownPolicy(),
        codePolicy: any MarkdownCodePolicy = DefaultMarkdownPolicy(),
        mathPolicy: any MarkdownMathPolicy = DefaultMarkdownPolicy(),
        codeHighlighter: any MarkdownCodeHighlighter = DefaultMarkdownCodeHighlighter(),
        mermaidRenderer: (any MarkdownMermaidRenderer)? = DefaultMarkdownMermaidRenderer(),
        mathRenderer: any MarkdownMathRenderer = PlainMarkdownMathRenderer(),
        documentStyle: (any MarkdownDocumentStyle)? = nil,
        affordanceActionHandler: MarkdownAffordanceActionHandler = .platformDefault,
        preparationCache: MarkdownRenderPreparationCache = MarkdownRenderPreparationCache(),
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.init(
            theme: theme,
            inlineRenderingMode: inlineRenderingMode,
            nativeTextSelection: nativeTextSelection,
            documentSelection: nativeTextSelection == .enabled ? .disabled : .enabled,
            linkAction: linkAction,
            copyProvider: copyProvider,
            linkPolicy: linkPolicy,
            linkMetadataResolver: linkMetadataResolver,
            linkDecoration: linkDecoration,
            imagePolicy: imagePolicy,
            imageResolver: imageResolver,
            htmlPolicy: htmlPolicy,
            codePolicy: codePolicy,
            mathPolicy: mathPolicy,
            codeHighlighter: codeHighlighter,
            mermaidRenderer: mermaidRenderer,
            mathRenderer: mathRenderer,
            documentStyle: documentStyle,
            affordanceActionHandler: affordanceActionHandler,
            preparationCache: preparationCache,
            diagnosticsRecorder: diagnosticsRecorder
        )
    }

    public static var compactChat: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .compactChat, inlineRenderingMode: .coreTextPaintedLines)
    }

    public static var document: MarkdownRendererConfiguration {
        MarkdownRendererConfiguration(theme: .document, inlineRenderingMode: .coreTextPaintedLines)
    }

    public func prepare(block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        prepare(block: block, reusing: nil)
    }

    private func prepare(
        block: MarkdownBlock,
        reusing previousContent: MarkdownPreparedBlockContent?
    ) -> MarkdownPreparedBlockContent {
        diagnosticsRecorder.recordRenderPreparation()

        switch block.kind {
        case .codeBlock:
            let code = Self.codeText(for: block)
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: code) {
            case .allow:
                let language = MarkdownCodeLanguage(infoString: block.infoString)
                if language.isMermaid,
                   let mermaid = preparedMermaid(code, block: block)
                {
                    return MarkdownPreparedBlockContent(
                        blockID: block.id,
                        mermaid: mermaid
                    )
                }
                let selectionInline = preparedCodeSelectionInline(for: block)
                // A mutable streaming tail changes on every publication. Do
                // not fill the sealed-content cache with hundreds of complete
                // historical copies that can never be requested again.
                let key = block.isSealed ? Self.codeCacheKey(
                    for: block,
                    code: code,
                    language: language,
                    palette: theme.syntaxHighlightingPalette,
                    highlighterIdentity: codeHighlighterCacheIdentity
                ) : nil
                if let key,
                   let cached = preparationCache.code(forKey: key) {
                    diagnosticsRecorder.recordCacheHit()
                    return MarkdownPreparedBlockContent(
                        blockID: block.id,
                        selectionInlineLayout: selectionInline,
                        code: cached
                    )
                }

                if key != nil {
                    diagnosticsRecorder.recordCacheMiss()
                }
                let highlighted = preparedHighlightedCode(
                    code,
                    block: block,
                    language: language
                )
                if let key {
                    preparationCache.insertCode(highlighted, forKey: key)
                }
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    selectionInlineLayout: selectionInline,
                    code: highlighted
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .mathBlock:
            let math = Self.mathText(for: block)
            switch mathPolicy.evaluateMath(math, isBlock: true) {
            case .allow:
                let fontSize = mathBlockFontSize
                if block.isSealed,
                   let key = blockMathCacheKey(for: block, math: math, fontSize: fontSize) {
                    if let cached = preparationCache.math(forKey: key) {
                        diagnosticsRecorder.recordCacheHit()
                        return mathBlockContent(for: block, math: cached)
                    }

                    diagnosticsRecorder.recordCacheMiss()
                    let rendered = renderPreparedMath(math, isBlock: true, fontSize: fontSize)
                    preparationCache.insertMath(rendered, forKey: key)
                    return mathBlockContent(for: block, math: rendered)
                }

                let rendered = renderPreparedMath(math, isBlock: true, fontSize: fontSize)
                return mathBlockContent(for: block, math: rendered)
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .htmlBlock:
            switch htmlPolicy.evaluateHTML(block.text) {
            case .allow:
                let richContent = block.richContent.map { richContent in
                    MarkdownPreparedRichContent(
                        blocks: richContent.blocks.map { richBlock in
                            MarkdownPreparedRichBlock(
                                block: richBlock,
                                preparedContent: prepare(block: richBlock)
                            )
                        }
                    )
                }
                let selectionInline = htmlSelectionText(for: block).flatMap { text in
                    preparedVisibleTextSelectionInline(
                        text: text,
                        sourceRange: block.sourceRange,
                        block: block
                    )
                }
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    selectionInlineLayout: selectionInline,
                    htmlAllowed: true,
                    richContent: richContent
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    htmlAllowed: false,
                    policyDenialReason: reason
                )
            }
        case .unorderedList, .orderedList, .taskList:
            let inline = preparedInline(for: block.inlines, sourceRange: block.sourceRange, block: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: inline?.attributed,
                inlineLayout: inline,
                listItems: preparedListItems(block.listItems)
            )
        case .table:
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                table: block.table.map { table in
                    preparedTable(
                        table,
                        parentID: block.id.rawValue,
                        isSealed: block.isSealed,
                        reusing: previousContent?.table
                    )
                }
            )
        default:
            let inline = preparedInline(for: block.inlines, sourceRange: block.sourceRange, block: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                inline: inline?.attributed,
                inlineLayout: inline
            )
        }
    }

    public func prepare(snapshot: MarkdownSnapshot) -> MarkdownPreparedSnapshot {
        prepare(snapshot: snapshot, reusing: nil)
    }

    func prepare(
        snapshot: MarkdownSnapshot,
        reusing previousSnapshot: MarkdownPreparedSnapshot?
    ) -> MarkdownPreparedSnapshot {
        var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent] = [:]
        var preparedItems: [MarkdownPreparedSnapshotItem] = []
        preparedContentByBlockID.reserveCapacity(snapshot.blocks.count)
        preparedItems.reserveCapacity(snapshot.items.count)

        let previousItems = previousSnapshot?.items ?? []
        var fallbackReuse: MarkdownPreparedSnapshotReuse?
        var changedItemIDs: Set<String> = []
        var newItemIDs: Set<String> = []

        for (index, item) in snapshot.items.enumerated() {
            if index < previousItems.count,
               let reused = Self.reusedPreparedItem(for: item, previousItem: previousItems[index]) {
                switch reused {
                case let .block(block, prepared):
                    preparedContentByBlockID[block.id] = prepared
                case .hostBoundary:
                    break
                }
                preparedItems.append(reused)
                continue
            }

            switch item {
            case let .block(block):
                if fallbackReuse == nil, previousSnapshot != nil {
                    fallbackReuse = MarkdownPreparedSnapshotReuse(
                        previousItems: previousItems.dropFirst(index)
                    )
                }
                let prepared = fallbackReuse?.content(for: block) ?? prepare(
                    block: block,
                    reusing: previousSnapshot?.preparedContentByBlockID[block.id]
                )
                preparedContentByBlockID[block.id] = prepared
                preparedItems.append(.block(block, prepared))
                let itemID = "block:\(block.id.rawValue)"
                if index < previousItems.count {
                    changedItemIDs.insert(itemID)
                } else {
                    newItemIDs.insert(itemID)
                }
            case let .hostBoundary(boundary):
                preparedItems.append(.hostBoundary(boundary))
                let itemID = "host:\(boundary.id.rawValue)"
                if index < previousItems.count {
                    changedItemIDs.insert(itemID)
                } else {
                    newItemIDs.insert(itemID)
                }
            }
        }

        var removedItemIDs: Set<String> = []
        if previousItems.count > preparedItems.count {
            let newItemIDSet = Set(preparedItems.map(\.id))
            for previousItem in previousItems {
                if !newItemIDSet.contains(previousItem.id) {
                    removedItemIDs.insert(previousItem.id)
                }
            }
        }

        let generation = snapshot.generation
        let diff = MarkdownPreparedSnapshotDiff(
            changedItemIDs: changedItemIDs,
            newItemIDs: newItemIDs,
            removedItemIDs: removedItemIDs,
            generation: generation
        )

        return MarkdownPreparedSnapshot(
            snapshot: snapshot,
            items: preparedItems,
            preparedContentByBlockID: preparedContentByBlockID,
            diff: diff
        )
    }

    private static func reusedPreparedItem(
        for item: MarkdownSnapshotItem,
        previousItem: MarkdownPreparedSnapshotItem
    ) -> MarkdownPreparedSnapshotItem? {
        switch (item, previousItem) {
        case let (.block(block), .block(previousBlock, previousContent))
            where Self.renderPreparationEquivalent(block, previousBlock) &&
                !Self.tableNeedsSealPreparation(block, previousBlock):
            return .block(block, previousContent)
        case let (.hostBoundary(boundary), .hostBoundary(previousBoundary))
            where boundary == previousBoundary:
            return .hostBoundary(boundary)
        default:
            return nil
        }
    }

    fileprivate static func tableNeedsSealPreparation(
        _ block: MarkdownBlock,
        _ previousBlock: MarkdownBlock
    ) -> Bool {
        block.kind == .table && block.isSealed && !previousBlock.isSealed
    }

    fileprivate static func renderPreparationEquivalent(
        _ lhs: MarkdownBlock,
        _ rhs: MarkdownBlock
    ) -> Bool {
        var lhs = lhs
        var rhs = rhs
        lhs.isSealed = false
        rhs.isSealed = false
        return lhs == rhs
    }

    func unpreparedSnapshot(for snapshot: MarkdownSnapshot) -> MarkdownPreparedSnapshot {
        var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent] = [:]
        var preparedItems: [MarkdownPreparedSnapshotItem] = []

        for item in snapshot.items {
            switch item {
            case let .block(block):
                let content = unpreparedContent(for: block)
                preparedContentByBlockID[block.id] = content
                preparedItems.append(.block(block, content))
            case let .hostBoundary(boundary):
                preparedItems.append(.hostBoundary(boundary))
            }
        }

        return MarkdownPreparedSnapshot(
            snapshot: snapshot,
            items: preparedItems,
            preparedContentByBlockID: preparedContentByBlockID
        )
    }

    func unpreparedContent(for block: MarkdownBlock) -> MarkdownPreparedBlockContent {
        switch block.kind {
        case .codeBlock:
            switch codePolicy.evaluateCodeBlock(infoString: block.infoString, code: Self.codeText(for: block)) {
            case .allow:
                break
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .mathBlock:
            switch mathPolicy.evaluateMath(Self.mathText(for: block), isBlock: true) {
            case .allow:
                break
            case let .deny(reason):
                return MarkdownPreparedBlockContent(blockID: block.id, policyDenialReason: reason)
            }
        case .htmlBlock:
            switch htmlPolicy.evaluateHTML(block.text) {
            case .allow:
                let richContent = block.richContent.map { richContent in
                    MarkdownPreparedRichContent(
                        blocks: richContent.blocks.map { richBlock in
                            MarkdownPreparedRichBlock(
                                block: richBlock,
                                preparedContent: unpreparedContent(for: richBlock)
                            )
                        }
                    )
                }
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    htmlAllowed: true,
                    richContent: richContent
                )
            case let .deny(reason):
                return MarkdownPreparedBlockContent(
                    blockID: block.id,
                    htmlAllowed: false,
                    policyDenialReason: reason
                )
            }
        default:
            break
        }

        return MarkdownPreparedBlockContent(
            blockID: block.id,
            inline: unpreparedInline(block.inlines),
            listItems: block.listItems.map { unpreparedListItem($0, parentID: block.id.rawValue) },
            table: unpreparedTable(block.table, parentID: block.id.rawValue)
        )
    }

    private func unpreparedListItem(
        _ item: MarkdownListItem,
        parentID: String
    ) -> MarkdownPreparedListItem {
        let id = "unprepared-list:\(parentID):\(item.sourceRange.byteRange.lowerBound)-\(item.sourceRange.byteRange.upperBound)"
        return MarkdownPreparedListItem(
            id: id,
            sourceRange: item.sourceRange,
            taskState: item.taskState,
            inline: unpreparedInline(item.inlines) ?? AttributedString(item.text),
            childListKind: item.childListKind,
            childOrderedListStart: item.childOrderedListStart,
            childItems: item.childItems.map { unpreparedListItem($0, parentID: id) }
        )
    }

    private func unpreparedTable(
        _ table: MarkdownTableBlock?,
        parentID: String
    ) -> MarkdownPreparedTableBlock? {
        guard let table else {
            return nil
        }

        let headerID = Self.tableRowID(parentID: parentID, role: "header", cells: table.header)
        let header = table.header.enumerated().map { column, cell in
            unpreparedTableCell(cell, rowID: headerID, column: column)
        }
        let rows = table.rows.map { row in
            let rowID = Self.tableRowID(parentID: parentID, role: "body", cells: row)
            return MarkdownPreparedTableRow(
                id: rowID,
                cells: row.enumerated().map { column, cell in
                    unpreparedTableCell(cell, rowID: rowID, column: column)
                }
            )
        }
        let columnCount = Self.tableColumnCount(
            alignments: table.columnAlignments,
            header: header,
            rows: rows
        )
        let naturalWidths = tableNaturalWidths(
            columnCount: columnCount,
            header: header,
            rows: rows
        )

        return MarkdownPreparedTableBlock(
            columnAlignments: table.columnAlignments,
            header: header,
            rows: rows,
            headerID: headerID,
            columnNaturalWidths: naturalWidths,
            columnWidths: tableEffectiveColumnWidths(
                naturalWidths: naturalWidths,
                columnCount: columnCount,
                isSealed: true,
                previousWidths: nil
            )
        )
    }

    private func unpreparedTableCell(
        _ cell: MarkdownTableCell,
        rowID: String,
        column: Int
    ) -> MarkdownPreparedTableCell {
        let id = Self.tableCellID(rowID: rowID, column: column, cell: cell)
        let inline = unpreparedInline(cell.inlines) ?? AttributedString(cell.text)
        let contentHash = Self.tableCellContentHash(cell)
        return MarkdownPreparedTableCell(
            id: id,
            sourceRange: cell.sourceRange,
            contentHash: contentHash,
            inline: inline,
            naturalWidth: Double(inline.characters.count) *
                Self.sanitizedPositive(theme.paragraphFontSize, fallback: 16) * 0.56,
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
    }

    private func unpreparedInline(_ runs: [MarkdownInlineRun]) -> AttributedString? {
        guard !runs.isEmpty else {
            return nil
        }

        return InlineRunsView.attributedString(
            for: runs,
            linkPolicy: linkPolicy,
            imagePolicy: imagePolicy
        )
    }

    public nonisolated static func codeText(for block: MarkdownBlock) -> String {
        block.text
    }

    public nonisolated static func mathText(for block: MarkdownBlock) -> String {
        if let mathRun = block.inlines.first(where: { $0.kind == .math }) {
            return mathRun.text
        }

        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\begin{"), trimmed.contains("\\end{") {
            return trimmed
        }

        for (open, close) in [("$$", "$$"), ("\\[", "\\]")] {
            guard trimmed.hasPrefix(open),
                  trimmed.hasSuffix(close),
                  trimmed.count >= open.count + close.count
            else {
                continue
            }

            let start = trimmed.index(trimmed.startIndex, offsetBy: open.count)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -close.count)
            if start <= end {
                return String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    private nonisolated static func cacheNamespace(_ fields: [(String, String)]) -> String {
        fields.map { name, value in
            "\(name)#\(value.utf8.count):\(value)"
        }
        .joined(separator: "|")
    }

    private func blockMathCacheKey(
        for block: MarkdownBlock,
        math: String,
        fontSize: Double
    ) -> MarkdownCacheKey? {
        guard let mathPolicyIdentity,
              let mathRendererIdentity
        else {
            return nil
        }

        return MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: Self.stableHash(math),
            namespace: Self.cacheNamespace([
                ("cache", "rendered-math:block"),
                ("version", "5"),
                ("policy", mathPolicyIdentity),
                ("renderer", mathRendererIdentity),
                ("fontSize", String(fontSize))
            ])
        )
    }

    private func inlineMathCacheKey(for run: MarkdownInlineRun, fontSize: Double) -> MarkdownCacheKey? {
        guard let mathPolicyIdentity,
              let mathRendererIdentity
        else {
            return nil
        }

        return MarkdownCacheKey(
            sourceRange: Self.sharedRenderedMathCacheRange,
            contentHash: Self.stableHash(run.text),
            namespace: Self.cacheNamespace([
                ("cache", "rendered-math:inline"),
                ("version", "1"),
                ("policy", mathPolicyIdentity),
                ("renderer", mathRendererIdentity),
                ("fontSize", String(fontSize))
            ])
        )
    }

    private nonisolated static let sharedRenderedMathCacheRange = MarkdownSourceRange(
        byteRange: 0..<0,
        lineRange: 0..<0
    )

    var mathBlockFontSize: Double {
        (Self.sanitizedPositive(theme.paragraphFontSize, fallback: 16) * 1.3).rounded()
    }

    private func mathBlockContent(
        for block: MarkdownBlock,
        math: MarkdownPreparedMath
    ) -> MarkdownPreparedBlockContent {
        switch math {
        case let .text(attributed):
            let visibleText = String(attributed.characters)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                selectionInlineLayout: preparedVisibleTextSelectionInline(
                    text: visibleText,
                    sourceRange: mathSelectionSourceRange(for: block),
                    block: block
                ),
                math: attributed,
                mathRender: .text(attributed)
            )
        case let .image(image):
            let sourceText = Self.mathText(for: block)
            return MarkdownPreparedBlockContent(
                blockID: block.id,
                selectionInlineLayout: preparedVisibleTextSelectionInline(
                    text: sourceText.isEmpty ? image.latex : sourceText,
                    sourceRange: mathSelectionSourceRange(for: block),
                    block: block
                ),
                math: AttributedString(image.latex),
                mathRender: .image(image)
            )
        }
    }

    private func preparedVisibleTextSelectionInline(
        text: String,
        sourceRange: MarkdownSourceRange,
        block: MarkdownBlock? = nil
    ) -> MarkdownPreparedInlineContent? {
        guard !text.isEmpty else {
            return nil
        }

        return preparedInline(
            for: [
                MarkdownInlineRun(
                    kind: .text,
                    text: text,
                    sourceRange: sourceRange
                )
            ],
            sourceRange: sourceRange,
            block: block
        )
    }

    private func htmlSelectionText(for block: MarkdownBlock) -> String? {
        let sourceByteCount = block.sourceRange.byteRange.count
        guard sourceByteCount > 0 else {
            return nil
        }
        if block.text.utf8.count == sourceByteCount {
            return block.text
        }

        var text = block.text
        while text.utf8.count > sourceByteCount,
              text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }
        guard text.utf8.count == sourceByteCount else {
            return nil
        }
        return text
    }

    private func mathSelectionSourceRange(for block: MarkdownBlock) -> MarkdownSourceRange {
        block.inlines.first { $0.kind == .math }?.sourceRange ?? block.sourceRange
    }

    private nonisolated static func codeCacheKey(
        for block: MarkdownBlock,
        code: String,
        language: MarkdownCodeLanguage,
        palette: MarkdownSyntaxHighlightingPalette,
        highlighterIdentity: String?
    ) -> MarkdownCacheKey? {
        guard let highlighterIdentity else {
            return nil
        }

        return MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: stableHash(code),
            namespace: cacheNamespace([
                ("cache", "highlighted-code"),
                ("version", "4"),
                ("language", language.cacheIdentity),
                ("infoStringPresent", block.infoString == nil ? "0" : "1"),
                ("infoString", block.infoString ?? ""),
                ("palette", palette.cacheIdentity),
                ("highlighter", highlighterIdentity)
            ])
        )
    }

    private nonisolated static func mermaidCacheKey(
        for block: MarkdownBlock,
        code: String,
        rendererIdentity: String?,
        themeIdentity: String
    ) -> MarkdownCacheKey? {
        guard let rendererIdentity else {
            return nil
        }

        return MarkdownCacheKey(
            sourceRange: block.sourceRange,
            contentHash: stableHash(code),
            namespace: cacheNamespace([
                ("cache", "rendered-mermaid"),
                ("version", "2"),
                ("renderer", rendererIdentity),
                ("theme", themeIdentity)
            ])
        )
    }

    private var codeHighlighterCacheIdentity: String? {
        if let identifying = codeHighlighter as? any MarkdownCodeHighlighterCacheIdentifying {
            return identifying.codeHighlighterCacheIdentity
        }

        return nil
    }

    private var mermaidRendererCacheIdentity: String? {
        guard let mermaidRenderer else {
            return nil
        }

        if let identifying = mermaidRenderer as? any MarkdownMermaidRendererCacheIdentifying {
            return identifying.mermaidRendererCacheIdentity
        }

        return nil
    }

    private var mermaidThemeCacheIdentity: String {
        theme.renderCacheIdentity
    }

    private var linkPolicyIdentity: String? {
        (linkPolicy as? any MarkdownLinkPolicyCacheIdentifying)?.linkPolicyCacheIdentity
    }

    private var imagePolicyIdentity: String? {
        (imagePolicy as? any MarkdownImagePolicyCacheIdentifying)?.imagePolicyCacheIdentity
    }

    private var imageResolverIdentity: String? {
        (imageResolver as? any MarkdownImageResolverCacheIdentifying)?.imageResolverCacheIdentity
    }

    private var mathPolicyIdentity: String? {
        (mathPolicy as? any MarkdownMathPolicyCacheIdentifying)?.mathPolicyCacheIdentity
    }

    private var mathRendererIdentity: String? {
        (mathRenderer as? any MarkdownMathRendererCacheIdentifying)?.mathRendererCacheIdentity
    }

    private var recordsTextMathFallbacks: Bool {
        (mathRenderer as? any MarkdownMathRendererFallbackDiagnosing)?.recordsTextFallbackAsMathFallback == true
    }

    private func shouldRecordCodeHighlight(language: MarkdownCodeLanguage) -> Bool {
        if codeHighlighter is PlainMarkdownCodeHighlighter {
            return false
        }

        if codeHighlighter is DefaultMarkdownCodeHighlighter {
            return language.shouldHighlight
        }

        return true
    }

    private func highlightedCode(
        _ code: String,
        infoString: String?,
        language: MarkdownCodeLanguage
    ) -> AttributedString {
        if codeHighlighter is PlainMarkdownCodeHighlighter {
            return DefaultMarkdownCodeHighlighter.plainCode(code)
        }

        if let defaultHighlighter = codeHighlighter as? DefaultMarkdownCodeHighlighter {
            guard language.shouldHighlight else {
                return DefaultMarkdownCodeHighlighter.plainCode(code)
            }

            return defaultHighlighter.highlightedCode(
                code,
                infoString: infoString,
                palette: theme.syntaxHighlightingPalette
            )
        }

        return codeHighlighter.highlightedCode(code, infoString: infoString)
    }

    private func preparedMermaid(
        _ code: String,
        block: MarkdownBlock
    ) -> MarkdownPreparedMermaidDiagram? {
        guard let mermaidRenderer else {
            return nil
        }

        let key = block.isSealed ? Self.mermaidCacheKey(
            for: block,
            code: code,
            rendererIdentity: mermaidRendererCacheIdentity,
            themeIdentity: mermaidThemeCacheIdentity
        ) : nil
        if let key,
           let cached = preparationCache.mermaid(forKey: key) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        if key != nil {
            diagnosticsRecorder.recordCacheMiss()
        }
        diagnosticsRecorder.recordMermaidRender()
        let rendered = MarkdownDiagnostics().signpost("MermaidRender", category: "RenderPreparation") {
            mermaidRenderer.renderedMermaid(code, sourceRange: block.sourceRange, theme: theme)
        }
        guard let rendered else {
            diagnosticsRecorder.recordMermaidFallback()
            return nil
        }

        if let key {
            preparationCache.insertMermaid(rendered, forKey: key)
        }
        return rendered
    }

    private func preparedInline(
        for runs: [MarkdownInlineRun],
        sourceRange: MarkdownSourceRange,
        block: MarkdownBlock? = nil
    ) -> MarkdownPreparedInlineContent? {
        guard !runs.isEmpty else {
            return nil
        }

        let decorated = preparedLinkDecorations(in: runs)
        let displaySourceRuns = decorated.runs
        let metrics = inlineMetrics(for: block)
        let imageDecisions = preparedImageDecisions(
            for: displaySourceRuns,
            preparedOverrides: decorated.preparedImagesBySource
        )
        let mathDecisions = preparedMathDecisions(for: displaySourceRuns)
        let cacheKey = block?.isSealed == false ? nil : inlineCacheNamespace(
            for: displaySourceRuns,
            metrics: metrics,
            imageDecisions: imageDecisions,
            mathDecisions: mathDecisions
        ).map { namespace in
            MarkdownCacheKey(
                sourceRange: sourceRange,
                contentHash: Self.inlineHash(displaySourceRuns),
                namespace: namespace
            )
        }
        if let cacheKey,
           let cached = preparationCache.inline(forKey: cacheKey) {
            diagnosticsRecorder.recordCacheHit()
            return cached
        }

        if cacheKey != nil {
            diagnosticsRecorder.recordCacheMiss()
        }
        let images = preparedImages(from: imageDecisions)
        let attachments = preparedAttachments(
            from: imageDecisions,
            images: images,
            fontSize: metrics.fontSize,
            fontProfiles: metrics.fontProfiles
        )
        let inlinePayload = preparedInlinePayload(
            for: displaySourceRuns,
            images: images,
            attachments: attachments,
            mathDecisions: mathDecisions,
            fontSize: metrics.fontSize
        )
        let prepared = PreparedInlineContent(runs: inlinePayload.runs, sourceRange: sourceRange)
        diagnosticsRecorder.recordPrepare()
        let measurer = CoreTextInlineMeasurer(
            profiles: metrics.fontProfiles,
            measurementCache: preparationCache.coreTextMeasurementCache
        )
        let measured = VariableWidthLineWalker(measurer: measurer).prepare(
            prepared,
            fontSize: metrics.fontSize
        )
        let layoutCache = MarkdownInlineLayoutCache(
            measurer: measurer,
            diagnosticsRecorder: diagnosticsRecorder
        )
        // Reserved attachment boxes can be taller than the surrounding
        // text; bump the uniform per-content line height so CoreText line
        // gaps/hosts have room without a re-layout thrash later (Inline
        // Attachments Part 02 §2.2.4). This package still lays out with a
        // single line height per prepared content (no per-line variable
        // height), so a tall attachment among plain-text lines evenly
        // taxes every line in that block — an honest v1 trade-off, not a
        // hidden bug.
        let effectiveLineHeight = max(
            metrics.lineHeight,
            inlinePayload.attachments.values.map(\.pointHeight).max() ?? 0
        )
        // Seed initial layout with the last real container width observed in
        // this session (if any) instead of a fixed constant, so the
        // pre-built initial layout / CTLine plan actually matches the width
        // new blocks will render at during streaming (INV-P1, INV-P2). Falls
        // back to `InlineRunsView.defaultLayoutWidth` before any real width
        // is known (e.g. the very first block in a session).
        let defaultLayoutWidth = preparationCache.currentDefaultLayoutWidth
        var inline = MarkdownPreparedInlineContent(
            attributed: inlinePayload.attributed,
            prepared: prepared,
            measured: measured,
            images: images,
            attachments: inlinePayload.attachments,
            fontSize: metrics.fontSize,
            lineHeight: effectiveLineHeight,
            fontProfiles: metrics.fontProfiles,
            layoutCache: layoutCache,
            mathTextPieces: inlinePayload.mathPieces
        )
        let initialLayoutWidth = InlineRunsView.nativeLineLayoutWidth(
            for: inline,
            containerWidth: defaultLayoutWidth
        )
        var initialLayoutEngine = InlineLayoutEngine(
            measurer: measurer,
            cacheCapacity: 0,
            diagnosticsRecorder: MarkdownDiagnosticsRecorder()
        )
        inline.initialLayoutResult = initialLayoutEngine.layout(
            measured,
            options: InlineLayoutOptions(
                containerWidth: initialLayoutWidth,
                fontSize: metrics.fontSize,
                lineHeight: effectiveLineHeight
            ),
            allowsOverwideFallback: true
        )
        inline.defaultLayoutWidth = defaultLayoutWidth
        inline.preparationCache = preparationCache
        #if canImport(CoreText)
        if let initialLayout = inline.initialLayoutResult,
           !initialLayout.lines.isEmpty
        {
            inline.coreTextLinePlan = MarkdownCoreTextPaintedLinePlan.make(
                prepared: inline,
                layout: initialLayout
            )
        }
        #endif
        if let cacheKey {
            preparationCache.insertInline(inline, forKey: cacheKey)
        }
        return inline
    }

    private func preparedCodeSelectionInline(for block: MarkdownBlock) -> MarkdownPreparedInlineContent? {
        guard block.kind == .codeBlock,
              !block.inlines.isEmpty
        else {
            return nil
        }

        let sourceRange = block.inlines.first?.sourceRange ?? block.sourceRange
        let selectionRuns = block.inlines.map { run in
            MarkdownInlineRun(
                kind: .text,
                text: run.text,
                sourceRange: run.sourceRange,
                destination: run.destination,
                imageSource: run.imageSource
            )
        }
        return preparedInline(for: selectionRuns, sourceRange: sourceRange, block: block)
    }

    private func preparedHighlightedCode(
        _ code: String,
        block: MarkdownBlock,
        language: MarkdownCodeLanguage
    ) -> AttributedString {
        let renderFull: (String) -> AttributedString = { fragment in
            if shouldRecordCodeHighlight(language: language) {
                diagnosticsRecorder.recordCodeHighlight(bytes: fragment.utf8.count)
                return MarkdownDiagnostics().signpost("CodeHighlight", category: "RenderPreparation") {
                    highlightedCode(fragment, infoString: block.infoString, language: language)
                }
            }
            return highlightedCode(fragment, infoString: block.infoString, language: language)
        }

        let removeRollingState = {
            if let removed = preparationCache.removeStreamingCodeHighlightState(blockID: block.id),
               let backendStateID = removed.backendStateID
            {
                DefaultMarkdownCodeHighlighter().removeIncrementalState(backendStateID)
            }
        }

        guard !block.isSealed else {
            removeRollingState()
            return renderFull(code)
        }

        let defaultHighlighter = codeHighlighter as? DefaultMarkdownCodeHighlighter
        let usesContextFreeSuffix = codeHighlighter is PlainMarkdownCodeHighlighter ||
            (defaultHighlighter != nil && !language.shouldHighlight)
        let usesHighlightJSContinuation = defaultHighlighter != nil &&
            language.shouldHighlight && language.backendName != "swift"
        guard usesContextFreeSuffix || usesHighlightJSContinuation else {
            // An arbitrary host highlighter may carry its own whole-document
            // lexical state. The native Swift highlighter also needs its full
            // prefix for nested comments, raw strings, and interpolation.
            // Preserve exact output unless a backend has a proven continuation
            // path; performance work must not trade away live syntax fidelity.
            removeRollingState()
            return renderFull(code)
        }

        let contextIdentity = Self.cacheNamespace([
            ("streamingCode", "2"),
            ("language", language.cacheIdentity),
            ("infoString", block.infoString ?? ""),
            ("palette", theme.syntaxHighlightingPalette.cacheIdentity),
            ("highlighter", codeHighlighterCacheIdentity ?? String(reflecting: type(of: codeHighlighter)))
        ])
        let backendStateID = usesHighlightJSContinuation
            ? preparationCache.streamingCodeHighlightStateID(
                blockID: block.id,
                contextIdentity: contextIdentity
            )
            : nil

        let renderIncrement: (String, Bool) -> AttributedString? = { fragment, reset in
            guard let defaultHighlighter, let backendStateID else {
                return renderFull(fragment)
            }
            if shouldRecordCodeHighlight(language: language) {
                diagnosticsRecorder.recordCodeHighlight(bytes: fragment.utf8.count)
            }
            return MarkdownDiagnostics().signpost(
                "CodeHighlight",
                category: "RenderPreparation"
            ) {
                defaultHighlighter.incrementallyHighlightedCode(
                    fragment,
                    language: language,
                    palette: theme.syntaxHighlightingPalette,
                    stateID: backendStateID,
                    reset: reset
                )
            }
        }

        let store: (AttributedString, Int) -> Void = { highlighted, fullHighlightByteCount in
            preparationCache.storeStreamingCodeHighlightState(
                MarkdownStreamingCodeHighlightState(
                    blockID: block.id,
                    contextIdentity: contextIdentity,
                    backendStateID: backendStateID,
                    code: code,
                    highlighted: highlighted,
                    fullHighlightByteCount: fullHighlightByteCount
                )
            )
        }

        let renderAndStoreFullContext: () -> AttributedString = {
            if let highlighted = renderIncrement(code, true) {
                store(highlighted, code.utf8.count)
                return highlighted
            }

            // A pinned-runtime mismatch or illegal Highlight.js parse fails
            // closed to the ordinary full-document highlighter. Do not retain
            // a rolling state whose continuation fidelity is unknown.
            if let backendStateID {
                DefaultMarkdownCodeHighlighter().removeIncrementalState(backendStateID)
            }
            _ = preparationCache.removeStreamingCodeHighlightState(blockID: block.id)
            return renderFull(code)
        }

        if let previous = preparationCache.streamingCodeHighlightState(
            blockID: block.id,
            contextIdentity: contextIdentity
        ), code.hasPrefix(previous.code) {
            if code == previous.code {
                return previous.highlighted
            }
            let previousByteCount = previous.code.utf8.count
            let codeByteCount = code.utf8.count
            let growthSinceFull = codeByteCount - previous.fullHighlightByteCount
            if growthSinceFull < Self.streamingCodeFullHighlightCheckpointBytes,
               previousByteCount <= codeByteCount
            {
                let suffixStart = code.utf8.index(code.utf8.startIndex, offsetBy: previousByteCount)
                let suffix = String(decoding: code.utf8[suffixStart...], as: UTF8.self)
                if let highlightedSuffix = renderIncrement(suffix, false) {
                    var highlighted = previous.highlighted
                    highlighted.append(highlightedSuffix)
                    store(highlighted, previous.fullHighlightByteCount)
                    return highlighted
                }
                return renderAndStoreFullContext()
            }
        }

        return renderAndStoreFullContext()
    }

    private static let streamingCodeFullHighlightCheckpointBytes = 16 * 1_024

    private func inlineCacheNamespace(
        for runs: [MarkdownInlineRun],
        metrics: (fontSize: Double, lineHeight: Double, fontProfiles: MarkdownInlineFontProfiles),
        imageDecisions: [MarkdownPreparedImageDecision],
        mathDecisions: [MarkdownPreparedMathDecision]
    ) -> String? {
        var components: [(String, String)] = [
            ("cache", "inline-prepared"),
            ("version", "3"),
            ("fontSize", String(metrics.fontSize)),
            ("lineHeight", String(metrics.lineHeight)),
            ("fontProfiles", metrics.fontProfiles.cacheKey)
        ]

        if runs.contains(where: { $0.isLinkPresentation }) {
            guard let linkPolicyIdentity else {
                return nil
            }
            components.append(("linkPolicy", linkPolicyIdentity))
        }

        if runs.contains(where: { $0.presentation.contains(.linkDecoration) }) {
            components.append(("linkDecorationMetricsVersion", "2"))
            components.append(("linkDecorationFallbackGlyph", linkDecoration.fallbackGlyph))
            components.append(("linkDecorationIconPointSize", String(linkDecoration.iconPointSize)))
        }

        if !imageDecisions.isEmpty {
            guard let imagePolicyIdentity else {
                return nil
            }
            components.append(("imagePolicy", imagePolicyIdentity))
            if imageDecisions.contains(where: { decision in
                if case .allow = decision.policyDecision {
                    return true
                }
                return false
            }) {
                guard let imageResolverIdentity else {
                    return nil
                }
                components.append(("imageResolver", imageResolverIdentity))
                // Allowed images may become reserved-box attachments
                // (Inline Attachments Part 01/04 §4.4): fold in the
                // metrics schema version and the theme's default
                // placeholder box so changing either invalidates prepared
                // inline content that embedded stale box metrics.
                components.append(("attachmentMetricsVersion", "1"))
                components.append(("themeAttachmentPlaceholder", theme.attachmentPlaceholder.renderCacheIdentity))
            }
        }

        if runs.contains(where: { $0.isMathPresentation }) {
            guard let mathPolicyIdentity else {
                return nil
            }
            components.append(("mathPolicy", mathPolicyIdentity))
            if mathDecisions.contains(where: { decision in
                if case .allow = decision.policyDecision {
                    return true
                }
                return false
            }) {
                guard let mathRendererIdentity else {
                    return nil
                }
                components.append(("mathRenderer", mathRendererIdentity))
            }
        }

        return Self.cacheNamespace(components)
    }

    private func preparedLinkDecorations(in runs: [MarkdownInlineRun]) -> MarkdownDecoratedLinkRuns {
        guard linkDecoration.isEnabled else {
            return MarkdownDecoratedLinkRuns(runs: runs, preparedImagesBySource: [:])
        }

        var decoratedRuns: [MarkdownInlineRun] = []
        decoratedRuns.reserveCapacity(runs.count + runs.count / 3)
        var preparedImagesBySource: [String: MarkdownPreparedImage] = [:]
        var previousDestination: String?

        for run in runs {
            guard run.isLinkPresentation,
                  run.kind != .softBreak,
                  run.kind != .hardBreak,
                  let destination = run.destination,
                  let destinationURL = markdownLinkURL(for: destination, policy: linkPolicy),
                  destinationURL.scheme?.lowercased() == "http" || destinationURL.scheme?.lowercased() == "https"
            else {
                decoratedRuns.append(run)
                previousDestination = nil
                continue
            }

            if previousDestination != destination {
                let resolvedDecoration: MarkdownLinkDecoration
                if let resolution = linkMetadataResolver?.cachedResolution(for: destinationURL),
                   case let .metadata(metadata) = resolution {
                    resolvedDecoration = metadata.decoration
                } else {
                    resolvedDecoration = .glyph(linkDecoration.fallbackGlyph)
                }

                switch resolvedDecoration {
                case let .glyph(glyph):
                    if !glyph.isEmpty {
                        decoratedRuns.append(
                            MarkdownInlineRun(
                                kind: .link,
                                text: glyph + "\u{00A0}",
                                sourceRange: Self.zeroLengthSourceRange(atStartOf: run.sourceRange),
                                destination: destination,
                                presentation: .linkDecoration
                            )
                        )
                    }
                case let .favicon(icon):
                    let token = Self.linkIconSourceToken(icon)
                    decoratedRuns.append(
                        MarkdownInlineRun(
                            kind: .link,
                            text: "Website icon",
                            sourceRange: nil,
                            destination: destination,
                            imageSource: token,
                            presentation: MarkdownInlinePresentation.image.union(.linkDecoration)
                        )
                    )
                    decoratedRuns.append(
                        MarkdownInlineRun(
                            kind: .link,
                            text: "\u{00A0}",
                            sourceRange: Self.zeroLengthSourceRange(atStartOf: run.sourceRange),
                            destination: destination,
                            presentation: .linkDecoration
                        )
                    )
                    preparedImagesBySource[token] = MarkdownPreparedImage(
                        source: token,
                        altText: "Website icon for \(destinationURL.host ?? destination)",
                        sourceRange: run.sourceRange,
                        preparedSource: .data(icon.data, mimeType: icon.mimeType)
                    )
                }
            }

            decoratedRuns.append(run)
            previousDestination = destination
        }

        return MarkdownDecoratedLinkRuns(
            runs: decoratedRuns,
            preparedImagesBySource: preparedImagesBySource
        )
    }

    private nonisolated static func zeroLengthSourceRange(
        atStartOf sourceRange: MarkdownSourceRange?
    ) -> MarkdownSourceRange? {
        guard let sourceRange else { return nil }
        return MarkdownSourceRange(
            byteRange: sourceRange.byteRange.lowerBound..<sourceRange.byteRange.lowerBound,
            lineRange: sourceRange.lineRange.lowerBound..<sourceRange.lineRange.lowerBound
        )
    }

    private nonisolated static func linkIconSourceToken(_ icon: MarkdownLinkIcon) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in icon.data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "sirius-link-icon:\(String(hash, radix: 16)):\(icon.sourceURL.absoluteString)"
    }

    private func preparedImageDecisions(for runs: [MarkdownInlineRun]) -> [MarkdownPreparedImageDecision] {
        preparedImageDecisions(for: runs, preparedOverrides: [:])
    }

    private func preparedImageDecisions(
        for runs: [MarkdownInlineRun],
        preparedOverrides: [String: MarkdownPreparedImage]
    ) -> [MarkdownPreparedImageDecision] {
        runs.compactMap { run in
            guard run.isImagePresentation,
                  let source = run.resolvedImageSource
            else {
                return nil
            }

            return MarkdownPreparedImageDecision(
                run: run,
                source: source,
                policyDecision: preparedOverrides[source] == nil
                    ? imagePolicy.evaluateImage(source: source, altText: run.text)
                    : .allow,
                preparedOverride: preparedOverrides[source]
            )
        }
    }

    private func preparedMathDecisions(for runs: [MarkdownInlineRun]) -> [MarkdownPreparedMathDecision] {
        runs.compactMap { run in
            guard run.isMathPresentation else {
                return nil
            }

            return MarkdownPreparedMathDecision(
                run: run,
                policyDecision: mathPolicy.evaluateMath(run.text, isBlock: false)
            )
        }
    }

    private func preparedInlinePayload(
        for runs: [MarkdownInlineRun],
        images: [MarkdownPreparedImage],
        attachments: [MarkdownPreparedAttachment?],
        mathDecisions: [MarkdownPreparedMathDecision],
        fontSize: Double
    ) -> (
        runs: [MarkdownInlineRun],
        attributed: AttributedString,
        mathPieces: [MarkdownInlineMathPiece]?,
        attachments: [MarkdownAttachmentID: MarkdownPreparedAttachment]
    ) {
        var displayRuns: [MarkdownInlineRun] = []
        var attributed = AttributedString()
        var pieces: [MarkdownInlineMathPiece] = []
        var pendingText = AttributedString()
        var producedMathImage = false
        var imageIndex = 0
        var mathDecisionIndex = 0
        var attachmentsByID: [MarkdownAttachmentID: MarkdownPreparedAttachment] = [:]

        func flushPendingText() {
            guard !pendingText.characters.isEmpty else {
                return
            }
            pieces.append(.text(pendingText))
            pendingText = AttributedString()
        }

        for run in runs {
            if run.isImagePresentation {
                let image: MarkdownPreparedImage?
                let attachment: MarkdownPreparedAttachment?
                if run.resolvedImageSource != nil, imageIndex < images.count {
                    image = images[imageIndex]
                    attachment = imageIndex < attachments.count ? attachments[imageIndex] : nil
                    imageIndex += 1
                } else {
                    image = nil
                    attachment = nil
                }
                if let attachment {
                    attachmentsByID[attachment.id] = attachment
                }
                let displayRun = preparedImageDisplayRun(for: run, image: image, attachment: attachment)
                displayRuns.append(displayRun)
                let piece = InlineRunsView.attributedString(
                    for: [displayRun],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
                continue
            }

            guard run.isMathPresentation else {
                displayRuns.append(run)
                let piece = InlineRunsView.attributedString(
                    for: [run],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
                continue
            }

            let mathDecision = mathDecisions[mathDecisionIndex]
            mathDecisionIndex += 1

            switch mathDecision.policyDecision {
            case .allow:
                let preparedMath = preparedInlineMath(for: run, fontSize: fontSize)

                switch preparedMath {
                case let .image(image):
                    producedMathImage = true
                    flushPendingText()
                    pieces.append(.math(image))
                    let fallback = mathAttributedString(
                        AttributedString(image.latex),
                        preservingLinkFrom: run
                    )
                    attributed.append(fallback)
                    let fallbackText = String(fallback.characters)
                    displayRuns.append(
                        MarkdownInlineRun(
                            kind: run.kind,
                            text: fallbackText.isEmpty ? run.text : fallbackText,
                            sourceRange: run.sourceRange,
                            destination: run.destination,
                            imageSource: run.imageSource,
                            presentation: run.presentation
                        )
                    )
                case let .text(renderedMath):
                    let rendered = mathAttributedString(renderedMath, preservingLinkFrom: run)
                    attributed.append(rendered)
                    pendingText.append(rendered)
                    let renderedText = String(rendered.characters)
                    displayRuns.append(
                        MarkdownInlineRun(
                            kind: run.kind,
                            text: renderedText.isEmpty ? run.text : renderedText,
                            sourceRange: run.sourceRange,
                            destination: run.destination,
                            imageSource: run.imageSource,
                            presentation: run.presentation
                        )
                    )
                }
            case .deny:
                displayRuns.append(run)
                let piece = InlineRunsView.attributedString(
                    for: [run],
                    linkPolicy: linkPolicy,
                    imagePolicy: imagePolicy
                )
                attributed.append(piece)
                pendingText.append(piece)
            }
        }

        flushPendingText()
        return (displayRuns, attributed, producedMathImage ? pieces : nil, attachmentsByID)
    }

    private func preparedInlineMath(for run: MarkdownInlineRun, fontSize: Double) -> MarkdownPreparedMath {
        if let key = inlineMathCacheKey(for: run, fontSize: fontSize) {
            if let cached = preparationCache.math(forKey: key) {
                diagnosticsRecorder.recordCacheHit()
                return cached
            }

            diagnosticsRecorder.recordCacheMiss()
            let rendered = renderPreparedMath(run.text, isBlock: false, fontSize: fontSize)
            preparationCache.insertMath(rendered, forKey: key)
            return rendered
        }

        return renderPreparedMath(run.text, isBlock: false, fontSize: fontSize)
    }

    private func renderPreparedMath(_ source: String, isBlock: Bool, fontSize: Double) -> MarkdownPreparedMath {
        diagnosticsRecorder.recordMathRender()
        let rendered = MarkdownDiagnostics().signpost("MathRender", category: "RenderPreparation") {
            mathRenderer.preparedMath(source, isBlock: isBlock, fontSize: fontSize)
        }
        if recordsTextMathFallbacks, case .text = rendered {
            diagnosticsRecorder.recordMathFallback()
            MarkdownDiagnostics().signpostEvent("MathFallback", category: "RenderPreparation")
        }
        return rendered
    }

    private func mathAttributedString(
        _ rendered: AttributedString,
        preservingLinkFrom run: MarkdownInlineRun
    ) -> AttributedString {
        guard run.kind == .link,
              let destination = run.destination,
              let url = markdownLinkURL(for: destination, policy: linkPolicy)
        else {
            return rendered
        }

        var copy = rendered
        copy.link = url
        return copy
    }

    private func preparedImageDisplayRun(
        for run: MarkdownInlineRun,
        image: MarkdownPreparedImage?,
        attachment: MarkdownPreparedAttachment?
    ) -> MarkdownInlineRun {
        guard let image else {
            return run
        }

        var copy = run
        if let attachment {
            // Allowed path (INV-IA2): reserve a box instead of measuring
            // alt text. The placeholder character paints invisibly if a
            // `CTRunDelegate` cannot be attached for some reason; the host
            // (Inline Attachments Part 03) draws the real pixels/chrome.
            copy.text = markdownAttachmentPlaceholderCharacter
            copy.attachmentMetrics = attachment.metrics
        } else {
            // Denied path (INV-IA1/IA4): unchanged alt/`[image: reason]` text.
            copy.text = imageDisplayText(for: image)
        }
        copy.imageSource = nil
        if copy.kind == .image {
            copy.destination = nil
        }
        return copy
    }

    private func imageDisplayText(for image: MarkdownPreparedImage) -> String {
        if let altText = image.altText, !altText.isEmpty {
            return altText
        }

        switch image.preparedSource {
        case let .placeholder(reason):
            return "[image: \(reason)]"
        case let .localFile(path):
            return path
        case .data:
            return "[image]"
        case let .remote(url):
            return url.absoluteString
        }
    }

    private func preparedListItems(_ items: [MarkdownListItem]) -> [MarkdownPreparedListItem] {
        items.map { item in
            let inline = preparedInline(for: item.inlines, sourceRange: item.sourceRange)
            let selectionInline: MarkdownPreparedInlineContent?
            if inline != nil {
                selectionInline = nil
            } else {
                selectionInline = preparedVisibleTextSelectionInline(
                    text: item.text,
                    sourceRange: item.sourceRange
                )
            }
            return MarkdownPreparedListItem(
                id: "list-item:\(item.sourceRange.byteRange.lowerBound):\(item.sourceRange.byteRange.upperBound)",
                sourceRange: item.sourceRange,
                taskState: item.taskState,
                inline: inline?.attributed,
                inlineLayout: inline,
                selectionInlineLayout: selectionInline,
                childListKind: item.childListKind,
                childOrderedListStart: item.childOrderedListStart,
                childItems: preparedListItems(item.childItems)
            )
        }
    }

    private func preparedImages(from decisions: [MarkdownPreparedImageDecision]) -> [MarkdownPreparedImage] {
        decisions.map { imageDecision in
            if let preparedOverride = imageDecision.preparedOverride {
                return preparedOverride
            }
            switch imageDecision.policyDecision {
            case .allow:
                return imageResolver.preparedImage(
                    source: imageDecision.source,
                    altText: imageDecision.run.text.isEmpty ? nil : imageDecision.run.text,
                    sourceRange: imageDecision.run.sourceRange,
                    policyDecision: imageDecision.policyDecision
                )
            case let .deny(reason):
                return MarkdownPreparedImage(
                    source: imageDecision.source,
                    altText: imageDecision.run.text.isEmpty ? nil : imageDecision.run.text,
                    sourceRange: imageDecision.run.sourceRange,
                    preparedSource: .placeholder(reason: reason)
                )
            }
        }
    }

    /// Builds reserved-box attachment records for allowed images (Inline
    /// Attachments Part 01 §1.2.2). Denied images (any policy `.deny`) stay
    /// on the text-atomic path and get `nil` here regardless of what the
    /// resolver would have returned, preserving INV-IA1/IA4 — the resolver
    /// is consulted for `.allow` only, never for `.deny` (see
    /// `preparedImages`).
    private func preparedAttachments(
        from decisions: [MarkdownPreparedImageDecision],
        images: [MarkdownPreparedImage],
        fontSize: Double,
        fontProfiles: MarkdownInlineFontProfiles
    ) -> [MarkdownPreparedAttachment?] {
        zip(decisions, images).enumerated().map { ordinal, pair in
            let (decision, image) = pair
            guard case .allow = decision.policyDecision else {
                return nil
            }

            let id = Self.attachmentID(for: decision.run, ordinal: ordinal)
            let isLinkDecoration = decision.run.presentation.contains(.linkDecoration)
            let metrics: (
                pointWidth: Double,
                pointHeight: Double,
                ascent: Double,
                descent: Double,
                sizingSource: MarkdownAttachmentSizingSource
            )
            let placeholderStyle: MarkdownAttachmentPlaceholderStyle
            if isLinkDecoration {
                let pointSize = linkDecoration.iconPointSize
                metrics = linkDecorationAttachmentMetrics(
                    pointSize: pointSize,
                    fontSize: fontSize,
                    fontProfiles: fontProfiles
                )
                placeholderStyle = MarkdownAttachmentPlaceholderStyle(
                    pointWidth: pointSize,
                    pointHeight: pointSize,
                    cornerRadius: min(4, pointSize / 4),
                    backgroundColor: Color.clear,
                    borderColor: Color.clear
                )
            } else {
                metrics = attachmentBoxMetrics(for: image.preparedSource)
                placeholderStyle = theme.attachmentPlaceholder
            }
            return MarkdownPreparedAttachment(
                id: id,
                image: image,
                pointWidth: metrics.pointWidth,
                pointHeight: metrics.pointHeight,
                ascent: metrics.ascent,
                descent: metrics.descent,
                sizingSource: metrics.sizingSource,
                policyDecision: decision.policyDecision,
                placeholderStyle: placeholderStyle,
                isDecorative: isLinkDecoration
            )
        }
    }

    /// Centers a bitmap favicon on the visual center of the configured
    /// fallback glyph. The fallback is what appears before metadata resolves,
    /// so matching its CoreText image bounds prevents a vertical jump when
    /// a branded image replaces it. These prepared metrics are shared by the
    /// CoreText, UIKit, and AppKit render paths.
    private func linkDecorationAttachmentMetrics(
        pointSize: Double,
        fontSize: Double,
        fontProfiles: MarkdownInlineFontProfiles
    ) -> (
        pointWidth: Double,
        pointHeight: Double,
        ascent: Double,
        descent: Double,
        sizingSource: MarkdownAttachmentSizingSource
    ) {
        let safePointSize = pointSize.isFinite && pointSize > 0 ? pointSize : 18
        let fallbackCenter = Self.linkDecorationFallbackCenterFromBaseline(
            glyph: linkDecoration.fallbackGlyph,
            fontSize: fontSize,
            fontProfile: fontProfiles.profile(for: .linkDecoration, kind: .link)
        ) ?? safePointSize * 0.34
        let boundedCenter = min(max(-safePointSize / 2, fallbackCenter), safePointSize / 2)
        let ascent = safePointSize / 2 + boundedCenter
        let descent = safePointSize - ascent
        return (safePointSize, safePointSize, ascent, descent, .intrinsicHint)
    }

    private nonisolated static func linkDecorationFallbackCenterFromBaseline(
        glyph: String,
        fontSize: Double,
        fontProfile: MarkdownFontProfile
    ) -> Double? {
        #if canImport(CoreText)
        guard !glyph.isEmpty else { return nil }
        let font = MarkdownCoreTextFontBridge.font(
            profile: fontProfile,
            kind: .link,
            presentation: .linkDecoration,
            size: fontSize
        )
        let attributed = NSAttributedString(
            string: glyph,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let imageBounds = CTLineGetImageBounds(line, nil)
        let centerFromBaseline = imageBounds.midY
        guard centerFromBaseline.isFinite,
              imageBounds.height > 0
        else {
            return nil
        }
        return Double(centerFromBaseline)
        #else
        return nil
        #endif
    }

    private nonisolated static func attachmentID(for run: MarkdownInlineRun, ordinal: Int) -> MarkdownAttachmentID {
        guard let sourceRange = run.sourceRange else {
            return MarkdownAttachmentID(rawValue: "attachment:ordinal:\(ordinal)")
        }
        return MarkdownAttachmentID(
            rawValue: "attachment:\(sourceRange.byteRange.lowerBound)-\(sourceRange.byteRange.upperBound)"
        )
    }

    /// Reserved box metrics for one attachment. Prefers a cheap intrinsic
    /// header probe over already-available bytes (no network, no full
    /// pixel decode — INV-IA1/IA3) and falls back to the theme default box
    /// so layout never has to wait on Async/Media before reserving space
    /// (Async INV-AL6 / Part 04 §4.4). Ascent/descent follow the math
    /// image precedent: the box sits entirely above the baseline
    /// (`ascent == pointHeight`, `descent == 0`), matching default inline
    /// image baseline behavior.
    private func attachmentBoxMetrics(
        for source: MarkdownPreparedImageSource
    ) -> (pointWidth: Double, pointHeight: Double, ascent: Double, descent: Double, sizingSource: MarkdownAttachmentSizingSource) {
        let placeholder = theme.attachmentPlaceholder
        if let probed = Self.probedIntrinsicPointSize(for: source, maxWidth: placeholder.renderPointWidth) {
            return (probed.width, probed.height, probed.height, 0, .intrinsicHint)
        }

        return (
            placeholder.renderPointWidth,
            placeholder.renderPointHeight,
            placeholder.renderPointHeight,
            0,
            .themeDefault
        )
    }

    /// Cheap header-only probe (no full pixel decode) of an attachment's
    /// natural pixel size, clamped to `maxWidth` preserving aspect ratio.
    /// Treats probed pixel dimensions as points (no device-scale hint is
    /// available in v1) — an intentional, documented simplification, not a
    /// silent inaccuracy: `sizingSource` is `.intrinsicHint`, not
    /// `.decoded`, precisely because this is an approximation.
    private nonisolated static func probedIntrinsicPointSize(
        for source: MarkdownPreparedImageSource,
        maxWidth: Double
    ) -> (width: Double, height: Double)? {
        #if canImport(ImageIO)
        let natural: (width: Double, height: Double)?
        switch source {
        case let .data(data, _):
            natural = probedImageIOPixelSize(data: data)
        case let .localFile(path):
            natural = probedImageIOPixelSize(fileAtPath: path)
        case .remote, .placeholder:
            natural = nil
        }
        guard let natural, natural.width > 0, natural.height > 0 else {
            return nil
        }
        return clampedAttachmentSize(naturalWidth: natural.width, naturalHeight: natural.height, maxWidth: maxWidth)
        #else
        return nil
        #endif
    }

    #if canImport(ImageIO)
    private nonisolated static func probedImageIOPixelSize(data: Data) -> (width: Double, height: Double)? {
        guard let cgSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return probedImageIOPixelSize(from: cgSource)
    }

    private nonisolated static func probedImageIOPixelSize(fileAtPath path: String) -> (width: Double, height: Double)? {
        guard let cgSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        return probedImageIOPixelSize(from: cgSource)
    }

    private nonisolated static func probedImageIOPixelSize(from cgSource: CGImageSource) -> (width: Double, height: Double)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(cgSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        let widthValue = width.doubleValue
        let heightValue = height.doubleValue
        guard widthValue.isFinite, heightValue.isFinite, widthValue > 0, heightValue > 0 else {
            return nil
        }
        return (widthValue, heightValue)
    }
    #endif

    private nonisolated static func clampedAttachmentSize(
        naturalWidth: Double,
        naturalHeight: Double,
        maxWidth: Double
    ) -> (width: Double, height: Double) {
        guard maxWidth.isFinite, maxWidth > 0, naturalWidth > maxWidth else {
            return (naturalWidth, naturalHeight)
        }
        let scale = maxWidth / naturalWidth
        return (maxWidth, naturalHeight * scale)
    }

    private func preparedTable(
        _ table: MarkdownTableBlock,
        parentID: String,
        isSealed: Bool,
        reusing previousTable: MarkdownPreparedTableBlock?
    ) -> MarkdownPreparedTableBlock {
        var changedCells: [(column: Int, cell: MarkdownPreparedTableCell)] = []
        let headerID = Self.tableRowID(parentID: parentID, role: "header", cells: table.header)
        let canReuseStructuralPrefix = previousTable?.columnAlignments == table.columnAlignments
        let reusesHeader = canReuseStructuralPrefix &&
            previousTable?.headerID == headerID &&
            previousTable?.header.count == table.header.count
        var header: [MarkdownPreparedTableCell]
        if reusesHeader, let previousTable {
            header = previousTable.header
            diagnosticsRecorder.recordTableCellReuse(count: header.count)
        } else {
            header = preparedTableCells(
                table.header,
                rowID: headerID,
                previousCellsByID: [:],
                changedCells: &changedCells
            )
        }

        let reusablePrefixCount = canReuseStructuralPrefix
            ? Self.reusablePreparedTableRowPrefixCount(
                currentRows: table.rows,
                parentID: parentID,
                previousRows: previousTable?.rows ?? []
            )
            : 0
        var rows = previousTable.map {
            Array($0.rows.prefix(reusablePrefixCount))
        } ?? []
        if reusablePrefixCount > 0 {
            // GFM normalizes body rows to the header's column count. Recording
            // this in one operation reflects the historical cells retained by
            // the persistent row values without iterating them again.
            diagnosticsRecorder.recordTableCellReuse(
                count: reusablePrefixCount * max(1, table.columnAlignments.count)
            )
        }
        rows.reserveCapacity(table.rows.count)
        for rowIndex in reusablePrefixCount..<table.rows.count {
            let row = table.rows[rowIndex]
            let rowID = Self.tableRowID(parentID: parentID, role: "body", cells: row)
            let previousCellsByID: [String: MarkdownPreparedTableCell]
            if let previousRows = previousTable?.rows,
               previousRows.indices.contains(rowIndex),
               previousRows[rowIndex].id == rowID
            {
                let previousRow = previousRows[rowIndex]
                previousCellsByID = Dictionary(
                    uniqueKeysWithValues: previousRow.cells.map { ($0.id, $0) }
                )
            } else {
                previousCellsByID = [:]
            }
            rows.append(MarkdownPreparedTableRow(
                id: rowID,
                cells: preparedTableCells(
                    row,
                    rowID: rowID,
                    previousCellsByID: previousCellsByID,
                    changedCells: &changedCells
                )
            ))
        }

        let columnCount = Self.tableColumnCount(
            alignments: table.columnAlignments,
            header: header,
            rows: rows
        )
        let canIncrementWidths = !isSealed &&
            previousTable?.columnNaturalWidths.count == columnCount
        var naturalWidths: [Double]
        if canIncrementWidths, let previousTable {
            naturalWidths = previousTable.columnNaturalWidths
            diagnosticsRecorder.recordTableColumnWidthScan(count: changedCells.count)
            for changed in changedCells where changed.column < naturalWidths.count {
                naturalWidths[changed.column] = max(
                    naturalWidths[changed.column],
                    Self.sanitizedTableNaturalWidth(changed.cell.naturalWidth)
                )
            }
        } else {
            let cellCount = header.count + rows.reduce(0) { $0 + $1.cells.count }
            diagnosticsRecorder.recordTableColumnWidthScan(count: cellCount)
            naturalWidths = tableNaturalWidths(
                columnCount: columnCount,
                header: header,
                rows: rows
            )
        }

        let previousWidths = canIncrementWidths ? previousTable?.columnWidths : nil
        let columnWidths = tableEffectiveColumnWidths(
            naturalWidths: naturalWidths,
            columnCount: columnCount,
            isSealed: isSealed,
            previousWidths: previousWidths
        )
        let widthsChanged = previousTable.map {
            !Self.tableWidthsEqual($0.columnWidths, columnWidths)
        } ?? false
        if widthsChanged {
            diagnosticsRecorder.recordTableColumnWidthChange()
        }
        let widthRevision = widthsChanged
            ? (previousTable?.columnWidthRevision ?? 0) &+ 1
            : (previousTable?.columnWidthRevision ?? 0)

        // A table cell's prepared inline leaf is initially seeded with the
        // session-wide container width. The actual cell width is narrower and
        // known here. Resolve a minimum row height from that width before
        // SwiftUI measures or caches the row, otherwise a late width
        // preference can add a line after the shorter row height is already
        // cached and the text will paint into (or be covered by) the next row.
        let canReusePreparedHeights = previousTable?.hasPreparedLayoutHeights == true &&
            !widthsChanged
        let headerPreparedLayoutHeight: Double
        if canReusePreparedHeights,
           reusesHeader,
           let previousHeight = previousTable?.headerPreparedLayoutHeight
        {
            headerPreparedLayoutHeight = previousHeight
        } else {
            headerPreparedLayoutHeight = resolvePreparedTableRowLayout(
                cells: &header,
                columnWidths: columnWidths
            )
        }

        let heightResolutionStart = canReusePreparedHeights ? reusablePrefixCount : 0
        if heightResolutionStart < rows.count {
            for rowIndex in heightResolutionStart..<rows.count {
                if canReusePreparedHeights,
                   let previousRows = previousTable?.rows,
                   previousRows.indices.contains(rowIndex),
                   previousRows[rowIndex].id == rows[rowIndex].id,
                   previousRows[rowIndex].contentFingerprint == rows[rowIndex].contentFingerprint,
                   let previousHeight = previousRows[rowIndex].preparedLayoutHeight
                {
                    rows[rowIndex].preparedLayoutHeight = previousHeight
                } else {
                    rows[rowIndex].preparedLayoutHeight = resolvePreparedTableRowLayout(
                        cells: &rows[rowIndex].cells,
                        columnWidths: columnWidths
                    )
                }
            }
        }

        var preparedTable = MarkdownPreparedTableBlock(
            columnAlignments: table.columnAlignments,
            header: header,
            rows: rows,
            headerID: headerID,
            columnNaturalWidths: naturalWidths,
            columnWidths: columnWidths,
            columnWidthRevision: widthRevision
        )
        preparedTable.headerPreparedLayoutHeight = headerPreparedLayoutHeight
        preparedTable.hasPreparedLayoutHeights = true
        return preparedTable
    }

    /// Resolves each table leaf at its exact prepared content width and stores
    /// that result back into the prepared inline value. Default table cells
    /// therefore enter SwiftUI with the correct line ranges and Core Text plan
    /// instead of mounting a GeometryReader/preference loop per cell merely
    /// to rediscover a width the preparation pipeline already knew.
    private func resolvePreparedTableRowLayout(
        cells: inout [MarkdownPreparedTableCell],
        columnWidths: [Double]
    ) -> Double {
        let horizontalPadding = Double(theme.renderTableHorizontalCellPadding)
        let verticalPadding = Double(theme.renderTableVerticalCellPadding)
        var tallestContent = 0.0

        for column in columnWidths.indices {
            guard cells.indices.contains(column),
                  var inline = cells[column].inlineLayout ?? cells[column].selectionInlineLayout
            else {
                continue
            }
            let contentWidth = max(1, columnWidths[column] - horizontalPadding * 2)
            let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
                for: inline,
                containerWidth: contentWidth
            )
            let layout = inline.layout(
                containerWidth: layoutWidth,
                allowsOverwideFallback: true
            )
            inline.initialLayoutResult = layout
            inline.defaultLayoutWidth = contentWidth
            #if canImport(CoreText)
            inline.coreTextLinePlan = layout.lines.isEmpty
                ? nil
                : MarkdownCoreTextPaintedLinePlan.make(prepared: inline, layout: layout)
            #endif
            if cells[column].inlineLayout != nil {
                cells[column].inlineLayout = inline
            } else {
                cells[column].selectionInlineLayout = inline
            }

            let lineCount = max(1, layout.lines.count)
            let lineSpacing = Double(InlineRunsView.nativeLineSpacing(for: inline))
            let contentHeight = Double(lineCount) * inline.lineHeight +
                Double(max(0, lineCount - 1)) * lineSpacing
            tallestContent = max(tallestContent, contentHeight)
        }

        return max(38, tallestContent + verticalPadding * 2)
    }

    private func preparedTableCells(
        _ cells: [MarkdownTableCell],
        rowID: String,
        previousCellsByID: [String: MarkdownPreparedTableCell],
        changedCells: inout [(column: Int, cell: MarkdownPreparedTableCell)]
    ) -> [MarkdownPreparedTableCell] {
        cells.enumerated().map { column, cell in
            diagnosticsRecorder.recordTableCellIncrementalComparison()
            let id = Self.tableCellID(rowID: rowID, column: column, cell: cell)
            let contentHash = Self.tableCellContentHash(cell)
            if let previous = previousCellsByID[id],
               previous.sourceRange == cell.sourceRange,
               previous.contentHash == contentHash,
               previous.colspan == cell.colspan,
               previous.rowspan == cell.rowspan
            {
                diagnosticsRecorder.recordTableCellReuse()
                return previous
            }

            let prepared = preparedTableCell(cell, id: id, contentHash: contentHash)
            changedCells.append((column: column, cell: prepared))
            return prepared
        }
    }

    private func preparedTableCell(
        _ cell: MarkdownTableCell,
        id: String,
        contentHash: UInt64
    ) -> MarkdownPreparedTableCell {
        diagnosticsRecorder.recordTableCellPreparation()
        let inline = preparedInline(for: cell.inlines, sourceRange: cell.sourceRange)
        let selectionInline: MarkdownPreparedInlineContent?
        if inline != nil {
            selectionInline = nil
        } else {
            selectionInline = preparedVisibleTextSelectionInline(
                text: cell.text,
                sourceRange: cell.sourceRange
            )
        }
        return MarkdownPreparedTableCell(
            id: id,
            sourceRange: cell.sourceRange,
            contentHash: contentHash,
            inline: inline?.attributed,
            inlineLayout: inline,
            selectionInlineLayout: selectionInline,
            naturalWidth: inline?.measured.naturalWidth ??
                selectionInline?.measured.naturalWidth ??
                Double(cell.text.count) *
                Self.sanitizedPositive(theme.paragraphFontSize, fallback: 16) * 0.56,
            colspan: cell.colspan,
            rowspan: cell.rowspan
        )
    }

    private nonisolated static func tableRowID(
        parentID: String,
        role: String,
        cells: [MarkdownTableCell]
    ) -> String {
        let sourceStart = cells.first?.sourceRange.byteRange.lowerBound ?? 0
        // Preserve the package's established `table-cell:` render-ID family
        // while dropping the mutable source upper bound that previously made
        // a growing row/cell look new on every append.
        return "table-cell:\(parentID):\(role):\(sourceStart)"
    }

    private nonisolated static func reusablePreparedTableRowPrefixCount(
        currentRows: [[MarkdownTableCell]],
        parentID: String,
        previousRows: [MarkdownPreparedTableRow]
    ) -> Int {
        // The semantic parser owns the complete table model, but the stream
        // contract is append-only and only its final row can still grow. Keep
        // that row mutable; every earlier row is a sealed subregion of the
        // table even though the enclosing Markdown block remains the tail.
        let count = min(max(0, previousRows.count - 1), currentRows.count)
        guard count > 0 else { return 0 }
        let firstID = tableRowID(parentID: parentID, role: "body", cells: currentRows[0])
        let lastID = tableRowID(
            parentID: parentID,
            role: "body",
            cells: currentRows[count - 1]
        )
        guard previousRows[0].id == firstID,
              previousRows[count - 1].id == lastID
        else {
            return 0
        }
        return count
    }

    private nonisolated static func tableCellID(
        rowID: String,
        column: Int,
        cell: MarkdownTableCell
    ) -> String {
        "\(rowID):cell:\(column):\(cell.sourceRange.byteRange.lowerBound)"
    }

    private nonisolated static func tableCellContentHash(_ cell: MarkdownTableCell) -> UInt64 {
        guard cell.contentHash == 0 else {
            return cell.contentHash
        }
        let inlineHash = inlineHash(cell.inlines)
        return appendField("table-cell-text", value: cell.text, to: inlineHash)
    }

    private nonisolated static func tableColumnCount(
        alignments: [MarkdownTableColumnAlignment?],
        header: [MarkdownPreparedTableCell],
        rows: [MarkdownPreparedTableRow]
    ) -> Int {
        max(
            max(alignments.count, header.count),
            rows.map { $0.cells.count }.max() ?? 0
        )
    }

    private func tableNaturalWidths(
        columnCount: Int,
        header: [MarkdownPreparedTableCell],
        rows: [MarkdownPreparedTableRow]
    ) -> [Double] {
        guard columnCount > 0 else { return [] }
        var widths = Array(repeating: 0.0, count: columnCount)
        for cell in header.enumerated() where cell.offset < columnCount {
            widths[cell.offset] = max(
                widths[cell.offset],
                Self.sanitizedTableNaturalWidth(cell.element.naturalWidth)
            )
        }
        for row in rows {
            for cell in row.cells.enumerated() where cell.offset < columnCount {
                widths[cell.offset] = max(
                    widths[cell.offset],
                    Self.sanitizedTableNaturalWidth(cell.element.naturalWidth)
                )
            }
        }
        return widths
    }

    private func tableEffectiveColumnWidths(
        naturalWidths: [Double],
        columnCount: Int,
        isSealed: Bool,
        previousWidths: [Double]?
    ) -> [Double] {
        guard columnCount > 0 else { return [] }
        let minimum = columnCount > 3 ? 112.0 : 132.0
        let maximum = columnCount <= 2 ? 520.0 : 360.0
        let quantizationStep = 64.0

        return (0..<columnCount).map { column in
            let natural = naturalWidths.indices.contains(column) ? naturalWidths[column] : 0
            let exact = min(
                max(natural + (theme.renderTableHorizontalCellPadding * 2) + 18, minimum),
                maximum
            )
            guard !isSealed else { return exact }
            let bucket = min(
                minimum + ceil(max(0, exact - minimum) / quantizationStep) * quantizationStep,
                maximum
            )
            let previous = previousWidths.flatMap { widths in
                widths.indices.contains(column) ? widths[column] : nil
            } ?? minimum
            return max(bucket, previous)
        }
    }

    private nonisolated static func sanitizedTableNaturalWidth(_ width: Double) -> Double {
        width.isFinite && width > 0 ? width : 0
    }

    private nonisolated static func tableWidthsEqual(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { pair in
            abs(pair.0 - pair.1) < 0.25
        }
    }

    private func inlineMetrics(
        for block: MarkdownBlock?
    ) -> (fontSize: Double, lineHeight: Double, fontProfiles: MarkdownInlineFontProfiles) {
        guard let block else {
            return Self.sanitizedInlineMetrics(
                fontSize: theme.paragraphFontSize,
                lineHeight: theme.paragraphLineHeight,
                fontProfiles: theme.paragraphFontProfiles,
                fallbackFontSize: 16,
                fallbackLineHeight: 22
            )
        }

        switch block.kind {
        case .heading:
            let style = theme.headingStyle(for: block.headingLevel)
            return Self.sanitizedInlineMetrics(
                fontSize: style.fontSize,
                lineHeight: style.lineHeight,
                fontProfiles: style.fontProfiles,
                fallbackFontSize: 20,
                fallbackLineHeight: 28
            )
        case .codeBlock, .htmlBlock, .mathBlock:
            return Self.sanitizedInlineMetrics(
                fontSize: theme.codeFontSize,
                lineHeight: theme.codeLineHeight,
                fontProfiles: theme.codeFontProfiles,
                fallbackFontSize: 14,
                fallbackLineHeight: 20
            )
        default:
            return Self.sanitizedInlineMetrics(
                fontSize: theme.paragraphFontSize,
                lineHeight: theme.paragraphLineHeight,
                fontProfiles: theme.paragraphFontProfiles,
                fallbackFontSize: 16,
                fallbackLineHeight: 22
            )
        }
    }

    private nonisolated static func sanitizedInlineMetrics(
        fontSize: Double,
        lineHeight: Double,
        fontProfiles: MarkdownInlineFontProfiles,
        fallbackFontSize: Double,
        fallbackLineHeight: Double
    ) -> (fontSize: Double, lineHeight: Double, fontProfiles: MarkdownInlineFontProfiles) {
        let safeFontSize = Self.sanitizedPositive(fontSize, fallback: fallbackFontSize)
        let safeLineHeight = Self.sanitizedPositive(lineHeight, fallback: max(fallbackLineHeight, safeFontSize))
        return (safeFontSize, safeLineHeight, fontProfiles)
    }

    private nonisolated static func sanitizedPositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private nonisolated static func inlineHash(_ runs: [MarkdownInlineRun]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for run in runs {
            hash = appendField("run", value: "start", to: hash)
            hash = appendField("kind", value: run.kind.rawValue, to: hash)
            hash = appendField("presentation", value: String(run.presentation.rawValue), to: hash)
            hash = appendField("text", value: run.text, to: hash)
            hash = appendOptionalField("destination", value: run.destination, to: hash)
            hash = appendOptionalField("imageSource", value: run.imageSource, to: hash)
            hash = appendAttachmentMetrics(run.attachmentMetrics, to: hash)
            if let sourceRange = run.sourceRange {
                hash = appendField("source.present", value: "1", to: hash)
                hash = appendField("source.byte.lower", value: String(sourceRange.byteRange.lowerBound), to: hash)
                hash = appendField("source.byte.upper", value: String(sourceRange.byteRange.upperBound), to: hash)
                hash = appendField("source.line.lower", value: String(sourceRange.lineRange.lowerBound), to: hash)
                hash = appendField("source.line.upper", value: String(sourceRange.lineRange.upperBound), to: hash)
            } else {
                hash = appendField("source.present", value: "0", to: hash)
            }
        }
        return hash
    }

    private nonisolated static func appendAttachmentMetrics(
        _ metrics: MarkdownInlineAttachmentMetrics?,
        to initialHash: UInt64
    ) -> UInt64 {
        var hash = appendField("attachment.present", value: metrics == nil ? "0" : "1", to: initialHash)
        guard let metrics else {
            return hash
        }

        hash = appendField("attachment.id", value: metrics.id.rawValue, to: hash)
        hash = appendDoubleField("attachment.pointWidth", value: metrics.pointWidth, to: hash)
        hash = appendDoubleField("attachment.pointHeight", value: metrics.pointHeight, to: hash)
        hash = appendDoubleField("attachment.ascent", value: metrics.ascent, to: hash)
        hash = appendDoubleField("attachment.descent", value: metrics.descent, to: hash)
        hash = appendField("attachment.sizingSource", value: attachmentSizingSourceKey(metrics.sizingSource), to: hash)
        return hash
    }

    private nonisolated static func appendDoubleField(_ name: String, value: Double, to initialHash: UInt64) -> UInt64 {
        appendField(name, value: String(value.bitPattern), to: initialHash)
    }

    private nonisolated static func attachmentSizingSourceKey(_ sizingSource: MarkdownAttachmentSizingSource) -> String {
        switch sizingSource {
        case .themeDefault:
            return "themeDefault"
        case .aspectPlaceholder:
            return "aspectPlaceholder"
        case .intrinsicHint:
            return "intrinsicHint"
        case .decoded:
            return "decoded"
        }
    }

    private nonisolated static func stableHash(_ text: String) -> UInt64 {
        append(text, to: 0xcbf29ce484222325)
    }

    private nonisolated static func append(_ text: String, to initialHash: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        hash = initialHash
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private nonisolated static func appendOptionalField(_ name: String, value: String?, to initialHash: UInt64) -> UInt64 {
        var hash = appendField("\(name).present", value: value == nil ? "0" : "1", to: initialHash)
        if let value {
            hash = appendField("\(name).value", value: value, to: hash)
        }
        return hash
    }

    private nonisolated static func appendField(_ name: String, value: String, to initialHash: UInt64) -> UInt64 {
        var hash = append(name, to: initialHash)
        hash = append("#\(value.utf8.count):", to: hash)
        hash = append(value, to: hash)
        hash = append("|", to: hash)
        return hash
    }
}

private struct MarkdownDecoratedLinkRuns {
    var runs: [MarkdownInlineRun]
    var preparedImagesBySource: [String: MarkdownPreparedImage]
}

private struct MarkdownPreparedImageDecision {
    var run: MarkdownInlineRun
    var source: String
    var policyDecision: MarkdownPolicyDecision
    var preparedOverride: MarkdownPreparedImage?
}

private struct MarkdownPreparedMathDecision {
    var run: MarkdownInlineRun
    var policyDecision: MarkdownPolicyDecision
}

private struct MarkdownPreparedSnapshotReuse {
    private var contentsByBlockID: [MarkdownBlockID: [(block: MarkdownBlock, content: MarkdownPreparedBlockContent)]]

    init(previousItems: ArraySlice<MarkdownPreparedSnapshotItem>) {
        var contentsByBlockID: [MarkdownBlockID: [(block: MarkdownBlock, content: MarkdownPreparedBlockContent)]] = [:]
        for item in previousItems {
            guard case let .block(block, content) = item else {
                continue
            }
            contentsByBlockID[block.id, default: []].append((block, content))
        }
        self.contentsByBlockID = contentsByBlockID
    }

    mutating func content(for block: MarkdownBlock) -> MarkdownPreparedBlockContent? {
        guard var candidates = contentsByBlockID[block.id],
              let index = candidates.firstIndex(where: {
                  MarkdownRendererConfiguration.renderPreparationEquivalent($0.block, block) &&
                      !MarkdownRendererConfiguration.tableNeedsSealPreparation(block, $0.block)
              })
        else {
            return nil
        }

        let match = candidates.remove(at: index)
        if candidates.isEmpty {
            contentsByBlockID.removeValue(forKey: block.id)
        } else {
            contentsByBlockID[block.id] = candidates
        }
        return match.content
    }
}

public struct MarkdownPreparedInlineContent: Sendable {
    public var attributed: AttributedString
    public var prepared: PreparedInlineContent {
        didSet {
            hasScriptTypography = Self.containsScriptTypography(prepared)
            refreshCacheFingerprint()
        }
    }
    public var measured: MeasuredInlineContent {
        didSet { refreshCacheFingerprint() }
    }
    public var images: [MarkdownPreparedImage]
    /// Reserved-box attachment records for allowed images, keyed by the
    /// stable `MarkdownAttachmentID` prepare assigned to their display run
    /// (Inline Attachments Part 01). Empty on the denied text-atomic path.
    public var attachments: [MarkdownAttachmentID: MarkdownPreparedAttachment]
    public var fontSize: Double {
        didSet { refreshTypographyMetricsAndCacheFingerprint() }
    }
    public var lineHeight: Double {
        didSet { refreshTypographyMetricsAndCacheFingerprint() }
    }
    public var fontProfiles: MarkdownInlineFontProfiles {
        didSet { refreshTypographyMetricsAndCacheFingerprint() }
    }
    var typographyMetrics = MarkdownPreparedTypographyMetrics(
        profile: .system(),
        fontSize: 14,
        lineHeight: 14
    )
    /// Prepared once with the inline model so the common AppKit text-leaf
    /// path can skip script-range inspection entirely.
    var hasScriptTypography: Bool
    /// Constant-size identity for every prepared/measured/font input used by
    /// view invalidation, inline layout, and source-backed selection caches.
    /// This replaces hashing full strings/runs/units/line arrays from SwiftUI
    /// layout evaluation.
    public private(set) var cacheFingerprint = MarkdownContentFingerprint(
        domain: "markdown-prepared-inline-empty"
    )
    public var layoutCache: MarkdownInlineLayoutCache
    /// When non-nil, this inline content contains typeset math and should be
    /// rendered with native `Text` composition instead of prepared CoreText lines.
    public var mathTextPieces: [MarkdownInlineMathPiece]?
    /// Pre-computed layout at `defaultLayoutWidth` so the first render shows
    /// content immediately without waiting for the width preference (INV-P2).
    public var initialLayoutResult: InlineLayoutResult?
    /// The container width used to compute `initialLayoutResult`.
    public var defaultLayoutWidth: Double
    /// Pre-built CTLine plan from `initialLayoutResult` so the representable
    /// assigns without creating CTLine objects in SwiftUI update (INV-P1).
    #if canImport(CoreText)
    var coreTextLinePlan: MarkdownCoreTextPaintedLinePlan?
    #endif
    /// The session's shared preparation cache, used to report the real
    /// on-screen container width back so later-prepared blocks in the same
    /// session pick up a `defaultLayoutWidth` that actually matches the
    /// rendering context (INV-P1, INV-P2). Not part of value equality —
    /// it is wiring, not content.
    var preparationCache: MarkdownRenderPreparationCache? = nil

    public init(
        attributed: AttributedString,
        prepared: PreparedInlineContent,
        measured: MeasuredInlineContent,
        images: [MarkdownPreparedImage] = [],
        attachments: [MarkdownAttachmentID: MarkdownPreparedAttachment] = [:],
        fontSize: Double,
        lineHeight: Double,
        fontProfiles: MarkdownInlineFontProfiles = .paragraphDefault,
        layoutCache: MarkdownInlineLayoutCache = MarkdownInlineLayoutCache(),
        mathTextPieces: [MarkdownInlineMathPiece]? = nil,
        initialLayoutResult: InlineLayoutResult? = nil,
        defaultLayoutWidth: Double = InlineRunsView.defaultLayoutWidth
    ) {
        let safeFontSize = Self.sanitizedPositive(fontSize, fallback: 14)
        let safeLineHeight = Self.sanitizedPositive(lineHeight, fallback: safeFontSize)
        self.attributed = attributed
        self.prepared = prepared
        self.hasScriptTypography = Self.containsScriptTypography(prepared)
        self.measured = Self.sanitizedMeasured(measured, fontSize: safeFontSize)
        self.images = images
        self.attachments = attachments
        self.fontSize = safeFontSize
        self.lineHeight = safeLineHeight
        self.fontProfiles = fontProfiles
        self.layoutCache = layoutCache
        self.mathTextPieces = mathTextPieces
        self.initialLayoutResult = initialLayoutResult
        self.defaultLayoutWidth = defaultLayoutWidth
        refreshTypographyMetrics()
        refreshCacheFingerprint()
    }

    private mutating func refreshTypographyMetricsAndCacheFingerprint() {
        refreshTypographyMetrics()
        refreshCacheFingerprint()
    }

    private mutating func refreshTypographyMetrics() {
        typographyMetrics = MarkdownPreparedTypographyMetrics(
            profile: fontProfiles.body,
            fontSize: fontSize,
            lineHeight: lineHeight
        )
    }

    private mutating func refreshCacheFingerprint() {
        var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-inline-v1")
        fingerprint.combine(prepared.cacheFingerprint)
        fingerprint.combine(measured.cacheFingerprint)
        fingerprint.combine(fontSize)
        fingerprint.combine(lineHeight)
        fingerprint.combine(fontProfiles.cacheKey)
        cacheFingerprint = fingerprint
    }

    private static func sanitizedPositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func containsScriptTypography(_ prepared: PreparedInlineContent) -> Bool {
        prepared.runs.contains { run in
            run.presentation.contains(.subscriptText) ||
                run.presentation.contains(.superscriptText)
        }
    }

    private static func sanitizedNonNegative(_ value: Double) -> Double {
        value.isFinite && value >= 0 ? value : 0
    }

    private static func sanitizedMeasured(
        _ measured: MeasuredInlineContent,
        fontSize: Double
    ) -> MeasuredInlineContent {
        let segments = measured.segments.map { measuredSegment in
            MeasuredInlineSegment(
                segment: measuredSegment.segment,
                width: sanitizedNonNegative(measuredSegment.width),
                units: measuredSegment.units.map { unit in
                    MeasuredInlineUnit(
                        byteRange: unit.byteRange,
                        width: sanitizedNonNegative(unit.width),
                        startsPreferredBreakUnit: unit.startsPreferredBreakUnit
                    )
                }
            )
        }
        return MeasuredInlineContent(
            prepared: measured.prepared,
            segments: segments,
            naturalWidth: sanitizedNonNegative(measured.naturalWidth),
            fontSize: fontSize
        )
    }

    public func layout(
        containerWidth: Double,
        allowsOverwideFallback: Bool = true
    ) -> InlineLayoutResult {
        layout(
            options: InlineLayoutOptions(
                containerWidth: containerWidth,
                fontSize: fontSize,
                lineHeight: lineHeight
            ),
            allowsOverwideFallback: allowsOverwideFallback
        )
    }

    public func layout(
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = true
    ) -> InlineLayoutResult {
        layoutCache.layout(
            measured,
            options: options,
            allowsOverwideFallback: allowsOverwideFallback
        )
    }
}

extension MarkdownPreparedInlineContent {
    /// A prepared leaf can omit the conventional underline only when every
    /// semantic link in that leaf has a package-owned non-color decoration.
    /// Mixed leaves (for example, one decorated HTTPS link plus an undecorated
    /// `mailto:` link) keep underlines rather than making that destination
    /// color-only.
    var allSemanticLinksHaveDecorations: Bool {
        var semanticDestinations: Set<String> = []
        var decoratedDestinations: Set<String> = []

        for run in prepared.runs {
            guard let destination = run.destination else { continue }
            if run.presentation.contains(.linkDecoration) {
                decoratedDestinations.insert(destination)
            } else if run.kind == .link {
                semanticDestinations.insert(destination)
            }
        }

        return !semanticDestinations.isEmpty &&
            semanticDestinations.isSubset(of: decoratedDestinations)
    }
}

public final class MarkdownInlineLayoutCache: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: InlineLayoutEngine<CoreTextInlineMeasurer>
    private var selectionLineFragmentCache: BoundedMarkdownCache<[MarkdownDocumentSelectionLineFragmentTemplate]>
    /// Caches the final, rect-mapped fragment array — as opposed to
    /// `selectionLineFragmentCache`, which caches rect-independent templates.
    /// A single content change during streaming can trigger several AppKit/
    /// SwiftUI layout-settle passes that re-query the same (content, layout,
    /// rect) repeatedly before geometry stabilizes; this cache turns those
    /// repeats into an O(1) lookup instead of re-mapping every template to
    /// an absolute rect on every pass (Streaming Performance Part 04).
    private var fragmentArrayCache: BoundedMarkdownCache<[MarkdownDocumentSelectionFragment]>

    public init(
        measurer: CoreTextInlineMeasurer = CoreTextInlineMeasurer(),
        cacheCapacity: Int = 256,
        diagnosticsRecorder: MarkdownDiagnosticsRecorder = MarkdownDiagnosticsRecorder()
    ) {
        self.engine = InlineLayoutEngine(
            measurer: measurer,
            cacheCapacity: cacheCapacity,
            diagnosticsRecorder: diagnosticsRecorder
        )
        self.selectionLineFragmentCache = BoundedMarkdownCache(capacity: cacheCapacity)
        self.fragmentArrayCache = BoundedMarkdownCache(capacity: cacheCapacity)
    }

    public var diagnosticsCounters: MarkdownDiagnosticsCounters {
        lock.withLock {
            engine.diagnosticsCounters
        }
    }

    public func layout(
        _ measured: MeasuredInlineContent,
        options: InlineLayoutOptions,
        allowsOverwideFallback: Bool = true
    ) -> InlineLayoutResult {
        lock.withLock {
            engine.layout(
                measured,
                options: options,
                allowsOverwideFallback: allowsOverwideFallback
            )
        }
    }

    public func recordNonFiniteInlineProposalFallback() {
        lock.withLock {
            engine.diagnosticsRecorder.recordNonFiniteInlineProposalFallback()
        }
    }

    public func recordNativeLineClipping() {
        lock.withLock {
            engine.diagnosticsRecorder.recordNativeLineClipping()
        }
    }

    func recordCoreTextLinePlanRebuiltInBody() {
        lock.withLock {
            engine.diagnosticsRecorder.recordCoreTextLinePlanRebuiltInBody()
        }
    }

    func recordSelectionPreferenceBodyEvaluation() {
        lock.withLock {
            engine.diagnosticsRecorder.recordSelectionPreferenceBodyEvaluation()
        }
    }

    func recordSelectionFrameQuery() {
        lock.withLock {
            engine.diagnosticsRecorder.recordSelectionFrameQuery()
        }
    }

    func selectionLineFragmentTemplates(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        idPrefix: String
    ) -> [MarkdownDocumentSelectionLineFragmentTemplate] {
        let key = selectionLineFragmentCacheKey(
            blockID: blockID,
            prepared: prepared,
            layout: layout,
            idPrefix: idPrefix
        )
        return lock.withLock {
            if let cached = selectionLineFragmentCache.value(forKey: key) {
                engine.diagnosticsRecorder.recordSelectionLineFragmentCacheHit()
                return cached
            }

            engine.diagnosticsRecorder.recordSelectionLineFragmentCacheMiss()
            let templates = MarkdownDocumentSelectionFragment.makeInlineLineFragmentTemplates(
                blockID: blockID,
                prepared: prepared,
                layout: layout,
                idPrefix: idPrefix,
                diagnosticsRecorder: engine.diagnosticsRecorder
            )
            if !templates.isEmpty {
                selectionLineFragmentCache[key] = templates
            }
            return templates
        }
    }

    /// Returns the final, rect-mapped selection fragment array for
    /// `(blockID, prepared, layout, rect, idPrefix)`, reusing a cached array
    /// when an identical query was already resolved (INV-P4). Falls back to
    /// the (already-cached) line fragment templates on a miss.
    func cachedInlineLineFragments(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        rect: CGRect,
        idPrefix: String
    ) -> [MarkdownDocumentSelectionFragment] {
        let key = fragmentArrayCacheKey(
            blockID: blockID,
            prepared: prepared,
            layout: layout,
            rect: rect,
            idPrefix: idPrefix
        )
        if let cached = lock.withLock({ fragmentArrayCache.value(forKey: key) }) {
            engine.diagnosticsRecorder.recordSelectionFragmentArrayCacheHit()
            return cached
        }
        engine.diagnosticsRecorder.recordSelectionFragmentArrayCacheMiss()

        let lineHeight = CGFloat(prepared.lineHeight)
        let spacing = InlineRunsView.nativeLineSpacing(for: prepared)
        let templates = selectionLineFragmentTemplates(
            blockID: blockID,
            prepared: prepared,
            layout: layout,
            idPrefix: idPrefix
        )
        let fragments = templates.map { template in
            template.fragment(in: rect, lineHeight: lineHeight, spacing: spacing)
        }

        if !fragments.isEmpty {
            lock.withLock {
                fragmentArrayCache[key] = fragments
            }
        }
        return fragments
    }

    private func fragmentArrayCacheKey(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        rect: CGRect,
        idPrefix: String
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "selection-fragment-array-v2")
        fingerprint.combine(blockID.rawValue)
        fingerprint.combine(idPrefix)
        fingerprint.combine(prepared.cacheFingerprint)
        fingerprint.combine(layout.cacheFingerprint)
        // Round to the nearest half-point so repeated queries during a
        // layout-settle burst (which can differ by sub-point rounding
        // noise across passes) still hit the cache, matching the existing
        // 0.5pt tolerance `sortedForSelection()` already uses for fragment
        // ordering.
        fingerprint.combine(Self.roundedForFingerprint(rect.origin.x))
        fingerprint.combine(Self.roundedForFingerprint(rect.origin.y))
        fingerprint.combine(Self.roundedForFingerprint(rect.width))
        fingerprint.combine(Self.roundedForFingerprint(rect.height))
        let sourceRange = prepared.prepared.sourceRange ?? MarkdownSourceRange(
            byteRange: 0..<prepared.prepared.naturalTextUTF8Count,
            lineRange: 0..<0
        )
        return MarkdownCacheKey(
            sourceRange: sourceRange,
            contentFingerprint: fingerprint,
            namespace: "selection-fragment-array"
        )
    }

    private static func roundedForFingerprint(_ value: CGFloat) -> Double {
        guard value.isFinite else {
            return 0
        }
        return (Double(value) * 2).rounded() / 2
    }

    private func selectionLineFragmentCacheKey(
        blockID: MarkdownBlockID,
        prepared: MarkdownPreparedInlineContent,
        layout: InlineLayoutResult,
        idPrefix: String
    ) -> MarkdownCacheKey {
        var fingerprint = MarkdownContentFingerprint(domain: "selection-line-fragments-v2")
        fingerprint.combine(blockID.rawValue)
        fingerprint.combine(idPrefix)
        fingerprint.combine(prepared.cacheFingerprint)
        fingerprint.combine(layout.cacheFingerprint)
        let sourceRange = prepared.prepared.sourceRange ?? MarkdownSourceRange(
            byteRange: 0..<prepared.prepared.naturalTextUTF8Count,
            lineRange: 0..<0
        )
        return MarkdownCacheKey(
            sourceRange: sourceRange,
            contentFingerprint: fingerprint,
            namespace: "selection-line-fragments"
        )
    }
}

private struct MarkdownStreamingCodeHighlightState: Sendable {
    var blockID: MarkdownBlockID
    var contextIdentity: String
    var backendStateID: String?
    var code: String
    var highlighted: AttributedString
    var fullHighlightByteCount: Int
}

public final class MarkdownRenderPreparationCache: @unchecked Sendable {
    private let lock = NSLock()
    let coreTextMeasurementCache: MarkdownCoreTextMeasurementCache
    private var inlineCache: BoundedMarkdownCache<MarkdownPreparedInlineContent>
    private var codeCache: BoundedMarkdownCache<AttributedString>
    private var mermaidCache: BoundedMarkdownCache<MarkdownPreparedMermaidDiagram>
    private var mathCache: BoundedMarkdownCache<MarkdownPreparedMath>
    private var activeStreamingCodeHighlight: MarkdownStreamingCodeHighlightState?
    private var tableRowSizes: [MarkdownStreamingTableRowLayoutToken: CGSize] = [:]
    private var tableRowTokenByID: [String: MarkdownStreamingTableRowLayoutToken] = [:]
    private var tableRowIDOrder: [String] = []
    private let tableRowSizeCapacity: Int
    private let streamingCodeHighlightNamespace = UUID().uuidString
    /// The most recent real container width reported by any prepared inline
    /// text view in this session, used to seed `defaultLayoutWidth` for
    /// newly prepared blocks so their pre-built initial layout / `CTLine`
    /// plan (INV-P1, INV-P2) actually matches the real rendering width
    /// instead of a fixed constant most layouts never hit.
    private var lastKnownContainerWidth: Double?

    public init(capacity: Int = 256) {
        self.tableRowSizeCapacity = max(256, capacity * 16)
        self.coreTextMeasurementCache = MarkdownCoreTextMeasurementCache(
            widthCapacity: max(4_096, capacity * 64)
        )
        self.inlineCache = BoundedMarkdownCache(capacity: capacity)
        self.codeCache = BoundedMarkdownCache(capacity: capacity)
        self.mermaidCache = BoundedMarkdownCache(capacity: capacity)
        self.mathCache = BoundedMarkdownCache(capacity: capacity)
    }

    /// Records a real, on-screen container width observed by a prepared
    /// inline text view. Subsequent `prepare(block:)` calls in this session
    /// use this as the width for pre-computing initial layout, so
    /// newly-streamed blocks are prepared at the width they will actually
    /// render at rather than a disconnected default (Streaming Performance
    /// Part 01/02, INV-P1, INV-P2).
    public func recordActualContainerWidth(_ width: Double) {
        guard width.isFinite, width > 0 else {
            return
        }
        lock.withLock {
            lastKnownContainerWidth = width
        }
    }

    /// The width to use when pre-computing initial layout for a newly
    /// prepared block: the last real width observed in this session, or
    /// `InlineRunsView.defaultLayoutWidth` before any real width is known
    /// (e.g. the very first block in a session).
    public var currentDefaultLayoutWidth: Double {
        lock.withLock {
            lastKnownContainerWidth ?? InlineRunsView.defaultLayoutWidth
        }
    }

    public func inline(forKey key: MarkdownCacheKey) -> MarkdownPreparedInlineContent? {
        lock.withLock {
            inlineCache.value(forKey: key)
        }
    }

    public func insertInline(_ inline: MarkdownPreparedInlineContent, forKey key: MarkdownCacheKey) {
        lock.withLock {
            inlineCache[key] = inline
        }
    }

    func tableRowSize(for token: MarkdownStreamingTableRowLayoutToken) -> CGSize? {
        lock.withLock {
            tableRowSizes[token]
        }
    }

    func storeTableRowSize(
        _ size: CGSize,
        for token: MarkdownStreamingTableRowLayoutToken
    ) {
        lock.withLock {
            if let previous = tableRowTokenByID[token.id], previous != token {
                tableRowSizes.removeValue(forKey: previous)
            }
            if tableRowTokenByID[token.id] == nil {
                tableRowIDOrder.append(token.id)
            }
            tableRowTokenByID[token.id] = token
            tableRowSizes[token] = size

            while tableRowTokenByID.count > tableRowSizeCapacity,
                  let evictedID = tableRowIDOrder.first
            {
                tableRowIDOrder.removeFirst()
                if let evictedToken = tableRowTokenByID.removeValue(forKey: evictedID) {
                    tableRowSizes.removeValue(forKey: evictedToken)
                }
            }
        }
    }

    public func code(forKey key: MarkdownCacheKey) -> AttributedString? {
        lock.withLock {
            codeCache.value(forKey: key)
        }
    }

    public func insertCode(_ code: AttributedString, forKey key: MarkdownCacheKey) {
        lock.withLock {
            codeCache[key] = code
        }
    }

    fileprivate func streamingCodeHighlightState(
        blockID: MarkdownBlockID,
        contextIdentity: String
    ) -> MarkdownStreamingCodeHighlightState? {
        lock.withLock {
            guard let state = activeStreamingCodeHighlight,
                  state.blockID == blockID,
                  state.contextIdentity == contextIdentity
            else {
                return nil
            }
            return state
        }
    }

    fileprivate func storeStreamingCodeHighlightState(
        _ state: MarkdownStreamingCodeHighlightState
    ) {
        lock.withLock {
            activeStreamingCodeHighlight = state
        }
    }

    fileprivate func streamingCodeHighlightStateID(
        blockID: MarkdownBlockID,
        contextIdentity: String
    ) -> String {
        "\(streamingCodeHighlightNamespace):\(blockID.rawValue):\(contextIdentity)"
    }

    @discardableResult
    fileprivate func removeStreamingCodeHighlightState(
        blockID: MarkdownBlockID
    ) -> MarkdownStreamingCodeHighlightState? {
        lock.withLock {
            guard activeStreamingCodeHighlight?.blockID == blockID else { return nil }
            defer { activeStreamingCodeHighlight = nil }
            return activeStreamingCodeHighlight
        }
    }

    public func mermaid(forKey key: MarkdownCacheKey) -> MarkdownPreparedMermaidDiagram? {
        lock.withLock {
            mermaidCache.value(forKey: key)
        }
    }

    public func insertMermaid(_ mermaid: MarkdownPreparedMermaidDiagram, forKey key: MarkdownCacheKey) {
        lock.withLock {
            mermaidCache[key] = mermaid
        }
    }

    public func math(forKey key: MarkdownCacheKey) -> MarkdownPreparedMath? {
        lock.withLock {
            mathCache.value(forKey: key)
        }
    }

    public func insertMath(_ math: MarkdownPreparedMath, forKey key: MarkdownCacheKey) {
        lock.withLock {
            mathCache[key] = math
        }
    }

    public func removeAll() {
        let backendStateID = lock.withLock {
            let backendStateID = activeStreamingCodeHighlight?.backendStateID
            inlineCache.removeAll()
            codeCache.removeAll()
            mermaidCache.removeAll()
            mathCache.removeAll()
            tableRowSizes.removeAll(keepingCapacity: false)
            tableRowTokenByID.removeAll(keepingCapacity: false)
            tableRowIDOrder.removeAll(keepingCapacity: false)
            activeStreamingCodeHighlight = nil
            return backendStateID
        }
        if let backendStateID {
            DefaultMarkdownCodeHighlighter().removeIncrementalState(backendStateID)
        }
        coreTextMeasurementCache.removeAll()
    }
}

private extension MarkdownInlineRun {
    var isLinkPresentation: Bool {
        kind == .link ||
            ((kind == .softBreak || kind == .hardBreak) && destination != nil)
    }

    var isImagePresentation: Bool {
        kind == .image || presentation.contains(.image)
    }

    var resolvedImageSource: String? {
        imageSource ?? (kind == .image ? destination : nil)
    }

    var isMathPresentation: Bool {
        kind == .math || presentation.contains(.math)
    }
}

public struct MarkdownPreparedSnapshot: Sendable {
    public var snapshot: MarkdownSnapshot
    public var items: [MarkdownPreparedSnapshotItem]
    public var renderItems: [MarkdownPreparedSnapshotRenderItem]
    public var itemIDs: [String]
    public var preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent]
    public var diff: MarkdownPreparedSnapshotDiff

    public init(
        snapshot: MarkdownSnapshot,
        items: [MarkdownPreparedSnapshotItem],
        renderItems: [MarkdownPreparedSnapshotRenderItem]? = nil,
        preparedContentByBlockID: [MarkdownBlockID: MarkdownPreparedBlockContent],
        diff: MarkdownPreparedSnapshotDiff = MarkdownPreparedSnapshotDiff()
    ) {
        self.snapshot = snapshot
        self.items = items
        let resolvedRenderItems = renderItems ?? Self.defaultRenderItems(for: items)
        self.renderItems = resolvedRenderItems
        self.itemIDs = resolvedRenderItems.map(\.id)
        self.preparedContentByBlockID = preparedContentByBlockID
        self.diff = diff
    }

    public subscript(blockID: MarkdownBlockID) -> MarkdownPreparedBlockContent? {
        preparedContentByBlockID[blockID]
    }

    public func item(at index: Int) -> MarkdownPreparedSnapshotItem? {
        guard items.indices.contains(index) else {
            return nil
        }
        return items[index]
    }

    private static func defaultRenderItems(
        for items: [MarkdownPreparedSnapshotItem]
    ) -> [MarkdownPreparedSnapshotRenderItem] {
        var occurrencesByID: [String: Int] = [:]
        var usedIDs: Set<String> = []
        return items.enumerated().map { index, item in
            let baseID = item.id
            let occurrence = occurrencesByID[baseID, default: 0]
            occurrencesByID[baseID] = occurrence + 1

            var renderID = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"
            var collisionIndex = 1
            while usedIDs.contains(renderID) {
                renderID = "\(baseID)#\(occurrence)#\(collisionIndex)"
                collisionIndex += 1
            }
            usedIDs.insert(renderID)
            return MarkdownPreparedSnapshotRenderItem(id: renderID, itemIndex: index)
        }
    }
}

public enum MarkdownPreparedSnapshotItem: Identifiable, Sendable {
    case block(MarkdownBlock, MarkdownPreparedBlockContent)
    case hostBoundary(MarkdownHostBoundary)

    public var id: String {
        switch self {
        case let .block(block, _):
            return "block:\(block.id.rawValue)"
        case let .hostBoundary(boundary):
            return "host:\(boundary.id.rawValue)"
        }
    }
}

public struct MarkdownPreparedSnapshotRenderItem: Identifiable, Sendable, Hashable {
    public var id: String
    public var itemIndex: Int

    public init(id: String, itemIndex: Int) {
        self.id = id
        self.itemIndex = itemIndex
    }
}

public struct MarkdownPreparedSnapshotDiff: Sendable, Hashable {
    public var changedItemIDs: Set<String>
    public var newItemIDs: Set<String>
    public var removedItemIDs: Set<String>
    public var generation: Int

    public init(
        changedItemIDs: Set<String> = [],
        newItemIDs: Set<String> = [],
        removedItemIDs: Set<String> = [],
        generation: Int = 0
    ) {
        self.changedItemIDs = changedItemIDs
        self.newItemIDs = newItemIDs
        self.removedItemIDs = removedItemIDs
        self.generation = generation
    }

    public var hasChanges: Bool {
        !changedItemIDs.isEmpty || !newItemIDs.isEmpty || !removedItemIDs.isEmpty
    }

    public func contains(_ id: String) -> Bool {
        changedItemIDs.contains(id) || newItemIDs.contains(id)
    }
}

public struct MarkdownPreparedRichBlock: Identifiable, Sendable {
    public var block: MarkdownBlock
    public var preparedContent: MarkdownPreparedBlockContent

    public var id: MarkdownBlockID { block.id }

    public init(
        block: MarkdownBlock,
        preparedContent: MarkdownPreparedBlockContent
    ) {
        precondition(
            block.id == preparedContent.blockID,
            "Rich HTML block and prepared content must share stable identity."
        )
        self.block = block
        self.preparedContent = preparedContent
    }
}

public struct MarkdownPreparedRichContent: Sendable {
    public var blocks: [MarkdownPreparedRichBlock]

    public init(blocks: [MarkdownPreparedRichBlock]) {
        self.blocks = blocks
    }
}

public struct MarkdownPreparedBlockContent: Sendable {
    public var blockID: MarkdownBlockID
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var selectionInlineLayout: MarkdownPreparedInlineContent?
    public var listItems: [MarkdownPreparedListItem]
    public var table: MarkdownPreparedTableBlock?
    public var mermaid: MarkdownPreparedMermaidDiagram?
    public var code: AttributedString?
    public var math: AttributedString?
    public var mathRender: MarkdownPreparedMath?
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?
    public var richContent: MarkdownPreparedRichContent?

    public init(
        blockID: MarkdownBlockID,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        selectionInlineLayout: MarkdownPreparedInlineContent? = nil,
        listItems: [MarkdownPreparedListItem] = [],
        table: MarkdownPreparedTableBlock? = nil,
        mermaid: MarkdownPreparedMermaidDiagram? = nil,
        code: AttributedString? = nil,
        math: AttributedString? = nil,
        mathRender: MarkdownPreparedMath? = nil,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil,
        richContent: MarkdownPreparedRichContent? = nil
    ) {
        self.blockID = blockID
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.selectionInlineLayout = selectionInlineLayout
        self.listItems = listItems
        self.table = table
        self.mermaid = mermaid
        self.code = code
        self.math = math
        self.mathRender = mathRender
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
        self.richContent = richContent
    }
}

public struct MarkdownPreparedListItem: Identifiable, Sendable {
    public var id: String
    public var sourceRange: MarkdownSourceRange
    public var taskState: MarkdownTaskState?
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var selectionInlineLayout: MarkdownPreparedInlineContent?
    public var childListKind: MarkdownBlockKind?
    public var childOrderedListStart: UInt?
    public var childItems: [MarkdownPreparedListItem]

    public init(
        id: String,
        sourceRange: MarkdownSourceRange,
        taskState: MarkdownTaskState? = nil,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        selectionInlineLayout: MarkdownPreparedInlineContent? = nil,
        childListKind: MarkdownBlockKind? = nil,
        childOrderedListStart: UInt? = nil,
        childItems: [MarkdownPreparedListItem] = []
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.taskState = taskState
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.selectionInlineLayout = selectionInlineLayout
        self.childListKind = childListKind
        self.childOrderedListStart = childOrderedListStart
        self.childItems = childItems
    }
}

public struct MarkdownPreparedTableCell: Identifiable, Sendable {
    public var id: String
    public var sourceRange: MarkdownSourceRange
    public var contentHash: UInt64
    /// Stable, constant-size identity consumed by table row layout caching.
    public var contentFingerprint: MarkdownContentFingerprint
    public var inline: AttributedString?
    public var inlineLayout: MarkdownPreparedInlineContent?
    public var selectionInlineLayout: MarkdownPreparedInlineContent?
    /// Natural prepared inline width captured outside SwiftUI body evaluation.
    public var naturalWidth: Double
    public var colspan: UInt
    public var rowspan: UInt

    public init(
        id: String,
        sourceRange: MarkdownSourceRange,
        contentHash: UInt64 = 0,
        contentFingerprint: MarkdownContentFingerprint? = nil,
        inline: AttributedString? = nil,
        inlineLayout: MarkdownPreparedInlineContent? = nil,
        selectionInlineLayout: MarkdownPreparedInlineContent? = nil,
        naturalWidth: Double = 0,
        colspan: UInt = 1,
        rowspan: UInt = 1
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.contentHash = contentHash
        self.inline = inline
        self.inlineLayout = inlineLayout
        self.selectionInlineLayout = selectionInlineLayout
        self.naturalWidth = naturalWidth
        self.colspan = colspan
        self.rowspan = rowspan
        if let contentFingerprint {
            self.contentFingerprint = contentFingerprint
        } else {
            var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-table-cell")
            fingerprint.combine(id)
            fingerprint.combine(sourceRange.byteRange.lowerBound)
            fingerprint.combine(sourceRange.byteRange.upperBound)
            fingerprint.combine(contentHash)
            fingerprint.combine(naturalWidth)
            fingerprint.combine(UInt(colspan))
            fingerprint.combine(UInt(rowspan))
            if let inlineLayout {
                fingerprint.combine(inlineLayout.cacheFingerprint)
            } else if let selectionInlineLayout {
                fingerprint.combine(selectionInlineLayout.cacheFingerprint)
            }
            self.contentFingerprint = fingerprint
        }
    }
}

public struct MarkdownPreparedTableRow: Identifiable, Sendable {
    public var id: String
    public var cells: [MarkdownPreparedTableCell]
    public var contentFingerprint: MarkdownContentFingerprint
    /// Width-resolved minimum row height produced during render preparation.
    /// `nil` is reserved for deliberately unprepared fallback content, whose
    /// SwiftUI subtree must be measured without cross-publication reuse.
    var preparedLayoutHeight: Double?

    public init(
        id: String,
        cells: [MarkdownPreparedTableCell],
        contentFingerprint: MarkdownContentFingerprint? = nil
    ) {
        self.id = id
        self.cells = cells
        self.preparedLayoutHeight = nil
        if let contentFingerprint {
            self.contentFingerprint = contentFingerprint
        } else {
            var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-table-row")
            fingerprint.combine(id)
            fingerprint.combine(cells.count)
            for cell in cells {
                fingerprint.combine(cell.contentFingerprint)
            }
            self.contentFingerprint = fingerprint
        }
    }
}

public struct MarkdownPreparedTableBlock: Sendable {
    public var columnAlignments: [MarkdownTableColumnAlignment?]
    public var header: [MarkdownPreparedTableCell]
    public var rows: [MarkdownPreparedTableRow]
    public var headerID: String
    public var headerContentFingerprint: MarkdownContentFingerprint
    /// Width-resolved minimum header height produced during preparation.
    var headerPreparedLayoutHeight: Double?
    /// True only when every row height was resolved from prepared inline data.
    /// The renderer uses this constant-time flag to decide whether stable row
    /// measurement reuse is safe.
    var hasPreparedLayoutHeights: Bool
    /// Monotonic natural-width maxima while streaming; exact maxima on seal.
    public var columnNaturalWidths: [Double]
    /// Prepared effective widths. SwiftUI consumes these directly without an
    /// all-cell scan from `body`.
    public var columnWidths: [Double]
    public var columnWidthFingerprint: MarkdownContentFingerprint
    /// Changes only when effective column widths change, allowing historical
    /// row measurement caches to survive unrelated tail-cell publications.
    public var columnWidthRevision: UInt64

    public init(
        columnAlignments: [MarkdownTableColumnAlignment?],
        header: [MarkdownPreparedTableCell],
        rows: [MarkdownPreparedTableRow],
        headerID: String = "table-header",
        headerContentFingerprint: MarkdownContentFingerprint? = nil,
        columnNaturalWidths: [Double] = [],
        columnWidths: [Double] = [],
        columnWidthFingerprint: MarkdownContentFingerprint? = nil,
        columnWidthRevision: UInt64 = 0
    ) {
        self.columnAlignments = columnAlignments
        self.header = header
        self.rows = rows
        self.headerID = headerID
        self.headerPreparedLayoutHeight = nil
        self.hasPreparedLayoutHeights = false
        if let headerContentFingerprint {
            self.headerContentFingerprint = headerContentFingerprint
        } else {
            var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-table-header")
            fingerprint.combine(headerID)
            fingerprint.combine(header.count)
            for cell in header {
                fingerprint.combine(cell.contentFingerprint)
            }
            self.headerContentFingerprint = fingerprint
        }
        let inferredColumnCount = max(
            max(columnAlignments.count, header.count),
            rows.map { $0.cells.count }.max() ?? 0
        )
        self.columnNaturalWidths = columnNaturalWidths.isEmpty && inferredColumnCount > 0
            ? Array(repeating: 0, count: inferredColumnCount)
            : columnNaturalWidths
        let resolvedColumnWidths = columnWidths.isEmpty && inferredColumnCount > 0
            ? Array(repeating: inferredColumnCount > 3 ? 112 : 132, count: inferredColumnCount)
            : columnWidths
        self.columnWidths = resolvedColumnWidths
        if let columnWidthFingerprint {
            self.columnWidthFingerprint = columnWidthFingerprint
        } else {
            var fingerprint = MarkdownContentFingerprint(domain: "markdown-prepared-table-widths")
            fingerprint.combine(resolvedColumnWidths.count)
            for width in resolvedColumnWidths {
                fingerprint.combine(width)
            }
            self.columnWidthFingerprint = fingerprint
        }
        self.columnWidthRevision = columnWidthRevision
    }
}

public struct MarkdownBlockRenderPlan: Sendable, Equatable {
    public var kind: MarkdownBlockKind
    public var listItemCount: Int
    public var tableColumnCount: Int
    public var tableBodyRowCount: Int
    public var codeAllowed: Bool?
    public var mermaidRendered: Bool
    public var mermaidControlsVisible: Bool
    public var mermaidZoomControlsVisible: Bool
    public var mermaidFitButtonVisible: Bool
    public var mermaidResetButtonVisible: Bool
    public var mermaidHasGeometry: Bool
    public var codeLanguageLabel: String?
    public var codeCopyButtonVisible: Bool
    public var codeExportButtonVisible: Bool
    public var codeCollapseButtonVisible: Bool
    public var codeInitiallyCollapsed: Bool
    public var mathAllowed: Bool?
    public var mathRendered: Bool
    public var htmlAllowed: Bool?
    public var policyDenialReason: String?

    public init(
        kind: MarkdownBlockKind,
        listItemCount: Int = 0,
        tableColumnCount: Int = 0,
        tableBodyRowCount: Int = 0,
        codeAllowed: Bool? = nil,
        mermaidRendered: Bool = false,
        mermaidControlsVisible: Bool = false,
        mermaidZoomControlsVisible: Bool = false,
        mermaidFitButtonVisible: Bool = false,
        mermaidResetButtonVisible: Bool = false,
        mermaidHasGeometry: Bool = false,
        codeLanguageLabel: String? = nil,
        codeCopyButtonVisible: Bool = false,
        codeExportButtonVisible: Bool = false,
        codeCollapseButtonVisible: Bool = false,
        codeInitiallyCollapsed: Bool = false,
        mathAllowed: Bool? = nil,
        mathRendered: Bool = false,
        htmlAllowed: Bool? = nil,
        policyDenialReason: String? = nil
    ) {
        self.kind = kind
        self.listItemCount = listItemCount
        self.tableColumnCount = tableColumnCount
        self.tableBodyRowCount = tableBodyRowCount
        self.codeAllowed = codeAllowed
        self.mermaidRendered = mermaidRendered
        self.mermaidControlsVisible = mermaidControlsVisible
        self.mermaidZoomControlsVisible = mermaidZoomControlsVisible
        self.mermaidFitButtonVisible = mermaidFitButtonVisible
        self.mermaidResetButtonVisible = mermaidResetButtonVisible
        self.mermaidHasGeometry = mermaidHasGeometry
        self.codeLanguageLabel = codeLanguageLabel
        self.codeCopyButtonVisible = codeCopyButtonVisible
        self.codeExportButtonVisible = codeExportButtonVisible
        self.codeCollapseButtonVisible = codeCollapseButtonVisible
        self.codeInitiallyCollapsed = codeInitiallyCollapsed
        self.mathAllowed = mathAllowed
        self.mathRendered = mathRendered
        self.htmlAllowed = htmlAllowed
        self.policyDenialReason = policyDenialReason
    }
}
