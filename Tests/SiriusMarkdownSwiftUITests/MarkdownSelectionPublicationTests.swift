import Combine
import Testing
import SiriusMarkdownCore
@testable import SiriusMarkdownSwiftUI

@Suite(.serialized) @MainActor
struct MarkdownSelectionPublicationTests {
    @Test func unselectedStreamingUpdatesDoNotPublishSelectionChanges() {
        let controller = MarkdownSelectionController()
        var notifications = 0
        let observation = controller.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        var stream = MarkdownStream()
        for index in 0..<40 {
            stream.append("Paragraph \(index)\n\n")
            controller.updateSnapshot(stream.snapshot())
        }
        #expect(notifications == 0)
        // The private source index must still advance despite no notification.
        controller.selectAll(in: stream.snapshot())
        #expect(controller.selectedSourceRanges.first?.byteRange.upperBound == stream.snapshot().sourceLength)
        #expect(notifications > 0)
    }
}
