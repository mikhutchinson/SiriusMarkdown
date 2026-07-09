//
//  MathFont.swift
//
//
//  Created by Peter Tang on 10/9/2023.
//

#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Now available for everyone to use
public enum MathFont: String, CaseIterable, Identifiable {
    
    public var id: Self { self }  // Makes things simpler for SwiftUI

    case latinModernFont = "latinmodern-math"
    case kpMathLightFont = "KpMath-Light"
    case kpMathSansFont  = "KpMath-Sans"
    case xitsFont        = "xits-math"
    case termesFont      = "texgyretermes-math"
    case asanaFont       = "Asana-Math"
    case eulerFont       = "Euler-Math"
    case firaFont        = "FiraMath-Regular"
    case notoSansFont    = "NotoSansMath-Regular"
    case libertinusFont  = "LibertinusMath-Regular"
    case garamondFont    = "Garamond-Math"
    case leteSansFont    = "LeteSansMath"
    
    var fontFamilyName: String {
        switch self {
            case .latinModernFont:  "Latin Modern Math"
            case .kpMathLightFont:  "KpMath"
            case .kpMathSansFont:   "KpMath"
            case .xitsFont:         "XITS Math"
            case .termesFont:       "TeX Gyre Termes Math"
            case .asanaFont:        "Asana Math"
            case .eulerFont:        "Euler Math"
            case .firaFont:         "Fira Math"
            case .notoSansFont:     "Noto Sans Math"
            case .libertinusFont:   "Libertinus Math"
            case .garamondFont:     "Garamond Math"
            case .leteSansFont:     "Lete Sans Math"
        }
    }
	
    var fontName: String { self.rawValue }
	
    public func cgFont() -> CGFont {
        guard let cgFont = BundleManager.manager.obtainCGFontIfAvailable(font: self) else {
            fatalError("\(#function) unable to locate CGFont \(fontName)")
        }
        return cgFont
    }
    public func ctFont(withSize size: CGFloat) -> CTFont {
        guard let ctFont = BundleManager.manager.obtainCTFontIfAvailable(font: self, withSize: size) else {
            fatalError("\(#function) unable to locate CTFont \(fontName)")
        }
        return ctFont
    }
    internal func rawMathTable() -> NSDictionary {
        guard let mathTable = BundleManager.manager.obtainRawMathTableIfAvailable(font: self) else {
            fatalError("\(#function) unable to locate mathTable: \(rawValue).plist")
        }
        return mathTable
    }
    internal func cgFontIfAvailable() -> CGFont? {
        BundleManager.manager.obtainCGFontIfAvailable(font: self)
    }
    internal func ctFontIfAvailable(withSize size: CGFloat) -> CTFont? {
        BundleManager.manager.obtainCTFontIfAvailable(font: self, withSize: size)
    }
    internal func rawMathTableIfAvailable() -> NSDictionary? {
        BundleManager.manager.obtainRawMathTableIfAvailable(font: self)
    }
    
    //Note: Below code are no longer supported, unable to tell if UIFont/NSFont is threadsafe, not used in SwiftMath.
    // #if os(iOS) || os(visionOS)
    // public func uiFont(withSize size: CGFloat) -> UIFont? {
    //     UIFont(name: fontName, size: size)
    // }
    // #endif
    // #if os(macOS)
    // public func nsFont(withSize size: CGFloat) -> NSFont? {
    //     NSFont(name: fontName, size: size)
    // }
    // #endif
}
internal extension CTFont {
    /** The size of this font in points. */
    var fontSize: CGFloat {
        CTFontGetSize(self)
    }
    var unitsPerEm: UInt {
        return UInt(CTFontGetUnitsPerEm(self))
    }
}
private class BundleManager {
    //Note: below should be lightweight and without threadsafe problem.
    static internal let manager = BundleManager()

    private var cgFonts = [MathFont: CGFont]()
    private var ctFonts = [CTFontSizePair: CTFont]()
    private var rawMathTables = [MathFont: NSDictionary]()
    private var registeredFontURLs = [MathFont: URL]()

    private let threadSafeQueue = DispatchQueue(label: "com.smartmath.mathfont.threadsafequeue",
                                                qos: .userInitiated,
                                                attributes: .concurrent)

    private func registerCGFont(mathFont: MathFont) throws {
        // Resolve `mathFonts.bundle` through the shared optional loader. It
        // filesystem-probes runtime locations and never calls generated
        // `Bundle.module`, whose missing-resource path is a fatal error.
        guard let resourceURL = MTFont.mathFontsResourceBundle()?.url(
            forResource: mathFont.rawValue,
            withExtension: "otf"
        ) else {
            throw FontError.fontPathNotFound
        }
        guard let fontData = NSData(contentsOf: resourceURL), let dataProvider = CGDataProvider(data: fontData) else {
            throw FontError.invalidFontFile
        }
        guard let defaultCGFont = CGFont(dataProvider) else {
            throw FontError.initFontError
        }
        
        cgFonts[mathFont] = defaultCGFont
        
        /// This does not load the complete math font, it only has about half the glyphs of the full math font.
        /// In particular it does not have the math italic characters which breaks our variable rendering.
        /// So we first load a CGFont from the file and then convert it to a CTFont.
        var errorRef: Unmanaged<CFError>? = nil
        let didRegister = CTFontManagerRegisterFontsForURL(resourceURL as CFURL, .process, &errorRef)
        guard didRegister || Self.registrationAlreadyExists(errorRef) else {
            throw FontError.registerFailed
        }
        if didRegister {
            registeredFontURLs[mathFont] = resourceURL
        }
        let postsript  = (defaultCGFont.postScriptName as? String) ?? ""
        let cgfontName = (defaultCGFont.fullName as? String) ?? ""
        let threadName = Thread.isMainThread ? "main" : "global"
        debugPrint("mathFonts bundle resource: \(mathFont.rawValue), font: \(cgfontName), ps: \(postsript) registered on \(threadName).")
    }

