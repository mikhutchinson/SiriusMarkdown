import DemoSupport
import SiriusMarkdown
import SiriusMarkdownMath
import SwiftUI

@main
struct StreamingTranscriptDemo: App {
    var body: some Scene {
        WindowGroup {
            StreamingTranscriptView()
                .frame(minWidth: 980, minHeight: 680)
        }
    }
}

@MainActor
private final class StreamingTranscriptModel: ObservableObject {
    @Published var selectedCaseID: StreamingCase.ID {
        didSet {
            guard selectedCaseID != oldValue else {
                return
            }
            restart()
        }
    }

    @Published var isPaused = false
    @Published private(set) var preparedSnapshot: MarkdownPreparedSnapshot
    private(set) var configuration: MarkdownRendererConfiguration
    @Published private(set) var streamCounters: MarkdownDiagnosticsCounters
    @Published private(set) var renderCounters: MarkdownDiagnosticsCounters
    @Published private(set) var emittedStepCount = 0
    @Published private(set) var sourceByteCount = 0

    private var stream: MarkdownStream
    private var streamRecorder: MarkdownDiagnosticsRecorder
    private var renderRecorder: MarkdownDiagnosticsRecorder

    init() {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        let configuration = MarkdownRendererConfiguration(
            theme: .compactChat,
            inlineRenderingMode: .preparedNativeLines,
            mathRenderer: NativeMarkdownMathRenderer(),
            diagnosticsRecorder: renderRecorder
        )
        let stream = MarkdownStream(diagnosticsRecorder: streamRecorder)

        self.selectedCaseID = StreamingCase.allCases[0].id
        self.streamRecorder = streamRecorder
        self.renderRecorder = renderRecorder
        self.stream = stream
        self.configuration = configuration
        self.preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
        self.streamCounters = streamRecorder.snapshot()
        self.renderCounters = renderRecorder.snapshot()

        appendNextStep()
    }

    var selectedCase: StreamingCase {
        StreamingCase.demoCase(for: selectedCaseID)
    }

    var totalStepCount: Int {
        selectedCase.steps.count
    }

    var isFinished: Bool {
        preparedSnapshot.snapshot.isFinished
    }

    var blockCount: Int {
        preparedSnapshot.snapshot.blocks.count
    }

    var sealedBlockCount: Int {
        preparedSnapshot.snapshot.blocks.filter(\.isSealed).count
    }

    var activeTailBlockCount: Int {
        preparedSnapshot.snapshot.blocks.filter { !$0.isSealed }.count
    }

    var hostBoundaryCount: Int {
        preparedSnapshot.items.reduce(into: 0) { count, item in
            if case .hostBoundary = item {
                count += 1
            }
        }
    }

    func tick() {
        guard !isPaused else {
            return
        }
        appendNextStep()
    }

    func appendNextStep() {
        guard emittedStepCount < selectedCase.steps.count else {
            return
        }

        let step = selectedCase.steps[emittedStepCount]
        emittedStepCount += 1

        switch step {
        case let .append(markdown):
            stream.append(markdown)
        case let .hostBoundary(id):
            stream.appendHostBoundary(id: MarkdownHostBoundaryID(id))
        case .finish:
            stream.finish()
        }

        refreshPreparedSnapshot()
    }

    func appendNextSteps(_ count: Int) {
        guard !isFinished else {
            return
        }

        for _ in 0..<count {
            guard emittedStepCount < selectedCase.steps.count else {
                break
            }
            appendNextStep()
        }
    }

    func restart() {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        let configuration = MarkdownRendererConfiguration(
            theme: .compactChat,
            inlineRenderingMode: .preparedNativeLines,
            mathRenderer: NativeMarkdownMathRenderer(),
            diagnosticsRecorder: renderRecorder
        )

        self.streamRecorder = streamRecorder
        self.renderRecorder = renderRecorder
        self.stream = MarkdownStream(diagnosticsRecorder: streamRecorder)
        self.configuration = configuration
        self.emittedStepCount = 0
        self.isPaused = false

        refreshPreparedSnapshot()
        appendNextStep()
    }

    func togglePaused() {
        isPaused.toggle()
    }

    private func refreshPreparedSnapshot() {
        preparedSnapshot = configuration.prepare(snapshot: stream.snapshot())
        streamCounters = streamRecorder.snapshot()
        renderCounters = renderRecorder.snapshot()
        sourceByteCount = stream.sourceLength
    }
}

