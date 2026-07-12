import SwiftUI

#if os(macOS)
import AppKit

/// Resolves SwiftUI semantic colors before native drawing code stores them as
/// fixed AppKit/Core Graphics values. `NSColor(Color.primary)` is dynamic, but
/// asking it for RGB components outside the active SwiftUI appearance can
/// flatten it to the wrong variant.
enum MarkdownPlatformColorResolver {
    static func appKitColor(_ color: Color, colorScheme: ColorScheme) -> NSColor {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: appearanceName) else {
            return NSColor(color)
        }

        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.deviceRGB)
        }
        if let resolved {
            return resolved
        }

        var fallback = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            fallback = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .labelColor
        }
        return fallback
    }

    static func appKitCGColor(_ color: Color, colorScheme: ColorScheme) -> CGColor {
        appKitColor(color, colorScheme: colorScheme).cgColor
    }
}
#elseif canImport(UIKit) && !os(watchOS)
import UIKit

/// UIKit's `CGColor` is also a fixed snapshot. Resolve the SwiftUI color under
/// an explicit trait collection before handing it to Core Text or CALayer.
enum MarkdownPlatformColorResolver {
    static func uiKitColor(_ color: Color, colorScheme: ColorScheme) -> UIColor {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    static func uiKitCGColor(_ color: Color, colorScheme: ColorScheme) -> CGColor {
        uiKitColor(color, colorScheme: colorScheme).cgColor
    }
}
#endif
