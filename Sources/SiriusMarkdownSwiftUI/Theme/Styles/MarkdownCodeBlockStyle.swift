import SiriusMarkdownCore
import SwiftUI

/// Copy / export / collapse actions for a code-like block (code block or
/// Mermaid diagram). Actions are already wired to the package's existing
/// affordance/pasteboard machinery by `MarkdownBlockView` — styles invoke
/// these closures; they do not reimplement pasteboard or file-export
/// behavior themselves.
///
/// A `nil` action means the corresponding affordance has nothing to do
/// (for example, a policy-denied or empty block) and default chrome hides
/// the associated control even if the theme affordance flag is enabled.
public struct MarkdownCodeBlockActions {
    public var copy: (@MainActor () -> Void)?
    public var export: (@MainActor () -> Void)?
    public var toggleCollapse: (@MainActor () -> Void)?

    public init(
        copy: (@MainActor () -> Void)? = nil,
        export: (@MainActor () -> Void)? = nil,
        toggleCollapse: (@MainActor () -> Void)? = nil
    ) {
        self.copy = copy
        self.export = export
        self.toggleCollapse = toggleCollapse
    }
}

/// Metadata and prepared content passed to `MarkdownCodeBlockStyle`.
///
/// `label` is already-highlighted (or plain, or collapsed-placeholder)
/// selectable code content — never raw source. `languageHint` is the
/// fence info string (for example `"swift"` from ` ```swift `);
/// `languageLabel` is the display name shown by default chrome (for
/// example `"Swift"`).
public struct MarkdownCodeBlockStyleConfiguration {
    public var label: MarkdownBlockStyleLabel
    public var theme: MarkdownTheme
    public var blockID: MarkdownBlockID
    public var indentationLevel: Int
    public var languageHint: String?
    public var languageLabel: String?
    public var isCollapsed: Bool
    public var actions: MarkdownCodeBlockActions

    /// Whether default chrome would show a header row for this
    /// configuration, given `theme.codeBlockAffordances` and which
    /// actions are actually available. Custom styles may ignore this.
    public var showsDefaultHeader: Bool {
        MarkdownDefaultCodeChromeHeader.showsHeader(
            theme: theme,
            languageLabel: languageLabel,
            actions: actions
        )
    }
}

/// Customizes chrome around an already-highlighted code block label.
///
/// `makeBody` receives prepared, already-highlighted (or plain) selectable
/// code content as `configuration.label`. Implementations must not
/// highlight code, parse fence info strings beyond reading
/// `languageHint`, or reimplement pasteboard/export behavior — use
/// `configuration.actions` (INV-BS2).
@MainActor
public protocol MarkdownCodeBlockStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
    typealias Configuration = MarkdownCodeBlockStyleConfiguration
}

/// Default code-block style: language label + copy/export/collapse
/// header, horizontally scrollable code, `theme.codeBackground` fill, and
/// a 6pt corner radius — matching pre-style `MarkdownBlockView` code-block
/// rendering exactly (INV-BS3).
public struct MarkdownDefaultCodeBlockStyle: MarkdownCodeBlockStyle {
    /// `internal` (not `private`) so `@testable import` can lock this
    /// geometry constant directly (Part 06 §6.2.1
    /// `defaultCodeBlockCornerRadiusIsSix`).
    static let cornerRadius: CGFloat = 6

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let showsHeader = configuration.showsDefaultHeader
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                MarkdownDefaultCodeChromeHeader(
                    theme: configuration.theme,
                    languageLabel: configuration.languageLabel,
                    isCollapsed: configuration.isCollapsed,
                    actions: configuration.actions
                )
            }
            if configuration.isCollapsed {
                configuration.label
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal) {
                    configuration.label
                        .padding(.horizontal, 10)
                        .padding(.top, showsHeader ? 4 : 10)
                        .padding(.bottom, 10)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(configuration.theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}

extension MarkdownCodeBlockStyle where Self == MarkdownDefaultCodeBlockStyle {
    public static var `default`: Self { .init() }
}

/// Shared header chrome (language label + copy/export/collapse buttons)
/// reused by the default code-block and Mermaid-block styles, mirroring
/// the single header implementation both cases shared before style
/// protocols existed.
struct MarkdownDefaultCodeChromeHeader: View {
    var theme: MarkdownTheme
    var languageLabel: String?
    var isCollapsed: Bool
    var actions: MarkdownCodeBlockActions

    nonisolated static func showsHeader(
        theme: MarkdownTheme,
        languageLabel: String?,
        actions: MarkdownCodeBlockActions
    ) -> Bool {
        (theme.codeBlockAffordances.showsLanguageLabel && languageLabel != nil) ||
            (theme.codeBlockAffordances.showsCopyButton && actions.copy != nil) ||
            (theme.codeBlockAffordances.showsExportButton && actions.export != nil) ||
            (theme.codeBlockAffordances.showsCollapseButton && actions.toggleCollapse != nil)
    }

    var body: some View {
        HStack(spacing: 8) {
            if theme.codeBlockAffordances.showsLanguageLabel, let languageLabel {
                Text(languageLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .lineLimit(1)
                    .accessibilityLabel("Code language: \(languageLabel)")
            }

            Spacer(minLength: 8)

            if theme.codeBlockAffordances.showsCopyButton, let copy = actions.copy {
                Button {
                    copy()
                } label: {
                    MarkdownAffordanceIcon(systemName: MarkdownAffordanceSymbols.copy, size: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Copy code")
                .help("Copy code")
            }

            if theme.codeBlockAffordances.showsExportButton, let export = actions.export {
                Button {
                    export()
                } label: {
                    MarkdownAffordanceIcon(systemName: MarkdownAffordanceSymbols.export, size: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("Export code")
                .help("Export code")
            }

            if theme.codeBlockAffordances.showsCollapseButton, let toggleCollapse = actions.toggleCollapse {
                Button {
                    toggleCollapse()
                } label: {
                    MarkdownAffordanceIcon(
                        systemName: isCollapsed ? MarkdownAffordanceSymbols.expand : MarkdownAffordanceSymbols.collapse,
                        size: 12
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel(isCollapsed ? "Expand code block" : "Collapse code block")
                .help(isCollapsed ? "Expand code block" : "Collapse code block")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