private struct StreamingTranscriptView: View {
    @StateObject private var model = StreamingTranscriptModel()
    private let timer = Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            StreamingSidebar(model: model)
        } detail: {
            StreamingCaseDetail(model: model)
                .navigationTitle(model.selectedCase.title)
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            model.restart()
                        } label: {
                            Label("Restart", systemImage: "arrow.counterclockwise")
                        }

                        Button {
                            model.togglePaused()
                        } label: {
                            Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                        }
                        .disabled(model.isFinished)

                        Button {
                            model.appendNextStep()
                        } label: {
                            Label("Step", systemImage: "forward.end.fill")
                        }
                        .disabled(model.isFinished)

                        Button {
                            model.appendNextSteps(25)
                        } label: {
                            Label("Burst", systemImage: "forward.fill")
                        }
                        .disabled(model.isFinished)
                    }
                }
        }
        .onReceive(timer) { _ in
            model.tick()
        }
    }
}

private struct StreamingSidebar: View {
    @ObservedObject var model: StreamingTranscriptModel

    var body: some View {
        List {
            Section("Streaming Cases") {
                ForEach(StreamingCase.allCases) { demoCase in
                    DemoSidebarRow(
                        title: demoCase.title,
                        subtitle: demoCase.summary,
                        systemImage: demoCase.systemImage,
                        isSelected: model.selectedCaseID == demoCase.id
                    ) {
                        model.selectedCaseID = demoCase.id
                    }
                }
            }

            Section("Stream State") {
                DemoMetricRow(title: "Progress", value: "\(model.emittedStepCount)/\(model.totalStepCount)")
                DemoMetricRow(title: "Source bytes", value: model.sourceByteCount.formatted())
                DemoMetricRow(title: "Blocks", value: model.blockCount.formatted())
                DemoMetricRow(title: "Mutable tail", value: model.activeTailBlockCount.formatted())
                DemoMetricRow(title: "Host boundaries", value: model.hostBoundaryCount.formatted())
            }

            Section("Controls") {
                Button {
                    model.restart()
                } label: {
                    Label("Restart Case", systemImage: "arrow.counterclockwise")
                }

                Button {
                    model.togglePaused()
                } label: {
                    Label(model.isPaused ? "Resume Stream" : "Pause Stream", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                .disabled(model.isFinished)

                Button {
                    model.appendNextStep()
                } label: {
                    Label("Append Next Chunk", systemImage: "forward.end.fill")
                }
                .disabled(model.isFinished)

                Button {
                    model.appendNextSteps(25)
                } label: {
                    Label("Append 25 Chunks", systemImage: "forward.fill")
                }
                .disabled(model.isFinished)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        .navigationTitle("Streams")
    }
}

private struct StreamingCaseDetail: View {
    @ObservedObject var model: StreamingTranscriptModel
    @State private var showsInspector = false

    var body: some View {
        ZStack {
            DemoColors.windowBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(
                    demoCase: model.selectedCase,
                    emittedStepCount: model.emittedStepCount,
                    totalStepCount: model.totalStepCount,
                    isPaused: model.isPaused,
                    isFinished: model.isFinished,
                    showsInspector: $showsInspector
                )

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
                TranscriptSurface(model: model)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if showsInspector {
                    StreamInspectorPanel(model: model)
                        .frame(width: 300)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                TranscriptSurface(model: model)
                if showsInspector {
                    StreamInspectorPanel(model: model)
                }
            }
        }
    }
}

private struct DetailHeader: View {
    var demoCase: StreamingCase
    var emittedStepCount: Int
    var totalStepCount: Int
    var isPaused: Bool
    var isFinished: Bool
    @Binding var showsInspector: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(demoCase.title, systemImage: demoCase.systemImage)
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

                    DemoStatusPill(text: statusText, color: statusColor)
                }
            }

            Text(demoCase.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(emittedStepCount), total: Double(max(totalStepCount, 1)))
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var statusText: String {
        if isFinished {
            return "Finished"
        }
        if isPaused {
            return "Paused"
        }
        return "Streaming \(emittedStepCount)/\(totalStepCount)"
    }

    private var statusColor: Color {
        if isFinished {
            return .green
        }
        if isPaused {
            return .orange
        }
        return .accentColor
    }
}

private struct TranscriptSurface: View {
    @ObservedObject var model: StreamingTranscriptModel

    var body: some View {
        DemoSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Rendered Stream", systemImage: "text.bubble")
                        .font(.headline)
                    Spacer()
                    DemoAffordanceBar {
                        DemoStatusPill(text: "\(model.sealedBlockCount) sealed", systemImage: "lock", color: .green)
                        DemoStatusPill(text: "\(model.activeTailBlockCount) tail", systemImage: "waveform", color: .orange)
                    }
                }

                Divider()

                StreamingMarkdownView(
                    preparedSnapshot: model.preparedSnapshot,
                    configuration: model.configuration
                ) { boundary in
                    HostBoundaryMarker(boundary: boundary)
                }
                .id(model.selectedCaseID)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }
}

private struct StreamInspectorPanel: View {
    @ObservedObject var model: StreamingTranscriptModel

