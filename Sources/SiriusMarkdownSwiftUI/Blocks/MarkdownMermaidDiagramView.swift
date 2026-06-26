import SiriusMarkdownCore
import SwiftUI

private enum MarkdownMermaidScaleMode: Hashable {
    case fitWidth
    case actualSize
    case custom(Double)
}

struct MarkdownMermaidDiagramView: View {
    var mermaid: MarkdownPreparedMermaidDiagram
    var colorScheme: ColorScheme
    var theme: MarkdownTheme
    var baseFont: Font

    private var platformImage: PlatformImage?
    @State private var scaleMode: MarkdownMermaidScaleMode
    @State private var availableWidth: CGFloat = 0

    init(
        mermaid: MarkdownPreparedMermaidDiagram,
        colorScheme: ColorScheme,
        theme: MarkdownTheme,
        baseFont: Font
    ) {
        self.mermaid = mermaid
        self.colorScheme = colorScheme
        self.theme = theme
        self.baseFont = baseFont
        if let svg = mermaid.svg(for: colorScheme),
           let data = svg.data(using: .utf8) {
            self.platformImage = PlatformImage(data: data)
        } else {
            self.platformImage = nil
        }
        _scaleMode = State(
            initialValue: theme.mermaidAffordances.startsFittedToWidth ? .fitWidth : .actualSize
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if controlsVisible {
                toolbar
            }
            diagramSurface
        }
        .padding(8)
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.tableBorderColor.opacity(0.8))
        }
        .background(widthReader)
        .accessibilityLabel("Mermaid diagram")
    }

    @ViewBuilder
    private var diagramSurface: some View {
        if let platformImage, let geometry = mermaid.geometry, geometry.isRenderableViewportGeometry {
            imageViewport(image: platformImage, geometry: geometry)
        } else if let platformImage {
            ScrollView([.horizontal, .vertical]) {
                platformImageView(platformImage)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: theme.mermaidAffordances.renderViewportHeightBounds.upperBound)
        } else {
            asciiFallback
        }
    }

    private func imageViewport(
        image: PlatformImage,
        geometry: MarkdownMermaidDiagramGeometry
    ) -> some View {
        let scale = effectiveScale(for: geometry)
        let scaledWidth = max(1, CGFloat(geometry.width) * scale)
        let scaledHeight = max(1, CGFloat(geometry.height) * scale)
        let viewportWidth = max(1, availableWidth - 16)
        let viewportHeight = clampedViewportHeight(forScaledHeight: scaledHeight)
        let horizontalInset = max(0, (viewportWidth - scaledWidth) / 2)
        let verticalInset = max(0, (viewportHeight - scaledHeight) / 2)

        return ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                Spacer(minLength: verticalInset)
                HStack(spacing: 0) {
                    Spacer(minLength: horizontalInset)
                    platformImageView(image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: scaledWidth, height: scaledHeight)
                    Spacer(minLength: horizontalInset)
                }
                Spacer(minLength: verticalInset)
            }
            .frame(minWidth: viewportWidth, minHeight: viewportHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: viewportHeight)
    }

    private var asciiFallback: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(verbatim: mermaid.ascii)
                .font(baseFont)
                .foregroundStyle(theme.textColor)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: theme.mermaidAffordances.renderViewportHeightBounds.upperBound)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if theme.mermaidAffordances.showsZoomControls {
                diagramButton(
                    systemImage: MarkdownAffordanceSymbols.zoomOut,
                    accessibilityLabel: "Zoom out diagram",
                    isDisabled: currentScale <= scaleBounds.lowerBound + 0.0001
                ) {
                    zoom(by: -theme.mermaidAffordances.renderScaleStep)
                }
                diagramButton(
                    systemImage: MarkdownAffordanceSymbols.zoomIn,
                    accessibilityLabel: "Zoom in diagram",
                    isDisabled: currentScale >= scaleBounds.upperBound - 0.0001
                ) {
                    zoom(by: theme.mermaidAffordances.renderScaleStep)
                }
            }
            if theme.mermaidAffordances.showsFitButton {
                diagramButton(
                    systemImage: MarkdownAffordanceSymbols.fit,
                    accessibilityLabel: "Fit diagram"
                ) {
                    scaleMode = .fitWidth
                }
            }
            if theme.mermaidAffordances.showsResetButton {
                diagramButton(
                    systemImage: MarkdownAffordanceSymbols.reset,
                    accessibilityLabel: "Reset diagram"
                ) {
                    scaleMode = .actualSize
                }
            }
        }
    }

    private func diagramButton(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MarkdownAffordanceIcon(systemName: systemImage, size: 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? theme.secondaryTextColor.opacity(0.45) : theme.secondaryTextColor)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private var controlsVisible: Bool {
        theme.mermaidAffordances.showsToolbar &&
            platformImage != nil &&
            mermaid.geometry?.isRenderableViewportGeometry == true
    }

    private func zoom(by delta: Double) {
        scaleMode = .custom(clampScale(currentScale + delta))
    }

    private var currentScale: Double {
        guard let geometry = mermaid.geometry else {
            return 1
        }
        return Double(effectiveScale(for: geometry))
    }

    private func effectiveScale(for geometry: MarkdownMermaidDiagramGeometry) -> CGFloat {
        guard geometry.isRenderableViewportGeometry else {
            return 1
        }
        let scale: Double
        switch scaleMode {
        case .fitWidth:
            let viewportWidth = max(1, Double(availableWidth - 16))
            scale = min(1.0, viewportWidth / geometry.width)
        case .actualSize:
            scale = 1.0
        case let .custom(value):
            scale = value
        }
        return CGFloat(clampScale(scale))
    }

    private func clampScale(_ scale: Double) -> Double {
        guard scale.isFinite else {
            return scaleBounds.lowerBound
        }
        return min(max(scale, scaleBounds.lowerBound), scaleBounds.upperBound)
    }

    private var scaleBounds: ClosedRange<Double> {
        theme.mermaidAffordances.renderScaleBounds
    }

    private func clampedViewportHeight(forScaledHeight scaledHeight: CGFloat) -> CGFloat {
        let bounds = theme.mermaidAffordances.renderViewportHeightBounds
        guard scaledHeight.isFinite else {
            return bounds.lowerBound
        }
        return min(max(scaledHeight, bounds.lowerBound), bounds.upperBound)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkdownMermaidWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
        .allowsHitTesting(false)
        .onPreferenceChange(MarkdownMermaidWidthPreferenceKey.self) { width in
            if width.isFinite, width > 0, abs(width - availableWidth) > 0.5 {
                availableWidth = width
            }
        }
    }

    @ViewBuilder
    private func platformImageView(_ image: PlatformImage) -> Image {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }
}

