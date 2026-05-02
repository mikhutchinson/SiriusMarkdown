import AppKit
import SiriusMarkdown
import SiriusMarkdownMath
import SwiftUI

@main
struct MarkdownDemoApp: App {
    var body: some Scene {
        WindowGroup {
            MarkdownDemoView()
                .frame(minWidth: 980, minHeight: 680)
        }
    }
}

@MainActor
private final class MarkdownDemoModel: ObservableObject {
    @Published var selectedExampleID: MarkdownExample.ID

    let examples: [PreparedMarkdownExample]

    init() {
        let examples = MarkdownExample.allCases.map(PreparedMarkdownExample.init(example:))
        self.examples = examples
        self.selectedExampleID = examples[0].id
    }

    var selectedExample: PreparedMarkdownExample {
        examples.first { $0.id == selectedExampleID } ?? examples[0]
    }
}

private struct MarkdownDemoView: View {
    @StateObject private var model = MarkdownDemoModel()

    var body: some View {
        NavigationSplitView {
            MarkdownDemoSidebar(model: model)
        } detail: {
            MarkdownExampleDetail(example: model.selectedExample)
                .navigationTitle(model.selectedExample.title)
        }
    }
}

private struct MarkdownDemoSidebar: View {
    @ObservedObject var model: MarkdownDemoModel

    var body: some View {
        List {
            Section("Markdown Examples") {
                ForEach(model.examples) { example in
                    SidebarExampleButton(
                        example: example,
                        isSelected: model.selectedExampleID == example.id
                    ) {
                        model.selectedExampleID = example.id
                    }
                }
            }

            Section("Selected Document") {
                MetricRow(title: "Source bytes", value: model.selectedExample.sourceByteCount.formatted())
                MetricRow(title: "Blocks", value: model.selectedExample.blockCount.formatted())
                MetricRow(title: "Headings", value: model.selectedExample.sectionCount.formatted())
                MetricRow(title: "Tables", value: model.selectedExample.tableCount.formatted())
                MetricRow(title: "Code blocks", value: model.selectedExample.codeBlockCount.formatted())
            }

            Section("Renderer Counters") {
                MetricRow(title: "Parses", value: model.selectedExample.streamCounters.parseCount.formatted())
                MetricRow(title: "Prepared blocks", value: model.selectedExample.renderCounters.renderPreparationCount.formatted())
                MetricRow(title: "Inline prepares", value: model.selectedExample.renderCounters.prepareCount.formatted())
                MetricRow(title: "Cache hits", value: model.selectedExample.cacheHitCount.formatted())
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        .navigationTitle("Markdown Demo")
    }
}

private struct SidebarExampleButton: View {
    var example: PreparedMarkdownExample
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: example.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(example.title)
                        .font(.headline)
                    Text(example.summary)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
    }
}

private struct MarkdownExampleDetail: View {
    var example: PreparedMarkdownExample

    var body: some View {
        ZStack {
            DemoColors.windowBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(example: example)

                Divider()

                GeometryReader { geometry in
                    ScrollView {
                        detailBody(isWide: geometry.size.width >= 980)
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailBody(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                DocumentSurface(example: example)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                DocumentInspectorPanel(example: example)
                    .frame(width: 300)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                DocumentSurface(example: example)
                DocumentInspectorPanel(example: example)
            }
        }
    }
}

private struct DetailHeader: View {
    var example: PreparedMarkdownExample

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(example.title, systemImage: example.systemImage)
                    .font(.title2.weight(.semibold))

                Spacer()

                Text(example.badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.accentColor.opacity(0.14))
                    }
                    .foregroundStyle(Color.accentColor)
            }