    var body: some View {
        DemoInspectorPanel {
            DemoInspectorSection(title: "Pipeline") {
                DemoMetricGrid(
                    metrics: [
                        ("Parse", model.streamCounters.parseCount.formatted()),
                        ("Tail", model.streamCounters.tailReparseCount.formatted()),
                        ("Sealed", model.streamCounters.sealedRegionParseCount.formatted()),
                        ("Scan", model.streamCounters.boundaryScanCount.formatted()),
                        ("Prepare", model.renderCounters.prepareCount.formatted()),
                        ("Cache", model.renderCounters.cacheHitCount.formatted())
                    ]
                )
            }

            DemoInspectorSection(title: "Snapshot") {
                VStack(spacing: 8) {
                    DemoMetricRow(title: "Source bytes", value: model.sourceByteCount.formatted())
                    DemoMetricRow(title: "Blocks", value: model.blockCount.formatted())
                    DemoMetricRow(title: "Sealed blocks", value: model.sealedBlockCount.formatted())
                    DemoMetricRow(title: "Mutable tail", value: model.activeTailBlockCount.formatted())
                    DemoMetricRow(title: "Host boundaries", value: model.hostBoundaryCount.formatted())
                }
            }

            DemoInspectorSection(title: "Chunk Timeline") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.selectedCase.steps.enumerated()), id: \.offset) { index, step in
                        StepTimelineRow(
                            step: step,
                            index: index,
                            isEmitted: index < model.emittedStepCount,
                            isCurrent: index == model.emittedStepCount
                        )
                    }
                }
            }
        }
    }
}

