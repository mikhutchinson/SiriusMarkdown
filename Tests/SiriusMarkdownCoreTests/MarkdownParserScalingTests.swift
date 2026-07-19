import Foundation
import Testing
@testable import SiriusMarkdownCore

private func generatedTable(rowCount: Int) -> String {
    var lines = [
        "| Index | Name | Status | Link | Code | Notes |",
        "| ---: | :--- | :---: | :--- | :--- | :--- |",
    ]
    lines.reserveCapacity(rowCount + 2)
    for row in 0..<rowCount {
        lines.append(
            "| \(row) | **item \(row)** | ready | "
                + "[details](https://example.com/items/\(row)) | `value_\(row)` | "
                + "Unicode 🚀 春天 row \(row) |"
        )
    }
    return lines.joined(separator: "\n")
}

private func mutableTailTableParseMilliseconds(rowCount: Int) throws -> Double {
    var stream = MarkdownStream()
    stream.append(generatedTable(rowCount: rowCount))

    let clock = ContinuousClock()
    let start = clock.now
    let snapshot = stream.snapshot()
    let elapsed = clock.now - start

    let table = try #require(snapshot.blocks.first?.table)
    #expect(table.rows.count == rowCount)
    return Double(elapsed.components.seconds) * 1_000
        + Double(elapsed.components.attoseconds) / 1e15
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

/// Source-location conversion must scale with the AST, not with
/// `AST nodes * preceding source bytes`. The old converter rescanned from byte
/// zero for every block, cell, and inline location, turning a single streamed
/// table into quadratic work and pinning a cooperative executor for seconds.
@Test
func largeMutableTailTableConversionStaysNearLinear() throws {
    _ = try mutableTailTableParseMilliseconds(rowCount: 20)

    let small = try median((0..<3).map { _ in
        try mutableTailTableParseMilliseconds(rowCount: 120)
    })
    let large = try median((0..<3).map { _ in
        try mutableTailTableParseMilliseconds(rowCount: 960)
    })
    let ratio = large / max(small, 0.001)

    print(
        "[parser-scaling] table rows 120=\(String(format: "%.2f", small))ms "
            + "960=\(String(format: "%.2f", large))ms "
            + "ratio=\(String(format: "%.2f", ratio))x"
    )

    let scalingMessage = "8x more table rows took \(String(format: "%.2f", ratio))x longer; "
        + "source-location conversion has regressed toward quadratic scaling"
    #expect(ratio < 20, Comment(rawValue: scalingMessage))
}

private func generatedRichHTML(paragraphCount: Int) -> String {
    var source = "<article>"
    source.reserveCapacity(paragraphCount * 110)
    for index in 0..<paragraphCount {
        source += "<p>Row \(index): <strong>native</strong> <a href=\"https://example.com/\(index)\">link</a> 🚀 春天</p>"
    }
    source += "</article>"
    return source
}

private func richHTMLParseMilliseconds(paragraphCount: Int) throws -> Double {
    let source = generatedRichHTML(paragraphCount: paragraphCount)
    let clock = ContinuousClock()
    let start = clock.now
    var stream = MarkdownStream()
    stream.append(source)
    stream.finish()
    let blocks = try #require(stream.snapshot().blocks.first?.richContent?.blocks)
    let elapsed = clock.now - start
    #expect(blocks.count == paragraphCount)
    return Double(elapsed.components.seconds) * 1_000
        + Double(elapsed.components.attoseconds) / 1e15
}

/// The native HTML adapter must remain tree-linear. Source mapping may not
/// rescan the entire HTML prefix for every converted text node.
@Test
func nativeRichHTMLConversionStaysNearLinear() throws {
    _ = try richHTMLParseMilliseconds(paragraphCount: 20)
    let small = try median((0..<3).map { _ in
        try richHTMLParseMilliseconds(paragraphCount: 100)
    })
    let large = try median((0..<3).map { _ in
        try richHTMLParseMilliseconds(paragraphCount: 800)
    })
    let ratio = large / max(small, 0.001)

    print(
        "[parser-scaling] HTML paragraphs 100=\(String(format: "%.2f", small))ms "
            + "800=\(String(format: "%.2f", large))ms "
            + "ratio=\(String(format: "%.2f", ratio))x"
    )
    #expect(
        ratio < 20,
        Comment(rawValue: "8x more HTML paragraphs took \(String(format: "%.2f", ratio))x longer")
    )
}