            Text(example.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                DetailStat(value: example.blockCount.formatted(), title: "Blocks")
                DetailStat(value: example.renderCounters.prepareCount.formatted(), title: "Prepares")
                DetailStat(value: example.cacheHitCount.formatted(), title: "Cache Hits")
                DetailStat(value: example.streamCounters.parseCount.formatted(), title: "Parses")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct DetailStat: View {
    var value: String
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DocumentSurface: View {
    var example: PreparedMarkdownExample

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rendered Document", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("\(example.blockCount) blocks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            MarkdownDocumentView(
                preparedSnapshot: example.preparedSnapshot,
                configuration: example.configuration
            )
            .frame(maxWidth: 920, alignment: .leading)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DemoColors.documentBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DemoColors.pageStroke)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
    }
}

private struct DocumentInspectorPanel: View {
    var example: PreparedMarkdownExample

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "Coverage") {
                InspectorMetricGrid(
                    metrics: [
                        ("Headings", example.sectionCount.formatted()),
                        ("Tables", example.tableCount.formatted()),
                        ("Code", example.codeBlockCount.formatted()),
                        ("Lists", example.listBlockCount.formatted()),
                        ("Quotes", example.quoteBlockCount.formatted()),
                        ("Math", example.mathBlockCount.formatted())
                    ]
                )
            }

            InspectorSection(title: "Pipeline") {
                InspectorMetricGrid(
                    metrics: [
                        ("Parse", example.streamCounters.parseCount.formatted()),
                        ("Tail", example.streamCounters.tailReparseCount.formatted()),
                        ("Sealed", example.streamCounters.sealedRegionParseCount.formatted()),
                        ("Scan", example.streamCounters.boundaryScanCount.formatted()),
                        ("Prepare", example.renderCounters.prepareCount.formatted()),
                        ("Warm hit", example.warmCacheHitCount.formatted()),
                        ("Layout", example.layoutCount.formatted()),
                        ("Layout hit", example.layoutCacheHitCount.formatted()),
                        ("Cache miss", example.cacheMissCount.formatted())
                    ]
                )
            }

            InspectorSection(title: "Assertions") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(example.assertions, id: \.self) { assertion in
                        AssertionRow(text: assertion)
                    }
                }
            }

            InspectorSection(title: "Sections") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(example.sections) { section in
                        HStack(spacing: 8) {
                            Image(systemName: section.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DemoColors.inspectorBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08))
        }
    }
}

private struct InspectorSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

private struct InspectorMetricGrid: View {
    var metrics: [(String, String)]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(metrics, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline.monospacedDigit())
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(DemoColors.documentBackground)
                }
            }
        }
    }
}

private struct AssertionRow: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.green)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MetricRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PreparedMarkdownExample: Identifiable {
    var id: String { example.id }
    var title: String { example.title }
    var summary: String { example.summary }
    var detail: String { example.detail }
    var systemImage: String { example.systemImage }
    var badge: String { example.badge }
    var assertions: [String] { example.assertions }

    let example: MarkdownExample
    let configuration: MarkdownRendererConfiguration
    let preparedSnapshot: MarkdownPreparedSnapshot
    let streamCounters: MarkdownDiagnosticsCounters
    let renderCounters: MarkdownDiagnosticsCounters
    let warmCacheHitCount: Int
    let warmCacheMissCount: Int
    let layoutCount: Int
    let layoutCacheHitCount: Int
    let layoutCacheMissCount: Int
    let sections: [DocumentSection]
    let sourceByteCount: Int
    let blockCount: Int
    let sectionCount: Int
    let tableCount: Int
    let codeBlockCount: Int
    let listBlockCount: Int
    let quoteBlockCount: Int
    let mathBlockCount: Int

    var cacheHitCount: Int {
        warmCacheHitCount + layoutCacheHitCount
    }

    var cacheMissCount: Int {
        warmCacheMissCount + layoutCacheMissCount
    }

