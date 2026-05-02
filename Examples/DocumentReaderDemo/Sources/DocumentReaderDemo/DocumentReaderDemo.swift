import AppKit
import SiriusMarkdown
import SiriusMarkdownMath
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
    let document: ReaderDocument

    init() {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        var stream = MarkdownStream(diagnosticsRecorder: streamRecorder)
        stream.append(DemoDocument.markdown)
        stream.finish()

        let copyProvider = MarkdownCopyProvider(markdownSource: DemoDocument.markdown)
        let configuration = MarkdownRendererConfiguration(
            theme: .document,
            inlineRenderingMode: .preparedNativeLines,
            copyProvider: copyProvider,
            mathRenderer: NativeMarkdownMathRenderer(),
            diagnosticsRecorder: renderRecorder
        )

        self.configuration = configuration
        let snapshot = stream.snapshot()
        let sections = DocumentSection.sections(in: snapshot)
        self.preparedSnapshot = configuration.prepare(snapshot: snapshot)
        self.sections = sections
        self.document = ReaderDocument(
            markdown: DemoDocument.markdown,
            snapshot: snapshot,
            sections: sections
        )
    }
}

private struct DocumentReaderView: View {
    @StateObject private var model: DocumentReaderModel
    @State private var measure = DocumentMeasure.readable
    @State private var selectedBlockID: MarkdownBlockID?
    @State private var scrollToTopRequest = 0

    @MainActor
    init() {
        let model = DocumentReaderModel()
        _model = StateObject(wrappedValue: model)
        _selectedBlockID = State(initialValue: model.sections.first?.id)
    }

    var body: some View {
        NavigationSplitView {
            ReaderSidebar(
                document: model.document,
                sections: model.sections,
                selectedBlockID: $selectedBlockID,
                measure: $measure
            )
        } detail: {
            readerSurface
                .navigationTitle(model.document.title)
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            selectedBlockID = model.sections.first?.id
                            scrollToTopRequest += 1
                        } label: {
                            Label("Back to Top", systemImage: "arrow.up.to.line")
                        }

                        Button {
                            copyDocumentMarkdown()
                        } label: {
                            Label("Copy Document", systemImage: "doc.on.doc")
                        }

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
                document: model.document,
                preparedSnapshot: model.preparedSnapshot,
                configuration: model.configuration,
                selectedBlockID: $selectedBlockID,
                scrollToTopRequest: scrollToTopRequest,
                currentSectionTitle: currentSectionTitle
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

    private var currentSectionTitle: String {
        guard let selectedBlockID,
              let section = model.sections.first(where: { $0.id == selectedBlockID })
        else {
            return model.sections.first?.title ?? "Overview"
        }
        return section.title
    }

    private func copyDocumentMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DemoDocument.markdown, forType: .string)
    }
}

private struct ReaderSidebar: View {
    var document: ReaderDocument
    var sections: [DocumentSection]
    @Binding var selectedBlockID: MarkdownBlockID?
    @Binding var measure: DocumentMeasure

    var body: some View {
        List {
            Section("Current Document") {
                ReaderDocumentSummary(document: document)
            }

            Section("Contents") {
                ForEach(sections) { section in
                    SidebarSectionButton(
                        section: section,
                        isSelected: selectedBlockID == section.id
                    ) {
                        selectedBlockID = section.id
                    }
                }
            }

            Section("Reader") {
                MetricRow(title: "Reading time", value: "\(document.readingMinutes) min")
                MetricRow(title: "Words", value: document.wordCount.formatted())
                MetricRow(title: "Sections", value: document.sectionCount.formatted())
                MetricRow(title: "Width", value: measure.title)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 330)
        .navigationTitle("Library")
    }
}

private struct ReaderDocumentSummary: View {
    var document: ReaderDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(document.title, systemImage: "book.closed")
                .font(.headline)
                .lineLimit(2)

            Text(document.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label(document.updated, systemImage: "calendar")
                Text("•")
                Text(document.author)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        .padding(.leading, section.level > 2 ? 12 : 0)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
    }
}

private struct PreparedDocumentScrollView: View {
    var document: ReaderDocument
    var preparedSnapshot: MarkdownPreparedSnapshot
    var configuration: MarkdownRendererConfiguration
    @Binding var selectedBlockID: MarkdownBlockID?
    var scrollToTopRequest: Int
    var currentSectionTitle: String

