import Foundation
import CoreGraphics
import Testing
import SiriusMarkdownCore
import SiriusMarkdownSwiftUI
@testable import SiriusMarkdownMath
#if canImport(SwiftMath)
@testable import SwiftMath
#endif

@Test
func nativeMathRendererProducesTypesetImageForValidLatex() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("x^2 + \\alpha", isBlock: true, fontSize: 20)

    guard case let .image(image) = prepared else {
        Issue.record("Expected a typeset image for valid LaTeX, got \(prepared).")
        return
    }

    #expect(!image.imageData.isEmpty)
    #expect(image.pointWidth > 0)
    #expect(image.pointHeight > 0)
    #expect(image.scale == NativeMarkdownMathRenderer.renderScale)
    #expect(image.latex == "x^2 + \\alpha")
}

@Test
func swiftMathTypesetterRejectsWhenResourcePathsAreMissing() {
    #if canImport(SwiftMath)
    let appURL = URL(fileURLWithPath: "/tmp/Sirius.app", isDirectory: true)

    // No bundle present in a packaged .app -> text fallback, never enter SwiftMath.
    #expect(!SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: appURL) { _ in false })

    // A packaged .app with only the bundle directory but missing the default
    // font assets must not enter SwiftMath; `MTFont(fontWithName:)` force
    // unwraps those assets.
    #expect(!SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: appURL) { path in
        path.hasSuffix("Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle")
    })

    // `MTFont.fontBundle` resolves `mathFonts.bundle` by direct filesystem
    // probe (via `MTFont.mathFontsBundleURL`) of `Contents/Resources` in a
    // signed macOS `.app`, and `canEnterSwiftMath` mirrors that same resolver
    // so the guard and the loader agree. The standard packaged-app resource
    // layout therefore enters SwiftMath without ever touching SwiftPM's
    // generated `Bundle.module` accessor (which fatals in a signed `.app`
    // because it never searches `Contents/Resources`). The bundle is named
    // `SiriusMarkdown_SwiftMath.bundle` because SwiftMath is vendored as an
    // inline target of the SiriusMarkdown package, so SwiftPM uses its
    // `<Package>_<Target>` resource-bundle naming convention.
    #expect(SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: appURL) { path in
        path.hasSuffix("Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle")
            || path.hasSuffix("Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle/latinmodern-math.otf")
            || path.hasSuffix("Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle/latinmodern-math.plist")
    })

    // A bundle at the .app root is also accepted (same filesystem probe).
    #expect(SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: appURL) { path in
        path.hasSuffix("Sirius.app/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle")
            || path.hasSuffix("Sirius.app/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle/latinmodern-math.otf")
            || path.hasSuffix("Sirius.app/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle/latinmodern-math.plist")
    })

    // Non-app hosts are not special: if filesystem-probed resources are absent,
    // do not enter SwiftMath and do not fall through to generated `Bundle.module`.
    let testHostURL = URL(fileURLWithPath: "/tmp/SiriusMarkdownPackageTests.xctest", isDirectory: true)
    #expect(!SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: testHostURL) { _ in false })
    #endif
}

@Test
func swiftMathBundleURLFindsSwiftPMTestHostSiblingResources() {
    #if canImport(SwiftMath)
    let testHostURL = URL(fileURLWithPath: "/tmp/.build/debug/SiriusMarkdownPackageTests.xctest", isDirectory: true)
    let expected = "/tmp/.build/debug/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle"

    let resolved = MTFont.mathFontsBundleURL(mainBundleURL: testHostURL) { path in
        path == expected
    }

    #expect(resolved?.path == expected)
    #endif
}

@Test
func swiftMathBundleURLFindsSwiftPMNestedXCTestRuntimeResources() {
    #if canImport(SwiftMath)
    let testHostURL = URL(
        fileURLWithPath: "/tmp/.build/debug/SiriusMarkdownPackageTests.xctest/Contents/MacOS",
        isDirectory: true
    )
    let expected = "/tmp/.build/debug/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle"

    let resolved = MTFont.mathFontsBundleURL(mainBundleURL: testHostURL) { path in
        path == expected
    }

    #expect(resolved?.path == expected)
    #endif
}

@Test
func swiftMathBundleURLFindsBundleContentsResources() {
    #if canImport(SwiftMath)
    let testHostURL = URL(fileURLWithPath: "/tmp/SiriusMarkdownPackageTests.xctest", isDirectory: true)
    let expected = "/tmp/SiriusMarkdownPackageTests.xctest/Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle"

    let resolved = MTFont.mathFontsBundleURL(mainBundleURL: testHostURL) { path in
        path == expected
    }

    #expect(resolved?.path == expected)
    #expect(SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: testHostURL) { path in
        path == expected
            || path == "\(expected)/latinmodern-math.otf"
            || path == "\(expected)/latinmodern-math.plist"
    })
    #endif
}

