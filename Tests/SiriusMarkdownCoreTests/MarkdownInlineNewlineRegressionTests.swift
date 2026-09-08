import Testing
@testable import SiriusMarkdownCore

@Suite
struct MarkdownInlineNewlineRegressionTests {
    private struct UnitMeasurer: InlineMeasuring {
        func width(of text: String, fontSize: Double) -> Double {
            Double(text.count)
        }
    }

    @Test(arguments: ["\u{00A0}", "\u{202F}"])
    func nonbreakingSpacesKeepSurroundingWordsTogether(space: String) {
        let text = "x a" + space + "b"
        let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: text)])
        let walker = VariableWidthLineWalker(measurer: UnitMeasurer())
        let layout = walker.layout(
            prepared,
            options: InlineLayoutOptions(containerWidth: 4, fontSize: 14, lineHeight: 20)
        )
        #expect(prepared.segments.map(\.text) == ["x", " ", "a" + space + "b"])
        #expect(layout.lines.map(\.byteRange) == [0..<2, 2..<text.utf8.count])
    }

    @Test
    func separateNonbreakingDecorationSpacerKeepsItsLabel() {
        let prepared = PreparedInlineContent(runs: [
            .init(kind: .text, text: "x "),
            .init(kind: .link, text: "◆", presentation: .linkDecoration),
            .init(kind: .link, text: "\u{00A0}"),
            .init(kind: .link, text: "abc")
        ])
        let walker = VariableWidthLineWalker(measurer: UnitMeasurer())
        let layout = walker.layout(
            prepared,
            options: InlineLayoutOptions(containerWidth: 4, fontSize: 14, lineHeight: 20)
        )
        #expect(layout.lines.count == 2)
        #expect(layout.lines.first?.byteRange == 0..<2)
        #expect(layout.lines.last?.width == 5)
    }

    @Test(arguments: ["\n", "\r", "\r\n"])
    func authoredInlineNewlinesPreserveLineBreaksAndByteOffsets(newline: String) {
        let text = "first" + newline + "second"
        let prepared = PreparedInlineContent(runs: [.init(kind: .text, text: text)])
        let walker = VariableWidthLineWalker(measurer: UnitMeasurer())
        let measured = walker.prepare(prepared)
        let layout = walker.layout(
            measured,
            options: InlineLayoutOptions(containerWidth: 100, fontSize: 14, lineHeight: 20)
        )
        #expect(prepared.naturalText == text)
        #expect(layout.lines.count == 2)
        #expect(layout.lines.first?.byteRange == 0..<5)
        #expect(layout.lines.first?.consumedByteRange == 0..<(5 + newline.utf8.count))
        #expect(layout.lines.last?.byteRange == (5 + newline.utf8.count)..<text.utf8.count)
        #expect(layout.height == 40)
        #expect(measured.naturalWidth == 6)
    }
}
