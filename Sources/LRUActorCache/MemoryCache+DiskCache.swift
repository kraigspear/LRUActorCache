import CryptoKit
import Foundation
import os

// MARK: - Private DiskCache Implementation

extension MemoryCache {
    /// A disk cache implementation for persistent storage.
    ///
    /// This is an internal implementation detail of MemoryCache and should not be used
    /// directly. It provides persistent storage for data objects on disk, automatically
    /// managing the cache directory. Thread safety is guaranteed by the enclosing actor.
    ///
    /// - Important: This class is internal to the module but should only be instantiated
    ///   by MemoryCache. Direct usage will bypass thread safety guarantees.
    final class DiskCache {
        // MARK: - Properties

        /// The directory where cache files are stored
        private let cacheFolder: URL?

        /// Logger for debugging and error reporting
        private let logger = LogContext.diskCache.logger()

        /// Last time cleanup was performed
        private var lastCleanupTime = Date()

        /// How often to check for cleanup (30 minutes)
        private let cleanupInterval: TimeInterval = 1800

        /// Maximum age for cache files (1 hour for radar images)
        private let maxFileAge: TimeInterval = 3600

        // MARK: - Initialization

        /// Creates a new disk cache instance with the specified identifier.
        ///
        /// The identifier determines the cache directory name. Multiple instances with the same
        /// identifier will share the same directory, enabling data persistence across app launches
        /// and instance lifecycles.
        ///
        /// - Parameter identifier: A unique identifier for this cache. Used to create the directory
        ///   name as "DiskCache-{identifier}" in the system's caches folder.
        ///
        /// - Note: If directory creation fails, the cache operates in a degraded mode where all
        ///   operations become no-ops.
        init(identifier: String) {
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

            // Create subdirectory based on the identifier
            let cacheFolder = cachePath.appending(path: "DiskCache-\(identifier)")

            do {
                try fileManager.createDirectory(
                    at: cacheFolder,
                    withIntermediateDirectories: true
                )
                self.cacheFolder = cacheFolder
            } catch {
                assertionFailure("Failed to create cache directory: error: \(error)")
                logger.critical("Failed to create cache directory: error: \(error)")
                self.cacheFolder = nil
                return
            }
            
            // Clean up old files on initialization
            cleanup()
        }
        
        deinit {
            // Clean up old files when this instance is deallocated
            // Note: We don't remove the directory itself since it may be shared with other instances
            cleanup()
        }

        // MARK: - Cache Operations

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

            // Check if enough time has passed since last cleanup
            let now = Date()
            if now.timeIntervalSince(lastCleanupTime) > cleanupInterval {
                lastCleanupTime = now
                // Perform cleanup synchronously - it's within actor context
                // Since cleanup only runs every 30 minutes, the occasional
                // blocking is acceptable for maintaining simplicity
                cleanup()
            }
        }

        // MARK: - Private Methods

        /// Removes cache files older than maxFileAge from the shared cache directory.
        /// This method is called:
        /// - On init to clean up old files from previous app sessions
        /// - On deinit to clean up before this instance is deallocated
        /// - Periodically when cleanupInterval has passed since last cleanup
        ///
        /// For radar images, files older than 1 hour are considered stale and removed.
        private func cleanup() {
            guard let cacheFolder else { return }

            let fileManager = FileManager.default
            let cutoffDate = Date().addingTimeInterval(-maxFileAge)

            do {
                let files = try fileManager.contentsOfDirectory(
                    at: cacheFolder,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )

                for file in files {
                    do {
                        let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey])
                        if let modificationDate = attributes.contentModificationDate,
                           modificationDate < cutoffDate {
                            try fileManager.removeItem(at: file)
                            logger.debug("Removed old cache file: \(file.lastPathComponent)")
                        }
                    } catch {
                        logger.error("Failed to process cache file \(file.lastPathComponent): \(error)")
                    }
                }
            } catch {
                logger.error("Failed to enumerate cache directory: \(error)")
            }
        }

        private func cacheFileName(for key: Key) -> String {
            key.description.cacheFileName
        }
    }
}

// MARK: - String Extension for Cache File Names

private extension String {
    var cacheFileName: String {
        let data = Data(utf8)
        let hash = SHA256.hash(data: data)
        // map each byte to a two‐digit hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
