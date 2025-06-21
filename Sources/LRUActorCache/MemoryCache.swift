
import Foundation
import os

private let logger = LogContext.cache.logger()

// MARK: - Protocols

/// A protocol representing a value that can be cached.
///
/// Conforming types must provide serialization and deserialization
/// capabilities for disk persistence.
public protocol CachedValue: Sendable {
    var data: Data { get }
    static func fromData(data: Data) throws -> Self
}

// MARK: - Container Class

// MARK: - MemoryCache Actor

/// An actor that manages a memory cache with a maximum item count and total cost limit.
///
/// `MemoryCache` provides thread-safe access to cached values, automatically
/// removing the least recently used items when limits are exceeded.
public actor MemoryCache<Key: Hashable & CustomStringConvertible & Sendable, Value: CachedValue> {
    // MARK: - Properties

    private let values = NSCache<NSString, NSData>()
    private let diskCache: DiskCache<Key, Value>

    // MARK: - Initialization

    /// Initializes a new memory cache with the specified limits.
    ///
    /// - Parameters:
    ///   - totalCostLimit: The maximum total cost of all items in the cache.
    ///   - maxCount: The maximum number of items the cache can hold.
    ///   - resetDiskCache: If true, clears the disk cache on initialization.
    public init(
        resetDiskCache: Bool = false
    ) {
        diskCache = DiskCache(reset: resetDiskCache)
    }

    // MARK: - Public Cache Access

    /// Retrieves a value from the cache for the given key.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: The cached value if found, or `nil` if not present.
    public func value(for key: Key) async -> Value? {
        logger.trace("value: \(key)")

        let nsKey = key.description as NSString

        if let data = values.object(forKey: nsKey) {
            if let value = try? Value.fromData(data: data as Data) {
                return value
            } else {
                assertionFailure("Could not convert data to value for key \(key)")
            }
        }

        if let fromDisk = diskCache.getData(for: key) {
            logger.debug("Found item on disk for \(key)")
            await set(fromDisk, for: key)
            return fromDisk
        }

        return nil
    }

    /// Checks if a value exists in the cache without affecting its LRU position.
    ///
    /// Unlike `value(for:)`, this method won't promote the item to the front of the LRU list,
    /// making it useful for cache inspection without side effects.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: `true` if the key exists in the cache, `false` otherwise.
    public func contains(_ key: Key) -> Bool {
        let nsKey = key.description as NSString
        return values.object(forKey: nsKey) != nil
    }

    /// Sets a value in the cache for the given key.
    ///
    /// If the key already exists, the value is updated. If adding the new value
    /// would exceed the cache limits, the least recently used items are removed.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key under which to store the value.
    public func set(_ value: Value, for key: Key) async {
        let nsKey = key.description as NSString
        let data = value.data as NSData
        values.setObject(data, forKey: nsKey)
        diskCache.setValue(value, at: key)
    }
}
