
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
    
    var defaultCGFont: CGFont!
    var ctFont: CTFont!
    var mathTable: MTFontMathTable?
    var rawMathTable: NSDictionary?
    
    init() {}
    
    /// `MTFont(fontWithName:)` does not load the complete math font, it only has about half the glyphs of the full math font.
    /// In particular it does not have the math italic characters which breaks our variable rendering.
    /// So we first load a CGFont from the file and then convert it to a CTFont.
    convenience init(fontWithName name: String, size:CGFloat) {
        self.init()
        //print("Loading font \(name)")
        let bundle = MTFont.fontBundle
        let fontPath = bundle.path(forResource: name, ofType: "otf")
        let fontDataProvider = CGDataProvider(filename: fontPath!)
        self.defaultCGFont = CGFont(fontDataProvider!)!
        //print("Num glyphs: \(self.defaultCGFont.numberOfGlyphs)")
        
        self.ctFont = CTFontCreateWithGraphicsFont(self.defaultCGFont, size, nil, nil);
        
        //print("Loading associated .plist")
        let mathTablePlist = bundle.url(forResource:name, withExtension:"plist")
        self.rawMathTable = NSDictionary(contentsOf: mathTablePlist!)
        self.mathTable = MTFontMathTable(withFont:self, mathTable:rawMathTable!)
    }
    
    /// Resolves the on-disk URL of the inner `mathFonts.bundle` resource
    /// directory across every context SwiftMath can be loaded in.
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
    /// fatal in shipped apps. A direct filesystem probe is loadable in every
    /// context (signed `.app`, `swift run`, demo `.app`, framework consumer)
    /// without going through `Bundle.module`.
    public static func mathFontsBundleURL(
        mainBundleURL: URL = Bundle.main.bundleURL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let outerName = "SiriusMarkdown_SwiftMath"
        let innerName = "mathFonts.bundle"
        let isApp = mainBundleURL.pathExtension.lowercased() == "app"

        var roots: [URL] = []
        func appendRoot(_ url: URL) {
            let standardized = url.standardizedFileURL
            if !roots.contains(standardized) {
                roots.append(standardized)
            }
        }
        // Signed macOS `.app`: resources live under `Contents/Resources`.
        if isApp {
            appendRoot(mainBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        }
        // `swift run` / SPM bin path: the built resource bundle sits next to the
        // host binary. Also covers an `.app` that keeps the bundle at its root.
        appendRoot(mainBundleURL)
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

    static var fontBundle:Bundle {
        // Resolve the inner `mathFonts.bundle` by direct filesystem probe and
        // load it as a `Bundle`. See `mathFontsBundleURL` for why this cannot
        // use `Bundle.module` or `Bundle.url(forResource:withExtension:)`.
        if let url = MTFont.mathFontsBundleURL(), let bundle = Bundle(url: url) {
            return bundle
        }

        // SwiftPM test / command-line fallback: SwiftMath's generated
        // `Bundle.module` accessor is only safe when `Bundle.main` is NOT a
        // packaged `.app`. In a signed `.app` its two candidates (the `.app`
        // root and a build-time path baked in at compile time) never include
        // `Contents/Resources`, so it would fatal. The filesystem probe above
        // is the only safe `.app` path; never reach `Bundle.module` there.
        if Bundle.main.bundleURL.pathExtension.lowercased() != "app",
           let buildURL = Bundle.module.url(forResource: "mathFonts", withExtension: "bundle"),
           let bundle = Bundle(url: buildURL) {
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