@Test
func swiftMathBundleURLFindsAppExtensionContentsResources() {
    #if canImport(SwiftMath)
    let extensionURL = URL(fileURLWithPath: "/tmp/SiriusMarkdownExtension.appex", isDirectory: true)
    let expected = "/tmp/SiriusMarkdownExtension.appex/Contents/Resources/SiriusMarkdown_SwiftMath.bundle/mathFonts.bundle"

    let resolved = MTFont.mathFontsBundleURL(mainBundleURL: extensionURL) { path in
        path == expected
    }

    #expect(resolved?.path == expected)
    #expect(SwiftMathTypesetter.canEnterSwiftMath(mainBundleURL: extensionURL) { path in
        path == expected
            || path == "\(expected)/latinmodern-math.otf"
            || path == "\(expected)/latinmodern-math.plist"
    })
    #endif
}

@Test
func swiftMathFontManagerReturnsNilForMissingFontName() {
    #if canImport(SwiftMath)
    let manager = MTFontManager()
    #expect(manager.font(withName: "__sirius_missing_math_font__", size: 20) == nil)
    #endif
}

@Test
func swiftMathImageReturnsNilWhenFontIsUnavailable() {
    #if canImport(SwiftMath)
    let image = MTMathImage(
        latex: "x^2",
        fontSize: 20,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    image.font = nil

    let (error, renderedImage, layout) = image.asImage()
    #expect(error == nil)
    #expect(renderedImage == nil)
    #expect(layout == nil)
    #endif
}

@Test
func swiftMathStructImageUsesOptionalBundleFontBoundary() {
    #if canImport(SwiftMath)
    var image = MathImage(
        latex: "x^2",
        fontSize: 20,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )

    let (error, renderedImage, layout) = image.asImage()
    #expect(error == nil)
    #expect(renderedImage != nil)
    #expect(layout != nil)
    #endif
}

@Test
func swiftMathImagesRejectOversizedRasterBeforeImageCreation() {
    #if canImport(SwiftMath)
    let oversizedLatex = String(repeating: "x", count: 128)
    let classImage = MTMathImage(
        latex: oversizedLatex,
        fontSize: 512,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    let (classError, classRenderedImage, classLayout) = classImage.asImage()
    #expect(classError == nil)
    #expect(classRenderedImage == nil)
    #expect(classLayout == nil)

    var structImage = MathImage(
        latex: oversizedLatex,
        fontSize: 512,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    let (structError, structRenderedImage, structLayout) = structImage.asImage()
    #expect(structError == nil)
    #expect(structRenderedImage == nil)
    #expect(structLayout == nil)
    #endif
}

@Test
func swiftMathStructImageKeepsCompactGlyphBaselineInsideRaster() throws {
    #if canImport(SwiftMath)
    let fontSize: CGFloat = 32
    let minimumRasterHeight = fontSize / 2
    let classImage = MTMathImage(
        latex: "x",
        fontSize: fontSize,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    let (classError, classRenderedImage, _) = classImage.asImage()
    #expect(classError == nil)
    #expect(try #require(classRenderedImage).size.height >= minimumRasterHeight)

    var structImage = MathImage(
        latex: "x",
        fontSize: fontSize,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    let (structError, structRenderedImage, _) = structImage.asImage()
    #expect(structError == nil)
    #expect(try #require(structRenderedImage).size.height >= minimumRasterHeight)
    #endif
}

@Test
func swiftMathDirectImagesRejectInvalidFontSizesBeforeFontCreation() {
    #if canImport(SwiftMath)
    let invalidFontSizes: [CGFloat] = [.nan, .infinity, -.infinity, 0, -12, 513]
    let manager = MTFontManager.manager

    for fontSize in invalidFontSizes {
        #expect(manager.latinModernFont(withSize: fontSize) == nil)

        let classImage = MTMathImage(
            latex: "x^2",
            fontSize: fontSize,
            textColor: MTColor.black,
            labelMode: .display,
            textAlignment: .left
        )
        let (classError, classRenderedImage, classLayout) = classImage.asImage()
        #expect(classError == nil)
        #expect(classRenderedImage == nil)
        #expect(classLayout == nil)

        var structImage = MathImage(
            latex: "x^2",
            fontSize: fontSize,
            textColor: MTColor.black,
            labelMode: .display,
            textAlignment: .left
        )
        let (structError, structRenderedImage, structLayout) = structImage.asImage()
        #expect(structError == nil)
        #expect(structRenderedImage == nil)
        #expect(structLayout == nil)
    }
    #endif
}

@Test
func swiftMathImageCanRecoverAfterInvalidFontSizeAssignment() {
    #if canImport(SwiftMath)
    let image = MTMathImage(
        latex: "x^2",
        fontSize: 20,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )

    image.fontSize = .nan
    let (_, invalidImage, invalidLayout) = image.asImage()
    #expect(invalidImage == nil)
    #expect(invalidLayout == nil)

    image.fontSize = 20
    let (error, recoveredImage, recoveredLayout) = image.asImage()
    #expect(error == nil)
    #expect(recoveredImage != nil)
    #expect(recoveredLayout != nil)
    #endif
}

@MainActor
@Test
func swiftMathLabelRejectsInvalidFontSizesWithoutPoisoningLayoutState() {
    #if canImport(SwiftMath)
    let label = MTMathUILabel(frame: .init(x: 0, y: 0, width: 240, height: 80))
    label.latex = "x^2"
    label.fontSize = 20

    let invalidFontSizes: [CGFloat] = [.nan, .infinity, -.infinity, 0, -12, 513]
    for fontSize in invalidFontSizes {
        label.fontSize = fontSize
        #expect(label.fontSize == 20)
    }

    label.fontSize = 24
    #expect(label.fontSize == 24)
    #endif
}

@Test
func swiftMathTypesetterRejectsMalformedCompositeAtomsWithoutTrapping() throws {
    #if canImport(SwiftMath)
    let font = try #require(MTFontManager.manager.latinModernFont(withSize: 20))

    let table = MTMathTable(environment: "array")
    table.set(cell: MTMathList(atom: MTFraction()), forRow: 0, column: 0)

    let malformedAtoms: [(String, MTMathAtom)] = [
        ("fraction", MTFraction()),
        ("radical", MTRadical()),
        ("inner", MTInner()),
        ("underline", MTUnderLine()),
        ("overline", MTOverLine()),
        ("accent", MTAccent(value: "\u{0302}")),
        ("color", MTMathColor()),
        ("textcolor", MTMathTextColor()),
        ("colorbox", MTMathColorbox()),
        ("table-cell", table)
    ]

    for (name, atom) in malformedAtoms {
        let list = MTMathList(atom: atom)
        let display = MTTypesetter.createLineForMathList(list, font: font, style: .display)
        #expect(display == nil, "\(name) should fail closed.")
    }
    #endif
}

@Test
func swiftMathAtomCopiesNormalizeMismatchedPublicTypesWithoutTrapping() {
    #if canImport(SwiftMath)
    let baseAtom = MTMathAtomFactory.placeholder()
    baseAtom.type = .largeOperator

    let scriptedBaseAtom = MTMathAtomFactory.placeholder()
    scriptedBaseAtom.superScript = MTMathList(atom: MTMathAtomFactory.placeholder())
    scriptedBaseAtom.type = .space

    let fraction = MTMathAtomFactory.placeholderFraction()
    fraction.type = .table

    let style = MTMathStyle(style: .display)
    style.type = .overline

    let scriptedStyle = MTMathStyle(style: .display)
    scriptedStyle.type = .ordinary
    scriptedStyle.subScript = MTMathList(atom: MTMathAtomFactory.placeholder())
    scriptedStyle.type = .style

    let copiedBase: MTMathAtom = baseAtom.copy()
    let copiedScriptedBase: MTMathAtom = scriptedBaseAtom.copy()
    let copiedFraction: MTMathAtom = fraction.copy()
    let copiedStyle: MTMathAtom = style.copy()
    let copiedScriptedStyle: MTMathAtom = scriptedStyle.copy()

    #expect(copiedBase.type == .ordinary)
    #expect(copiedScriptedBase.type == .ordinary)
    #expect(copiedScriptedBase.superScript != nil)
    #expect(copiedFraction is MTFraction)
    #expect(copiedFraction.type == .fraction)
    #expect(copiedStyle is MTMathStyle)
    #expect(copiedStyle.type == .style)
    #expect(copiedScriptedStyle is MTMathStyle)
    #expect(copiedScriptedStyle.type == .style)
    #expect(copiedScriptedStyle.subScript == nil)

    _ = MTMathList(atom: baseAtom).finalized
    _ = MTMathList(atom: scriptedBaseAtom).finalized
    _ = MTMathList(atom: fraction).finalized
    _ = MTMathList(atom: style).finalized
    _ = MTMathList(atom: scriptedStyle).finalized
    #endif
}

@Test
func swiftMathTableFinalizationFinalizesCopiedCells() throws {
    #if canImport(SwiftMath)
    let list = try #require(MTMathListBuilder.build(fromString: "\\begin{matrix}12\\end{matrix}"))
    let table = try #require(list.atoms.first as? MTMathTable)
    let originalCell = try #require(table.cells.first?.first)
    let finalizedTable = try #require(table.finalized as? MTMathTable)
    let finalizedCell = try #require(finalizedTable.cells.first?.first)

    let originalNumbers = originalCell.atoms.filter { $0.type == .number }
    let finalizedNumbers = finalizedCell.atoms.filter { $0.type == .number }
    #expect(originalNumbers.map(\.nucleus) == ["1", "2"])
    #expect(finalizedNumbers.count == 1)
    #expect(finalizedNumbers.first?.nucleus == "12")
    #expect(finalizedCell !== originalCell)
    #endif
}

@Test
func swiftMathLatexSerializationDoesNotMutateTableCells() throws {
    #if canImport(SwiftMath)
    let list = try #require(MTMathListBuilder.build(
        fromString: "\\begin{matrix}1&2\\\\3&4\\end{matrix}"
    ))
    let table = try #require(list.atoms.first as? MTMathTable)
    let atomCountsBefore = table.cells.map { row in row.map { $0.atoms.count } }

    let first = MTMathListBuilder.mathListToString(list)
    let second = MTMathListBuilder.mathListToString(list)

    #expect(first == second)
    #expect(first.contains("\\begin{matrix}"))
    #expect(first.contains("\\end{matrix}"))
    #expect(table.cells.map { row in row.map { $0.atoms.count } } == atomCountsBefore)
    #endif
}

@Test
func swiftMathLatexSerializationPreservesColorAtoms() throws {
    #if canImport(SwiftMath)
    let latex = "\\color{#FF0000}{x}+\\textcolor{blue}{y}+\\colorbox{yellow}{z}"
    let list = try #require(MTMathListBuilder.build(fromString: latex))
    let serialized = MTMathListBuilder.mathListToString(list)

    #expect(serialized == latex)
    #expect(MTMathListBuilder.build(fromString: serialized) != nil)
    #endif
}

@Test
func swiftMathLatexSerializationFailsClosedForIncompletePublicModels() {
    #if canImport(SwiftMath)
    let customOperator = MTMathAtomFactory.operatorWithName("customop", limits: false)
    let fraction = MTFraction()
    let color = MTMathColor()
    color.colorString = "red"
    let list = MTMathList(atoms: [customOperator, fraction, color])

    let serialized = MTMathListBuilder.mathListToString(list)

    #expect(serialized.contains("customop"))
    #expect(serialized.contains("\\frac{}{}"))
    #expect(serialized.contains("\\color{red}{}"))
    #expect(color.string == "\\color{red}{}")
    #endif
}

@Test
func swiftMathTableIgnoresNegativePublicIndices() {
    #if canImport(SwiftMath)
    let table = MTMathTable()
    table.set(cell: MTMathList(), forRow: -1, column: 0)
    table.set(cell: MTMathList(), forRow: 0, column: -1)
    table.set(alignment: .left, forColumn: -1)

    #expect(table.cells.isEmpty)
    #expect(table.alignments.isEmpty)
    #expect(table.get(alignmentForColumn: -1) == .center)
    #endif
}

@Test
func swiftMathTypesetterFallsBackWhenMathTableVariantListsAreEmpty() throws {
    #if canImport(SwiftMath)
    let font = try #require(MTFontManager.manager.latinModernFont(withSize: 20))
    let rawMathTable = try #require(font.rawMathTable)
    font.mathTable = EmptyVariantMathTable(withFont: font, mathTable: rawMathTable)

    let image = MTMathImage(
        latex: "\\sqrt{x} + \\hat{x}",
        fontSize: 20,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    image.font = font

    let (error, renderedImage, layout) = image.asImage()
    #expect(error == nil)
    #expect(renderedImage != nil)
    #expect(layout != nil)
    #endif
}

@Test
func swiftMathLegacyMathTableTreatsMissingOptionalTablesAsFallbacks() throws {
    #if canImport(SwiftMath)
    let font = try #require(MTFontManager.manager.latinModernFont(withSize: 20))
    let rawMathTable = try #require(font.rawMathTable)
    let incompleteMathTable = NSMutableDictionary(dictionary: rawMathTable)
    for key in ["v_variants", "h_variants", "v_assembly", "italic", "accents"] {
        incompleteMathTable.removeObject(forKey: key)
    }
    font.mathTable = MTFontMathTable(withFont: font, mathTable: incompleteMathTable)

    let image = MTMathImage(
        latex: "\\sum_{i=0}^{n} i + \\sqrt{x} + \\hat{x}",
        fontSize: 20,
        textColor: MTColor.black,
        labelMode: .display,
        textAlignment: .left
    )
    image.font = font

    let (error, renderedImage, layout) = image.asImage()
    #expect(error == nil)
    #expect(renderedImage != nil)
    #expect(layout != nil)
    #endif
}

@Test
func swiftMathBundleFontLoaderKeepsOptionalFallbackBoundary() throws {
    #if canImport(SwiftMath)
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let mathFontSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SwiftMath/MathBundle/MathFont.swift"),
        encoding: .utf8
    )
    let mtFontSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SwiftMath/MathBundle/MTFontV2.swift"),
        encoding: .utf8
    )
    let mtFontLoaderSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SwiftMath/MathRender/MTFont.swift"),
        encoding: .utf8
    )

    #expect(mathFontSource.contains("private func onDemandRegistration(mathFont: MathFont) -> Bool"))
    #expect(mathFontSource.contains("MTFont.mathFontsResourceBundle()"))
    #expect(mathFontSource.contains("clearCachedResources(for: mathFont)"))
    #expect(mathFontSource.contains("if let cachedFont = threadSafeQueue.sync"))
    #expect(!mathFontSource.contains("return ctFonts[fontSizePair]!"))
    #expect(!mathFontSource.contains("fatalError(\"MTMathFonts:"))
    #expect(!mtFontLoaderSource.contains("Bundle.module.url"))
    #expect(mtFontSource.contains("public func mtfont(size: CGFloat) -> MTFontV2 {"))
    #expect(mtFontSource.contains("internal func mtfontIfAvailable(size: CGFloat) -> MTFontV2?"))
    #endif
}

#if canImport(SwiftMath)
private final class EmptyVariantMathTable: MTFontMathTable {
    override func getVerticalVariantsForGlyph(_ glyph: CGGlyph) -> [NSNumber?] {
        []
    }

    override func getHorizontalVariantsForGlyph(_ glyph: CGGlyph) -> [NSNumber?] {
        []
    }
}
#endif

@Test
func swiftMathFontCacheSupportsConcurrentSizeLookups() {
    #if canImport(SwiftMath)
    let queue = DispatchQueue(label: "SiriusMarkdownTests.SwiftMathFontCache", attributes: .concurrent)
    let group = DispatchGroup()
    let failures = LockedFailureCounter()

    for index in 0..<96 {
        group.enter()
        queue.async {
            let size = CGFloat(12 + (index % 12))
            let font = MathFont.latinModernFont.mtfont(size: size)
            if abs(font.fontSize - size) > 0.001 {
                failures.increment()
            }
            group.leave()
        }
    }

    #expect(group.wait(timeout: .now() + 5) == .success)
    #expect(failures.value == 0)
    #endif
}

@Test
func swiftMathFontCopiesPreserveRequestedSize() throws {
    #if canImport(SwiftMath)
    let bundleFont = try #require(MTFontManager.manager.latinModernFont(withSize: 13))
    let copiedBundleFont = bundleFont.copy(withSize: 27)
    #expect(abs(bundleFont.fontSize - 13) <= 0.001)
    #expect(abs(copiedBundleFont.fontSize - 27) <= 0.001)

    let mathFont = MathFont.latinModernFont.mtfont(size: 14)
    let copiedMathFont = mathFont.copy(withSize: 28)
    #expect(abs(mathFont.fontSize - 14) <= 0.001)
    #expect(abs(copiedMathFont.fontSize - 28) <= 0.001)
    #endif
}

@Test
func swiftMathFontManagerSupportsConcurrentDefaultFontLookups() {
    #if canImport(SwiftMath)
    let queue = DispatchQueue(label: "SiriusMarkdownTests.SwiftMathFontManager", attributes: .concurrent)
    let group = DispatchGroup()
    let failures = LockedFailureCounter()

    for index in 0..<96 {
        group.enter()
        queue.async {
            let size = CGFloat(12 + (index % 12))
            guard let font = MTFontManager.manager.latinModernFont(withSize: size),
                  abs(font.fontSize - size) <= 0.001 else {
                failures.increment()
                group.leave()
                return
            }
            group.leave()
        }
    }

    #expect(group.wait(timeout: .now() + 5) == .success)
    #expect(failures.value == 0)
    #endif
}

@Test
func swiftMathV2FontSupportsConcurrentMathTableUse() {
    #if canImport(SwiftMath)
    let sharedFont = SharedMTFontBox(MathFont.latinModernFont.mtfont(size: 20))
    let queue = DispatchQueue(label: "SiriusMarkdownTests.SwiftMathV2MathTable", attributes: .concurrent)
    let group = DispatchGroup()
    let failures = LockedFailureCounter()

    for index in 0..<96 {
        group.enter()
        queue.async {
            let image = MTMathImage(
                latex: "x_\(index % 9)^2 + \\frac{a}{b}",
                fontSize: 20,
                textColor: MTColor.black,
                labelMode: .display,
                textAlignment: .left
            )
            image.font = sharedFont.font
            let (error, renderedImage, layout) = image.asImage()
            if error != nil || renderedImage == nil || layout == nil {
                failures.increment()
            }
            group.leave()
        }
    }

    #expect(group.wait(timeout: .now() + 5) == .success)
    #expect(failures.value == 0)
    #endif
}

@Test
func swiftMathCustomSymbolRegistrySupportsConcurrentReadsAndCleanOverrides() throws {
    #if canImport(SwiftMath)
    let symbolName = "siriusConcurrentRegistryProbe"
    let oldValue = MTMathAtomFactory.operatorWithName("siriusOldRegistryValue", limits: false)
    let newValue = MTMathAtomFactory.operatorWithName("siriusNewRegistryValue", limits: false)

    MTMathAtomFactory.add(latexSymbol: symbolName, value: oldValue)
    #expect(MTMathAtomFactory.latexSymbolName(for: oldValue) == symbolName)

    MTMathAtomFactory.add(latexSymbol: symbolName, value: newValue)
    #expect(MTMathAtomFactory.atom(forLatexSymbol: symbolName)?.nucleus == newValue.nucleus)
    #expect(MTMathAtomFactory.latexSymbolName(for: oldValue) == nil)
    #expect(MTMathAtomFactory.latexSymbolName(for: newValue) == symbolName)

    let alpha = try #require(MTMathAtomFactory.atom(forLatexSymbol: "alpha"))
    MTMathAtomFactory.add(latexSymbol: symbolName, value: alpha)
    #expect(MTMathAtomFactory.latexSymbolName(for: alpha) == symbolName)
    MTMathAtomFactory.add(latexSymbol: symbolName, value: newValue)
    #expect(MTMathAtomFactory.latexSymbolName(for: alpha) == "alpha")

    DispatchQueue.concurrentPerform(iterations: 200) { index in
        if index.isMultiple(of: 4) {
            let value = MTMathAtomFactory.operatorWithName(
                index.isMultiple(of: 8) ? "siriusConcurrentA" : "siriusConcurrentB",
                limits: false
            )
            MTMathAtomFactory.add(latexSymbol: symbolName, value: value)
        } else {
            _ = MTMathAtomFactory.atom(forLatexSymbol: symbolName)
            _ = MTMathAtomFactory.textToLatexSymbolName
            _ = MTMathAtomFactory.delimValueToName
            _ = MTMathAtomFactory.accentValueToName
        }
    }

    #expect(MTMathAtomFactory.atom(forLatexSymbol: symbolName) != nil)
    #endif
}

@Test
func nativeMathRendererTypesetsDisplayAndInlineStyles() {
    let renderer = NativeMarkdownMathRenderer()
    let block = renderer.preparedMath("\\sum_{i=1}^{n} i", isBlock: true, fontSize: 22)
    let inline = renderer.preparedMath("\\sum_{i=1}^{n} i", isBlock: false, fontSize: 14)

    if case let .image(blockImage) = block, case let .image(inlineImage) = inline {
        #expect(blockImage.pointHeight > 0)
        #expect(inlineImage.pointHeight > 0)
    } else {
        Issue.record("Expected typeset images for both display and inline math.")
    }
}

@Test
func nativeMathRendererFallsBackToTextForInvalidLatex() {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath("\\unknowncommandxyz", isBlock: false, fontSize: 16)

    guard case .text = prepared else {
        Issue.record("Expected a plain-text fallback for invalid LaTeX, got \(prepared).")
        return
    }
}

@Test
func nativeMathRendererTypesetsSupportedUnicodeMathShorthand() {
    let renderer = NativeMarkdownMathRenderer()
    let latex = "ψ(t) = w₁ · t²"
    let prepared = renderer.preparedMath(latex, isBlock: false, fontSize: 16)

    guard case let .image(image) = prepared else {
        Issue.record("Expected supported Unicode shorthand to typeset, got \(prepared).")
        return
    }

    #expect(image.latex == latex)
}

@Test
func nativeMathRendererFallsBackToTextForUnsupportedUnicodeMathInput() {
    let renderer = NativeMarkdownMathRenderer()
    let unsupportedFormulas = ["score 😀", "score \\😀", "\\α"]

    for formula in unsupportedFormulas {
        let prepared = renderer.preparedMath(formula, isBlock: false, fontSize: 16)
        guard case .text = prepared else {
            Issue.record("Expected a plain-text fallback for unsupported Unicode math input, got \(prepared).")
            continue
        }
    }
}

@Test
func nativeMathRendererFallsBackToTextForInvalidFontSizes() {
    let renderer = NativeMarkdownMathRenderer()
    let invalidFontSizes: [Double] = [.nan, .infinity, -.infinity, 0, -12, 513]

    for fontSize in invalidFontSizes {
        let prepared = renderer.preparedMath("x^2", isBlock: false, fontSize: fontSize)
        guard case .text = prepared else {
            Issue.record("Expected a plain-text fallback for invalid font size \(fontSize), got \(prepared).")
            continue
        }
    }
}

@Test
func swiftMathTypesetterRejectsUnsafeRasterInputs() {
    #if canImport(SwiftMath)
    let typesetter = SwiftMathTypesetter.shared

    #expect(typesetter.preparedImage(latex: "x^2", isBlock: false, fontSize: 513, scale: 2) == nil)
    #expect(typesetter.preparedImage(latex: "x^2", isBlock: false, fontSize: 16, scale: .infinity) == nil)
    #expect(typesetter.preparedImage(latex: "x^2", isBlock: false, fontSize: 16, scale: 9) == nil)
    #endif
}

@Test
func nativeMathRendererTypesetsChatScoreFormula() throws {
    let renderer = NativeMarkdownMathRenderer()
    let prepared = renderer.preparedMath(
        "S_c = w₁ · \\text{Match}\\text{NPI} + w₂ · \\text{Match}\\text{Google} + w₃ · \\text{Match}\\text{Website} - \\text{Penalty}\\text{Conflicts}",
        isBlock: true,
        fontSize: 18
    )

    guard case .image = prepared else {
        Issue.record("Expected a typeset image for the chat score formula, got \(prepared).")
        return
    }
}

@Test
func nativeMathRendererTypesetsGeneratedFormulaFamilies() throws {
    let renderer = NativeMarkdownMathRenderer()
    let formulas = [
        "p(y \\mid x) = \\operatorname{softmax}(Wx + b)_y",
        "\\mathbb{E}[X] = \\sum_i p_i x_i",
        "\\hat{\\theta} = \\arg\\max_\\theta \\log p(D \\mid \\theta)",
        "\\partial L / \\partial w = 0",
        "\\nabla_\\theta J(\\theta) = \\mathbb{E}[r \\nabla_\\theta \\log \\pi_\\theta(a \\mid s)]",
        "\\mathrm{score}(x) = \\log p(x)",
        "\\Pr(A \\mid B) = \\frac{\\Pr(B \\mid A)\\Pr(A)}{\\Pr(B)}",
        "\\left\\|x\\right\\|_2 = \\sqrt{x^\\top x}",
        "\\mathbf{x}^{\\top}\\mathbf{w} + b",
        "x_i \\in \\mathbb{R}^d",
        "\\begin{cases} x + y = 5 \\\\ 2x - y = 1 \\end{cases}",
        "f(x) = \\begin{cases} x^2 & x \\ge 0 \\\\ -x & x < 0 \\end{cases}",
        "\\operatorname*{argmax}_{x \\in \\mathbb{R}^d} f(x)",
        "\\left\\langle x, y \\right\\rangle = \\sum_i x_i y_i",
        "\\begin{equation} x^2 + y^2 = z^2 \\end{equation}",
        "\\begin{align*} x &= y + 1 \\\\ y &= z - 1 \\end{align*}",
        "\\psi(t) = e^{-i\\omega t}",
        "\\mathfrak{g} \\oplus \\mathcal{h}",
        "\\Delta E \\approx \\hbar\\omega",
        "A \\subseteq B \\Rightarrow A \\cap C \\subseteq B \\cap C",
        "\\det(A) \\neq 0 \\iff A^{-1}\\text{ exists}",
        "\\mu \\pm 1.96\\sigma",
        "\\dfrac{a+b}{c+d}",
        "\\tfrac{1}{2}mv^2",
        "\\dbinom{n}{k}p^k(1-p)^{n-k}",
        "x \\ne y \\implies f(x) \\notin S",
        "a_1 + \\dots + a_n = \\sum_i a_i",
        "\\Re z \\ne 0 \\implies \\Im z = 0",
        "\\pr(A) = 1",
        "\\inf_n a_n \\le \\liminf_n a_n \\le \\limsup_n a_n \\le \\sup_n a_n",
        "u \\downarrow v \\iff v \\uparrow u",
        "x \\succ y \\perp z",
        "\\begin{array}{cc} a & b \\\\ c & d \\end{array}",
        "\\begin{array}[t]{cc} a & b \\\\ c & d \\end{array}",
        "\\begin{smallmatrix} 1 & 0 \\\\ 0 & 1 \\end{smallmatrix}"
    ]

    for formula in formulas {
        let prepared = renderer.preparedMath(formula, isBlock: true, fontSize: 18)
        guard case .image = prepared else {
            Issue.record("Expected a typeset image for generated formula: \(formula)")
            continue
        }
    }
}

@Test
func nativeMathRendererPreservesOriginalLatexAfterCompatibilityNormalization() throws {
    let renderer = NativeMarkdownMathRenderer()
    let formulas = [
        "\\dfrac{a}{b}",
        "\\tbinom{n}{k}",
        "x \\ne y \\implies z",
        "a_1 + \\dots + a_n",
        "\\pr(A) = 1",
        "\\begin{array}{cc} a & b \\\\ c & d \\end{array}",
        "\\begin{array}[t]{cc} a & b \\\\ c & d \\end{array}"
    ]

    for formula in formulas {
        let prepared = renderer.preparedMath(formula, isBlock: true, fontSize: 18)
        guard case let .image(image) = prepared else {
            Issue.record("Expected normalized formula to typeset: \(formula)")
            continue
        }
        #expect(image.latex == formula)
    }
}

@Test
func nativeMathRendererExposesStableCacheIdentity() {
    let renderer = NativeMarkdownMathRenderer()
    #expect(!renderer.mathRendererCacheIdentity.isEmpty)
    #expect(renderer.mathRendererCacheIdentity == NativeMarkdownMathRenderer().mathRendererCacheIdentity)
}

@Test
func mathBlockPreparesTypesetImageAndReusesCache() throws {
    var stream = MarkdownStream()
    stream.append("""
    $$
    \\frac{a}{b}
    $$
    """)
    stream.finish()

    let recorder = MarkdownDiagnosticsRecorder()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()
    configuration.diagnosticsRecorder = recorder

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })

    let first = configuration.prepare(block: block)
    guard case .image = first.mathRender else {
        Issue.record("Expected a typeset image for the math block.")
        return
    }

    let afterFirst = recorder.snapshot()
    #expect(afterFirst.mathRenderCount == 1)

    let second = configuration.prepare(block: block)
    guard case .image = second.mathRender else {
        Issue.record("Expected the cached math block to remain a typeset image.")
        return
    }

    let afterSecond = recorder.snapshot()
    #expect(afterSecond.mathRenderCount == 1)
    #expect(afterSecond.cacheHitCount > afterFirst.cacheHitCount)
}

