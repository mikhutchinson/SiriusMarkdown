import Foundation
import SiriusMarkdownSwiftUI

#if canImport(SwiftMath)
import SwiftMath

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Bridges vendored SwiftMath `MTMathImage` CoreText typesetting into a
/// `Sendable` `MarkdownPreparedMathImage`.
///
/// `SwiftMath`'s typesetting objects are reference types and are not `Sendable`,
/// so all access is confined behind a single lock (mirroring the package's
/// `MermaidJavaScriptRuntime`). The lock yields only value types: PNG data plus
/// point metrics from `MTMathImage.LayoutInfo` (`MTMathListDisplay` ascent/
/// descent). Glyphs are rasterized in opaque black so the bitmap's alpha
/// channel encodes coverage; the SwiftUI layer draws it as a theme-tinted
/// template image.
///
/// `MTMathImage` is preferred over `MathImage` here because its font path uses
/// `MTFont.fontBundle` (filesystem probe + SwiftPM `Bundle.module` fallback),
/// which is the packaging-safe path covered by `canEnterSwiftMath` (INV-M7).
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
        guard Self.canEnterSwiftMath() else {
            return nil
        }

        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return lock.withLock {
            let typesetLatex = Self.swiftMathCompatibleLatex(latex)
            let mathImage = MTMathImage(
                latex: typesetLatex,
                fontSize: CGFloat(fontSize),
                textColor: MTColor.black,
                labelMode: isBlock ? .display : .text,
                textAlignment: .left
            )

            let (error, image, layout) = mathImage.asImage()
            guard error == nil,
                  let image,
                  let layout,
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

            let (ascent, descent) = Self.metricsMatchingImageHeight(
                layout: layout,
                pointHeight: pointHeight,
                fontSize: fontSize
            )

            return MarkdownPreparedMathImage(
                imageData: imageData,
                scale: scale,
                pointWidth: pointWidth,
                pointHeight: pointHeight,
                ascent: ascent,
                descent: descent,
                latex: latex
            )
        }
    }

    /// Maps `MTMathImage.LayoutInfo` onto the rasterized image so
    /// `ascent + descent == pointHeight` and `-descent` matches the bitmap
    /// baseline produced by `MTMathImage.layoutImage`.
    ///
    /// SwiftMath positions the display-list baseline at
    /// `(availableHeight - max(contentHeight, fontSize/2)) / 2 + descent`
    /// from the image bottom (plus bottom content inset). Splitting leftover
    /// height evenly would disagree with that formula whenever the
    /// `fontSize/2` floor is active.
    private static func metricsMatchingImageHeight(
        layout: MTMathImage.LayoutInfo,
        pointHeight: Double,
        fontSize: Double,
        contentInsetsTop: Double = 0,
        contentInsetsBottom: Double = 0
    ) -> (ascent: Double, descent: Double) {
        let layoutAscent = max(0, Double(layout.ascent))
        let layoutDescent = max(0, Double(layout.descent))
        let availableHeight = pointHeight - contentInsetsTop - contentInsetsBottom
        guard availableHeight > 0 else {
            return (ascent: max(0, pointHeight), descent: 0)
        }

        let contentHeight = layoutAscent + layoutDescent
        let layoutHeight = max(contentHeight, fontSize / 2)
        let baselineFromBottom =
            (availableHeight - layoutHeight) / 2 + layoutDescent + contentInsetsBottom
        let descent = min(pointHeight, max(0, baselineFromBottom))
        return (ascent: pointHeight - descent, descent: descent)
    }

    private static func swiftMathCompatibleLatex(_ latex: String) -> String {
        replacingCasesEnvironment(
            in: replacingEnvironmentAliases(
                in: replacingOperatorNameCommands(in: latex)
            )
        )
    }

    private static func replacingEnvironmentAliases(in latex: String) -> String {
        var result = latex
        for wrapper in ["equation", "equation*", "displaymath"] {
            result = result
                .replacingOccurrences(of: "\\begin{\(wrapper)}", with: "")
                .replacingOccurrences(of: "\\end{\(wrapper)}", with: "")
        }

        for (source, target) in [
            ("align", "aligned"),
            ("align*", "aligned"),
            ("multline", "gather"),
            ("multline*", "gather")
        ] {
            result = result
                .replacingOccurrences(of: "\\begin{\(source)}", with: "\\begin{\(target)}")
                .replacingOccurrences(of: "\\end{\(source)}", with: "\\end{\(target)}")
        }

        return result
    }

    private static func replacingCasesEnvironment(in latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\begin{cases}", with: "\\left\\{\\begin{matrix}")
            .replacingOccurrences(of: "\\end{cases}", with: "\\end{matrix}\\right.")
    }

    private static func replacingOperatorNameCommands(in latex: String) -> String {
        let token = "\\operatorname"
        var result = ""
        var cursor = latex.startIndex

        while cursor < latex.endIndex {
            guard latex[cursor...].hasPrefix(token),
                  var groupStart = latex.index(cursor, offsetBy: token.count, limitedBy: latex.endIndex)
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            if groupStart < latex.endIndex, latex[groupStart] == "*" {
                groupStart = latex.index(after: groupStart)
            }

            guard groupStart < latex.endIndex,
                  latex[groupStart] == "{"
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            let contentStart = latex.index(after: groupStart)
            guard
                  let contentEnd = balancedGroupContentEnd(in: latex, contentStart: contentStart)
            else {
                result.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }

            result.append("\\mathrm{")
            result.append(contentsOf: latex[contentStart..<contentEnd])
            result.append("}")
            cursor = latex.index(after: contentEnd)
        }

        return result
    }

    private static func balancedGroupContentEnd(
        in latex: String,
        contentStart: String.Index
    ) -> String.Index? {
        var depth = 1
        var cursor = contentStart

        while cursor < latex.endIndex {
            if latex[cursor] == "{" {
                depth += 1
            } else if latex[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = latex.index(after: cursor)
        }

        return nil
    }

    static func canEnterSwiftMath(
        mainBundleURL: URL = Bundle.main.bundleURL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        // Mirror `MTFont.fontBundle`'s resolution exactly: enter SwiftMath only
        // when the inner `mathFonts.bundle` is loadable from one of the
        // filesystem-probed candidate roots. `MTFont.fontBundle` resolves the
        // same URL via `MTFont.mathFontsBundleURL` and loads it as a `Bundle`,
        // so the guard and the loader agree across signed-`.app`, `swift run`,
        // demo-`.app`, and framework-consumer layouts. Neither path touches
        // SwiftPM's generated `Bundle.module` accessor in a packaged `.app`,
        // because that accessor only checks the `.app` root and a build-time
        // path — never `Contents/Resources` — and would trap with
        // `EXC_BREAKPOINT` in any signed `.app` that ships the bundle under
        // `Contents/Resources`.
        //
        // The resource bundle is named `SiriusMarkdown_SwiftMath.bundle`
        // (SwiftPM's `<PackageName>_<TargetName>` convention) because SwiftMath
        // is vendored as an inline target of the SiriusMarkdown package, not a
        // separate package. Host build scripts must copy
        // `SiriusMarkdown_SwiftMath.bundle` into `Contents/Resources`.
        if MTFont.mathFontsBundleURL(mainBundleURL: mainBundleURL, fileExists: fileExists) != nil {
            return true
        }

        // SwiftPM test and command-line contexts resolve `Bundle.module`'s
        // build-time candidate instead.
        return mainBundleURL.pathExtension.lowercased() != "app"
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
