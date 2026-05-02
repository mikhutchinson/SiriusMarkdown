import Foundation
import SiriusMarkdownCore

public struct PretextFixture: Codable, Sendable, Hashable {
    public var name: String
    public var group: String?
    public var description: String?
    public var markdown: String
    public var oracleText: String?
    public var containerWidth: Double
    public var font: String?
    public var lineHeight: Double?
    public var whiteSpace: String?
    public var wordBreak: String?
    public var expected: PretextExpectedLayout
    public var expectedInlineKinds: [MarkdownInlineKind]?
    public var expectedPreparedSegments: [PretextExpectedPreparedSegment]?

    public init(
        name: String,
        group: String? = nil,
        description: String? = nil,
        markdown: String,
        oracleText: String? = nil,
        containerWidth: Double,
        font: String? = nil,
        lineHeight: Double? = nil,
        whiteSpace: String? = nil,
        wordBreak: String? = nil,
        expected: PretextExpectedLayout,
        expectedInlineKinds: [MarkdownInlineKind]? = nil,
        expectedPreparedSegments: [PretextExpectedPreparedSegment]? = nil
    ) {
        self.name = name
        self.group = group
        self.description = description
        self.markdown = markdown
        self.oracleText = oracleText
        self.containerWidth = containerWidth
        self.font = font
        self.lineHeight = lineHeight
        self.whiteSpace = whiteSpace
        self.wordBreak = wordBreak
        self.expected = expected
        self.expectedInlineKinds = expectedInlineKinds
        self.expectedPreparedSegments = expectedPreparedSegments
    }
}

public extension PretextFixture {
    static let requiredProductGroups: Set<String> = [
        "autolink-inline",
        "cjk-wrap",
        "code-font-profile",
        "code-span",
        "combining-marks",
        "emoji-cjk",
        "emphasis-inline",
        "hard-breaks",
        "heading-font-profile",
        "image-placeholder",
        "inline-math",
        "link-inline",
        "list-cell-inline",
        "long-word",
        "mixed-script",
        "paragraph-wrap-medium",
        "paragraph-wrap-narrow",
        "paragraph-wrap-wide",
        "punctuation-trailing-whitespace",
        "rtl-wrap",
        "smoke-baseline",
        "soft-wraps",
        "strikethrough-inline",
        "strong-inline",
        "table-cell-inline"
    ]

    static func bundledFixtures() throws -> [PretextFixture] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PretextFixture.self, from: data)
        }
    }
}

public struct PretextExpectedLayout: Codable, Sendable, Hashable {
    public var lineCount: Int
    public var naturalWidth: Double
    public var height: Double
    public var segments: [PretextExpectedSegment]
    public var lines: [PretextExpectedLine]

    public init(
        lineCount: Int,
        naturalWidth: Double,
        height: Double,
        segments: [PretextExpectedSegment] = [],
        lines: [PretextExpectedLine] = []
    ) {
        self.lineCount = lineCount
        self.naturalWidth = naturalWidth
        self.height = height
        self.segments = segments
        self.lines = lines
    }
}

public struct PretextExpectedSegment: Codable, Sendable, Hashable {
    public var text: String
    public var kind: String
    public var width: Double
    public var byteRange: PretextByteRange

    public init(text: String, kind: String, width: Double, byteRange: PretextByteRange) {
        self.text = text
        self.kind = kind
        self.width = width
        self.byteRange = byteRange
    }
}

public struct PretextExpectedLine: Codable, Sendable, Hashable {
    public var text: String
    public var width: Double
    public var byteRange: PretextByteRange
    public var start: PretextLayoutCursor
    public var end: PretextLayoutCursor

    public init(
        text: String,
        width: Double,
        byteRange: PretextByteRange,
        start: PretextLayoutCursor,
        end: PretextLayoutCursor
    ) {
        self.text = text
        self.width = width
        self.byteRange = byteRange
        self.start = start
        self.end = end
    }
}

public struct PretextExpectedPreparedSegment: Codable, Sendable, Hashable {
    public var kind: MarkdownInlineKind
    public var text: String
    public var byteRange: PretextByteRange
    public var isHardBreak: Bool
    public var isBreakOpportunity: Bool

    public init(
        kind: MarkdownInlineKind,
        text: String,
        byteRange: PretextByteRange,
        isHardBreak: Bool = false,
        isBreakOpportunity: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.byteRange = byteRange
        self.isHardBreak = isHardBreak
        self.isBreakOpportunity = isBreakOpportunity
    }
}

public struct PretextLayoutCursor: Codable, Sendable, Hashable {
    public var segmentIndex: Int
    public var graphemeIndex: Int

    public init(segmentIndex: Int, graphemeIndex: Int) {
        self.segmentIndex = segmentIndex
        self.graphemeIndex = graphemeIndex
    }
}

public struct PretextByteRange: Codable, Sendable, Hashable {
    public var lowerBound: Int
    public var upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var range: Range<Int> {
        lowerBound..<upperBound
    }
}

