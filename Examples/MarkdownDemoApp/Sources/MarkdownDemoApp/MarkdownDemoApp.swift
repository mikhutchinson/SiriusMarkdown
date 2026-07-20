import DemoSupport
import Foundation
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
    @Published var selectedExampleID: MarkdownExample.ID {
        didSet {
            guard selectedExampleID != oldValue else { return }
            renderSelectedExample()
        }
    }

    let examples: [PreparedMarkdownExample]
    let renderSession: MarkdownRenderSession

    init() {
        let examples = MarkdownExample.allCases.map(PreparedMarkdownExample.init(example:))
        let firstExample = examples[0]
        self.examples = examples
        self.renderSession = MarkdownRenderSession(configuration: firstExample.configuration)
        self.selectedExampleID = firstExample.id
        renderSession.append(firstExample.example.markdown)
        renderSession.finish()
    }

    var selectedExample: PreparedMarkdownExample {
        examples.first { $0.id == selectedExampleID } ?? examples[0]
    }

    private func renderSelectedExample() {
        renderSession.reset()
        renderSession.append(selectedExample.example.markdown)
        renderSession.finish()
    }
}

private struct MarkdownDemoView: View {
    @StateObject private var model = MarkdownDemoModel()

    var body: some View {
        NavigationSplitView {
            MarkdownDemoSidebar(model: model)
        } detail: {
            MarkdownExampleDetail(
                example: model.selectedExample,
                renderSession: model.renderSession
            )
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
                    DemoSidebarRow(
                        title: example.title,
                        subtitle: example.summary,
                        systemImage: example.systemImage,
                        isSelected: model.selectedExampleID == example.id
                    ) {
                        model.selectedExampleID = example.id
                    }
                }
            }

            Section("Selected Document") {
                DemoMetricRow(title: "Source bytes", value: model.selectedExample.sourceByteCount.formatted())
                DemoMetricRow(title: "Blocks", value: model.selectedExample.blockCount.formatted())
                DemoMetricRow(title: "Headings", value: model.selectedExample.sectionCount.formatted())
                DemoMetricRow(title: "Tables", value: model.selectedExample.tableCount.formatted())
                DemoMetricRow(title: "Code blocks", value: model.selectedExample.codeBlockCount.formatted())
                if model.selectedExample.richHTMLBlockCount > 0 {
                    DemoMetricRow(title: "HTML nodes", value: model.selectedExample.htmlParsedNodeCount.formatted())
                    DemoMetricRow(title: "HTML dropped", value: model.selectedExample.htmlDroppedNodeCount.formatted())
                }
            }

            Section("Renderer Counters") {
                DemoMetricRow(title: "Parses", value: model.selectedExample.streamCounters.parseCount.formatted())
                DemoMetricRow(title: "Prepared blocks", value: model.selectedExample.renderCounters.renderPreparationCount.formatted())
                DemoMetricRow(title: "Inline prepares", value: model.selectedExample.renderCounters.prepareCount.formatted())
                DemoMetricRow(title: "Cache hits", value: model.selectedExample.cacheHitCount.formatted())
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        .navigationTitle("Markdown Demo")
    }
}

private struct MarkdownExampleDetail: View {
    var example: PreparedMarkdownExample
    @ObservedObject var renderSession: MarkdownRenderSession
    @State private var showsInspector = false

