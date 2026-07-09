
import Foundation
import CoreText

//
//  Created by Mike Griebling on 2022-12-31.
//  Translated from an Objective-C implementation by Kostub Deshmukh.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

public class MTFont {
    static let maximumRenderableFontSize: CGFloat = 512

    static func canRenderFontSize(_ size: CGFloat) -> Bool {
        size.isFinite && size > 0 && size <= maximumRenderableFontSize
    }
    
    var defaultCGFont: CGFont!
    var ctFont: CTFont!
    var mathTable: MTFontMathTable?
    var rawMathTable: NSDictionary?
    
    init() {}
    
    /// `MTFont(fontWithName:)` does not load the complete math font, it only has about half the glyphs of the full math font.
    /// In particular it does not have the math italic characters which breaks our variable rendering.
    /// So we first load a CGFont from the file and then convert it to a CTFont.
    convenience init?(fontWithName name: String, size:CGFloat) {
        guard Self.canRenderFontSize(size) else { return nil }
        self.init()
        //print("Loading font \(name)")
        let bundle = MTFont.fontBundle
        guard let fontPath = bundle.path(forResource: name, ofType: "otf"),
              let fontDataProvider = CGDataProvider(filename: fontPath),
              let defaultCGFont = CGFont(fontDataProvider) else {
            return nil
        }
        self.defaultCGFont = defaultCGFont
        //print("Num glyphs: \(self.defaultCGFont.numberOfGlyphs)")
        
        self.ctFont = CTFontCreateWithGraphicsFont(self.defaultCGFont, size, nil, nil);
        
        //print("Loading associated .plist")
        guard let mathTablePlist = bundle.url(forResource:name, withExtension:"plist"),
              let rawMathTable = NSDictionary(contentsOf: mathTablePlist) else {
            return nil
        }
        self.rawMathTable = rawMathTable
        self.mathTable = MTFontMathTable(withFont:self, mathTable:rawMathTable)
    }
    
    /// Resolves the on-disk URL of the inner `mathFonts.bundle` resource
    /// directory by probing runtime filesystem locations.
    ///
    /// This deliberately avoids SwiftPM's generated `Bundle.module` accessor and
    /// `Bundle.url(forResource:withExtension:)`. `Bundle.module` (as emitted by
    /// current Swift 5.9–6.x toolchains) only loads from
    /// `Bundle.main.bundleURL/<name>.bundle` and a build-time path baked in at
    /// compile time — neither of which is `Contents/Resources`, so it fatals
    /// (`EXC_BREAKPOINT`) inside any signed macOS `.app` that ships the resource
    /// bundle under `Contents/Resources`. `Bundle.url(forResource:withExtension:)`
    /// is also not a reliable way to locate a nested `.bundle` directory: some
    /// macOS releases stop returning wrapped-bundle directories from that API,
    /// which is exactly the regression that re-triggered the `Bundle.module`
    /// fatal in shipped apps. A direct filesystem probe covers signed `.app`,
    /// demo `.app`, framework consumer, SwiftPM test hosts, and command-line
    /// layouts without going through `Bundle.module`.
    public static func mathFontsBundleURL(
        mainBundleURL: URL = Bundle.main.bundleURL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let outerName = "SiriusMarkdown_SwiftMath"
        let innerName = "mathFonts.bundle"
        let isApp = mainBundleURL.pathExtension.lowercased() == "app"

        var roots: [URL] = []
        func appendUniqueRoot(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !roots.contains(standardized) {
                roots.append(standardized)
            }
        }
        func appendRoot(_ url: URL) {
            appendUniqueRoot(url)
            appendUniqueRoot(url.appendingPathComponent("Contents/Resources", isDirectory: true))
        }
        func appendRootAndAncestors(_ url: URL, limit: Int) {
            appendRoot(url)
            var ancestor = url
            for _ in 0..<limit {
                ancestor = ancestor.deletingLastPathComponent()
                appendRoot(ancestor)
            }
        }
        // Signed macOS `.app`: resources live under `Contents/Resources`.
        if isApp {
            appendRoot(mainBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        }
        // `swift run` / SPM bin path: the built resource bundle sits next to the
        // host binary. Also covers an `.app` that keeps the bundle at its root.
        appendRoot(mainBundleURL)
        if !isApp {
            // XCTest can report Bundle.main under
            // `.build/debug/PackageTests.xctest/Contents/MacOS`; climb a
            // bounded ancestor chain back to `.build/debug` without using
            // SwiftPM's generated `Bundle.module` accessor.
            appendRootAndAncestors(mainBundleURL, limit: 5)

            // Swift Testing runs inside `swiftpm-testing-helper`, with the real
            // `.xctest` bundle path passed as an argument.
            for (index, argument) in CommandLine.arguments.enumerated()
                where argument == "--test-bundle-path" && index + 1 < CommandLine.arguments.count {
                appendRootAndAncestors(URL(fileURLWithPath: CommandLine.arguments[index + 1]), limit: 6)
            }
        }
        // Framework / dylib consumer: the bundle owning `MTFont` may differ from
        // `Bundle.main` when SwiftMath is linked into a framework rather than an app.
        if let ownerResources = Bundle(for: MTFont.self).resourceURL {
            appendRoot(ownerResources)
        }

        for root in roots {
            let candidate = root
                .appendingPathComponent("\(outerName).bundle", isDirectory: true)
                .appendingPathComponent(innerName, isDirectory: true)
            if fileExists(candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func mathFontsResourceBundle() -> Bundle? {
        // Resolve the inner `mathFonts.bundle` by direct filesystem probe and
        // load it as a `Bundle`. See `mathFontsBundleURL` for why packaged apps
        // cannot use `Bundle.module` or `Bundle.url(forResource:withExtension:)`.
        if let url = MTFont.mathFontsBundleURL(), let bundle = Bundle(url: url) {
            return bundle
        }

        return nil
    }

    static var fontBundle:Bundle {
        if let bundle = mathFontsResourceBundle() {
            return bundle
        }

        // Unreachable in a packaged `.app` when `canEnterSwiftMath` has gated
        // entry (it uses the same resolver). Return `Bundle.main` instead of
        // trapping so a missed guard degrades to a font-load nil rather than a
        // process crash.
        return Bundle.main
    }
    
    /** Returns a copy of this font but with a different size. */
    public func copy(withSize size: CGFloat) -> MTFont {
        guard Self.canRenderFontSize(size) else { return self }
        let newFont = MTFont()
        newFont.defaultCGFont = self.defaultCGFont
        newFont.ctFont = CTFontCreateWithGraphicsFont(self.defaultCGFont, size, nil, nil)
        newFont.rawMathTable = self.rawMathTable
        newFont.mathTable = MTFontMathTable(withFont: newFont, mathTable: newFont.rawMathTable!)
        return newFont
    }
    
    func get(nameForGlyph glyph:CGGlyph) -> String {
        let name = defaultCGFont.name(for: glyph) as? String
        return name ?? ""
    }
    
    func get(glyphWithName name:String) -> CGGlyph {
        defaultCGFont.getGlyphWithGlyphName(name: name as CFString)
    }
    
    /** The size of this font in points. */
    public var fontSize:CGFloat { CTFontGetSize(self.ctFont) }
    
    deinit {
        self.ctFont = nil
        self.defaultCGFont = nil
    }
    
}
