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

    func restart() {
        let streamRecorder = MarkdownDiagnosticsRecorder()
        let renderRecorder = MarkdownDiagnosticsRecorder()
        let configuration = MarkdownRendererConfiguration(
            theme: .compactChat,
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
                    SidebarCaseButton(
                        demoCase: demoCase,
                        isSelected: model.selectedCaseID == demoCase.id
                    ) {
                        model.selectedCaseID = demoCase.id
                    }
                }
            }

            Section("Stream State") {
                MetricRow(title: "Progress", value: "\(model.emittedStepCount)/\(model.totalStepCount)")
                MetricRow(title: "Source bytes", value: model.sourceByteCount.formatted())
                MetricRow(title: "Blocks", value: model.blockCount.formatted())
                MetricRow(title: "Mutable tail", value: model.activeTailBlockCount.formatted())
                MetricRow(title: "Host boundaries", value: model.hostBoundaryCount.formatted())
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
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        .navigationTitle("Streams")
    }
}

private struct SidebarCaseButton: View {
    var demoCase: StreamingCase
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: demoCase.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(demoCase.title)
                        .font(.headline)
                    Text(demoCase.summary)
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

private struct StreamingCaseDetail: View {
    @ObservedObject var model: StreamingTranscriptModel
    @State private var showsInspector = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
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

                Button {
                    showsInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help(showsInspector ? "Hide diagnostics" : "Show diagnostics")

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(statusColor.opacity(0.16))
                    }
                    .foregroundStyle(statusColor)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rendered Stream", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Text("\(model.sealedBlockCount) sealed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            StreamingMarkdownView(
                preparedSnapshot: model.preparedSnapshot,
                configuration: model.configuration
            ) { boundary in
                HostBoundaryMarker(boundary: boundary)
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08))
        }
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
    }
}

private struct StreamInspectorPanel: View {
    @ObservedObject var model: StreamingTranscriptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "Pipeline") {
                InspectorMetricGrid(
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

            InspectorSection(title: "Snapshot") {
                VStack(spacing: 8) {
                    MetricRow(title: "Source bytes", value: model.sourceByteCount.formatted())
                    MetricRow(title: "Blocks", value: model.blockCount.formatted())
                    MetricRow(title: "Sealed blocks", value: model.sealedBlockCount.formatted())
                    MetricRow(title: "Mutable tail", value: model.activeTailBlockCount.formatted())
                    MetricRow(title: "Host boundaries", value: model.hostBoundaryCount.formatted())
                }
            }

            InspectorSection(title: "Chunk Timeline") {
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
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
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
                        .fill(Color(nsColor: .textBackgroundColor))
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
                .append("# Streaming Transcript\n\n"),
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
                .append("# Open Fence Tail\n\n"),
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
                .append("# Host Boundary Stream\n\n"),
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
                .append("# Policy Stress\n\n"),
                .append("Links stay policy-controlled while content streams:\n\n"),
                .append("- [Safe link](https://example.com)\n"),
                .append("- [Blocked JavaScript](javascript:alert('blocked'))\n"),
                .append("- Remote image is inert by default: ![architecture diagram](https://example.com/architecture.png)\n\n"),
                .append("$$\n"),
                .append("layout(width) = preparedSegments \\rightarrow lines\n"),
                .append("$$\n\n"),
                .append("<aside>Raw HTML remains inert by default.</aside>\n"),
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
                .append("# Mixed Document Tail\n\n"),
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
                .append("# Wide Content\n\n"),
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
        )
    ]
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
