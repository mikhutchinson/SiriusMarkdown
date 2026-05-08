import SwiftUI

enum MarkdownAffordanceSymbols {
    static let copy = "square.on.square"
    static let export = "square.and.arrow.down.on.square"
    static let collapse = "chevron.up"
    static let expand = "chevron.down"
    static let zoomOut = "minus.magnifyingglass"
    static let zoomIn = "plus.magnifyingglass"
    static let fit = "arrow.up.left.and.arrow.down.right"
    static let reset = "arrow.counterclockwise"

    static func opticalYOffset(for symbolName: String) -> CGFloat {
        switch symbolName {
        case collapse, expand:
            return 1
        default:
            return 0
        }
    }
}

struct MarkdownAffordanceIcon: View {
    var systemName: String
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 24, height: 24)
            .offset(y: MarkdownAffordanceSymbols.opticalYOffset(for: systemName))
    }
}
