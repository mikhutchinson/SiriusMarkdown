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
    /// Display-list ascent/descent from the typeset `MTMathListDisplay`.
    ///
    /// Mirrors `MathImage.LayoutInfo` so callers that must use `MTMathImage`
    /// (which loads fonts through `MTFont.fontBundle` / `Bundle.module` in
    /// SwiftPM tests) can still obtain true typographic metrics without the
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

    /// Typesets and rasterizes the equation, returning display-list metrics.
    public func asImage() -> (NSError?, MTImage?, LayoutInfo?) {
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
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: currentStyle) else {
            return (error, nil, nil)
        }
         
        intrinsicContentSize = intrinsicContentSize(displayList)
        displayList.textColor = textColor
        
        let size = intrinsicContentSize
        layoutImage(size: size, displayList: displayList)
        let layout = LayoutInfo(ascent: displayList.ascent, descent: displayList.descent)
        
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
