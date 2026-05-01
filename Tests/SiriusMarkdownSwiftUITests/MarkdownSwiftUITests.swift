import Foundation
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI

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
