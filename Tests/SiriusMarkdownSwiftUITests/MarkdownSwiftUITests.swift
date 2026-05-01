import Foundation
import SwiftUI
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
#if os(macOS)
import AppKit
#endif

@Test
@MainActor
func documentViewCanBeConstructedFromSnapshot() {
    let block = MarkdownBlock(
        id: MarkdownBlockID("block-1"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        isSealed: true
    )
    let snapshot = MarkdownSnapshot(blocks: [block], sourceLength: 5, generation: 1, isFinished: true)

    _ = MarkdownDocumentView(snapshot: snapshot)
    _ = StreamingMarkdownView(snapshot: snapshot)
}

@Test
func inlineRunsApplyLinkAndImagePolicies() {
    let linked = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(
                kind: .link,
                text: "example",
                destination: "https://example.com"
            )
        ]
    )
    #expect(linked.runs.compactMap(\.link).first?.absoluteString == "https://example.com")

    let blocked = InlineRunsView.attributedString(
        for: [
            MarkdownInlineRun(
                kind: .link,
                text: "local",
                destination: "file:///tmp/secret"
            )
        ]
    )
    #expect(blocked.runs.compactMap(\.link).isEmpty)

    let hiddenImage = InlineRunsView.plainText(
        for: [
            MarkdownInlineRun(
                kind: .image,
                text: "",
                destination: "https://example.com/image.png"
            )
        ]
    )
    #expect(hiddenImage == "[image]")
}

@Test
func blockRenderPlanCapturesStructuredListsAndTables() throws {
    let taskList = try firstBlock("- [ ] first\n- [x] second")
    let taskPlan = MarkdownBlockView.renderPlan(for: taskList)
    #expect(taskPlan.kind == .taskList)
    #expect(taskPlan.listItemCount == 2)

    let table = try firstBlock("| A | B |\n| - | - |\n| 1 | 2 |")
    let tablePlan = MarkdownBlockView.renderPlan(for: table)
    #expect(tablePlan.kind == .table)
    #expect(tablePlan.tableColumnCount == 2)
    #expect(tablePlan.tableBodyRowCount == 1)
}

@Test
func preparedSnapshotPreservesHostBoundaryItems() {
    let block = MarkdownBlock(
        id: MarkdownBlockID("block"),
        kind: .paragraph,
        sourceRange: MarkdownSourceRange(byteRange: 0..<5, lineRange: 1..<2),
        text: "Hello",
        inlines: [.init(kind: .text, text: "Hello")],
        isSealed: true
    )
    let boundary = MarkdownHostBoundary(id: MarkdownHostBoundaryID("native"), sourceOffset: 5)
    let snapshot = MarkdownSnapshot(
        blocks: [block],
        items: [.block(block), .hostBoundary(boundary)],
        sourceLength: 5,
        generation: 1,
        isFinished: true
    )

    let prepared = MarkdownRendererConfiguration().prepare(snapshot: snapshot)

    #expect(prepared.items.count == 2)
    #expect(prepared.preparedContentByBlockID[block.id]?.inline != nil)
    if case let .hostBoundary(preparedBoundary) = prepared.items.last {
        #expect(preparedBoundary == boundary)
    } else {
        Issue.record("Expected host boundary item to be preserved.")
    }
}

@Test
func copyProviderReturnsExactSourceSlice() throws {
    var stream = MarkdownStream()
    stream.append("- item\n- second\n\n")
    stream.finish()
    let block = try #require(stream.snapshot().blocks.first)
    let copyStream = stream
    let provider = MarkdownCopyProvider { range in
        copyStream.markdown(in: range)
    }

    #expect(provider.markdown(block.sourceRange) == "- item\n- second\n")
}

@Test
func blockAccessibilityLabelsDescribeStructuredBlocks() throws {
    let heading = try firstBlock("## Title")
    let table = try firstBlock("| A | B |\n| - | - |\n| 1 | 2 |")
    let code = try firstBlock("```swift\nlet x = 1\n```")

    #expect(MarkdownBlockView.accessibilityLabel(for: heading) == "Heading 2: Title")
    #expect(MarkdownBlockView.accessibilityLabel(for: table) == "Table with 2 columns and 1 rows")
    #expect(MarkdownBlockView.accessibilityLabel(for: code) == "Code block")
}

@Test
func blockRenderPlanUsesProtocolPoliciesForCodeMathAndHTML() throws {
    let code = try firstBlock("```swift\nlet x = 1\n```")
    let deniedCode = MarkdownBlockView.renderPlan(
        for: code,
        configuration: MarkdownRendererConfiguration(codePolicy: DenyCodePolicy())
    )
    #expect(deniedCode.codeAllowed == false)
    #expect(deniedCode.policyDenialReason == "code denied")

    let math = try firstBlock("$$\nx^2\n$$")
    let deniedMath = MarkdownBlockView.renderPlan(
        for: math,
        configuration: MarkdownRendererConfiguration(mathPolicy: DenyMathPolicy())
    )
    #expect(deniedMath.mathAllowed == false)
    #expect(deniedMath.policyDenialReason == "math denied")

    let html = try firstBlock("<div>raw</div>")
    let defaultHTML = MarkdownBlockView.renderPlan(for: html)
    #expect(defaultHTML.htmlAllowed == false)

    let allowedHTML = MarkdownBlockView.renderPlan(
        for: html,
        configuration: MarkdownRendererConfiguration(htmlPolicy: AllowHTMLPolicy())
    )
    #expect(allowedHTML.htmlAllowed == true)
}