extension MarkdownMermaidDiagramAffordances {
    var renderScaleBounds: ClosedRange<Double> {
        let rawMinimum = finitePositive(minimumScale, fallback: 0.5)
        let rawMaximum = finitePositive(maximumScale, fallback: max(rawMinimum, 3.0))
        let lower = max(0.05, min(rawMinimum, rawMaximum))
        let upper = max(lower, rawMinimum, rawMaximum)
        return lower...upper
    }

    var renderScaleStep: Double {
        finitePositive(scaleStep, fallback: 0.2)
    }

    var renderViewportHeightBounds: ClosedRange<CGFloat> {
        let rawMinimum = finitePositive(minimumViewportHeight, fallback: 120)
        let rawMaximum = finitePositive(maximumViewportHeight, fallback: max(rawMinimum, 420))
        let lower = min(rawMinimum, rawMaximum)
        let upper = max(rawMinimum, rawMaximum)
        return lower...upper
    }

    private func finitePositive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private func finitePositive(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }
}

private struct MarkdownMermaidWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

extension MarkdownMermaidDiagramGeometry {
    var isRenderableViewportGeometry: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

private extension MarkdownPreparedMermaidDiagram {
    func svg(for colorScheme: ColorScheme) -> String? {
        if colorScheme == .dark {
            return darkSVG ?? svg
        }
        return svg
    }
}
