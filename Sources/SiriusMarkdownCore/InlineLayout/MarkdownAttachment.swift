import Foundation

/// Stable identity for one prepared attachment (image or future atomic
/// inline media) instance within a block. Derived from source range and
/// ordinal, not from array offsets, so identity survives sealed-region
/// reuse (Inline Attachments Part 01 §1.2.1).
public struct MarkdownAttachmentID: Sendable, Hashable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// Where an attachment's reserved box metrics came from. Informational —
/// does not change layout behavior, but lets hosts/tests distinguish a
/// guessed placeholder box from a size backed by real pixel data.
public enum MarkdownAttachmentSizingSource: Sendable, Hashable {
    /// No size information available; theme default placeholder box used.
    case themeDefault
    /// A best-guess aspect box (e.g. known aspect ratio, unknown pixels).
    case aspectPlaceholder
    /// Derived from a cheap header/metadata probe of real bytes (no full
    /// pixel decode).
    case intrinsicHint
    /// Derived from fully decoded pixel dimensions.
    case decoded
}

/// Reserved box metrics for one atomic attachment segment, carried on
/// `MarkdownInlineRun`/`PreparedInlineSegment` so CoreText line layout can
/// use box width instead of measuring placeholder text (INV-IA2).
public struct MarkdownInlineAttachmentMetrics: Sendable, Hashable {
    public var id: MarkdownAttachmentID
    public var pointWidth: Double
    public var pointHeight: Double
    public var ascent: Double
    public var descent: Double
    public var sizingSource: MarkdownAttachmentSizingSource

    public init(
        id: MarkdownAttachmentID,
        pointWidth: Double,
        pointHeight: Double,
        ascent: Double,
        descent: Double,
        sizingSource: MarkdownAttachmentSizingSource
    ) {
        self.id = id
        self.pointWidth = max(0, pointWidth.isFinite ? pointWidth : 0)
        self.pointHeight = max(0, pointHeight.isFinite ? pointHeight : 0)
        self.ascent = max(0, ascent.isFinite ? ascent : 0)
        self.descent = max(0, descent.isFinite ? descent : 0)
        self.sizingSource = sizingSource
    }
}

/// The placeholder character prepare substitutes for an allowed attachment
/// run's display text. A single space (rather than the object-replacement
/// character `\u{FFFC}`) so that if a `CTRunDelegate` cannot be applied for
/// some reason, the fallback glyph paints as invisible whitespace instead
/// of a visible "tofu" box — the reserved box/host image is always the
/// source of truth for what the user sees.
public let markdownAttachmentPlaceholderCharacter = " "
