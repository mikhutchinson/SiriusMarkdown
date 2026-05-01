import Foundation

public struct MarkdownCacheKey: Sendable, Hashable {
    public var sourceRange: MarkdownSourceRange
    public var contentHash: UInt64
    public var namespace: String

    public init(sourceRange: MarkdownSourceRange, contentHash: UInt64, namespace: String) {
        self.sourceRange = sourceRange
        self.contentHash = contentHash
        self.namespace = namespace
    }
}

public struct BoundedMarkdownCache<Value: Sendable>: Sendable {
    private var storage: [MarkdownCacheKey: Value]
    private var order: [MarkdownCacheKey]
    public private(set) var capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
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
                order.removeAll { $0 == key }
            }
        }
    }

    public mutating func insert(_ value: Value, forKey key: MarkdownCacheKey) {
        if storage[key] == nil {
            order.append(key)
        }

        storage[key] = value

        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}

public final class MarkdownParserCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: BoundedMarkdownCache<[MarkdownBlock]>

    public init(capacity: Int = 256) {
        self.cache = BoundedMarkdownCache(capacity: capacity)
    }

    public func blocks(forKey key: MarkdownCacheKey, isSealed: Bool) -> [MarkdownBlock]? {
        lock.withLock {
            cache[key]?.withSealedState(isSealed)
        }
    }

    public func insert(_ blocks: [MarkdownBlock], forKey key: MarkdownCacheKey) {
        lock.withLock {
            cache[key] = blocks.withSealedState(false)
        }
    }

    public func removeAll() {
        lock.withLock {
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
