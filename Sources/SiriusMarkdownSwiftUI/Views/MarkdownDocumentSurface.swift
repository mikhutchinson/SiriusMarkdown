import SiriusMarkdownCore
import SwiftUI

public struct MarkdownDocumentSurfaceRenderPlan: Sendable, Equatable {
    public var blockCount: Int
    public var itemIDs: [String]
    public var snapshotGeneration: Int
    public var documentCopyButtonVisible: Bool
    public var documentExportButtonVisible: Bool
    public var documentCollapseButtonVisible: Bool
    public var isCollapsed: Bool

    public init(
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        isCollapsed: Bool? = nil
    ) {
        let hasDocumentMarkdown = configuration.copyProvider?.hasDocumentMarkdown == true
        self.blockCount = preparedSnapshot.snapshot.blocks.count
        self.itemIDs = preparedSnapshot.items.map(\.id)
        self.snapshotGeneration = preparedSnapshot.snapshot.generation
        self.documentCopyButtonVisible = affordances.showsCopyButton && hasDocumentMarkdown
        self.documentExportButtonVisible = affordances.showsExportButton && hasDocumentMarkdown
        self.documentCollapseButtonVisible = affordances.showsCollapseButton
        self.isCollapsed = isCollapsed ?? affordances.startsCollapsed
    }

    public var hasVisibleChrome: Bool {
        documentCopyButtonVisible || documentExportButtonVisible || documentCollapseButtonVisible
    }
}

public struct MarkdownDocumentSurface<Content: View>: View {
    private var title: String?
    private var subtitle: String?
    private var suggestedFilename: String
    private var preparedSnapshot: MarkdownPreparedSnapshot
    private var configuration: MarkdownRendererConfiguration
    private var affordances: MarkdownDocumentAffordances
    private var controlledCollapse: Binding<Bool>?
    private var onCollapseChanged: (@MainActor (Bool) -> Void)?
    private var content: @MainActor () -> Content

    @State private var localIsCollapsed: Bool

    private var theme: MarkdownTheme {
        configuration.theme
    }

    private var isCollapsed: Bool {
        controlledCollapse?.wrappedValue ?? localIsCollapsed
    }

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.suggestedFilename = suggestedFilename
        self.preparedSnapshot = preparedSnapshot
        self.configuration = configuration
        self.affordances = affordances
        self.controlledCollapse = nil
        self.onCollapseChanged = nil
        self.content = content
        _localIsCollapsed = State(initialValue: affordances.startsCollapsed)
    }

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        isCollapsed: Binding<Bool>,
        onCollapseChanged: (@MainActor (Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.suggestedFilename = suggestedFilename
        self.preparedSnapshot = preparedSnapshot
        self.configuration = configuration
        self.affordances = affordances
        self.controlledCollapse = isCollapsed
        self.onCollapseChanged = onCollapseChanged
        self.content = content
        _localIsCollapsed = State(initialValue: isCollapsed.wrappedValue)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
            }

            if isCollapsed {
                collapsedSummary
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.tableBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.tableBorderColor)
        }
        .accessibilityElement(children: .contain)
    }

    private var showsHeader: Bool {
        title != nil || subtitle != nil || hasVisibleChrome
    }

    private var hasDocumentMarkdown: Bool {
        configuration.copyProvider?.hasDocumentMarkdown == true
    }

    private var documentCopyButtonVisible: Bool {
        affordances.showsCopyButton && hasDocumentMarkdown
    }

    private var documentExportButtonVisible: Bool {
        affordances.showsExportButton && hasDocumentMarkdown
    }

    private var documentCollapseButtonVisible: Bool {
        affordances.showsCollapseButton
    }

    private var hasVisibleChrome: Bool {
        documentCopyButtonVisible || documentExportButtonVisible || documentCollapseButtonVisible
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(2)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if documentExportButtonVisible {
                    affordanceButton(
                        systemImage: MarkdownAffordanceSymbols.export,
                        accessibilityLabel: "Export document",
                        help: "Export document"
                    ) {
                        exportDocument()
                    }
                }

                if documentCopyButtonVisible {
                    affordanceButton(
                        systemImage: MarkdownAffordanceSymbols.copy,
                        accessibilityLabel: "Copy document",
                        help: "Copy document"
                    ) {
                        copyDocument()
                    }
                }

                if documentCollapseButtonVisible {
                    affordanceButton(
                        systemImage: isCollapsed ? MarkdownAffordanceSymbols.expand : MarkdownAffordanceSymbols.collapse,
                        accessibilityLabel: isCollapsed ? "Expand document" : "Collapse document",
                        help: isCollapsed ? "Expand document" : "Collapse document"
                    ) {
                        setCollapsed(!isCollapsed)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(theme.codeBackground.opacity(0.45))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.tableBorderColor)
                .frame(height: 1)
        }
    }

    private var collapsedSummary: some View {
        Text("\(preparedSnapshot.snapshot.blocks.count.formatted()) blocks hidden")
            .font(.caption)
            .foregroundStyle(theme.secondaryTextColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Document collapsed")
    }

    private func affordanceButton(
        systemImage: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MarkdownAffordanceIcon(systemName: systemImage)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondaryTextColor)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    @MainActor
    private func setCollapsed(_ collapsed: Bool) {
        if let controlledCollapse {
            controlledCollapse.wrappedValue = collapsed
        } else {
            localIsCollapsed = collapsed
        }
        onCollapseChanged?(collapsed)
    }

    private func copyDocument() {
        guard let markdown = configuration.copyProvider?.markdownForDocument() else {
            return
        }

        Task { @MainActor in
            configuration.affordanceActionHandler.copyString(markdown)
        }
    }

    private func exportDocument() {
        guard let markdown = configuration.copyProvider?.markdownForDocument() else {
            return
        }

        let payload = MarkdownExportPayload(
            markdown: markdown,
            suggestedFilename: suggestedFilename
        )
        Task { @MainActor in
            configuration.affordanceActionHandler.exportMarkdown(payload)
        }
    }
}

