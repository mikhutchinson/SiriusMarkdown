import Foundation
import SiriusMarkdownCore
import Testing
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized)
@MainActor
struct MarkdownExplicitAnchorTests {
    @Test
    func explicitIDsWinSlugCollisionsAndFirstDuplicateWins() throws {
        let prepared = prepare("# Destination\n\n<div id=\"destination\"><p>First target</p></div>\n\n<p id=\"destination\">Duplicate target</p>")
        let index = MarkdownPreparedDocumentIndex(preparedSnapshot: prepared)
        let heading = try #require(index.heading(forFragment: "#destination"))
        let anchor = try #require(index.anchor(forFragment: "#destination"))
        #expect(anchor.blockID != heading.blockID)
        #expect(anchor.blockID == prepared.snapshot.blocks[1].id)
        #expect(index.anchors.filter { $0.id == "destination" }.count == 1)
    }

    @Test
    func inlineUnicodeAndEmptyIDsResolveWithoutAHeading() throws {
        let prepared = prepare("Before <span id=\"caf&#233;\">text</span> <a id=\"empty\"></a> after")
        let index = MarkdownPreparedDocumentIndex(preparedSnapshot: prepared)
        #expect(index.headings.isEmpty)
        #expect(index.anchor(forFragment: "#caf%C3%A9")?.id == "café")
        #expect(index.anchor(forFragment: "#empty") != nil)
        #expect(index.anchor(forFragment: "#EMPTY") == nil)
    }

    @Test
    func cachedPreparationDoesNotReuseOldIDsWithEqualVisibleText() throws {
        let configuration = MarkdownRendererConfiguration(linkMetadataResolver: nil)
        let first = prepare("Before <span id=\"first\">same</span> after", configuration: configuration)
        let second = prepare("Before <span id=\"other\">same</span> after", configuration: configuration)
        let original = MarkdownPreparedDocumentIndex(preparedSnapshot: first)
        let replaced = MarkdownPreparedDocumentIndex(preparedSnapshot: second)
        #expect(original.anchor(forFragment: "first") != nil)
        #expect(replaced.anchor(forFragment: "first") == nil)
        #expect(replaced.anchor(forFragment: "other") != nil)
    }

    @Test
    func deniedHTMLAndDroppedSubtreesHaveNoDestinations() {
        let denied = prepare("<p id=\"hidden\">Text</p>", configuration: MarkdownRendererConfiguration(linkMetadataResolver: nil, htmlPolicy: DenyAnchorHTML()))
        #expect(MarkdownPreparedDocumentIndex(preparedSnapshot: denied).anchor(forFragment: "hidden") == nil)
        let dropped = prepare("<div><script id=\"script\">text</script><iframe id=\"frame\"></iframe><p id=\"visible\">Text</p></div>")
        let index = MarkdownPreparedDocumentIndex(preparedSnapshot: dropped)
        #expect(index.anchor(forFragment: "script") == nil)
        #expect(index.anchor(forFragment: "frame") == nil)
        #expect(index.anchor(forFragment: "visible") != nil)
    }

    @Test
    func navigationUsesGenericExplicitDestination() async throws {
        let prepared = prepare("Before <a id=\"target\"></a> after")
        let find = MarkdownDocumentFindController()
        let navigation = MarkdownDocumentNavigationState(snapshot: prepared, findController: find, externalLinkAction: nil)
        await navigation.open("#target")
        let anchor = try #require(find.index.anchor(forFragment: "target"))
        #expect(navigation.revealRequest?.blockID == anchor.blockID)
        #expect(navigation.revealRequest?.sourceRange == anchor.sourceRange)
    }

    private func prepare(_ source: String, configuration: MarkdownRendererConfiguration = MarkdownRendererConfiguration(linkMetadataResolver: nil)) -> MarkdownPreparedSnapshot {
        var stream = MarkdownStream()
        stream.append(source)
        stream.finish()
        return configuration.prepare(snapshot: stream.snapshot())
    }
}

private struct DenyAnchorHTML: MarkdownHTMLPolicy {
    func evaluateHTML(_ html: String) -> MarkdownPolicyDecision { .deny(reason: "Test deny") }
}
