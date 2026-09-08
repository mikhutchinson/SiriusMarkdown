//
//  File.swift
//  
//
//  Created by Peter Tang on 12/9/2023.
//

import Foundation

#if os(iOS) || os(visionOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

public class MTMathImage {
    public var font: MTFont? = MTFontManager.fontManager.defaultFont
    public var fontSize:CGFloat {
        set {
            _fontSize = newValue
            guard MTFont.canRenderFontSize(newValue) else {
                return
            }
            let font = font?.copy(withSize: newValue)
            self.font = font  // also forces an update
        }
        get { _fontSize }
    }
    private var _fontSize:CGFloat = 0
    public let textColor: MTColor

    public let labelMode: MTMathUILabelMode
    public let textAlignment: MTTextAlignment

    public var contentInsets: MTEdgeInsets = MTEdgeInsetsZero
    
    public let latex: String
    /// Parsed atoms from the successful render, for preparation-time consumers.
    public private(set) var parsedMathList: MTMathList?
    private(set) var intrinsicContentSize = CGSize.zero

    public init(latex: String, fontSize: CGFloat, textColor: MTColor, labelMode: MTMathUILabelMode = .display, textAlignment: MTTextAlignment = .center) {
        self.latex = latex
        self.textColor = textColor
        self.labelMode = labelMode
        self.textAlignment = textAlignment
        self.fontSize = fontSize
    }
}
extension MTMathImage {
    private static let maximumAssumedRasterScale: CGFloat = 4
    private static let maximumRasterPixelDimension: CGFloat = 16_384
    private static let maximumRasterPixelCount: CGFloat = 16_777_216

    /// Display-list ascent/descent from the typeset `MTMathListDisplay`.
    ///
    /// Mirrors `MathImage.LayoutInfo` so callers that must use `MTMathImage`
    /// (which loads fonts through `MTFont.fontBundle`'s runtime filesystem
    /// probe) can still obtain true typographic metrics without the
    /// atom-tree heuristic in `SiriusMarkdownMath`.
    public struct LayoutInfo {
        public var ascent: CGFloat = 0
        public var descent: CGFloat = 0

        public init(ascent: CGFloat, descent: CGFloat) {
            self.ascent = ascent
            self.descent = descent
        }
    }

    public var currentStyle: MTLineStyle {
        switch labelMode {
            case .display: return .display
            case .text: return .text
        }
    }
    private func intrinsicContentSize(_ displayList: MTMathListDisplay) -> CGSize {
        // `layoutImage` centers against `max(ascent+descent, fontSize/2)`. Grow
        // the image to that minimum so the baseline stays inside the bitmap
        // instead of being pushed below the bottom edge for compact glyphs.
        let contentHeight =
            displayList.ascent + displayList.descent + contentInsets.top + contentInsets.bottom
        let minimumHeight = (fontSize / 2) + contentInsets.top + contentInsets.bottom
        return CGSize(
            width: displayList.width + contentInsets.left + contentInsets.right,
            height: max(contentHeight, minimumHeight)
        )
    }