@Test
func inlineMathProducesNativeTextPiecesWithTypesetRenderer() throws {
    var stream = MarkdownStream()
    stream.append("The limit \\(\\frac{f(x)}{g(x)}\\) is evaluated here.")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)
    let pieces = try #require(inline.mathTextPieces)

    let hasMath = pieces.contains { piece in
        if case .math = piece { return true }
        return false
    }
    let hasText = pieces.contains { piece in
        if case .text = piece { return true }
        return false
    }
    #expect(hasMath)
    #expect(hasText)
}

@Test
func inlineMathWithPlainRendererDoesNotProduceTypesetPieces() throws {
    var stream = MarkdownStream()
    stream.append("The limit $x^2$ is evaluated here.")
    stream.finish()

    // `.document` keeps the default PlainMarkdownMathRenderer, so inline math stays
    // on the prepared CoreText line path with no native Text pieces.
    let configuration = MarkdownRendererConfiguration.document

    let block = try #require(stream.snapshot().blocks.first)
    let prepared = configuration.prepare(block: block)
    let inline = try #require(prepared.inlineLayout)

    #expect(inline.mathTextPieces == nil)
}

@Test
func streamingDisplayMathShowsFallbackUntilClosedThenTypesets() throws {
    var stream = MarkdownStream()
    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    // Unclosed display math stays in the mutable tail and must not typeset yet.
    stream.append("\\[\n\\lim_{x \\to a} \\frac{f(x)}{g(x)}\n")
    let partial = stream.snapshot()
    #expect(partial.blocks.allSatisfy { $0.kind != .mathBlock })

    // Closing the delimiter seals the region into a real math block that typesets.
    stream.append("\\]\n")
    stream.finish()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    guard case .image = configuration.prepare(block: block).mathRender else {
        Issue.record("Expected the completed display math to typeset to an image.")
        return
    }
}

