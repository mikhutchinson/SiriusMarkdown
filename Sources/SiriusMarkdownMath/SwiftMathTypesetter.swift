import Foundation
import SiriusMarkdownSwiftUI

#if canImport(SwiftMath)
import SwiftMath

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Bridges `SwiftMath`'s public `MTMathImage` CoreText typesetting into a
/// `Sendable` `MarkdownPreparedMathImage`.
///
/// `SwiftMath`'s typesetting objects are reference types and are not `Sendable`,
/// so all access is confined behind a single lock (mirroring the package's
/// `MermaidJavaScriptRuntime`). The lock yields only value types: PNG data plus
/// point metrics. Glyphs are rasterized in opaque black so the bitmap's alpha
/// channel encodes coverage; the SwiftUI layer draws it as a theme-tinted
/// template image.
final class SwiftMathTypesetter: @unchecked Sendable {
    static let shared = SwiftMathTypesetter()

    private let lock = NSLock()

    private init() {}

    func preparedImage(
        latex: String,
        isBlock: Bool,
        fontSize: Double,
        scale: Double
    ) -> MarkdownPreparedMathImage? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return lock.withLock {
            let mathImage = MTMathImage(
                latex: latex,
                fontSize: CGFloat(fontSize),
                textColor: MTColor.black,
                labelMode: isBlock ? .display : .text,
                textAlignment: .left
            )

            let (error, image) = mathImage.asImage()
            guard error == nil,
                  let image,
                  image.size.width > 0,
                  image.size.height > 0
            else {
                return nil
            }

            let pointWidth = Double(image.size.width)
            let pointHeight = Double(image.size.height)
            guard let imageData = Self.pngData(from: image, scale: CGFloat(scale)) else {
                return nil
            }

            return MarkdownPreparedMathImage(
                imageData: imageData,
                scale: scale,
                pointWidth: pointWidth,
                pointHeight: pointHeight,
                ascent: pointHeight,
                descent: 0,
                latex: latex
            )
        }
    }

    /// Re-rasterizes the typeset equation at the requested pixel scale so the
    /// stored bitmap stays crisp when SwiftUI draws it at point size.
    private static func pngData(from image: MTImage, scale: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        if scale > 0 {
            format.scale = scale
        }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rasterized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rasterized.pngData()
        #elseif canImport(AppKit)
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}
#endif