    var body: some View {
        ZStack {
            DemoColors.windowBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(example: example, showsInspector: $showsInspector)

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
            VStack(alignment: .leading, spacing: 16) {
                DemoAssertionStrip(assertions: example.assertions)
                HStack(alignment: .top, spacing: 24) {
                    DocumentSurface(example: example, renderSession: renderSession)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if showsInspector {
                        DocumentInspectorPanel(example: example)
                            .frame(width: 300)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                DemoAssertionStrip(assertions: example.assertions)
                DocumentSurface(example: example, renderSession: renderSession)
                if showsInspector {
                    DocumentInspectorPanel(example: example)
                }
            }
        }
    }
}

private struct DetailHeader: View {
    var example: PreparedMarkdownExample
    @Binding var showsInspector: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(example.title, systemImage: example.systemImage)
                    .font(.title2.weight(.semibold))

                Spacer()

                DemoAffordanceBar {
                    DemoIconButton(
                        title: showsInspector ? "Hide diagnostics" : "Show diagnostics",
                        systemImage: "sidebar.right",
                        isActive: showsInspector
                    ) {
                        showsInspector.toggle()
                    }

                    DemoStatusPill(text: example.badge)
                }
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
    @ObservedObject var renderSession: MarkdownRenderSession

    var body: some View {
        MarkdownDocumentSurface(
            title: "Rendered Document",
            subtitle: "\(example.blockCount.formatted()) blocks prepared through the public render session.",
            suggestedFilename: "\(example.id).md",
            preparedSnapshot: renderSession.preparedSnapshot,
            configuration: renderSession.configuration
        )
        .id(example.id)
        .frame(maxWidth: 920, alignment: .leading)
    }
}

private struct DocumentInspectorPanel: View {
    var example: PreparedMarkdownExample

    var body: some View {
        DemoInspectorPanel {
            DemoInspectorSection(title: "Coverage") {
                DemoMetricGrid(
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

            DemoInspectorSection(title: "Pipeline") {
                DemoMetricGrid(
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

            if example.richHTMLBlockCount > 0 {
                DemoInspectorSection(title: "Native HTML") {
                    DemoMetricGrid(
                        metrics: [
                            ("HTML blocks", example.richHTMLBlockCount.formatted()),
                            ("Nodes", example.htmlParsedNodeCount.formatted()),
                            ("Dropped", example.htmlDroppedNodeCount.formatted()),
                            ("Unwrapped", example.htmlUnwrappedNodeCount.formatted()),
                            ("Map fallback", example.htmlSourceMappingFallbackCount.formatted())
                        ]
                    )
                }
            }

            DemoInspectorSection(title: "Sections") {
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
    let richHTMLBlockCount: Int
    let htmlParsedNodeCount: Int
    let htmlDroppedNodeCount: Int
    let htmlUnwrappedNodeCount: Int
    let htmlSourceMappingFallbackCount: Int

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
            imagePolicy: DemoNativeHTMLImagePolicy(),
            imageResolver: DemoNativeHTMLImageResolver(),
            mathRenderer: NativeMarkdownMathRenderer(),
            diagnosticsRecorder: renderRecorder
        )
        let snapshot = stream.snapshot()
        let renderedBlocks = snapshot.blocks.flatMap(\.demoRenderedBlocks)
        let richHTML = snapshot.blocks.compactMap(\.richContent)

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
        self.blockCount = renderedBlocks.count
        self.sectionCount = sections.count
        self.tableCount = renderedBlocks.filter { $0.kind == .table }.count
        self.codeBlockCount = renderedBlocks.filter { $0.kind == .codeBlock }.count
        self.listBlockCount = renderedBlocks.filter { $0.kind == .unorderedList || $0.kind == .orderedList || $0.kind == .taskList }.count
        self.quoteBlockCount = renderedBlocks.filter { $0.kind == .blockQuote }.count
        self.mathBlockCount = renderedBlocks.filter { $0.kind == .mathBlock }.count
        self.richHTMLBlockCount = richHTML.count
        self.htmlParsedNodeCount = richHTML.reduce(0) { $0 + $1.diagnostics.parsedNodeCount }
        self.htmlDroppedNodeCount = richHTML.reduce(0) { $0 + $1.diagnostics.droppedNodeCount }
        self.htmlUnwrappedNodeCount = richHTML.reduce(0) { $0 + $1.diagnostics.unwrappedNodeCount }
        self.htmlSourceMappingFallbackCount = richHTML.reduce(0) { $0 + $1.diagnostics.sourceMappingFallbackCount }
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
        snapshot.blocks.flatMap(\.demoRenderedBlocks).compactMap { block in
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
        case "Dense Inline Run":
            return "link.badge.plus"
        case "Renderer Priorities":
            return "text.alignleft"
        case "Cache Evidence":
            return "externaldrive.badge.checkmark"
        case "Closing Section":
            return "text.justify.leading"
        case "Cache Summary":
            return "externaldrive.badge.checkmark"
        default:
            return "text.justify.leading"
        }
    }
}

private extension MarkdownBlock {
    var demoRenderedBlocks: [MarkdownBlock] {
        guard let richContent else {
            return [self]
        }
        return richContent.blocks.flatMap(\.demoRenderedBlocks)
    }
}

private struct DemoNativeHTMLImagePolicy:
    MarkdownImagePolicy,
    MarkdownImagePolicyCacheIdentifying
{
    static let approvedSource = "sirius-demo://native-html/approved-swatch"

    var imagePolicyCacheIdentity: String {
        "markdown-demo.native-html-image-policy.v1"
    }

    func evaluateImage(source: String, altText: String?) -> MarkdownPolicyDecision {
        if source == Self.approvedSource {
            return .allow
        }
        return DefaultMarkdownPolicy().evaluateImage(source: source, altText: altText)
    }
}

private struct DemoNativeHTMLImageResolver:
    MarkdownImageResolver,
    MarkdownImageResolverCacheIdentifying
{
    private static let nativeHTMLBadgePNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAMKADAAQAAAABAAAAMAAAAAD4/042AAAE/klEQVRoBe1aa2wUVRT+ZvZZKzUu8cG2EmsRpDXRYH0B4qskCsHUtol/8I+Y8sfEP5TQ/iLRRBGjSY1GiYlRI5LQIBokGDHUqliSShBF02qzpNhiIkRait3HPDx3Zu7OzHam05bZZSfhJts7c+89537fueece7t3gYAXwRV/+0CkesmyZhVCM1Q0AkJSEHCt63gfO1QVk4A6BgEDAtT9o38O7seuxpzTFI4EFr0y8bQYCu0kgTonoSvQNqzIcsfZzqrPCucO2Rq2bxeTTx7YIYpiN7UnbH1X9iUhiOIzC5q6Ki+ujn6D3l6VwxH5A6uTFVteFQShw9pWTs8MG8NoxZR3IcNt9lk7y/WZ3KmFu5O+AhSwhs+XK2YbLg0rYWaNGgGWbei5XALWBtblpc7ArBPQUqXLyHJt5ph1F9LyfLlCdcFlYDaykJB0GVbGzTpmjUCpdlg/rcExGyvgp+rS6rpKoLT2nj5beHqT/y2isd/TKZMOtv6WohOoSwj4dlOFhnoio6Khe8pXEkWPgdYG00bHxxRfwTOrFJ1Ay3LzxN5zSvLXfy6XQJSw3VftboMHakTUXKf3T2ZVHPpDzhOopKPYikXusvmBHg/z0sBisrU+hL5NcXzcFnOdou1O032+HJSRtizAysUhfLExjo9aY1h+Q/5U76rLrcOcwW1EQfujtSI610RRf6PO/RJZ1qnESfP6pab77P3Vgt4i8NhtITxSG8e+32Ts/D6H0QlnfRYR2+OsCdx9s4iuhyNglptNWVsXwoKYbtkz4wr6/1JcxUQ6F7RRsG9YFsKHJyR0/5jDhbTrcFuHpwvVXi/gvaeiOPBs3AZeoaR+cEjCxp6MTSF/sWYfZt3C0ndaxtavMhg6ZxKLhQW0N0ZwtL0CL9wfBltFr+I55N0NMTTcZPK8SLn8018kfHBcwplx5+VeeA3ILUyZHgf3yRCn3Sdl7bPmVhHP3xMBc0/6vxdVtHLbyE2zNGbXgLPrcWKeBPhAXu/4LodPfpaQMw3Hu/J18x1hhI3t96cxGakLzkS5QN9pBYP/ZPFSUwTrls4Nkmkmrq2gHjpvR/pyUxTHNlfgxQfDSOgbbIEEZSjL5tVzarr7WAXuoth6a30U/ZvjNvAZScWIywpb5bUoq37t0owmWrVYRMfqCBqr7QGcpklYdun82vzS7PaFAo48pzNjIFa8M4VxhzBhsfXGE1HcW2PXmZVV7DlJgdwv4e/JGWFhdGul4LkCjO0PIwqad2coYNM4cda0aJyCrqXevuStlvfDw7IjeKZzSUK0gZcUleJBwkPvp9F1OOcJnulgxT673ub6tzeloDeVQROlyI5VEVtwc6EW2uB48XIfNk4m4CxLvXk0NyuX4bp5PScCXIhZln3W0Ub1OG1EvKy8RUSySl/U8/+pOJIyV4uP4fUI7Q17KJu9fSyH1L8zuwqXcarnRYArOjgk015ggrQG7+e/S5Ds8c/FtHrwnIoth7K2tvm8XBaBwgnZ2X88rVtzr0f2KZSd77uvBFigl7rMKguVGtRc5rtKYC7WKsZYbQX0O6liqC+eTo7ZcCG6UAtc0THrBOg2MHD4DcwaAXaVGTQCHLNGQLuHBYYDRGLYwGx8L0SXyOweNigENKzGxbcRxAC79VNVlV1ul3VhGPkNJQOaJ8BexqZe31bOJBg2hpFh5cXxG6Ug/dTAkYDGLiA/9uArEdj6f4R+o6WYnuwsAAAAAElFTkSuQmCC"
    )!

    var imageResolverCacheIdentity: String {
        "markdown-demo.native-html-image-resolver.v1"
    }

    func preparedImage(
        source: String,
        altText: String?,
        sourceRange: MarkdownSourceRange?,
        policyDecision: MarkdownPolicyDecision
    ) -> MarkdownPreparedImage {
        precondition(source == DemoNativeHTMLImagePolicy.approvedSource)
        precondition(policyDecision == .allow)
        return MarkdownPreparedImage(
            source: source,
            altText: altText,
            sourceRange: sourceRange,
            preparedSource: .data(Self.nativeHTMLBadgePNG, mimeType: "image/png")
        )
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

            ```mermaid
            graph LR
                A[Source] --> B[Stream]
                B --> C[Snapshot]
                C --> D[Prepare]
                D --> E[Render]
            ```

            [Swift Markdown](https://github.com/swiftlang/swift-markdown)
            """,
            assertions: [
                "The demo goes through MarkdownStream and MarkdownDocumentView.",
                "Code and tables use shared renderer blocks.",
                "Task list markers come from parsed Markdown semantics."
            ]
        ),
        MarkdownExample(
            id: "native-rich-html",
            title: "Native Rich HTML",
            summary: "Sanitized HTML5 rendered as native headings, prose, lists, tables, code, and decorated links.",
            detail: "A dedicated HTML document proves that authorized markup becomes source-mapped native renderer models—not a WebView, raw tags, or a code block.",
            systemImage: "chevron.left.forwardslash.chevron.right",
            badge: "Native HTML",
            markdown: """
            <div>
              <h2>Quarterly filing snapshot</h2>
              <p><strong>Revenue reached $3,233 million</strong>, including <em>$724 million</em> from related parties. The filing presents the figures through the same native inline pipeline used by Markdown.</p>
              <p>Source trail: <a href="https://www.sec.gov/">SEC filing</a>, <a href="https://find-and-update.company-information.service.gov.uk/">Companies House</a>, <a href="https://github.com/">GitHub</a>, <a href="https://www.wikipedia.org/">Wikipedia</a>, and <a href="https://openai.com/">OpenAI</a>.</p>
              <blockquote><p>These anchors keep one activation and accessibility range while their prepared glyphs can upgrade asynchronously to site icons.</p></blockquote>
              <h3>Native inline semantics</h3>
              <p><b>Bold</b>, <i>italic</i>, <s>superseded</s>, <code>inline code</code>, H<sub>2</sub>O, x<sup>2</sup>, and an explicit<br>line break all remain semantic.</p>
              <ol start="3"><li>HTML5 recovery normalizes authored structure.</li><li>Sanitization removes active content before preparation.</li><li>SwiftUI receives prepared native models only.</li></ol>
              <table><thead><tr><th align="left">Input</th><th align="left">Native result</th></tr></thead><tbody><tr><td>Heading and paragraph tags</td><td>Structured document blocks</td></tr><tr><td>Anchor tags</td><td>Policy-checked decorated links</td></tr><tr><td>Table tags</td><td>Contained native table layout</td></tr></tbody></table>
              <pre><code class="language-swift">let prepared = configuration.prepare(snapshot: stream.snapshot())</code></pre>
              <hr>
              <p><a href="javascript:alert('blocked')">Unsafe JavaScript link</a> and <img src="https://example.com/remote.png" alt="remote image denied by default"> remain governed by normal link and image policies.</p>
              <script>document.body.innerHTML = "This must never execute or appear"</script>
            </div>
            """,
            assertions: [
                "Supported HTML renders as native structured content; source tags never become the successful presentation.",
                "HTML anchors share Markdown's policy, activation, accessibility, glyph, and runtime favicon pipeline.",
                "Script content, event-capable behavior, unsafe links, and implicit remote images stay inert.",
                "Parsing, sanitization, resource resolution, and measurement remain outside SwiftUI body evaluation."
            ]
        ),
        MarkdownExample(
            id: "native-html-elements",
            title: "HTML Element Gallery",
            summary: "Every supported native HTML element and alias in one scrollable reference page.",
            detail: "This exhaustive gallery renders the complete documented subset, including a policy-approved in-memory image attachment and a denied remote image.",
            systemImage: "textformat.alt",
            badge: "All Elements",
            markdown: """
            <div>
              <h1>Heading level 1</h1>
              <h2>Heading level 2</h2>
              <h3>Heading level 3</h3>
              <h4>Heading level 4</h4>
              <h5>Heading level 5</h5>
              <h6>Heading level 6</h6>
              <p><span>A neutral span stays native text.</span> Paragraph and div containers establish document structure without browser layout.</p>
              <p><strong>strong</strong> and <b>b</b> are bold; <em>em</em> and <i>i</i> are italic; <s>s</s> and <del>del</del> are struck; <code>code</code> is monospaced.</p>
              <p>Subscript H<sub>2</sub>O and superscript x<sup>2</sup> preserve baseline semantics.<br>A br element creates this explicit second line.</p>
              <p>HTML anchors share decorated-link preparation: <a href="https://developer.apple.com/">Apple Developer</a> and <a href="https://www.w3.org/">W3C</a>.</p>
              <blockquote><p>Blockquote content uses the package's native quote style, source mapping, selection, and copy behavior.</p></blockquote>
              <ul><li>Unordered list item</li><li>Nested structure<ul><li>Nested unordered child</li></ul></li></ul>
              <ol start="7"><li>Ordered list begins at seven</li><li>Second ordered item</li></ol>
              <table><thead><tr><th align="left">Left</th><th align="center">Center</th><th align="right">Right</th></tr></thead><tbody><tr><td>thead/th</td><td>tbody/tr</td><td>td</td></tr><tr><td>Native</td><td>Contained</td><td>Aligned</td></tr></tbody></table>
              <pre><code class="language-swift">let html = sanitize(source)
            let nativeBlocks = prepare(html)</code></pre>
              <hr>
              <p>Policy-approved in-memory img → <img src="sirius-demo://native-html/approved-swatch" alt="approved native badge"> ← native atomic attachment.</p>
              <p>Default remote-image denial remains textual and performs no fetch: <img src="https://example.com/remote-image.png" alt="remote image denied by default"></p>
            </div>
            """,
            assertions: [
                "h1 through h6 render as native heading levels.",
                "Every documented inline semantic and alias uses prepared native text.",
                "Paragraphs, containers, quotes, both list types, tables, code, and hr use structured block renderers.",
                "The demo-only allowlist supplies one local data image; ordinary remote images remain denied without a network request."
            ]
        ),
        MarkdownExample(
            id: "native-html-safety",
            title: "HTML Safety And Media",
            summary: "Active content and unsupported media are dropped while safe descendants and policy fallbacks remain.",
            detail: "The source deliberately contains scripts, styles, embeds, browser media, controls, executable attributes, unsafe URLs, and a remote image so their inert outcomes are visible and counted.",
            systemImage: "shield.lefthalf.filled",
            badge: "Sanitized",
            markdown: """
            <div>
              <h2>Sanitizer and media boundary</h2>
              <p>Native rich HTML means document semantics, not an embedded browser. The source of this example contains every active family listed below.</p>
              <table><thead><tr><th align="left">Authored input</th><th align="left">Native outcome</th></tr></thead><tbody><tr><td><code>script / style</code></td><td>Entire subtree dropped</td></tr><tr><td><code>iframe / object / embed</code></td><td>Entire subtree dropped</td></tr><tr><td><code>video / audio / canvas / svg</code></td><td>No player, canvas, or vector DOM</td></tr><tr><td><code>form / input / button</code></td><td>Controls removed; safe descendants may remain</td></tr><tr><td><code>style / onclick / onerror</code></td><td>Attributes ignored</td></tr><tr><td><code>javascript: / remote img</code></td><td>Normal URL and image policies still apply</td></tr></tbody></table>
              <p style="color:red" onclick="SCRIPT_ATTRIBUTE_SENTINEL">Style and event-handler attributes are ignored while this safe text survives.</p>
              <form action="https://example.com/submit"><input name="secret" value="FORM_INPUT_SENTINEL"><button>FORM_BUTTON_SENTINEL</button><p>Safe form descendant text survives without controls or submission behavior.</p></form>
              <script>SCRIPT_SUBTREE_SENTINEL</script>
              <style>STYLE_SUBTREE_SENTINEL</style>
              <iframe src="https://example.com/">IFRAME_SUBTREE_SENTINEL</iframe>
              <object data="https://example.com/object">OBJECT_SUBTREE_SENTINEL</object>
              <embed src="https://example.com/embed">
              <video controls><source src="https://example.com/movie.mp4">VIDEO_SUBTREE_SENTINEL</video>
              <audio controls><source src="https://example.com/audio.mp3">AUDIO_SUBTREE_SENTINEL</audio>
              <canvas>CANVAS_SUBTREE_SENTINEL</canvas>
              <svg><text>SVG_SUBTREE_SENTINEL</text></svg>
              <p><a href="javascript:alert('blocked')">Unsafe JavaScript destination is visible but inert</a>.</p>
              <p><img src="https://example.com/tracker.png" alt="remote image denied by default" onerror="IMAGE_EVENT_SENTINEL"> No implicit image request is made.</p>
              <blockquote><p>If this closing quote is visible without any payload sentinel, native sanitization succeeded.</p></blockquote>
            </div>
            """,
            assertions: [
                "Scripts, styles, embedded browsing, plugins, browser media, canvas, SVG, and their descendant payloads never reach native render models.",
                "Form controls disappear and no submission surface exists; only explicitly safe descendant prose remains.",
                "Executable and style attributes are ignored rather than interpreted.",
                "Unsafe links are non-interactive and remote images use denied alt-text fallback without fetching."
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
            A single paragraph can mix **strong text**, *emphasis*, ~~strikethrough~~, `inline code`, a [safe HTTPS link](https://example.com/safe), a [relative link](/docs/local), and an unsafe [JavaScript link](javascript:alert('blocked')).

            The default image policy keeps remote images inert: ![Remote dashboard](https://example.com/dashboard.png)

            Autolinks such as <https://example.com/autolink> remain link-shaped while unsafe schemes stay blocked.

            Reference-style links resolve through `swift-markdown` semantics too: [defined before use][docs-ref], [defined after use][late-ref], and [**strong linked text**][strong-ref] all keep their inline presentation and destinations.

            ## Dense Inline Run

            Prepared inline content should preserve semantic boundaries across wrapped lines: `cacheKey` combines source range, content hash, font traits, and policy-relevant inputs while **bold**, *italic*, and `code spans` remain visually distinct.

            | Destination | Default Behavior | Reason |
            | :--- | :--- | :--- |
            | `https://example.com` | allowed | safe web scheme |
            | `/docs/local` | allowed | relative app URL |
            | reference definitions | resolved | parser-owned CommonMark semantics |
            | `javascript:alert(1)` | inert | unsafe scheme |
            | remote image URL | placeholder only | no network fetch by default |

            [docs-ref]: https://example.com/docs
            [late-ref]: https://example.com/reference-later
            [strong-ref]: https://example.com/strong-reference
            """,
            assertions: [
                "Safe links remain interactive through the policy hook.",
                "Reference definitions resolve without app-private link routing.",
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
            Tables matter in AI, docs, reports, and operational transcripts. The renderer should make them visually distinguishable without turning the whole document into a spreadsheet.

            | Scenario | Input Shape | Renderer Requirement | Evidence |
            | :--- | :--- | :--- | :--- |
            | Short comparison | two or three compact columns | quiet header, stable row height | prepared table cells |
            | Dense status table | many rows with repeated labels | separators and banding support scanning | row source IDs |
            | Long explanation | a wide final column with technical prose | horizontal containment instead of window growth | measured natural widths |
            | Multilingual values | 日本語, 한국어, العربية, emoji 😀 | CoreText-backed measurement remains stable | prepared inline layout |

            ## Narrow Cell Containment Regression

            This is the user-bubble stress table that caught a cached two-line row painting a third line into the following row. Resize the window and scroll horizontally: every divider must remain below all of its row's text.

            | Feature | Expected | Very long evidence column | Status |
            | --- | --- | --- | ---: |
            | Code | Horizontal containment | A deliberately long table value that must stay within the finite user bubble instead of widening the transcript | 1 |
            | HTML | Native rendering | Sanitized rich blocks and decorated links | 2 |
            | Math | Native rendering | x^2 + alpha and a display equation | 3 |

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
                "Wide cells remain inside horizontal table containment.",
                "Prepared row heights contain every wrapped line before stable row measurements are cached."
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
            id: "math-showcase",
            title: "Native LaTeX Math",
            summary: "Beautiful CoreText math typeset from LaTeX delimiters.",
            detail: "Display and inline math typeset natively through SiriusMarkdownMath — no WebView and no SVG rasterization.",
            systemImage: "x.squareroot",
            badge: "LaTeX",
            markdown: """
            SiriusMarkdown typesets LaTeX **natively** with CoreText. It understands \
            display delimiters `\\[ ... \\]`, inline delimiters `\\( ... \\)`, the TeX \
            forms `$$ ... $$` and `$ ... $`, and `\\begin{...}` environments.

            L'Hopital's rule, written with display brackets:

            \\[
            \\lim_{x \\to a} \\frac{f(x)}{g(x)} = \\lim_{x \\to a} \\frac{f'(x)}{g'(x)}
            \\]

            The quadratic formula, written with `$$`:

            $$
            x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
            $$

            A Gaussian integral keeps proper limits, radicals, and fractions:

            \\[
            \\int_{0}^{\\infty} e^{-x^2}\\, dx = \\frac{\\sqrt{\\pi}}{2}
            \\]

            Inline math flows with prose: the limit \\(\\frac{\\sin x}{x} \\to 1\\) as \
            \\(x \\to 0\\), and Euler's identity $e^{i\\pi} + 1 = 0$ stays on the line.

            Environments typeset too:

            \\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}
            """,
            assertions: [
                "Display math (\\[ \\], $$) renders as centered native glyphs.",
                "Inline math (\\( \\), $) flows with the surrounding text.",
                "LaTeX environments such as bmatrix typeset through the same engine.",
                "Copying a math block yields the original LaTeX source."
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
              - sanitized native HTML
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
