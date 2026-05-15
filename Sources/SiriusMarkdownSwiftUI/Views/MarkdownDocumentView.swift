import SiriusMarkdownCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

private let markdownDocumentSelectionCoordinateSpaceName = "SiriusMarkdownDocumentSelectionSpace"

public struct MarkdownDocumentView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    @StateObject private var internalSelectionController = MarkdownSelectionController()

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .document) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .preparedNativeLines)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { boundary in AnyView(hostBoundaryContent(boundary)) }
    }

    public var body: some View {
        let controller = activeSelectionController
        ScrollView {
            selectionDocumentContent(selectionController: controller)
        }
        .onAppear {
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .onChange(of: preparedSnapshot.snapshot.generation) { _ in
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    private var activeSelectionController: MarkdownSelectionController? {
        guard configuration.documentSelection == .enabled else {
            return nil
        }
        return selectionController ?? internalSelectionController
    }

    @ViewBuilder
    private func selectionDocumentContent(selectionController: MarkdownSelectionController?) -> some View {
        let content = LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(preparedSnapshot.items) { item in
                preparedItemView(item, selectionController: selectionController)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)

        if let selectionController {
            MarkdownDocumentSelectionLayer(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            ) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func preparedItemView(
        _ item: MarkdownPreparedSnapshotItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectionFragmentContainer(
                    block: block,
                    preparedContent: preparedContent,
                    selectionController: selectionController
                ) {
                    blockView
                }
            } else {
                blockView
            }
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}

public struct StreamingMarkdownView: View {
    private var configuration: MarkdownRendererConfiguration
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var selectionController: MarkdownSelectionController?
    private var hostBoundaryView: @MainActor (MarkdownHostBoundary) -> AnyView

    @StateObject private var internalSelectionController = MarkdownSelectionController()

    private var theme: MarkdownTheme {
        configuration.theme
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, theme: MarkdownTheme = .compactChat) {
        self.configuration = MarkdownRendererConfiguration(theme: theme, inlineRenderingMode: .preparedNativeLines)
        self.preparedSnapshot = self.configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    @available(*, deprecated, message: "Prepare snapshots outside SwiftUI update paths and use init(preparedSnapshot:configuration:) for streaming or large documents.")
    public init(snapshot: MarkdownSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init(preparedSnapshot: MarkdownPreparedSnapshot, configuration: MarkdownRendererConfiguration) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = nil
        self.hostBoundaryView = { _ in AnyView(EmptyView()) }
    }

    public init<HostBoundaryContent: View>(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.configuration = configuration
        self.preparedSnapshot = preparedSnapshot
        self.selectionController = selectionController
        self.hostBoundaryView = { boundary in AnyView(hostBoundaryContent(boundary)) }
    }

    public var body: some View {
        let controller = activeSelectionController
        selectionDocumentContent(selectionController: controller)
        .onAppear {
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
        .onChange(of: preparedSnapshot.snapshot.generation) { _ in
            controller?.updateSnapshot(preparedSnapshot.snapshot)
        }
    }

    private var activeSelectionController: MarkdownSelectionController? {
        guard configuration.documentSelection == .enabled else {
            return nil
        }
        return selectionController ?? internalSelectionController
    }

    @ViewBuilder
    private func selectionDocumentContent(selectionController: MarkdownSelectionController?) -> some View {
        let content = LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(preparedSnapshot.items) { item in
                preparedItemView(item, selectionController: selectionController)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let selectionController {
            MarkdownDocumentSelectionLayer(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            ) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func preparedItemView(
        _ item: MarkdownPreparedSnapshotItem,
        selectionController: MarkdownSelectionController?
    ) -> some View {
        switch item {
        case let .block(block, preparedContent):
            let blockView = MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            if let selectionController {
                MarkdownSelectionFragmentContainer(
                    block: block,
                    preparedContent: preparedContent,
                    selectionController: selectionController
                ) {
                    blockView
                }
            } else {
                blockView
            }
        case let .hostBoundary(boundary):
            hostBoundaryView(boundary)
        }
    }
}

private struct MarkdownSelectionFragmentContainer<Content: View>: View {
    var block: MarkdownBlock
    var preparedContent: MarkdownPreparedBlockContent
    @ObservedObject var selectionController: MarkdownSelectionController
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(fragmentPreference)
            .contextMenu {
                Button("Select Block") {
                    selectionController.select(block.id)
                }
                Button("Clear Selection") {
                    selectionController.clearSelection()
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fragmentPreference: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkdownDocumentSelectionFragmentsKey.self,
                value: MarkdownDocumentSelectionFragment.fragments(
                    for: block,
                    preparedContent: preparedContent,
                    rect: proxy.frame(in: .named(markdownDocumentSelectionCoordinateSpaceName))
                )
            )
        }
    }

    private var isSelected: Bool {
        selectionController.isSelected(block.id)
    }
}

private struct MarkdownDocumentSelectionLayer<Content: View>: View {
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    @ObservedObject var selectionController: MarkdownSelectionController
    @ViewBuilder var content: () -> Content

    @State private var fragments: [MarkdownDocumentSelectionFragment] = []
    @State private var dragAnchor: MarkdownDocumentSelectionFragment?
    @State private var focusToken = 0

    var body: some View {
        content()
            .coordinateSpace(name: markdownDocumentSelectionCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                selectionHighlights
            }
            .background {
                MarkdownDocumentSelectionKeyHandler(focusToken: focusToken) {
                    copySelection()
                }
                .frame(width: 0, height: 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(selectionGesture)
            .onPreferenceChange(MarkdownDocumentSelectionFragmentsKey.self) { value in
                fragments = value.sortedForSelection()
            }
            .contextMenu {
                Button("Copy Selection") {
                    copySelection()
                }
                Button("Clear Selection") {
                    selectionController.clearSelection()
                }
            }
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                takeFocus()
                let anchor = dragAnchor ?? hitFragment(at: value.startLocation)
                dragAnchor = anchor
                guard let anchor,
                      let current = hitFragment(at: value.location)
                else {
                    return
                }
                selectRange(from: anchor, to: current)
            }
            .onEnded { _ in
                dragAnchor = nil
            }
    }

    @ViewBuilder
    private var selectionHighlights: some View {
        let selectedRanges = selectionController.selectedSourceRanges
        ForEach(fragments.filter { $0.intersectsAny(selectedRanges) }) { fragment in
            Rectangle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: max(1, fragment.rect.width), height: max(1, fragment.rect.height))
                .position(x: fragment.rect.midX, y: fragment.rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func hitFragment(at location: CGPoint) -> MarkdownDocumentSelectionFragment? {
        let hitSlop: CGFloat = 4
        if let direct = fragments.first(where: { $0.rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(location) }) {
            return direct
        }

        return fragments.min { lhs, rhs in
            lhs.distanceSquared(to: location) < rhs.distanceSquared(to: location)
        }
    }

    private func selectRange(
        from lower: MarkdownDocumentSelectionFragment,
        to upper: MarkdownDocumentSelectionFragment
    ) {
        let selection = MarkdownDocumentSelectionFragment.selection(
            from: lower,
            to: upper,
            in: fragments
        )
        selectionController.selectSourceRanges(selection.ranges, selectedBlockIDs: selection.blockIDs)
    }

    private func copySelection() {
        let markdown = selectionController.selectedMarkdown(
            in: preparedSnapshot,
            copyProvider: configuration.copyProvider
        )
        guard !markdown.isEmpty else {
            return
        }
        Task { @MainActor in
            configuration.affordanceActionHandler.copyString(markdown)
        }
    }

    private func takeFocus() {
        focusToken &+= 1
    }
}

struct MarkdownDocumentSelectionFragment: Identifiable, Equatable {
    var id: String
    var blockID: MarkdownBlockID
    var sourceRange: MarkdownSourceRange
    var rect: CGRect

    static func selection(
        from lower: MarkdownDocumentSelectionFragment,
        to upper: MarkdownDocumentSelectionFragment,
        in fragments: [MarkdownDocumentSelectionFragment]
    ) -> (ranges: [MarkdownSourceRange], blockIDs: [MarkdownBlockID]) {
        let lowerBound = min(lower.sourceRange.byteRange.lowerBound, upper.sourceRange.byteRange.lowerBound)
        let upperBound = max(lower.sourceRange.byteRange.upperBound, upper.sourceRange.byteRange.upperBound)
        let selectedFragments = fragments.filter {
            $0.sourceRange.byteRange.lowerBound < upperBound &&
                lowerBound < $0.sourceRange.byteRange.upperBound
        }
        let lineLower = selectedFragments.map(\.sourceRange.lineRange.lowerBound).min() ??
            min(lower.sourceRange.lineRange.lowerBound, upper.sourceRange.lineRange.lowerBound)
        let lineUpper = selectedFragments.map(\.sourceRange.lineRange.upperBound).max() ??
            max(lower.sourceRange.lineRange.upperBound, upper.sourceRange.lineRange.upperBound)
        let blockIDs = selectedFragments.map(\.blockID).orderedUnique()
        let range = MarkdownSourceRange(
            byteRange: lowerBound..<upperBound,
            lineRange: lineLower..<lineUpper
        )
        return ([range], blockIDs)
    }

    static func fragments(
        for block: MarkdownBlock,
        preparedContent: MarkdownPreparedBlockContent,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return [blockFragment(for: block, rect: rect)]
        }

        if let inlineLayout = preparedContent.inlineLayout {
            let lines = lineFragments(
                block: block,
                inlineLayout: inlineLayout,
                rect: rect,
                idPrefix: "block"
            )
            if !lines.isEmpty {
                return lines
            }
        }

        if !preparedContent.listItems.isEmpty {
            let itemFragments = preparedContent.listItems.flatMap {
                listFragments(block: block, item: $0, rect: rect)
            }
            if !itemFragments.isEmpty {
                return itemFragments
            }
        }

        if let table = preparedContent.table {
            let cells = table.header + table.rows.flatMap(\.cells)
            let cellFragments = cells.enumerated().map { index, cell in
                MarkdownDocumentSelectionFragment(
                    id: "table-cell:\(block.id.rawValue):\(index):\(cell.sourceRange.byteRange.lowerBound)",
                    blockID: block.id,
                    sourceRange: cell.sourceRange,
                    rect: rect
                )
            }
            if !cellFragments.isEmpty {
                return cellFragments
            }
        }

        return [blockFragment(for: block, rect: rect)]
    }

    func intersectsAny(_ ranges: [MarkdownSourceRange]) -> Bool {
        ranges.contains { range in
            sourceRange.byteRange.lowerBound < range.byteRange.upperBound &&
                range.byteRange.lowerBound < sourceRange.byteRange.upperBound
        }
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }

    private static func blockFragment(for block: MarkdownBlock, rect: CGRect) -> MarkdownDocumentSelectionFragment {
        MarkdownDocumentSelectionFragment(
            id: "block:\(block.id.rawValue)",
            blockID: block.id,
            sourceRange: block.sourceRange,
            rect: rect
        )
    }

    private static func lineFragments(
        block: MarkdownBlock,
        inlineLayout: MarkdownPreparedInlineContent,
        rect: CGRect,
        idPrefix: String
    ) -> [MarkdownDocumentSelectionFragment] {
        let layoutWidth = InlineRunsView.nativeLineLayoutWidth(
            for: inlineLayout,
            containerWidth: Double(rect.width)
        )
        let layout = InlineRunsView.lineLayout(
            for: inlineLayout,
            containerWidth: layoutWidth,
            allowsOverwideFallback: true
        )
        guard !layout.lines.isEmpty else {
            return []
        }

        let lineHeight = CGFloat(inlineLayout.lineHeight)
        let spacing = InlineRunsView.nativeLineSpacing(for: inlineLayout)
        return layout.lines.enumerated().compactMap { index, line in
            guard let sourceRange = sourceRange(
                for: line.consumedByteRange,
                in: inlineLayout
            ) else {
                return nil
            }
            let y = rect.minY + CGFloat(index) * (lineHeight + spacing)
            return MarkdownDocumentSelectionFragment(
                id: "\(idPrefix):\(block.id.rawValue):line:\(index):\(sourceRange.byteRange.lowerBound)",
                blockID: block.id,
                sourceRange: sourceRange,
                rect: CGRect(
                    x: rect.minX,
                    y: y,
                    width: max(1, min(rect.width, CGFloat(max(line.width, 1)) + 8)),
                    height: lineHeight
                )
            )
        }
    }

    private static func listFragments(
        block: MarkdownBlock,
        item: MarkdownPreparedListItem,
        rect: CGRect
    ) -> [MarkdownDocumentSelectionFragment] {
        var fragments = [
            MarkdownDocumentSelectionFragment(
                id: "\(item.id):\(item.sourceRange.byteRange.lowerBound)",
                blockID: block.id,
                sourceRange: item.sourceRange,
                rect: rect
            )
        ]
        fragments.append(contentsOf: item.childItems.flatMap { listFragments(block: block, item: $0, rect: rect) })
        return fragments
    }

    private static func sourceRange(
        for relativeByteRange: Range<Int>,
        in inlineLayout: MarkdownPreparedInlineContent
    ) -> MarkdownSourceRange? {
        guard !relativeByteRange.isEmpty else {
            return inlineLayout.prepared.sourceRange
        }

        var cursor = 0
        var lower: Int?
        var upper: Int?
        var lineLower: Int?
        var lineUpper: Int?

        for run in inlineLayout.prepared.runs {
            let runLength = run.text.utf8.count
            let runRange = cursor..<(cursor + runLength)
            let overlapLower = max(relativeByteRange.lowerBound, runRange.lowerBound)
            let overlapUpper = min(relativeByteRange.upperBound, runRange.upperBound)
            if overlapLower < overlapUpper, let sourceRange = run.sourceRange {
                let overlap = overlapLower..<overlapUpper
                let absoluteLower = sourceRange.byteRange.lowerBound + (overlap.lowerBound - runRange.lowerBound)
                let absoluteUpper = min(
                    sourceRange.byteRange.upperBound,
                    sourceRange.byteRange.lowerBound + (overlap.upperBound - runRange.lowerBound)
                )
                lower = min(lower ?? absoluteLower, absoluteLower)
                upper = max(upper ?? absoluteUpper, absoluteUpper)
                lineLower = min(lineLower ?? sourceRange.lineRange.lowerBound, sourceRange.lineRange.lowerBound)
                lineUpper = max(lineUpper ?? sourceRange.lineRange.upperBound, sourceRange.lineRange.upperBound)
            }
            cursor += runLength
        }

        if let lower, let upper, lower < upper {
            return MarkdownSourceRange(
                byteRange: lower..<upper,
                lineRange: (lineLower ?? 1)..<(lineUpper ?? ((lineLower ?? 1) + 1))
            )
        }

        guard let sourceRange = inlineLayout.prepared.sourceRange else {
            return nil
        }
        let lowerBound = min(sourceRange.byteRange.upperBound, sourceRange.byteRange.lowerBound + relativeByteRange.lowerBound)
        let upperBound = min(sourceRange.byteRange.upperBound, sourceRange.byteRange.lowerBound + relativeByteRange.upperBound)
        guard lowerBound < upperBound else {
            return sourceRange
        }
        return MarkdownSourceRange(byteRange: lowerBound..<upperBound, lineRange: sourceRange.lineRange)
    }
}

private struct MarkdownDocumentSelectionFragmentsKey: PreferenceKey {
    static let defaultValue: [MarkdownDocumentSelectionFragment] = []

    static func reduce(
        value: inout [MarkdownDocumentSelectionFragment],
        nextValue: () -> [MarkdownDocumentSelectionFragment]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private extension Array where Element == MarkdownDocumentSelectionFragment {
    func sortedForSelection() -> [MarkdownDocumentSelectionFragment] {
        sorted {
            if $0.sourceRange.byteRange.lowerBound == $1.sourceRange.byteRange.lowerBound {
                return $0.sourceRange.byteRange.upperBound < $1.sourceRange.byteRange.upperBound
            }
            return $0.sourceRange.byteRange.lowerBound < $1.sourceRange.byteRange.lowerBound
        }
    }
}

private extension Array where Element == MarkdownBlockID {
    func orderedUnique() -> [MarkdownBlockID] {
        var seen: Set<MarkdownBlockID> = []
        var result: [MarkdownBlockID] = []
        for id in self where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }
}

#if os(macOS)
struct MarkdownDocumentSelectionKeyHandler: NSViewRepresentable {
    var focusToken: Int
    var copy: @MainActor () -> Void

    func makeNSView(context: Context) -> CopyKeyView {
        let view = CopyKeyView()
        view.coordinator = context.coordinator
        context.coordinator.copy = copy
        context.coordinator.focusToken = focusToken
        return view
    }

    func updateNSView(_ nsView: CopyKeyView, context: Context) {
        context.coordinator.copy = copy
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else {
                    return
                }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(copy: copy)
    }

    final class Coordinator {
        var copy: @MainActor () -> Void
        var focusToken = 0

        init(copy: @escaping @MainActor () -> Void) {
            self.copy = copy
        }
    }

    final class CopyKeyView: NSView {
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                coordinator?.copy()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
#else
struct MarkdownDocumentSelectionKeyHandler: View {
    var focusToken: Int
    var copy: @MainActor () -> Void

    var body: some View {
        EmptyView()
    }
}
#endif
