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

            let (ascent, descent) = Self.estimateAscentDescent(
                latex: typesetLatex,
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

    /// Estimates the typographic ascent and descent of a typeset equation by
    /// inspecting the parsed `MTMathList` atom tree for below-baseline content.
    ///
    /// `MTMathImage` does not expose its internal `MTMathListDisplay` ascent/
    /// descent publicly, so we parse the LaTeX with `MTMathListBuilder` and
    /// recursively check for atoms that extend below the math baseline
    /// (subscripts, fraction denominators, radical degrees, large-operator
    /// limits). The estimate partitions `pointHeight` into `ascent + descent`
    /// so the baseline offset can align the equation with surrounding text.
    ///
    /// - When no descenders are found, the descent is a small fraction of the
    ///   font size (typical font descender).
    /// - When descenders are present, the descent is a larger fraction of the
    ///   total height, reflecting the below-baseline content.
    private static func estimateAscentDescent(
        latex: String,
        pointHeight: Double,
        fontSize: Double
    ) -> (ascent: Double, descent: Double) {
        var error: NSError?
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error),
              error == nil
        else {
            let descent = max(0, fontSize * 0.2)
            return (ascent: max(0, pointHeight - descent), descent: descent)
        }

        let hasDescenders = atomTreeHasDescenders(mathList)

        let descent: Double
        if hasDescenders {
            descent = pointHeight * 0.38
        } else {
            descent = min(pointHeight * 0.25, fontSize * 0.22)
        }

        let clampedDescent = max(0, min(descent, pointHeight))
        return (ascent: max(0, pointHeight - clampedDescent), descent: clampedDescent)
    }

    /// Recursively inspects a `MTMathList` atom tree for content that extends
    /// below the math baseline.
    private static func atomTreeHasDescenders(_ list: MTMathList) -> Bool {
        for atom in list.atoms {
            if atomHasDescenders(atom) {
                return true
            }
        }
        return false
    }

    /// Checks whether a single `MTMathAtom` (and its subtrees) has descenders.
    private static func atomHasDescenders(_ atom: MTMathAtom) -> Bool {
        if atom.subScript != nil {
            return true
        }

        if let fraction = atom as? MTFraction, fraction.denominator != nil {
            return true
        }

        if let radical = atom as? MTRadical, let radicand = radical.radicand {
            if atomTreeHasDescenders(radicand) {
                return true
            }
        }

        if let largeOp = atom as? MTLargeOperator, largeOp.limits {
            return true
        }

        if let inner = atom as? MTInner, let innerList = inner.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let overline = atom as? MTOverLine, let innerList = overline.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let underline = atom as? MTUnderLine, let innerList = underline.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let accent = atom as? MTAccent, let innerList = accent.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let color = atom as? MTMathColor, let innerList = color.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let textColor = atom as? MTMathTextColor, let innerList = textColor.innerList {
            if atomTreeHasDescenders(innerList) {
                return true
            }
        }

        if let superScript = atom.superScript, atomTreeHasDescenders(superScript) {
            return true
        }

        return false
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
        // The vendored SwiftMath target's `MTFont.fontBundle` searches
        // `Bundle.main.url(forResource:)` and `Bundle(for:).url(forResource:)`
        // before falling back to `Bundle.module`, so it loads the resource
        // bundle from either the signed-macOS-`.app` resource directory
        // (`Contents/Resources`) or the `.app` root. Accept both layouts here,
        // then fall back to text rendering when neither loadable location
        // exists. `MTFont.fontBundle` also requires the inner `mathFonts.bundle`,
        // so verify it is present at the same location.
        //
        // The resource bundle is named `SiriusMarkdown_SwiftMath.bundle`
        // (SwiftPM's `<PackageName>_<TargetName>` convention) because SwiftMath
        // is vendored as an inline target of the SiriusMarkdown package, not a
        // separate package. Host build scripts must copy
        // `SiriusMarkdown_SwiftMath.bundle` into `Contents/Resources`.
        for resourceDirectory in swiftMathResourceDirectories(mainBundleURL: mainBundleURL) {
            let mathFontsBundle = resourceDirectory
                .appendingPathComponent("SiriusMarkdown_SwiftMath.bundle", isDirectory: true)
                .appendingPathComponent("mathFonts.bundle", isDirectory: true)
            if fileExists(mathFontsBundle.path) {
                return true
            }
        }

        // SwiftPM test and command-line contexts resolve `Bundle.module`'s
        // build-time candidate instead.
        return mainBundleURL.pathExtension.lowercased() != "app"
    }

    private static func swiftMathResourceDirectories(mainBundleURL: URL) -> [URL] {
        var directories: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else {
                return
            }
            directories.append(standardized)
        }

        append(mainBundleURL)
        if mainBundleURL.pathExtension.lowercased() == "app" {
            append(mainBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        }

        return directories
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
