
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
    
    static var fontBundle:Bundle {
        // SwiftPM's generated `Bundle.module` accessor (built from a
        // `swift-tools-version: 5.7`–6.0 manifest) only checks two candidates:
        //
        //   1. `Bundle.main.bundleURL/<bundle>.bundle` (the `.app` root)
        //   2. A build-time path baked in when SwiftMath was compiled.
        //
        // It never searches `Contents/Resources`, so a signed macOS `.app` —
        // which must keep resources under `Contents/Resources` or codesign
        // rejects the bundle root as unsealed — would fatal at the
        // force-unwrap below. `Bundle.main.url(forResource:withExtension:)`
        // and `Bundle(for:).url(forResource:withExtension:)` DO search the
        // platform resource locations (including `Contents/Resources` on
        // macOS), so try them first, then the `.app` root, and only fall back
        // to `Bundle.module` for SwiftPM test/command-line contexts where the
        // build-time candidate is valid.
        let outerName = "SiriusMarkdown_SwiftMath"
        let outerCandidates: [URL?] = [
            Bundle.main.url(forResource: outerName, withExtension: "bundle"),
            Bundle(for: MTFont.self).url(forResource: outerName, withExtension: "bundle"),
            Bundle.main.bundleURL.appendingPathComponent("\(outerName).bundle", isDirectory: true)
        ]
        for case let outer? in outerCandidates {
            let innerURL = outer.appendingPathComponent("mathFonts.bundle", isDirectory: true)
            if let inner = Bundle(url: innerURL) {
                return inner
            }
        }

        // Test / command-line fallback: SwiftPM's build-time candidate.
        return Bundle(url: Bundle.module.url(forResource: "mathFonts", withExtension: "bundle")!)!
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