    private var theme: MarkdownTheme {
        configuration.theme
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ReaderDocumentHeader(
                        document: document,
                        currentSectionTitle: currentSectionTitle
                    )
                    .id(ReaderDocumentTopAnchor.id)
                    .padding(.bottom, 10)

                    ForEach(preparedSnapshot.items) { item in
                        preparedItemView(item)
                    }
                }
                .padding(.horizontal, 38)
                .padding(.vertical, 34)
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
            .onChange(of: scrollToTopRequest) { _ in
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(ReaderDocumentTopAnchor.id, anchor: .top)
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
    var level: Int

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
                systemImage: systemImage(for: title),
                level: block.headingLevel ?? 2
            )
        }
    }

    private static func systemImage(for title: String) -> String {
        switch title {
        case "Overview":
            return "doc.richtext"
        case "Reading Workflow":
            return "eyeglasses"
        case "Working Notes":
            return "note.text"
        case "International Sections":
            return "globe"
        case "Technical Appendix":
            return "curlybraces"
        case "Reference Table":
            return "tablecells"
        case "Formula Notes":
            return "function"
        case "Cached Stress Appendix":
            return "externaldrive.badge.checkmark"
        default:
            return "text.justify.leading"
        }
    }
}

private enum ReaderDocumentTopAnchor {
    static let id = "reader-document-top"
}

private struct MetricRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct ReaderDocument: Hashable {
    var title: String
    var subtitle: String
    var author: String
    var updated: String
    var wordCount: Int
    var readingMinutes: Int
    var sectionCount: Int
    var blockCount: Int
    var sourceBytes: Int

    init(markdown: String, snapshot: MarkdownSnapshot, sections: [DocumentSection]) {
        self.title = "Native Reader Field Guide"
        self.subtitle = "A compact technical brief with outline navigation, reading-width controls, source copy, and policy-safe rich content."
        self.author = "SiriusMarkdown"
        self.updated = "May 2026"
        self.wordCount = Self.wordCount(in: markdown)
        self.readingMinutes = max(1, Int(ceil(Double(wordCount) / 220.0)))
        self.sectionCount = sections.count
        self.blockCount = snapshot.blocks.count
        self.sourceBytes = snapshot.sourceLength
    }

    private static func wordCount(in markdown: String) -> Int {
        markdown.split { character in
            !character.isLetter && !character.isNumber
        }.count
    }
}

private struct ReaderDocumentHeader: View {
    var document: ReaderDocument
    var currentSectionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.title)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                Text(document.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 142), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ReaderMetadataLabel(title: "Author", value: document.author, systemImage: "person.text.rectangle")
                ReaderMetadataLabel(title: "Updated", value: document.updated, systemImage: "calendar")
                ReaderMetadataLabel(title: "Length", value: "\(document.readingMinutes) min", systemImage: "clock")
                ReaderMetadataLabel(title: "Now Reading", value: currentSectionTitle, systemImage: "location")
            }
            .font(.caption)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DemoColors.pageStroke)
                .frame(height: 1)
        }
    }
}

