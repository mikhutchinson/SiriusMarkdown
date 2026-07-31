import SiriusMarkdownCore
import Foundation

#if canImport(CoreText)
import CoreText
#endif

enum MarkdownInlineLineHeight {
    private static let minimumHeightCache =
        MarkdownInlineMinimumHeightCache(capacity: 128)

    nonisolated static func resolved(
        requested: Double,
        fontSize: Double,
        profiles: MarkdownInlineFontProfiles
    ) -> Double {
        let safeFontSize = fontSize.isFinite && fontSize > 0 ? fontSize : 14
        let safeRequested = requested.isFinite && requested > 0 ? requested : safeFontSize
        return max(safeRequested, minimumTypographicHeight(
            fontSize: safeFontSize,
            profiles: profiles
        ))
    }

    private nonisolated static func minimumTypographicHeight(
        fontSize: Double,
        profiles: MarkdownInlineFontProfiles
    ) -> Double {
        let cacheKey = "\(fontSize.bitPattern)|\(profiles.cacheKey)"
        if let cached = minimumHeightCache.value(forKey: cacheKey) {
            return cached
        }

        #if canImport(CoreText)
        let fonts = [
            MarkdownCoreTextFontBridge.font(
                profile: profiles.body,
                kind: .text,
                presentation: [],
                size: fontSize
            ),
            MarkdownCoreTextFontBridge.font(
                profile: profiles.emphasis,
                kind: .emphasis,
                presentation: .emphasis,
                size: fontSize
            ),
            MarkdownCoreTextFontBridge.font(
                profile: profiles.strong,
                kind: .strong,
                presentation: .strong,
                size: fontSize
            ),
            MarkdownCoreTextFontBridge.font(
                profile: profiles.code,
                kind: .code,
                presentation: .code,
                size: fontSize
            ),
            MarkdownCoreTextFontBridge.font(
                profile: profiles.math,
                kind: .math,
                presentation: .math,
                size: fontSize
            ),
            MarkdownCoreTextFontBridge.font(
                profile: profiles.imagePlaceholder,
                kind: .image,
                presentation: .image,
                size: fontSize
            ),
        ]
        let largest = fonts.reduce(CGFloat(fontSize)) { result, font in
            max(
                result,
                CTFontGetAscent(font) +
                    CTFontGetDescent(font) +
                    max(0, CTFontGetLeading(font))
            )
        }
        let result = Double(ceil(largest))
        #else
        let result = fontSize
        #endif
        minimumHeightCache.insert(result, forKey: cacheKey)
        return result
    }
}

private final class MarkdownInlineMinimumHeightCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Double] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func value(forKey key: String) -> Double? {
        lock.withLock {
            values[key]
        }
    }

    func insert(_ value: Double, forKey key: String) {
        lock.withLock {
            if values[key] != nil {
                values[key] = value
                return
            }
            values[key] = value
            order.append(key)
            while order.count > capacity {
                let evicted = order.removeFirst()
                values.removeValue(forKey: evicted)
            }
        }
    }
}
