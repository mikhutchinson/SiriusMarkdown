import Foundation

public struct MarkdownCacheKey: Sendable, Hashable {
    public var sourceRange: MarkdownSourceRange
    public var contentHash: UInt64
    /// Second lane for call sites with a precomputed
    /// `MarkdownContentFingerprint`. Legacy 64-bit cache keys keep zero here.
    public var contentHashHigh: UInt64
    public var namespace: String

    public init(sourceRange: MarkdownSourceRange, contentHash: UInt64, namespace: String) {
        self.sourceRange = sourceRange
        self.contentHash = contentHash
        self.contentHashHigh = 0
        self.namespace = namespace
    }

    public init(
        sourceRange: MarkdownSourceRange,
        contentFingerprint: MarkdownContentFingerprint,
        namespace: String
    ) {
        self.sourceRange = sourceRange
        self.contentHash = contentFingerprint.low
        self.contentHashHigh = contentFingerprint.high
        self.namespace = namespace
    }
}

public struct BoundedMarkdownCache<Value: Sendable>: Sendable {
    private var storage: [MarkdownCacheKey: Value]
    private var order: [MarkdownCacheKey]
    public private(set) var capacity: Int

    public var count: Int {
        storage.count
    }

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [:]
        self.order = []
    }

    public subscript(key: MarkdownCacheKey) -> Value? {
        get {
            storage[key]
        }
        set {
            if let newValue {
                insert(newValue, forKey: key)
            } else {
                storage.removeValue(forKey: key)
                removeKeyFromOrder(key)
            }
        }
    }

    public mutating func insert(_ value: Value, forKey key: MarkdownCacheKey) {
        removeKeyFromOrder(key)
        order.append(key)
        storage[key] = value

        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    public mutating func value(forKey key: MarkdownCacheKey) -> Value? {
        guard let value = storage[key] else {
            return nil
        }

        removeKeyFromOrder(key)
        order.append(key)
        return value
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private mutating func removeKeyFromOrder(_ key: MarkdownCacheKey) {
        guard !order.isEmpty else {
            return
        }

        var compacted: [MarkdownCacheKey] = []
        compacted.reserveCapacity(order.count)
        for existing in order where existing != key {
            compacted.append(existing)
        }
        order = compacted
    }
}

final class MarkdownTableCellConversionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MarkdownCacheKey: MarkdownTableCell] = [:]
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func cell(forKey key: MarkdownCacheKey) -> MarkdownTableCell? {
        lock.withLock {
            storage[key]
        }
    }

    func insert(_ cell: MarkdownTableCell, forKey key: MarkdownCacheKey) {
        lock.withLock {
            if storage[key] != nil {
                storage[key] = cell
                return
            }
            // An append-only table is reparsed from its first historical row.
            // Once full, retaining that oldest stable prefix guarantees useful
            // hits on every later pass. Conventional FIFO/LRU eviction would
            // thrash when a table grows beyond capacity: early misses evict the
            // later entries immediately before the same scan reaches them.
            guard storage.count < capacity else { return }
            storage[key] = cell
        }
    }

    var count: Int {
        lock.withLock {
            storage.count
        }
    }
}

public final class MarkdownParserCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: BoundedMarkdownCache<[MarkdownBlock]>

    public init(capacity: Int = 256) {
        self.cache = BoundedMarkdownCache(capacity: capacity)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func blocks(forKey key: MarkdownCacheKey, isSealed: Bool) -> [MarkdownBlock]? {
        withLock {
            cache.value(forKey: key)?.withSealedState(isSealed)
        }
    }

    public func insert(_ blocks: [MarkdownBlock], forKey key: MarkdownCacheKey) {
        withLock {
            cache[key] = blocks.withSealedState(false)
        }
    }

    public func removeAll() {
        withLock {
            cache.removeAll()
        }
    }
}

private extension Array where Element == MarkdownBlock {
    func withSealedState(_ isSealed: Bool) -> [MarkdownBlock] {
        map { block in
            var copy = block
            copy.isSealed = isSealed
            return copy
        }
    }
}