    init(example: MarkdownExample) {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        var stream = MarkdownStream(diagnosticsRecorder: streamRecorder)
        stream.append(example.markdown)
        stream.finish()

        let copyProvider = MarkdownCopyProvider(markdownSource: example.markdown)
        let configuration = MarkdownRendererConfiguration(
            theme: .document,
            inlineRenderingMode: .preparedNativeLines,
            copyProvider: copyProvider,
            mathRenderer: NativeMarkdownMathRenderer(),
            diagnosticsRecorder: renderRecorder
        )
        let snapshot = stream.snapshot()

        self.example = example
        self.configuration = configuration
        let preparedSnapshot = configuration.prepare(snapshot: snapshot)
        let coldRenderCounters = renderRecorder.snapshot()
        _ = configuration.prepare(snapshot: snapshot)
        let warmRenderCounters = renderRecorder.snapshot()
        Self.exerciseLayoutCache(in: preparedSnapshot)
        let layoutRenderCounters = renderRecorder.snapshot()

        self.preparedSnapshot = preparedSnapshot
        self.streamCounters = streamRecorder.snapshot()
        self.renderCounters = coldRenderCounters
        self.warmCacheHitCount = max(0, warmRenderCounters.cacheHitCount - coldRenderCounters.cacheHitCount)
        self.warmCacheMissCount = max(0, warmRenderCounters.cacheMissCount - coldRenderCounters.cacheMissCount)
        self.layoutCount = max(0, layoutRenderCounters.layoutCount - warmRenderCounters.layoutCount)
        self.layoutCacheHitCount = max(0, layoutRenderCounters.cacheHitCount - warmRenderCounters.cacheHitCount)
        self.layoutCacheMissCount = max(0, layoutRenderCounters.cacheMissCount - warmRenderCounters.cacheMissCount)
        self.sections = DocumentSection.sections(in: snapshot)
        self.sourceByteCount = stream.sourceLength
        self.blockCount = snapshot.blocks.count
        self.sectionCount = sections.count
        self.tableCount = snapshot.blocks.filter { $0.kind == .table }.count
        self.codeBlockCount = snapshot.blocks.filter { $0.kind == .codeBlock }.count
        self.listBlockCount = snapshot.blocks.filter { $0.kind == .unorderedList || $0.kind == .orderedList || $0.kind == .taskList }.count
        self.quoteBlockCount = snapshot.blocks.filter { $0.kind == .blockQuote }.count
        self.mathBlockCount = snapshot.blocks.filter { $0.kind == .mathBlock }.count
    }

    private static func exerciseLayoutCache(in preparedSnapshot: MarkdownPreparedSnapshot) {
        for inlineLayout in inlineLayouts(in: preparedSnapshot) {
            _ = inlineLayout.layout(containerWidth: 360)
            _ = inlineLayout.layout(containerWidth: 360)
            _ = inlineLayout.layout(containerWidth: 640)
        }
    }

    private static func inlineLayouts(in preparedSnapshot: MarkdownPreparedSnapshot) -> [MarkdownPreparedInlineContent] {
        var layouts: [MarkdownPreparedInlineContent] = []
        for item in preparedSnapshot.items {
            guard case let .block(_, content) = item else {
                continue
            }
            appendInlineLayouts(from: content, to: &layouts)
        }
        return layouts
    }

    private static func appendInlineLayouts(
        from content: MarkdownPreparedBlockContent,
        to layouts: inout [MarkdownPreparedInlineContent]
    ) {
        if let inlineLayout = content.inlineLayout {
            layouts.append(inlineLayout)
        }

        for item in content.listItems {
            appendInlineLayouts(from: item, to: &layouts)
        }

        if let table = content.table {
            for cell in table.header {
                if let inlineLayout = cell.inlineLayout {
                    layouts.append(inlineLayout)
                }
            }
            for cell in table.rows.flatMap(\.cells) {
                if let inlineLayout = cell.inlineLayout {
                    layouts.append(inlineLayout)
                }
            }
        }
    }

    private static func appendInlineLayouts(
        from item: MarkdownPreparedListItem,
        to layouts: inout [MarkdownPreparedInlineContent]
    ) {
        if let inlineLayout = item.inlineLayout {
            layouts.append(inlineLayout)
        }
        for child in item.childItems {
            appendInlineLayouts(from: child, to: &layouts)
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
            let title = headingText.isEmpty ? "Section" : headingText
            return DocumentSection(
                id: block.id,
                title: title,
                systemImage: systemImage(for: title)
            )
        }
    }