private struct ReaderMetadataLabel: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .labelStyle(.titleAndIcon)
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
    static let markdown = [
        baseMarkdown,
        cachedStressAppendix(sectionCount: 48)
    ].joined(separator: "\n\n")

    private static let baseMarkdown = """
    ## Overview

    This field guide is written as a compact technical brief with a table of contents, reading-width controls, source-copy behavior, inline math like $x^2 \\rightarrow y_1 + \\alpha$, and rich content that belongs in a native reader.

    The reader surface should feel calm and persistent. The sidebar is for document navigation and reading metadata, the toolbar is for document actions, and the page itself stays focused on long-form content.

    $$
    readableMeasure = preparedSegments \\rightarrow layout(width)
    $$

    ## Reading Workflow

    Readers usually scan first, choose a section, then settle into a stable measure. The outline supports fast jumps, while the segmented width control lets the same prepared document move between compact, readable, and wide layouts without changing the document identity.

    > The reader is not a benchmark panel. It is a product surface that proves a prepared Markdown document can behave like native reading material.

    A useful reader still needs Markdown fidelity. Inline runs such as **strong text**, *emphasis*, ~~revisions~~, `code spans`, safe [reference links](https://example.com/reference), and denied [script links](javascript:alert('blocked')) should all flow inside the same paragraph without stealing attention from the prose.

    ## Working Notes

    A document reader benefits from predictable source operations. A context menu can copy the exact Markdown for a block, while the toolbar can copy the full source. Those operations should not depend on rendered text approximations.

    - [x] Copy exact Markdown ranges for selected blocks
    - [x] Keep links policy-controlled by default
    - [x] Keep remote images inert unless a host app opts in
    - [ ] Add annotation and bookmark APIs after renderer correctness is stable

    A denied network image should remain a readable placeholder rather than fetching anything by default: ![Remote architecture diagram](https://example.com/architecture.png)

    ## International Sections

    English, 日本語, 한국어, العربية, עברית, emoji 😀😎, and CJK punctuation should all remain part of the same document flow. Reading width should influence wrapping, not parser behavior.

    Mixed direction text should still wrap as a normal paragraph: Start with English, continue with العربية داخل الجملة, then return to English with `inline code` and a safe [reference](https://example.com/i18n).

    Hard line breaks should stay visible in prepared layout: first line  
    second line after a Markdown hard break.

    ## Technical Appendix

    ```swift
    struct ReaderBookmark: Identifiable, Hashable {
        var id: String
        var title: String
        var sourceRange: MarkdownSourceRange
    }

    let measure = DocumentMeasure.readable
    let pageWidth = measure.width
    ```

    ```json
    {"document":"Native Reader Field Guide","mode":"reader","features":["outline","copy-source","reading-width","policy-safe-content"]}
    ```

    ## Reference Table

    | Reader Area | User Action | Expected Behavior | Native Surface | Failure Avoided |
    | :--- | :--- | :--- | :--- | :--- |
    | Outline | choose a heading | scroll directly to the section | sidebar list | losing place in a long document |
    | Measure | switch compact/readable/wide | relayout prepared content for width | segmented toolbar control | cramped or over-wide prose |
    | Copy | copy block or full document | preserve original Markdown source | context menu and toolbar | copying rendered approximations |
    | Safety | open links or encounter images | obey explicit policy decisions | link action and image placeholder | accidental network or scheme access |

    ## Formula Notes

    $$
    readableMeasure = preparedSegments + selectedWidth
    $$

    $$
    sourceCopy(block) = markdown[sourceRange]
    $$

    <aside>Raw HTML remains inert in the default public-reader policy.</aside>
    """

    private static func cachedStressAppendix(sectionCount: Int) -> String {
        var sections: [String] = [
            """
            ## Cached Stress Appendix

            This generated appendix makes the reader demo open with a large prepared document rather than a short hand-authored sample. It keeps the product surface calm while source bytes, headings, tables, code, and prepared inline segments scale up.
            """
        ]

        for index in 1...sectionCount {
            sections.append(stressSection(index))
        }

        sections.append(
            """
            ## Appendix Close

            The reader should still scroll smoothly, preserve source-backed copy, and relayout the same prepared document when the measure changes.
            """
        )

        return sections.joined(separator: "\n\n")
    }

    private static func stressSection(_ index: Int) -> String {
        var parts: [String] = [
            """
            ### Stress Section \(index)

            Reader section \(index) repeats realistic long-form content with **strong emphasis**, `inline code`, safe [reference links](https://example.com/reader/\(index)), inline math $reader_\(index) + width$, and mixed scripts: 日本語, 한국어, العربية داخل الفقرة, עברית, and emoji 😀. Changing the segmented measure should relayout prepared content without rebuilding the document model.

            - keep outline navigation responsive for section \(index)
            - keep block copy source-backed
            - keep table/code overflow contained
            """
        ]

        if index.isMultiple(of: 6) {
            parts.append(
                """
                | Reader Stress | Section \(index) | Expected Behavior |
                | :--- | :--- | :--- |
                | Width | compact/readable/wide | prepared relayout |
                | Cache | repeated source shape | stable prepared content |
                | Text | CJK, RTL, emoji | no parser churn |
                """
            )
        }

        if index.isMultiple(of: 10) {
            parts.append(
                """
                ```json
                {"readerSection":\(index),"surface":"DocumentReaderDemo","stress":"cached-large-document"}
                ```
                """
            )
        }

        if index.isMultiple(of: 12) {
            parts.append(
                """
                $$
                readerMeasure_\(index) = preparedDocument + selectedWidth
                $$
                """
            )
        }

        return parts.joined(separator: "\n\n")
    }
}
