import Foundation
import os

public struct MarkdownDiagnosticsCounters: Sendable, Hashable {
    public var parseCount: Int
    public var prepareCount: Int
    public var layoutCount: Int
    public var cacheHitCount: Int
    public var cacheMissCount: Int

    public init(
        parseCount: Int = 0,
        prepareCount: Int = 0,
        layoutCount: Int = 0,
        cacheHitCount: Int = 0,
        cacheMissCount: Int = 0
    ) {
        self.parseCount = parseCount
        self.prepareCount = prepareCount
        self.layoutCount = layoutCount
        self.cacheHitCount = cacheHitCount
        self.cacheMissCount = cacheMissCount
    }
}

public struct MarkdownDiagnostics: Sendable {
    public static let subsystem = "SiriusMarkdown"

    public init() {}

    public func makeLog(category: String) -> OSLog {
        OSLog(subsystem: Self.subsystem, category: category)
    }

    public func debugDump(_ snapshot: MarkdownSnapshot) -> String {
        snapshot.blocks
            .map { "\($0.id.rawValue) \($0.kind.rawValue) \($0.sourceRange.byteRange)" }
            .joined(separator: "\n")
    }
}
