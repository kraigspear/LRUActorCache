import Foundation
import os

private let signposter = LogContext.cache.signposter()

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
    private let diskCache: DiskCache

    /// Tracks write operations to trigger periodic disk cleanup.
    ///
    /// We use count-based cleanup instead of time-based because:
    /// - Simpler state management (just an integer vs dates)
    /// - Predictable cleanup intervals based on usage patterns
    /// - Avoids date comparisons and time calculations
    private var numberOfWrites = 0

    // MARK: - Initialization

    /// Initializes a new memory cache with the specified identifier.
    ///
    /// The identifier is passed to the disk cache to determine the storage directory.
    /// Multiple MemoryCache instances with the same identifier will share the same
    /// disk storage, enabling data persistence across instances.
    ///
    /// - Parameter identifier: A unique identifier for this cache's disk storage.
    public init(identifier: String) {
        diskCache = DiskCache(identifier: identifier)
    }

    /// Determines if disk cleanup should run after the next write.
    ///
    /// Returns true every 100 writes to prevent unbounded disk growth
    /// while avoiding excessive cleanup operations that could impact performance.
    private var dueForCleanup: Bool {
        let numberOfWritesBeforeCleanup = 100
        return numberOfWrites >= numberOfWritesBeforeCleanup
    }

    // MARK: - Public Cache Access

    /// Sets a value in memory cache only, without writing to disk.
    ///
    /// This internal method exists to avoid redundant disk writes when loading
    /// from disk. Writing back to disk would be wasteful since the data
    /// already exists there and hasn't changed.
    ///
    /// - Parameters:
    ///   - value: The value to store in memory
    ///   - key: The cache key
    private func setInMemoryOnly(_ value: Value, for key: Key) {
        let nsKey = key.description as NSString
        let data = value.data as NSData
        values.setObject(data, forKey: nsKey)
    }

    /// Retrieves a value from the cache for the given key.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: The cached value if found, or `nil` if not present.
    public func value(for key: Key) async -> Value? {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("CacheRead", id: signpostID)
        defer { signposter.endInterval("CacheRead", state) }

        let nsKey = key.description as NSString

        if let data = values.object(forKey: nsKey) {
            if let value = try? Value.fromData(data: data as Data) {
                return value
            } else {
                assertionFailure("Could not convert data to value for key \(key)")
            }
        }

        // Load from disk if not in memory. This is now async and doesn't block
        // the actor because DiskCache is Sendable and uses async file operations.
        if let fromDisk = await diskCache.getData(for: key) {
            setInMemoryOnly(fromDisk, for: key)
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
    /// The disk write is performed asynchronously and fire-and-forget.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key under which to store the value.
    public func set(_ value: Value, for key: Key) async {
        let nsKey = key.description as NSString
        let data = value.data as NSData
        values.setObject(data, forKey: nsKey)

        // Check cleanup status before the write to maintain consistent state.
        // We pass this decision to DiskCache rather than calling cleanup directly
        // to keep all disk operations encapsulated within DiskCache.
        let dueForCleanup = dueForCleanup
        diskCache.setValue(
            value,
            at: key,
            cleanUpAfterSet: dueForCleanup
        )

        // Reset counter after cleanup to track the next batch of writes.
        // Incrementing before cleanup could cause off-by-one errors.
        if dueForCleanup {
            numberOfWrites = 0
        } else {
            numberOfWrites += 1
        }
    }
}
