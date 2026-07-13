import Foundation

/// A deterministic, two-lane fingerprint for immutable prepared/render data.
///
/// SiriusMarkdown uses this value to move content-sized cache-key work to the
/// prepare/layout-result construction boundary. Cache lookups in SwiftUI and
/// selection geometry can then combine a fixed number of machine words rather
/// than rescanning source strings, runs, measured units, or line arrays.
///
/// This is deliberately not Swift's `Hasher`: `Hasher` is process-randomized
/// and only exposes one machine word. Two independently seeded FNV-1a lanes
/// keep the identity deterministic and make accidental cache aliasing far less
/// likely while remaining cheap to extend during preparation.
public struct MarkdownContentFingerprint: Sendable, Hashable {
    public private(set) var low: UInt64
    public private(set) var high: UInt64

    public init(low: UInt64, high: UInt64) {
        self.low = low
        self.high = high
    }

    public init(domain: String) {
        self.low = 0xcbf29ce484222325
        self.high = 0x6c62272e07bb0142
        combine(domain)
    }

    public mutating func combine(_ fingerprint: MarkdownContentFingerprint) {
        combine(fingerprint.low)
        combine(fingerprint.high)
    }

    public mutating func combine(_ value: Bool) {
        combine(value ? UInt64(1) : UInt64(0))
    }

    public mutating func combine(_ value: Int) {
        combine(UInt64(bitPattern: Int64(value)))
    }

    public mutating func combine(_ value: UInt) {
        combine(UInt64(value))
    }

    public mutating func combine(_ value: UInt64) {
        // Fixed-width little-endian encoding keeps numeric boundaries
        // unambiguous without allocating a decimal String.
        for shift in stride(from: 0, through: 56, by: 8) {
            combine(byte: UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    public mutating func combine(_ value: Double) {
        combine(value.bitPattern)
    }

    public mutating func combine(_ value: String) {
        combine(UInt64(value.utf8.count))
        for byte in value.utf8 {
            combine(byte: byte)
        }
    }

    private mutating func combine(byte: UInt8) {
        low ^= UInt64(byte)
        low &*= 0x100000001b3

        // A separately seeded lane with a decorrelated byte stream. The
        // rotation prevents the two lanes from becoming simple affine
        // transforms of one another for repetitive generated text.
        high ^= UInt64(byte ^ 0xa5)
        high &*= 0x100000001b3
        high = (high << 13) | (high >> 51)
    }
}