public struct PretextGoldenDifference: Sendable, Hashable, CustomStringConvertible {
    public var fixtureName: String
    public var field: String
    public var expected: String
    public var actual: String

    public init(fixtureName: String, field: String, expected: Double, actual: Double) {
        self.init(
            fixtureName: fixtureName,
            field: field,
            expected: String(expected),
            actual: String(actual)
        )
    }

    public init(fixtureName: String, field: String, expected: String, actual: String) {
        self.fixtureName = fixtureName
        self.field = field
        self.expected = expected
        self.actual = actual
    }

    public var description: String {
        "\(fixtureName): \(field) expected \(expected), got \(actual)"
    }
}

public enum PretextGoldenComparator {
    public static func compare(
        fixture: PretextFixture,
        actual: InlineLayoutResult,
        naturalText: String? = nil,
        tolerance: Double = 0.5
    ) -> [PretextGoldenDifference] {
        var differences: [PretextGoldenDifference] = []

        appendDifference(
            &differences,
            fixtureName: fixture.name,
            field: "lineCount",
            expected: Double(fixture.expected.lineCount),
            actual: Double(actual.lines.count),
            tolerance: 0
        )
        appendDifference(
            &differences,
            fixtureName: fixture.name,
            field: "naturalWidth",
            expected: fixture.expected.naturalWidth,
            actual: actual.naturalWidth,
            tolerance: tolerance
        )
        appendDifference(
            &differences,
            fixtureName: fixture.name,
            field: "height",
            expected: fixture.expected.height,
            actual: actual.height,
            tolerance: tolerance
        )

        appendLineDifferences(
            &differences,
            fixture: fixture,
            actual: actual,
            naturalText: naturalText,
            tolerance: tolerance
        )

        return differences
    }

    private static func appendLineDifferences(
        _ differences: inout [PretextGoldenDifference],
        fixture: PretextFixture,
        actual: InlineLayoutResult,
        naturalText: String?,
        tolerance: Double
    ) {
        guard !fixture.expected.lines.isEmpty else {
            return
        }

        appendDifference(
            &differences,
            fixtureName: fixture.name,
            field: "lines.count",
            expected: Double(fixture.expected.lines.count),
            actual: Double(actual.lines.count),
            tolerance: 0
        )

        for (index, expectedLine) in fixture.expected.lines.enumerated() {
            guard actual.lines.indices.contains(index) else {
                continue
            }

            let actualLine = actual.lines[index]
            appendDifference(
                &differences,
                fixtureName: fixture.name,
                field: "lines[\(index)].width",
                expected: expectedLine.width,
                actual: actualLine.width,
                tolerance: tolerance
            )
            appendDifference(
                &differences,
                fixtureName: fixture.name,
                field: "lines[\(index)].consumedByteRange.lowerBound",
                expected: Double(expectedLine.byteRange.lowerBound),
                actual: Double(actualLine.consumedByteRange.lowerBound),
                tolerance: 0
            )
            appendDifference(
                &differences,
                fixtureName: fixture.name,
                field: "lines[\(index)].consumedByteRange.upperBound",
                expected: Double(expectedLine.byteRange.upperBound),
                actual: Double(actualLine.consumedByteRange.upperBound),
                tolerance: 0
            )

            guard let naturalText else {
                continue
            }

            let actualText = textSlice(naturalText, byteRange: actualLine.byteRange) ?? "<invalid range>"
            appendTextDifference(
                &differences,
                fixtureName: fixture.name,
                field: "lines[\(index)].text",
                expected: expectedLine.text,
                actual: actualText
            )
        }
    }

    private static func appendDifference(
        _ differences: inout [PretextGoldenDifference],
        fixtureName: String,
        field: String,
        expected: Double,
        actual: Double,
        tolerance: Double
    ) {
        guard abs(expected - actual) > tolerance else {
            return
        }

        differences.append(
            PretextGoldenDifference(
                fixtureName: fixtureName,
                field: field,
                expected: expected,
                actual: actual
            )
        )
    }

    private static func appendTextDifference(
        _ differences: inout [PretextGoldenDifference],
        fixtureName: String,
        field: String,
        expected: String,
        actual: String
    ) {
        guard expected != actual else {
            return
        }

        differences.append(
            PretextGoldenDifference(
                fixtureName: fixtureName,
                field: field,
                expected: expected,
                actual: actual
            )
        )
    }

    private static func textSlice(_ text: String, byteRange: Range<Int>) -> String? {
        guard byteRange.lowerBound >= 0,
              byteRange.upperBound <= text.utf8.count,
              let lowerUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.lowerBound,
                limitedBy: text.utf8.endIndex
              ),
              let upperUTF8 = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: byteRange.upperBound,
                limitedBy: text.utf8.endIndex
              ),
              let lower = String.Index(lowerUTF8, within: text),
              let upper = String.Index(upperUTF8, within: text)
        else {
            return nil
        }

        return String(text[lower..<upper])
    }
}
