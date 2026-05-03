import AppKit
import SwiftUI

public enum DemoColors {
    public static let windowBackground = Color(nsColor: .windowBackgroundColor)
    public static let documentBackground = Color(nsColor: .textBackgroundColor)
    public static let inspectorBackground = Color(nsColor: .controlBackgroundColor)
    public static let separator = Color(nsColor: .separatorColor).opacity(0.46)
    public static let pageStroke = Color(nsColor: .separatorColor).opacity(0.45)
    public static let quietFill = Color.primary.opacity(0.035)
    public static let selectedFill = Color.accentColor
}

public struct DemoMetricRow: View {
    public var title: String
    public var value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

public struct DemoSidebarRow: View {
    public var title: String
    public var subtitle: String?
    public var systemImage: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? DemoColors.selectedFill : Color.clear)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
    }
}

public struct DemoIconButton: View {
    public var title: String
    public var systemImage: String
    public var isActive: Bool
    public var action: () -> Void

    public init(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .help(title)
        .accessibilityLabel(title)
    }
}

public struct DemoAffordanceBar<Content: View>: View {
    @ViewBuilder public var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 6) {
            content
        }
    }
}

public struct DemoStatusPill: View {
    public var text: String
    public var systemImage: String?
    public var color: Color

    public init(text: String, systemImage: String? = nil, color: Color = .accentColor) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        label
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(color.opacity(0.14))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(text, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        } else {
            Text(text)
        }
    }
}

public struct DemoSurface<Content: View>: View {
    public var padding: CGFloat
    @ViewBuilder public var content: Content

    public init(padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(DemoColors.documentBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DemoColors.separator)
            }
    }
}

public struct DemoInspectorSection<Content: View>: View {
    public var title: String
    @ViewBuilder public var content: Content

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

public struct DemoMetricGrid: View {
    public var metrics: [(String, String)]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    public init(metrics: [(String, String)]) {
        self.metrics = metrics
    }

    public var body: some View {
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

public struct DemoInspectorPanel<Content: View>: View {
    @ViewBuilder public var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(DemoColors.inspectorBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(DemoColors.separator)
        }
    }
}

public struct DemoAssertionStrip: View {
    public var assertions: [String]

    public init(assertions: [String]) {
        self.assertions = assertions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(assertions, id: \.self) { assertion in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                        .frame(width: 16)
                    Text(assertion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(DemoColors.quietFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(DemoColors.separator)
        }
    }
}

public struct DemoEmptyState: View {
    public var title: String
    public var message: String
    public var systemImage: String

    public init(title: String, message: String, systemImage: String = "doc.text.magnifyingglass") {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
