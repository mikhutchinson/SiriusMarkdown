import AppKit
import SiriusMarkdown
import SwiftUI

@main
struct DocumentReaderDemo: App {
    var body: some Scene {
        WindowGroup {
            DocumentReaderView()
                .frame(minWidth: 920, minHeight: 680)
        }
    }
}

@MainActor
private final class DocumentReaderModel: ObservableObject {
    let configuration: MarkdownRendererConfiguration
    let preparedSnapshot: MarkdownPreparedSnapshot
    let sections: [DocumentSection]
    let streamCounters: MarkdownDiagnosticsCounters
    let renderCounters: MarkdownDiagnosticsCounters

    init() {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        var stream = MarkdownStream(diagnosticsRecorder: streamRecorder)
        stream.append(DemoDocument.markdown)
        stream.finish()

        let finishedStream = stream
        let copyProvider = MarkdownCopyProvider { range in
            finishedStream.markdown(in: range)
        }
        let configuration = MarkdownRendererConfiguration(
            theme: .document,
            copyProvider: copyProvider,
            diagnosticsRecorder: renderRecorder
        )

        self.configuration = configuration
        let snapshot = stream.snapshot()
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.sections = DocumentSection.sections(in: snapshot)
        self.streamCounters = streamRecorder.snapshot()
        self.renderCounters = renderRecorder.snapshot()
    }
}

private struct DocumentReaderView: View {
    @StateObject private var model: DocumentReaderModel
    @State private var measure = DocumentMeasure.readable
    @State private var selectedBlockID: MarkdownBlockID?

    @MainActor
    init() {
        let model = DocumentReaderModel()
        _model = StateObject(wrappedValue: model)
        _selectedBlockID = State(initialValue: model.sections.first?.id)
    }