@Test
func mathBlockRenderPlanReportsMathRenderedWithTypesetRenderer() throws {
    var stream = MarkdownStream()
    stream.append("$$\n\\frac{a}{b}\n$$")
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)
    let plan = MarkdownBlockView.renderPlan(
        for: block,
        configuration: configuration,
        preparedContent: prepared
    )

    #expect(plan.mathAllowed == true)
    #expect(plan.mathRendered == true)
}

@Test
func latexDisplayBracketBlockPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    \\[
    \\lim_{x \\to a} \\frac{f(x)}{g(x)}
    \\]
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected a typeset image for the \\[...\\] display block.")
        return
    }
    #expect(image.latex == "\\lim_{x \\to a} \\frac{f(x)}{g(x)}")
}

@Test
func paragraphEmbeddedDisplayMathPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    Then:
    \\[
    \\frac{f'(x)}{g'(x)}
    \\]
    if the derivative limit exists.
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let blocks = stream.snapshot().blocks
    #expect(blocks.map(\.kind) == [.paragraph, .mathBlock, .paragraph])
    let block = try #require(blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected embedded display math to prepare a typeset image.")
        return
    }
    #expect(image.latex == "\\frac{f'(x)}{g'(x)}")
}

@Test
func degradedBareDisplayBracketMathPreparesTypesetImage() throws {
    var stream = MarkdownStream()
    stream.append("""
    [
    \\frac{f'(x)}{g'(x)}
    ]
    """)
    stream.finish()

    var configuration = MarkdownRendererConfiguration.document
    configuration.mathRenderer = NativeMarkdownMathRenderer()

    let block = try #require(stream.snapshot().blocks.first { $0.kind == .mathBlock })
    let prepared = configuration.prepare(block: block)

    guard case let .image(image) = prepared.mathRender else {
        Issue.record("Expected degraded bare-bracket display math to prepare a typeset image.")
        return
    }
    #expect(image.latex == "\\frac{f'(x)}{g'(x)}")
}

private final class LockedFailureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock {
            count += 1
        }
    }

    var value: Int {
        lock.withLock {
            count
        }
    }
}

#if canImport(SwiftMath)
private final class SharedMTFontBox: @unchecked Sendable {
    let font: MTFont

    init(_ font: MTFont) {
        self.font = font
    }
}
#endif