    private static func registrationAlreadyExists(_ errorRef: Unmanaged<CFError>?) -> Bool {
        guard let error = errorRef?.takeRetainedValue() else {
            return false
        }
        return CFEqual(CFErrorGetDomain(error), kCTFontManagerErrorDomain)
            && CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue
    }
    
    private func registerMathTable(mathFont: MathFont) throws {
        guard let mathTablePlist = MTFont.mathFontsResourceBundle()?.url(
            forResource: mathFont.rawValue,
            withExtension: "plist"
        ) else {
            throw FontError.fontPathNotFound
        }
        guard let rawMathTable = NSDictionary(contentsOf: mathTablePlist),
                let version = rawMathTable["version"] as? String,
                version == "1.3" else {
            throw FontError.invalidMathTable
        }
        
        rawMathTables[mathFont] = rawMathTable
        
        let threadName = Thread.isMainThread ? "main" : "global"
        debugPrint("mathFonts bundle resource: \(mathFont.rawValue).plist registered on \(threadName).")
    }
    
    private func onDemandRegistration(mathFont: MathFont) -> Bool {
        let alreadyLoaded = threadSafeQueue.sync {
            cgFonts[mathFont] != nil && rawMathTables[mathFont] != nil
        }
        guard !alreadyLoaded else { return true }
        // Note: resourceLoading is now serialized.
        return threadSafeQueue.sync(flags: .barrier, execute: { [weak self] in
            guard let self else { return false }
            if self.cgFonts[mathFont] == nil || self.rawMathTables[mathFont] == nil {
                do {
                    try BundleManager.manager.registerCGFont(mathFont: mathFont)
                    try BundleManager.manager.registerMathTable(mathFont: mathFont)
                    return true
                } catch {
                    BundleManager.manager.clearCachedResources(for: mathFont)
                    return false
                }
            }
            return true
        })
    }
    private func clearCachedResources(for mathFont: MathFont) {
        cgFonts[mathFont] = nil
        rawMathTables[mathFont] = nil
        ctFonts = ctFonts.filter { $0.key.font != mathFont }
        if let resourceURL = registeredFontURLs.removeValue(forKey: mathFont) {
            var errorRef: Unmanaged<CFError>? = nil
            CTFontManagerUnregisterFontsForURL(resourceURL as CFURL, .process, &errorRef)
        }
    }
    fileprivate func obtainCGFontIfAvailable(font: MathFont) -> CGFont? {
        guard onDemandRegistration(mathFont: font) else { return nil }
        return threadSafeQueue.sync(execute: { cgFonts[font] })
    }
    
    fileprivate func obtainCTFontIfAvailable(font: MathFont, withSize size: CGFloat) -> CTFont? {
        guard MTFont.canRenderFontSize(size) else { return nil }
        guard onDemandRegistration(mathFont: font) else { return nil }
        let fontSizePair = CTFontSizePair(font: font, size: size)
        if let ctFont = threadSafeQueue.sync(execute: { ctFonts[fontSizePair] }) {
            return ctFont
        }
        guard let cgFont = threadSafeQueue.sync(execute: { cgFonts[font] }) else {
            return nil
        }
        //Note: ctfont creation and caching is now threadsafe.
        if let cachedFont = threadSafeQueue.sync(execute: { ctFonts[fontSizePair] }) {
            return cachedFont
        }
        return threadSafeQueue.sync(flags: .barrier, execute: {
            if let ctfont = ctFonts[fontSizePair] {
                return ctfont
            } else {
                let result = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
                ctFonts[fontSizePair] = result
                return result
            }
        })
    }
    fileprivate func obtainRawMathTableIfAvailable(font: MathFont) -> NSDictionary? {
        guard onDemandRegistration(mathFont: font) else { return nil }
        return threadSafeQueue.sync(execute: { rawMathTables[font] } )
    }
    deinit {
        ctFonts.removeAll()
        var errorRef: Unmanaged<CFError>? = nil
        registeredFontURLs.values.forEach { resourceURL in
            CTFontManagerUnregisterFontsForURL(resourceURL as CFURL, .process, &errorRef)
        }
        registeredFontURLs.removeAll()
        cgFonts.removeAll()
    }
    public enum FontError: Error {
        case invalidFontFile
        case fontPathNotFound
        case initFontError
        case registerFailed
        case invalidMathTable
    }
    
    private struct CTFontSizePair: Hashable {
        let font: MathFont
        let size: CGFloat
    }
}