private struct StepTimelineRow: View {
    var step: StreamingStep
    var index: Int
    var isEmitted: Bool
    var isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: step.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)
                .background {
                    Circle()
                        .fill(iconColor.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(index + 1). \(step.title)")
                    .font(.caption.weight(.semibold))
                Text(step.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .opacity(isEmitted || isCurrent ? 1 : 0.48)
    }

    private var iconColor: Color {
        if isCurrent {
            return .orange
        }
        if isEmitted {
            return .accentColor
        }
        return .secondary
    }
}

private struct HostBoundaryMarker: View {
    var boundary: MarkdownHostBoundary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Native host boundary")
                    .font(.caption.weight(.semibold))
                Text("Markdown sealed before source offset \(boundary.sourceOffset.formatted()).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.accentColor.opacity(0.24))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StreamingCase: Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var detail: String
    var systemImage: String
    var steps: [StreamingStep]

    static func demoCase(for id: ID) -> StreamingCase {
        allCases.first { $0.id == id } ?? allCases[0]
    }

    static let allCases: [StreamingCase] = [
        StreamingCase(
            id: "assistant-answer",
            title: "Assistant Answer",
            summary: "Task lists, quote, and code arrive as chat chunks.",
            detail: "A compact chat answer streams through common assistant Markdown while counters show mutable tail reparses and sealed-region parses.",
            systemImage: "message.badge.waveform",
            steps: [
                .append("This transcript appends Markdown in small chunks while preserving stable block identity and inline math like $x^2 \\rightarrow y_1 + \\alpha$.\n\n"),
                .append("- [ ] Parse only the mutable tail\n"),
                .append("- [x] Keep sealed regions immutable\n\n"),
                .append("$$\n"),
                .append("tailReparseCount \\rightarrow activeTailOnly\n"),
                .append("$$\n\n"),
                .append("> Host apps can interleave native UI at stream boundaries.\n\n"),
                .append("```swift\n"),
                .append("var stream = MarkdownStream()\n"),
                .append("stream.append(chunk)\n"),
                .append("let snapshot = stream.snapshot()\n"),
                .append("```\n\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "open-fence",
            title: "Open Code Fence",
            summary: "An incomplete fence keeps the tail mutable until close.",
            detail: "The stream opens a Swift fence, appends several body chunks, and closes it late to demonstrate conservative sealing.",
            systemImage: "chevron.left.forwardslash.chevron.right",
            steps: [
                .append("The scanner should not seal this region while the code fence is still open.\n\n"),
                .append("```swift\n"),
                .append("let chunks = [\"alpha\", \"beta\", \"gamma\"]\n"),
                .append("for chunk in chunks {\n"),
                .append("    stream.append(chunk)\n"),
                .append("    let snapshot = stream.snapshot()\n"),
                .append("}\n"),
                .append("```\n\n"),
                .append("Once the closing fence and blank line arrive, the block can become sealed and cacheable.\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "host-boundary",
            title: "Host Boundary",
            summary: "Markdown seals before native content is inserted.",
            detail: "This case places native host markers between Markdown regions so the renderer shows the app-owned insertion points explicitly.",
            systemImage: "puzzlepiece.extension",
            steps: [
                .append("Markdown before a native insertion should seal before the host-owned row appears.\n\n"),
                .hostBoundary("lookup-result"),
                .append("## Markdown After The Boundary\n\n"),
                .append("The next Markdown region resumes after the host boundary without merging source ranges across native UI.\n\n"),
                .append("- Stable IDs continue to come from block source ranges.\n"),
                .append("- The boundary remains a snapshot item, not Markdown text.\n\n"),
                .hostBoundary("tool-followup"),
                .append("> Host apps can render tool output, attachments, or status rows between sealed Markdown regions.\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "policy-stress",
            title: "Policy Stress",
            summary: "Links, image placeholders, HTML, and math stream together.",
            detail: "Safe and unsafe destinations arrive in one stream so default public-package policy behavior is visible in the demo.",
            systemImage: "lock.shield",
            steps: [
                .append("Links stay policy-controlled while content streams:\n\n"),
                .append("- [Safe link](https://example.com)\n"),
                .append("- [Blocked JavaScript](javascript:alert('blocked'))\n"),
                .append("- Remote image is inert by default: ![architecture diagram](https://example.com/architecture.png)\n\n"),
                .append("$$\n"),
                .append("layout(width) = preparedSegments \\rightarrow lines\n"),
                .append("$$\n\n"),
                .append("<aside>Raw HTML remains inert by default.</aside>\n\n"),
                .append("```mermaid\ngraph LR\n    A[Source] --> B[Stream]\n    B --> C[Render]\n```\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "reference-definitions",
            title: "Reference Definitions",
            summary: "Reference links wait for matching definitions before sealing.",
            detail: "This stream shows the mutable tail staying open for an unresolved reference link, then sealing once its definition arrives while later references reuse earlier definitions.",
            systemImage: "link.circle",
            steps: [
                .append("The first paragraph starts with [release notes][release-ref] before the destination exists.\n\n"),
                .append("While that label is unresolved, the region should remain the mutable tail instead of sealing into the wrong semantics.\n\n"),
                .append("[release-ref]: https://example.com/siriusmarkdown/0.5.0\n\n"),
                .append("A later paragraph can reuse [release notes][release-ref] after the definition has already sealed.\n\n"),
                .append("[docs-ref]: https://example.com/siriusmarkdown/docs\n\n"),
                .append("Definitions can also arrive before use: [documentation][docs-ref] should resolve without keeping the tail open.\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "mixed-document",
            title: "Mixed Document Tail",
            summary: "Nested lists, tables, CJK, RTL, emoji, and hard breaks.",
            detail: "A denser transcript streams document-like content that should remain native, structured, and resize-stable.",
            systemImage: "doc.richtext",
            steps: [
                .append("Nested lists, tables, and multilingual text should not destabilize row sizing.\n\n"),
                .append("- Parent item\n"),
                .append("  - Child item with `inline code`\n"),
                .append("  - Child item with **strong text** and ~~removed text~~\n\n"),
                .append("3. Ordered item starting at three\n"),
                .append("4. Next item keeps the source-order marker stable\n\n"),
                .append("| Region | Text | Evidence |\n"),
                .append("| :--- | :--- | :--- |\n"),
                .append("| CJK | 日本語 and 한국어 | prepared inline layout |\n"),
                .append("| RTL | العربية داخل الجملة | CoreText measurement |\n"),
                .append("| Emoji | 😀 😎 🚀 | cached segment widths |\n\n"),
                .append("Hard line breaks stay visible in prepared layout: first line  \nsecond line after a Markdown hard break.\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "wide-content",
            title: "Wide Content",
            summary: "Long code and tables exercise overflow containment.",
            detail: "Wide rows stream into the compact chat renderer so code and tables can be inspected without layout collapse.",
            systemImage: "rectangle.expand.vertical",
            steps: [
                .append("The renderer should contain wide blocks instead of letting them destabilize the transcript width.\n\n"),
                .append("```json\n"),
                .append("{\"renderer\":\"SiriusMarkdown\",\"mode\":\"streaming\",\"features\":[\"sealed-regions\",\"mutable-tail\",\"prepared-inline-layout\",\"bounded-caches\",\"host-boundaries\"]}\n"),
                .append("```\n\n"),
                .append("| Scenario | Long Value |\n"),
                .append("| :--- | :--- |\n"),
                .append("| Cache key | sourceRange + contentHash + theme + policyInputs + fontTraits |\n"),
                .append("| Resize path | cheap layout over prepared segments without parsing or highlighting |\n"),
                .finish
            ]
        ),
        StreamingCase(
            id: "very-long-document",
            title: "Very Long Document Stream",
            summary: "A generated multi-section document streams in many chunks.",
            detail: "This case appends a long document as repeated sections with tables, code, math, multilingual text, and host checkpoints. Use Burst to drive the stream hard without waiting for the timer.",
            systemImage: "text.line.first.and.arrowtriangle.forward",
            steps: StreamingCase.veryLongDocumentSteps(sectionCount: 120)
        )
    ]

    private static func veryLongDocumentSteps(sectionCount: Int) -> [StreamingStep] {
        var steps: [StreamingStep] = [
            .append("This generated stream is intentionally long. It repeatedly seals Markdown regions, keeps one mutable tail active, and forces prepared snapshots to grow while counters remain visible.\n\n"),
            .append("$$\nstreamedDocument = sealedRegions + mutableTail\n$$\n\n")
        ]

        for index in 1...sectionCount {
            steps.append(.append(veryLongSection(index)))
            if index.isMultiple(of: 30) {
                steps.append(.hostBoundary("stream-checkpoint-\(index)"))
            }
        }

        steps.append(.finish)
        return steps
    }

    private static func veryLongSection(_ index: Int) -> String {
        var parts: [String] = [
            """
            ## Streamed Section \(index)

            Section \(index) is a document-like chunk with **strong text**, *emphasis*, `inline code`, inline math $x_\(index)^2 + y_\(index)$, and mixed-script text: 日本語, 한국어, العربية, עברית, and emoji 😀😎. It should append cleanly, preserve stable block IDs after sealing, and render through prepared native lines.

            - [x] Append generated section \(index)
            - [x] Keep sealed regions immutable
            - [x] Reuse prepared renderer caches on refresh

            """
        ]

        if index.isMultiple(of: 5) {
            parts.append(
                """
                | Section | Content | Renderer Stress |
                | :--- | :--- | :--- |
                | \(index) | table cells with long prose | prepared table layout |
                | \(index) | RTL العربية داخل الجدول | CoreText measurement |
                | \(index) | emoji 😀😎🚀 | cached segment widths |
                """
            )
        }

        if index.isMultiple(of: 8) {
            parts.append(
                """
                ```swift
                let streamedSection = \(index)
                stream.append(sectionMarkdown)
                let snapshot = stream.snapshot()
                ```
                """
            )
        }

        if index.isMultiple(of: 11) {
            parts.append(
                """
                $$
                tail_\(index) \\rightarrow sealWhenSafe + prepare(snapshot_\(index))
                $$
                """
            )
        }

        return parts.joined(separator: "\n\n") + "\n\n"
    }
}

private enum StreamingStep: Hashable {
    case append(String)
    case hostBoundary(String)
    case finish

    var title: String {
        switch self {
        case .append:
            return "Append"
        case .hostBoundary:
            return "Host boundary"
        case .finish:
            return "Finish"
        }
    }

    var summary: String {
        switch self {
        case let .append(markdown):
            let line = markdown
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? "Markdown chunk"
            return line.count > 48 ? "\(line.prefix(45))..." : line
        case let .hostBoundary(id):
            return id
        case .finish:
            return "Seal final tail"
        }
    }

    var systemImage: String {
        switch self {
        case .append:
            return "plus"
        case .hostBoundary:
            return "puzzlepiece.extension"
        case .finish:
            return "checkmark"
        }
    }
}