@Test
@MainActor
func preparedBlockContentMovesCodeAndMathRenderingOutOfBlockBody() throws {
    let code = try firstBlock("```swift\nlet x = 1\n```")
    let highlighter = CountingCodeHighlighter()
    let codeConfiguration = MarkdownRendererConfiguration(codeHighlighter: highlighter)

    _ = MarkdownBlockView.renderPlan(for: code, configuration: codeConfiguration)
    #expect(highlighter.count == 0)

    let preparedCode = codeConfiguration.prepare(block: code)
    #expect(highlighter.count == 1)
    _ = codeConfiguration.prepare(block: code)
    #expect(highlighter.count == 1)

    _ = MarkdownBlockView(
        block: code,
        configuration: codeConfiguration,
        preparedContent: preparedCode
    )
    #expect(highlighter.count == 1)

    let math = try firstBlock("$$\nx^2\n$$")
    let mathRenderer = CountingMathRenderer()
    let mathConfiguration = MarkdownRendererConfiguration(mathRenderer: mathRenderer)
    let preparedMath = mathConfiguration.prepare(block: math)
    #expect(mathRenderer.count == 1)
    _ = mathConfiguration.prepare(block: math)
    #expect(mathRenderer.count == 1)

    _ = MarkdownBlockView(
        block: math,
        configuration: mathConfiguration,
        preparedContent: preparedMath
    )
    #expect(mathRenderer.count == 1)
}

#if os(macOS)
@Test
@MainActor
func swiftUISnapshotRendersRepresentativeDocument() throws {
    var stream = MarkdownStream()
    stream.append(
        """
        # Title

        Paragraph with **strong**, *emphasis*, `code`, [link](https://example.com), and ![alt](image.png).

        - [ ] task
        - [x] done

        > Quote

        ```swift
        let veryLongIdentifierName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        ```

        | A | B |
        | - | - |
        | 1 | 2 |

        $$
        x^2
        $$
        """
    )
    stream.finish()
    let snapshot = stream.snapshot()
    let configuration = MarkdownRendererConfiguration(theme: .document)
    let prepared = configuration.prepare(snapshot: snapshot)
    let image = renderedBitmap(
        MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration),
        size: CGSize(width: 720, height: 720)
    )

    #expect(bitmapHasInk(image))
}

@MainActor
private func renderedBitmap<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
    let hostingView = NSHostingView(
        rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color.white)
    )
    hostingView.setFrameSize(size)
    hostingView.layoutSubtreeIfNeeded()
    let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        ?? NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
    return representation
}

private func bitmapHasInk(_ representation: NSBitmapImageRep) -> Bool {
    guard let data = representation.bitmapData else {
        return false
    }

    let byteCount = representation.bytesPerRow * representation.pixelsHigh
    for index in stride(from: 0, to: byteCount, by: max(1, representation.samplesPerPixel)) {
        let red = data[index]
        let green = index + 1 < byteCount ? data[index + 1] : red
        let blue = index + 2 < byteCount ? data[index + 2] : red
        if red < 245 || green < 245 || blue < 245 {
            return true
        }
    }
    return false
}
#endif

private func firstBlock(_ markdown: String) throws -> MarkdownBlock {
    var stream = MarkdownStream()
    stream.append(markdown)
    stream.finish()
    return try #require(stream.snapshot().blocks.first)
}

private struct DenyCodePolicy: MarkdownCodePolicy {
    func evaluateCodeBlock(infoString: String?, code: String) -> MarkdownPolicyDecision {
        .deny(reason: "code denied")
    }
}

private struct DenyMathPolicy: MarkdownMathPolicy {
    func evaluateMath(_ source: String, isBlock: Bool) -> MarkdownPolicyDecision {
        .deny(reason: "math denied")
    }
}

private struct AllowHTMLPolicy: MarkdownHTMLPolicy {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision {
        .allow
    }
}

private final class CountingCodeHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func highlightedCode(_ code: String, infoString: String?) -> AttributedString {
        lock.withLock {
            callCount += 1
        }
        return AttributedString(code)
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}

private final class CountingMathRenderer: MarkdownMathRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func renderedMath(_ source: String, isBlock: Bool) -> AttributedString {
        lock.withLock {
            callCount += 1
        }
        return AttributedString(source)
    }

    var count: Int {
        lock.withLock {
            callCount
        }
    }
}
