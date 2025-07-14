
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

/// Conformance of `Data` to `CachedValue` protocol.
///
/// This extension allows `Data` objects to be stored directly in the cache
/// without requiring a wrapper type. Since `Data` is already serialized,
/// the implementation simply returns itself for both serialization and
/// deserialization operations.
extension Data: CachedValue {
    /// Returns self as the serialized data representation.
    ///
    /// Since `Data` is already in a serialized format, no conversion is needed.
    public var data: Data { self }

    /// Creates a `Data` instance from serialized data.
    ///
    /// Since the input is already `Data`, this method simply returns it unchanged.
    ///
    /// - Parameter data: The serialized data.
    /// - Returns: The same `Data` instance.
    public static func fromData(data: Data) throws -> Data { data }
}

// MARK: - Container Class

// MARK: - MemoryCache Actor

/// An actor that manages a memory cache with automatic eviction.
///
/// `MemoryCache` provides thread-safe access to cached values using NSCache
/// for automatic memory management and eviction based on system memory pressure.
public actor MemoryCache<Key: Hashable & CustomStringConvertible & Sendable, Value: CachedValue> {
    // MARK: - Properties

    private let values = NSCache<NSString, NSData>()
    private let diskCache: DiskCache<Key, Value>

    // MARK: - Initialization

    /// Initializes a new memory cache.
    ///
    /// Creates a new cache instance with its own unique disk cache directory.
    public init() {
        diskCache = DiskCache()
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

    /// Checks if a value exists in the memory cache.
    ///
    /// This method only checks the in-memory cache and doesn't check disk storage.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: `true` if the key exists in the cache, `false` otherwise.
    public func contains(_ key: Key) -> Bool {
        let nsKey = key.description as NSString
        return values.object(forKey: nsKey) != nil
    }

    /// Sets a value in the cache for the given key.
    ///
    /// If the key already exists, the value is updated. NSCache automatically
    /// handles eviction when memory pressure occurs.
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