public extension MarkdownDocumentSurface where Content == MarkdownDocumentView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            suggestedFilename: suggestedFilename,
            preparedSnapshot: preparedSnapshot,
            configuration: configuration,
            affordances: affordances
        ) {
            MarkdownDocumentView(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            )
        }
    }

    init(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        isCollapsed: Binding<Bool>,
        onCollapseChanged: (@MainActor (Bool) -> Void)? = nil,
        selectionController: MarkdownSelectionController? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            suggestedFilename: suggestedFilename,
            preparedSnapshot: preparedSnapshot,
            configuration: configuration,
            affordances: affordances,
            isCollapsed: isCollapsed,
            onCollapseChanged: onCollapseChanged
        ) {
            MarkdownDocumentView(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController
            )
        }
    }

    init<HostBoundaryContent: View>(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            suggestedFilename: suggestedFilename,
            preparedSnapshot: preparedSnapshot,
            configuration: configuration,
            affordances: affordances
        ) {
            MarkdownDocumentView(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController,
                hostBoundaryContent: hostBoundaryContent
            )
        }
    }

    init<HostBoundaryContent: View>(
        title: String? = nil,
        subtitle: String? = nil,
        suggestedFilename: String = "Document.md",
        preparedSnapshot: MarkdownPreparedSnapshot,
        configuration: MarkdownRendererConfiguration,
        affordances: MarkdownDocumentAffordances = .default,
        isCollapsed: Binding<Bool>,
        onCollapseChanged: (@MainActor (Bool) -> Void)? = nil,
        selectionController: MarkdownSelectionController? = nil,
        @ViewBuilder hostBoundaryContent: @escaping @MainActor (MarkdownHostBoundary) -> HostBoundaryContent
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            suggestedFilename: suggestedFilename,
            preparedSnapshot: preparedSnapshot,
            configuration: configuration,
            affordances: affordances,
            isCollapsed: isCollapsed,
            onCollapseChanged: onCollapseChanged
        ) {
            MarkdownDocumentView(
                preparedSnapshot: preparedSnapshot,
                configuration: configuration,
                selectionController: selectionController,
                hostBoundaryContent: hostBoundaryContent
            )
        }
    }
}