    private static func canRasterize(size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return false
        }
        let pixelWidth = (size.width * maximumAssumedRasterScale).rounded(.up)
        let pixelHeight = (size.height * maximumAssumedRasterScale).rounded(.up)
        return pixelWidth.isFinite
            && pixelHeight.isFinite
            && pixelWidth > 0
            && pixelHeight > 0
            && pixelWidth <= maximumRasterPixelDimension
            && pixelHeight <= maximumRasterPixelDimension
            && pixelWidth * pixelHeight <= maximumRasterPixelCount
    }

    /// Typesets and rasterizes the equation, returning display-list metrics.
    public func asImage() -> (NSError?, MTImage?, LayoutInfo?) {
        makeImage(rasterizationScale: nil)
    }

    /// Draws the vector display list directly at the requested pixel scale.
    /// No screen-scale intermediate image or NSImage cache is involved.
    public func asImage(rasterizationScale: CGFloat) -> (NSError?, MTImage?, LayoutInfo?) {
        guard rasterizationScale.isFinite, rasterizationScale > 0, rasterizationScale <= 8 else {
            return (nil, nil, nil)
        }
        return makeImage(rasterizationScale: rasterizationScale)
    }

    private func makeImage(rasterizationScale: CGFloat?) -> (NSError?, MTImage?, LayoutInfo?) {
        guard MTFont.canRenderFontSize(fontSize) else {
            return (nil, nil, nil)
        }

        func layoutImage(size: CGSize, displayList: MTMathListDisplay) {
            var textX = CGFloat(0)
            switch self.textAlignment {
                case .left:   textX = contentInsets.left
                case .center: textX = (size.width - contentInsets.left - contentInsets.right - displayList.width) / 2 + contentInsets.left
                case .right:  textX = size.width - displayList.width - contentInsets.right
            }
            let availableHeight = size.height - contentInsets.bottom - contentInsets.top
            
            // center things vertically
            var height = displayList.ascent + displayList.descent
            if height < fontSize/2 {
                height = fontSize/2  // set height to half the font size
            }
            let textY = (availableHeight - height) / 2 + displayList.descent + contentInsets.bottom
            displayList.position = CGPoint(x: textX, y: textY)
        }

        var error: NSError?
        guard let font,
              let mathList = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: currentStyle) else {
            return (error, nil, nil)
        }
         
        parsedMathList = mathList
        intrinsicContentSize = intrinsicContentSize(displayList)
        displayList.textColor = textColor
        
        var size = intrinsicContentSize
        if let scale = rasterizationScale {
            // Reserve whole pixels so consumers can display at exactly the
            // requested scale without squeezing a rounded bitmap back into
            // fractional pixel bounds.
            size = CGSize(
                width: ceil(size.width * scale) / scale,
                height: ceil(size.height * scale) / scale
            )
        }
        guard Self.canRasterize(size: size) else {
            return (nil, nil, nil)
        }
        layoutImage(size: size, displayList: displayList)
        let layout = LayoutInfo(ascent: displayList.ascent, descent: displayList.descent)

        if let scale = rasterizationScale {
            let pixelWidth = (size.width * scale).rounded()
            let pixelHeight = (size.height * scale).rounded()
            guard pixelWidth.isFinite, pixelHeight.isFinite,
                  pixelWidth > 0, pixelHeight > 0,
                  pixelWidth <= Self.maximumRasterPixelDimension,
                  pixelHeight <= Self.maximumRasterPixelDimension,
                  pixelWidth * pixelHeight <= Self.maximumRasterPixelCount,
                  let context = CGContext(
                    data: nil,
                    width: Int(pixelWidth),
                    height: Int(pixelHeight),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return (nil, nil, nil) }
            context.scaleBy(x: scale, y: scale)
            // Some vendored display nodes draw rules with NS/UIBezierPath,
            // which consults the platform's current graphics context.
            #if os(iOS) || os(visionOS)
            UIGraphicsPushContext(context)
            displayList.draw(context)
            UIGraphicsPopContext()
            #elseif os(macOS)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            displayList.draw(context)
            NSGraphicsContext.restoreGraphicsState()
            #endif
            guard let bitmap = context.makeImage() else { return (nil, nil, nil) }
            #if os(iOS) || os(visionOS)
            return (nil, UIImage(cgImage: bitmap, scale: scale, orientation: .up), layout)
            #elseif os(macOS)
            // NSImage(cgImage:size:) may retain an NSCGImageSnapshotRep,
            // which is not an NSBitmapImageRep. Install the explicit bitmap
            // representation so the bridge can encode these exact pixels.
            let representation = NSBitmapImageRep(cgImage: bitmap)
            representation.size = size
            let image = NSImage(size: size)
            image.addRepresentation(representation)
            return (nil, image, layout)
            #endif
        }
        
        #if os(iOS) || os(visionOS)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { rendererContext in
                rendererContext.cgContext.saveGState()
                rendererContext.cgContext.concatenate(.flippedVertically(size.height))
                displayList.draw(rendererContext.cgContext)
                rendererContext.cgContext.restoreGState()
            }
            return (nil, image, layout)
        #endif
        #if os(macOS)
            let image = NSImage(size: size, flipped: false) { bounds in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.saveGState()
                displayList.draw(context)
                context.restoreGState()
                return true
            }
            return (nil, image, layout)
        #endif
    }
}
private extension CGAffineTransform {
    static func flippedVertically(_ height: CGFloat) -> CGAffineTransform {
        var transform = CGAffineTransform(scaleX: 1, y: -1)
        transform = transform.translatedBy(x: 0, y: -height)
        return transform
    }
}
