import Foundation
import SiriusMarkdownCore

public struct PretextFixture: Codable, Sendable, Hashable {
    public var name: String
    public var markdown: String
    public var containerWidth: Double
    public var expected: PretextExpectedLayout

    public init(
        name: String,
        markdown: String,
        containerWidth: Double,
        expected: PretextExpectedLayout
    ) {
        self.name = name
        self.markdown = markdown
        self.containerWidth = containerWidth
        self.expected = expected
    }
}

public extension PretextFixture {
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

    public init(lineCount: Int, naturalWidth: Double, height: Double) {
        self.lineCount = lineCount
        self.naturalWidth = naturalWidth
        self.height = height
    }
}

public struct PretextGoldenDifference: Sendable, Hashable, CustomStringConvertible {
    public var fixtureName: String
    public var field: String
    public var expected: Double
    public var actual: Double

    public init(fixtureName: String, field: String, expected: Double, actual: Double) {
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

        return differences
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
}
