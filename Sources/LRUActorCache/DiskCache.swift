//
//  DiskCache.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 6/8/25.
//

import CryptoKit
import Foundation

/// A disk cache implementation for persistent storage.
///
/// `DiskCache` provides persistent storage for data objects on disk, automatically
/// managing the cache directory in the system's caches folder. It uses generic
/// keys to store and retrieve data.
///
/// ## Usage
/// ```swift
/// let cache = DiskCache<String, MyValue>()
///
/// // Store data
/// cache.setValue(myValue, at: "myKey")
///
/// // Retrieve data
/// if let cachedValue = cache.getData(for: "myKey") {
///     // Use cached value
/// }
/// ```
///
/// ## Implementation Details
/// - Each instance creates a unique subdirectory in `~/Library/Caches/DiskCache-{UUID}/`
/// - The cache directory is automatically cleaned up when the instance is deallocated
/// - Cache keys are hashed using SHA256 for filesystem compatibility
/// - Thread safety must be managed by the caller (e.g., MemoryCache actor)
/// - Failed operations are logged and don't throw errors
/// - Corrupted cache files are automatically deleted on read failures
final class DiskCache<Key: Hashable & CustomStringConvertible, Value: CachedValue>: Sendable {
    // MARK: - Properties

    /// The directory where cache files are stored
    private let cacheFolder: URL?

    /// Logger for debugging and error reporting
    private let logger = LogContext.diskCache.logger()

    // MARK: - Initialization

    /// Creates a new disk cache instance.
    ///
    /// The initializer creates a unique cache directory for this instance in the system's
    /// caches folder. If directory creation fails, the cache operates in a degraded
    /// mode where all operations become no-ops.
    ///
    /// - Parameter reset: If `true`, attempts to remove any existing cache directory
    ///   before creating a new one. This parameter is largely obsolete since each
    ///   instance now uses a unique directory.
    public init(reset: Bool = false) {
        let cachePath: URL

        let fileManager = FileManager.default

        do {
            cachePath = try fileManager
                .url(
                    for: .cachesDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
        } catch {
            assertionFailure("Failed to get cache directory: error: \(error)")
            logger.critical("Failed to get cache directory: error: \(error)")
            cacheFolder = nil
            return
        }

        // Generate a unique subdirectory name for this instance
        let uniqueID = UUID().uuidString
        let cacheFolder = cachePath.appending(path: "DiskCache-\(uniqueID)")

        if reset {
            do {
                if fileManager.fileExists(atPath: cacheFolder.path) {
                    try fileManager.removeItem(at: cacheFolder)
                }
            } catch {
                logger.error("Failed to remove cache folder error: \(error)")
            }
        }

        do {
            try fileManager.createDirectory(at: cacheFolder,
                                            withIntermediateDirectories: true)
            self.cacheFolder = cacheFolder
        } catch {
            assertionFailure("Failed to create cache directory: error: \(error)")
            logger.critical("Failed to create cache directory: error: \(error)")
            self.cacheFolder = nil
            return
        }
    }

    deinit {
        // Clean up the unique cache directory when this instance is deallocated
        guard let cacheFolder else { return }

        do {
            try FileManager.default.removeItem(at: cacheFolder)
            logger.debug("Cleaned up cache directory: \(cacheFolder.lastPathComponent)")
        } catch {
            // It's okay if deletion fails - the system will eventually clean up caches
            logger.debug("Failed to clean up cache directory: \(error)")
        }
    }

    /// Checks if a cached value exists for the given key.
    ///
    /// - Parameter key: The key to check
    /// - Returns: `true` if a cache file exists for the key, `false` otherwise
    func exist(for key: Key) -> Bool {
        guard let cacheFolder else {
            return false
        }
        let cacheSource = cacheFolder.appending(
            path: cacheFileName(for: key)
        )
        return FileManager.default.fileExists(atPath: cacheSource.path)
    }

    // MARK: - Public API

    /// Retrieves a value from the cache for a given key.
    ///
    /// If the cached file exists but cannot be read or deserialized, it will be
    /// automatically deleted and `nil` will be returned.
    ///
    /// - Parameter key: The key for the cached value
    /// - Returns: The cached value if found and valid, `nil` otherwise
    func getData(for key: Key) -> Value? {
        guard exist(for: key) else {
            return nil
        }

        logger.debug("key: \(key) found in cache")

        guard let cacheFolder else {
            return nil
        }

        let cacheSource = cacheFolder.appending(
            path: cacheFileName(for: key)
        )

        let data: Data

        do {
            data = try Data(contentsOf: cacheSource)
        } catch {
            logger.error("Error loading data for \(key) from cache")
            do {
                try FileManager.default.removeItem(at: cacheSource)
            } catch {
                logger.error("Tried to delete corrupted file \(cacheSource.path) failed with error: \(error)")
            }
            return nil
        }

        do {
            let value = try Value.fromData(data: data)
            logger.debug("success loading \(key) from cache")
            return value
        } catch {
            logger.error("Error decoding \(key) from cache, deleting corrupted file")
            do {
                try FileManager.default.removeItem(at: cacheSource)
                logger.debug("Successfully deleted corrupted cache file for \(key)")
            } catch {
                logger.error("Failed to delete corrupted file \(cacheSource.path) error: \(error)")
            }
            return nil
        }
    }

    /// Stores a value in the cache for a given key.
    ///
    /// The value's data is written to a file named using the SHA256 hash of the key.
    /// If the write operation fails, the error is logged but not thrown.
    ///
    /// - Parameters:
    ///   - value: The value to cache
    ///   - key: The key for storing the value
    func setValue(_ value: Value, at key: Key) {
        guard let cacheFolder else { return }

        let cacheDestination = cacheFolder.appending(
            path: cacheFileName(for: key)
        )

        do {
            try value.data.write(to: cacheDestination)
        } catch {
            assertionFailure("Error writing to at path: \(cacheDestination) cache: \(error)")
            logger.error("Error writing to at path: \(cacheDestination) cache: \(error)")
        }
    }

    private func cacheFileName(for key: Key) -> String {
        key.description.cacheFileName
    }
}

// MARK: - URL Extension

private extension String {
    var cacheFileName: String {
        let data = Data(utf8)
        let hash = SHA256.hash(data: data)
        // map each byte to a two‐digit hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