    var body: some View {
        NavigationSplitView {
            DemoSidebar(
                sections: model.sections,
                selectedBlockID: $selectedBlockID,
                streamCounters: model.streamCounters,
                renderCounters: model.renderCounters
            )
        } detail: {
            readerSurface
                .navigationTitle("Document Reader")
                .toolbar {
                    ToolbarItemGroup {
                        Picker("Measure", selection: $measure) {
                            ForEach(DocumentMeasure.allCases) { measure in
                                Text(measure.title).tag(measure)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 270)
                    }
                }
        }
    }

    private var readerSurface: some View {
        ZStack(alignment: .top) {
            DemoColors.windowBackground
                .ignoresSafeArea()

            PreparedDocumentScrollView(
                preparedSnapshot: model.preparedSnapshot,
                configuration: model.configuration,
                selectedBlockID: $selectedBlockID
            )
            .frame(maxWidth: measure.width, maxHeight: .infinity)
            .background(DemoColors.documentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DemoColors.pageStroke)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct DemoSidebar: View {
    var sections: [DocumentSection]
    @Binding var selectedBlockID: MarkdownBlockID?
    var streamCounters: MarkdownDiagnosticsCounters
    var renderCounters: MarkdownDiagnosticsCounters

    var body: some View {
        List {
            Section("Document") {
                ForEach(sections) { section in
                    SidebarSectionButton(
                        section: section,
                        isSelected: selectedBlockID == section.id
                    ) {
                        selectedBlockID = section.id
                    }
                }
            }

            Section("Counters") {
                MetricRow(title: "Parses", value: streamCounters.parseCount)
                MetricRow(title: "Sealed parses", value: streamCounters.sealedRegionParseCount)
                MetricRow(title: "Prepared blocks", value: renderCounters.renderPreparationCount)
                MetricRow(title: "Inline prepares", value: renderCounters.prepareCount)
                MetricRow(title: "Code highlights", value: renderCounters.codeHighlightCount)
                MetricRow(title: "Math renders", value: renderCounters.mathRenderCount)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        .navigationTitle("SiriusMarkdown")
    }
}

private struct SidebarSectionButton: View {
    var section: DocumentSection
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
    }
}

private struct PreparedDocumentScrollView: View {
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    @Binding var selectedBlockID: MarkdownBlockID?

    private var theme: MarkdownTheme {
        configuration.theme
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(preparedSnapshot.items) { item in
                        preparedItemView(item)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: selectedBlockID) { blockID in
                guard let blockID else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(blockID, anchor: .top)
                }
            }
            .onAppear {
                guard let selectedBlockID else {
                    return
                }

                Task { @MainActor in
                    proxy.scrollTo(selectedBlockID, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func preparedItemView(_ item: MarkdownPreparedSnapshotItem) -> some View {
        switch item {
        case let .block(block, preparedContent):
            MarkdownBlockView(
                block: block,
                configuration: configuration,
                preparedContent: preparedContent
            )
            .id(block.id)
        case .hostBoundary:
            EmptyView()
        }
    }
}

private struct DocumentSection: Identifiable, Hashable {
    var id: MarkdownBlockID
    var title: String
    var systemImage: String

    static func sections(in snapshot: MarkdownSnapshot) -> [DocumentSection] {
        snapshot.blocks.compactMap { block in
            guard block.kind == .heading else {
                return nil
            }

            let headingText = block.inlines.map(\.text).joined()
            let title = block.headingLevel == 1 ? "Overview" : headingText
            return DocumentSection(
                id: block.id,
                title: title.isEmpty ? "Section" : title,
                systemImage: systemImage(for: title)
            )
        }
    }

    private static func systemImage(for title: String) -> String {
        switch title {
        case "Overview":
            return "doc.richtext"
        case "Long Paragraph":
            return "text.alignleft"
        case "Lists And Inline Runs":
            return "list.bullet"
        case "Wide Code":
            return "chevron.left.forwardslash.chevron.right"
        case "Table":
            return "tablecells"
        case "Math And Policy":
            return "function"
        default:
            return "text.justify.leading"
        }
    }
}

private struct MetricRow: View {
    var title: String
    var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private enum DocumentMeasure: String, CaseIterable, Identifiable {
    case compact
    case readable
    case wide

    var id: Self { self }

    var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .readable:
            return "Readable"
        case .wide:
            return "Wide"
        }
    }

    var width: CGFloat {
        switch self {
        case .compact:
            return 620
        case .readable:
            return 820
        case .wide:
            return 1080
        }
    }
}

private enum DemoColors {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let documentBackground = Color(nsColor: .textBackgroundColor)
    static let pageStroke = Color(nsColor: .separatorColor).opacity(0.45)
}

private enum DemoDocument {
    static let markdown = """
    # SiriusMarkdown Renderer Contract

    SiriusMarkdown renders long native documents from prepared snapshots. This demo keeps Markdown parsing, code highlighting, math rendering, and inline preparation outside SwiftUI view evaluation while the reader surface can be resized between compact, readable, and wide measures.

    The paragraph below is deliberately long enough to expose wrapping regressions. It should use the available document width instead of collapsing into a narrow word column, and resizing the window should relayout prepared inline segments without reparsing the source document.

    ## Long Paragraph

    Streaming assistants and document readers often receive dense technical prose mixed with links, code spans, tables, quotes, and host-native insertions. A renderer that measures text inside each SwiftUI row will become fragile under those workloads. A renderer that prepares inline content once and performs cheap width-specific layout can stay stable while users resize a transcript, split view, or document window.

    > Width changes are layout work. They are not parser work, highlighter work, or AST conversion work.

    ## Lists And Inline Runs

    - [x] Parse Markdown semantics with `swift-markdown`
    - [x] Keep sealed streaming regions immutable
    - [ ] Continue expanding golden fixtures
      - CJK, emoji, RTL, hard breaks, and atomic inline items stay in the layout test matrix
      - Links such as [the package README](https://example.com/readme) remain policy-controlled

    ## Wide Code

    ```swift
    let longLine = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
    let renderer = MarkdownRendererConfiguration.document.prepare(snapshot: snapshot)
    print(longLine, renderer.items.count)
    ```

    ## Table

    | Area | Behavior | Evidence | Failure Mode Avoided |
    | :--- | :--- | :--- | :--- |
    | Streaming | Mutable tail reparses while sealed regions stay cacheable | Parse and tail counters | Full transcript reparses |
    | Layout | Prepare once and relayout cheaply for new widths | Pretext fixtures and render probe | Intrinsic-width feedback collapse |
    | Safety | Links, images, HTML, code, and math go through policies | Default policy hooks | App-private behavior leaking into a public package |

    ## Math And Policy

    $$
    widthChange -> layout(preparedSegments, width)
    $$

    <aside>Raw HTML remains inert by default.</aside>
    """
}