    private static func systemImage(for title: String) -> String {
        switch title {
        case "Overview":
            return "doc.richtext"
        case "Inline Policy Matrix":
            return "link.badge.plus"
        case "Table Stress":
            return "tablecells"
        case "Wide Blocks":
            return "rectangle.expand.vertical"
        case "Multilingual Layout":
            return "character.book.closed"
        case "Math And HTML Policy":
            return "function"
        case "Long Document":
            return "text.alignleft"
        case "Big Cached Document":
            return "externaldrive.badge.checkmark"
        default:
            return "text.justify.leading"
        }
    }
}

private struct MarkdownExample: Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var detail: String
    var systemImage: String
    var badge: String
    var markdown: String
    var assertions: [String]

    static let allCases: [MarkdownExample] = [
        MarkdownExample(
            id: "overview",
            title: "Overview",
            summary: "The renderer contract in one representative document.",
            detail: "A compact end-to-end sample showing paragraphs, headings, task lists, quotes, code, a table, and a safe link through the public document renderer.",
            systemImage: "doc.richtext",
            badge: "Document",
            markdown: """
            # Overview

            SiriusMarkdown renders native SwiftUI documents from prepared snapshots. The demo app intentionally uses the same public renderer path a host app would use, including inline math like $x^2 \\rightarrow y_1 + \\alpha$.

            $$
            widthChange \\rightarrow layout(preparedSegments, width)
            $$

            - [x] Parse semantics with `swift-markdown`
            - [x] Prepare inline content before SwiftUI evaluates document rows
            - [x] Keep table, list, quote, and code rendering structured
            - [ ] Expand host-specific polish outside the package surface

            > Width changes should be cheap layout work, not parser work.

            ```swift
            var stream = MarkdownStream()
            stream.append(markdown)
            stream.finish()

            let configuration = MarkdownRendererConfiguration.document
            let prepared = configuration.prepare(snapshot: stream.snapshot())
            MarkdownDocumentView(preparedSnapshot: prepared, configuration: configuration)
            ```

            | Area | Contract |
            | :--- | :--- |
            | Parser | `swift-markdown` owns semantics |
            | Stream | immutable sealed regions plus one mutable tail |
            | SwiftUI | renders prepared snapshots |
            | Policy | safe defaults, host-controlled expansion |

            [Swift Markdown](https://github.com/swiftlang/swift-markdown)
            """,
            assertions: [
                "The demo goes through MarkdownStream and MarkdownDocumentView.",
                "Code and tables use shared renderer blocks.",
                "Task list markers come from parsed Markdown semantics."
            ]
        ),
        MarkdownExample(
            id: "inline-policy",
            title: "Inline Policy Matrix",
            summary: "Links, images, emphasis, code, and policy denial in one run.",
            detail: "This case stresses inline conversion and default policy behavior without adding app-private routing or network image loading.",
            systemImage: "link.badge.plus",
            badge: "Policy",
            markdown: """
            # Inline Policy Matrix

            A single paragraph can mix **strong text**, *emphasis*, ~~strikethrough~~, `inline code`, a [safe HTTPS link](https://example.com/safe), a [relative link](/docs/local), and an unsafe [JavaScript link](javascript:alert('blocked')).

            The default image policy keeps remote images inert: ![Remote dashboard](https://example.com/dashboard.png)

            Autolinks such as <https://example.com/autolink> remain link-shaped while unsafe schemes stay blocked.

            ## Dense Inline Run

            Prepared inline content should preserve semantic boundaries across wrapped lines: `cacheKey` combines source range, content hash, font traits, and policy-relevant inputs while **bold**, *italic*, and `code spans` remain visually distinct.

            | Destination | Default Behavior | Reason |
            | :--- | :--- | :--- |
            | `https://example.com` | allowed | safe web scheme |
            | `/docs/local` | allowed | relative app URL |
            | `javascript:alert(1)` | inert | unsafe scheme |
            | remote image URL | placeholder only | no network fetch by default |
            """,
            assertions: [
                "Safe links remain interactive through the policy hook.",
                "Unsafe JavaScript links do not become active URLs.",
                "Remote image markdown does not fetch network data by default."
            ]
        ),
        MarkdownExample(
            id: "tables",
            title: "Table Stress",
            summary: "Dense Markdown tables with alignment and long cells.",
            detail: "Tables are first-class renderer output, so this case focuses on visual identity, stable row sizing, and horizontal containment.",
            systemImage: "tablecells",
            badge: "Tables",
            markdown: """
            # Table Stress

            Tables matter in AI, docs, reports, and operational transcripts. The renderer should make them visually distinguishable without turning the whole document into a spreadsheet.

            | Scenario | Input Shape | Renderer Requirement | Evidence |
            | :--- | :--- | :--- | :--- |
            | Short comparison | two or three compact columns | quiet header, stable row height | prepared table cells |
            | Dense status table | many rows with repeated labels | separators and banding support scanning | row source IDs |
            | Long explanation | a wide final column with technical prose | horizontal containment instead of window growth | measured natural widths |
            | Multilingual values | 日本語, 한국어, العربية, emoji 😀 | CoreText-backed measurement remains stable | prepared inline layout |

            | Metric | Current Contract | Failure Avoided |
            | :--- | :--- | :--- |
            | Parse count | one finished document parse | full reparse from SwiftUI body |
            | Table identity | row and cell source ranges | offset-based churn |
            | Resize behavior | cheap layout over prepared segments | intrinsic-width feedback collapse |

            Text after the table should keep normal document rhythm and must not be pushed into an awkward narrow column.
            """,
            assertions: [
                "Tables use native MarkdownBlockView rendering.",
                "Header accent and row separators come from MarkdownTheme tokens.",
                "Wide cells remain inside horizontal table containment."
            ]
        ),
        MarkdownExample(
            id: "wide-blocks",
            title: "Wide Blocks",
            summary: "Long code and wide rows stay contained.",
            detail: "This sample catches the layout failures that make document windows expand or rows collapse when code and tables are wider than the readable measure.",
            systemImage: "rectangle.expand.vertical",
            badge: "Overflow",
            markdown: """
            # Wide Blocks

            Wide code should remain inspectable without forcing the entire document surface to grow.

            ```json
            {"renderer":"SiriusMarkdown","mode":"document","features":["native-swiftui","streaming-aware","prepared-inline-layout","bounded-caches","policy-hooks","host-boundaries"],"longValue":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}
            ```

            ```swift
            let widthChange = "compact -> readable -> wide -> split view"
            let invariant = "layout(preparedSegments, width) must not call parse(markdown)"
            print(widthChange, invariant)
            ```

            | Case | Long Value |
            | :--- | :--- |
            | Cache key | sourceRange + contentHash + rendererConfiguration + theme font traits + policy-relevant inputs |
            | Resize path | cheap layout over prepared segments without parsing, highlighting, or AST conversion |
            | Render path | structured block views consume already prepared table cells, code text, math, and inline runs |
            """,
            assertions: [
                "Code blocks expose horizontal scrolling.",
                "Wide tables stay contained inside the document surface.",
                "The window width remains stable while content overflows internally."
            ]
        ),
        MarkdownExample(
            id: "multilingual",
            title: "Multilingual Layout",
            summary: "CJK, RTL, emoji, hard breaks, and inline code.",
            detail: "This document exercises the text shaping and wrapping cases that are easy to regress when the renderer falls back to naive string measurement.",
            systemImage: "character.book.closed",
            badge: "Layout",
            markdown: """
            # Multilingual Layout

            English, 日本語, 한국어, العربية, עברית, emoji 😀😎🚀, and CJK punctuation should all remain in one prepared document without parser-time special cases.

            Mixed direction text should wrap as a normal paragraph: Start with English, continue with العربية داخل الجملة, then return to English with `inline code` and a safe [reference](https://example.com/i18n).

            Hard line breaks stay visible after preparation: first line\\
            second line after a Markdown hard break.

            - 日本語 item with `code`
            - العربية داخل عنصر قائمة
            - Emoji sequence 😀 😎 🚀 inside a list item

            | Region | Text | Renderer Concern |
            | :--- | :--- | :--- |
            | CJK | 日本語 and 한국어 | glyph measurement and line breaks |
            | RTL | العربية داخل الجملة | bidirectional shaping |
            | Emoji | 😀 😎 🚀 | cached segment widths |
            """,
            assertions: [
                "CJK and RTL are measured in the prepared inline path.",
                "Hard breaks survive rendering.",
                "Emoji does not destabilize line sizing."
            ]
        ),
        MarkdownExample(
            id: "math-html",
            title: "Math And HTML Policy",
            summary: "Math hooks and inert raw HTML in the default public package.",
            detail: "This sample shows math flowing through renderer hooks while raw HTML remains governed by the default policy.",
            systemImage: "function",
            badge: "Hooks",
            markdown: """
            # Math And HTML Policy

            Math blocks are renderer hooks, not hardcoded app-private UI:

            $$
            widthChange \\rightarrow layout(preparedSegments, width)
            $$

            Inline math-like text can remain ordinary Markdown when no math policy claims it: `f(x) = x^2 + 1`.

            $$
            parseCount(document) = sealedRegions + activeTail
            $$

            <aside>Raw HTML remains inert by default.</aside>

            | Surface | Default |
            | :--- | :--- |
            | Math block | rendered by configured math renderer |
            | Raw HTML | denied or inert unless policy allows it |
            | Code | plain safe text unless highlighter is supplied |
            """,
            assertions: [
                "Math rendering is pluggable.",
                "Raw HTML stays controlled by MarkdownHTMLPolicy.",
                "Code highlighting remains optional."
            ]
        ),
        MarkdownExample(
            id: "long-document",
            title: "Long Document",
            summary: "A denser prose document with nested structure.",
            detail: "This case gives the static demo a fuller document workload with long paragraphs, nested lists, quotes, tables, and repeated section rhythm.",
            systemImage: "text.alignleft",
            badge: "Long Form",
            markdown: """
            # Long Document

            SiriusMarkdown needs to feel at home in technical documents, not only short chat snippets. This sample uses longer paragraphs and repeated structure so the renderer has to maintain readable rhythm across a full page.

            ## Renderer Priorities

            The renderer is native SwiftUI, but semantics come from `swift-markdown`. The view layer should receive prepared value models, render structured blocks, and avoid doing expensive interpretation while SwiftUI is asking for body values.

            - Preserve semantic structure from the parser
              - headings
              - paragraphs
              - ordered and unordered lists
              - tables and code blocks
            - Keep policies explicit
              - links
              - images
              - raw HTML
              - math and code hooks

            > The static app is a product surface for the package. It should look like a serious renderer demo, not a throwaway smoke test.

            ## Cache Evidence

            Preparing a document should populate reusable inline and render outputs once. A warm pass over the same snapshot should report cache hits without increasing expensive inline preparation, highlighting, or math rendering. Repeated width-specific layout should reuse cached line records over already measured inline content.

            ```swift
            let first = configuration.prepare(snapshot: snapshot)
            let warm = configuration.prepare(snapshot: snapshot)
            assert(first.preparedContentByBlockID.keys == warm.preparedContentByBlockID.keys)

            _ = inline.layout(containerWidth: 360)
            _ = inline.layout(containerWidth: 360)
            _ = inline.layout(containerWidth: 640)
            ```

            ```json
            {"cache":"highlighted-code","state":"reused","surface":"MarkdownRenderPreparationCache"}
            ```

            $$
            warmCacheHits > 0
            $$

            | Evidence | Key Inputs | Demonstrated By |
            | :--- | :--- | :--- |
            | Prepared inline | source range, content hash, theme traits | wrapped paragraphs and table cells |
            | Highlighted code | source range, info string, highlighter | fenced Swift and JSON blocks |
            | Math render | source range and math renderer | formula block |
            | Measured layout | width and prepared segments | repeated compact/readable/wide layout probes |

            ## Closing Section

            The demo should make package behavior obvious: native structure, safe defaults, polished tables, contained wide content, and instrumentation close enough to prove the pipeline is doing the right work.
            """,
            assertions: [
                "Long prose remains readable in the document surface.",
                "Nested lists render through structured list models.",
                "Warm cache hits are measured from the shared renderer path."
            ]
        ),
        MarkdownExample(
            id: "big-cached-document",
            title: "Big Cached Document",
            summary: "A generated large document prepared cold, warmed, and layout-probed.",
            detail: "This case stresses a large static document with repeated sections, tables, code, math, multilingual text, and warm-cache evidence from the same public renderer path.",
            systemImage: "externaldrive.badge.checkmark",
            badge: "Cache Stress",
            markdown: MarkdownExample.bigCachedDocumentMarkdown(sectionCount: 96),
            assertions: [
                "The document is generated as one large source and prepared through MarkdownRenderPreparationCache.",
                "A warm pass over the same snapshot records cache hits.",
                "Repeated layout probes exercise prepared inline layout at multiple widths."
            ]
        )
    ]

    private static func bigCachedDocumentMarkdown(sectionCount: Int) -> String {
        var parts: [String] = [
            """
            # Big Cached Document

            This generated document exists to make cache behavior visible at product scale. It repeats enough structure to exercise parser identity, prepared inline caching, highlighted code reuse, math rendering, table cell preparation, and width-specific layout caches.

            $$
            cachedDocument = prepare(snapshot) + warmPrepare(snapshot) + layout(widths)
            $$

            | Surface | Stress Shape | Expected Behavior |
            | :--- | :--- | :--- |
            | Paragraphs | repeated long prose | prepared inline content is reused |
            | Tables | recurring dense rows | cell layout stays bounded |
            | Code | repeated fenced blocks | highlighted code cache records reuse |
            | Math | repeated formula blocks | renderer cache records reuse |
            """
        ]

        for index in 1...sectionCount {
            parts.append(bigCachedSection(index))
        }

        parts.append(
            """
            ## Cache Summary

            A large cached document should not feel like a special mode. It should use the same public configuration, policies, copy provider, theme, prepared snapshot, and native SwiftUI block renderers as every other document in this package.
            """
        )

        return parts.joined(separator: "\n\n")
    }

    private static func bigCachedSection(_ index: Int) -> String {
        var parts: [String] = [
            """
            ## Cached Section \(index)

            Section \(index) repeats a realistic document rhythm: a long paragraph with **strong text**, *emphasis*, `inline code`, a safe [reference link](https://example.com/cache/\(index)), inline math $x_\(index)^2 + y_\(index)$, and mixed-script text with 日本語, العربية, עברית, and emoji 😀. The goal is not novel prose; it is stable renderer pressure across many prepared blocks.

            - [x] Preserve block identity for generated section \(index)
            - [x] Keep inline preparation outside SwiftUI body
            - [x] Reuse prepared line layout when width changes
            - [ ] Add host-specific product affordances outside the package
            """
        ]

        if index.isMultiple(of: 4) {
            parts.append(
                """
                | Metric | Section \(index) Value | Renderer Concern |
                | :--- | :--- | :--- |
                | Cache namespace | `section-\(index)` | stable keys |
                | Paragraph width | compact/readable/wide | cheap relayout |
                | Scripts | 日本語 / العربية / emoji 😀 | measured inline segments |
                """
            )
        }

        if index.isMultiple(of: 6) {
            parts.append(
                """
                ```swift
                let sectionIndex = \(index)
                let cacheKey = "section-\\(sectionIndex)-prepared-inline"
                let widthPasses = [320, 520, 760]
                ```
                """
            )
        }

        if index.isMultiple(of: 9) {
            parts.append(
                """
                $$
                layout_\(index)(w) = preparedSegments_\(index) \\rightarrow lines(w)
                $$
                """
            )
        }

        if index.isMultiple(of: 13) {
            parts.append(
                """
                > Section \(index) also includes a quote so repeated blockquote styling and source-backed copy ranges stay in the stress path.
                """
            )
        }

        return parts.joined(separator: "\n\n")
    }
}

private enum DemoColors {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let documentBackground = Color(nsColor: .textBackgroundColor)
    static let inspectorBackground = Color(nsColor: .controlBackgroundColor)
    static let pageStroke = Color(nsColor: .separatorColor).opacity(0.45)
}
