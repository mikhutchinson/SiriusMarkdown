import SwiftUI

/// Native Find controls that hosts can also use above a host-scrolled transcript.
/// The host supplies a prepared index and reveals the controller's current match.
public struct MarkdownDocumentFindBar: View {
    @ObservedObject private var controller: MarkdownDocumentFindController
    @FocusState private var fieldFocused: Bool

    public init(controller: MarkdownDocumentFindController) { self.controller = controller }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Find in Document", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { controller.next() }
                .accessibilityIdentifier("SiriusMarkdown.FindField")
            Text(countLabel)
                .font(.caption)
                .monospacedDigit()
                .accessibilityLabel(countLabel)
                .accessibilityIdentifier("SiriusMarkdown.FindCount")
            Button { controller.previous() } label: { Image(systemName: "chevron.up") }
                .disabled(controller.matches.isEmpty)
                .accessibilityLabel("Previous Match")
                .accessibilityIdentifier("SiriusMarkdown.FindPrevious")
                .markdownFindShortcut("g", modifiers: [.command, .shift])
            Button { controller.next() } label: { Image(systemName: "chevron.down") }
                .disabled(controller.matches.isEmpty)
                .accessibilityLabel("Next Match")
                .accessibilityIdentifier("SiriusMarkdown.FindNext")
                .markdownFindShortcut("g", modifiers: .command)
            Toggle("Match Case", isOn: Binding(
                get: { !controller.options.contains(.caseInsensitive) },
                set: { matchCase in
                    if matchCase { controller.options.remove(.caseInsensitive) }
                    else { controller.options.insert(.caseInsensitive) }
                }
            ))
            .toggleStyle(.button)
            Button("Done") { controller.isPresented = false }
                .accessibilityIdentifier("SiriusMarkdown.FindDone")
                .markdownFindShortcut(.escape, modifiers: [])
        }
        .padding(8)
        .onAppear { fieldFocused = true }
    }

    private var countLabel: String {
        guard !controller.matches.isEmpty else { return controller.query.isEmpty ? "" : "No matches" }
        return "\((controller.currentMatchIndex ?? 0) + 1) of \(controller.matches.count)"
    }
}

extension View {
    @ViewBuilder
    func markdownFindShortcut(_ key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        keyboardShortcut(key, modifiers: modifiers)
        #else
        self
        #endif
    }
}
