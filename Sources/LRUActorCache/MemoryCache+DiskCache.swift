import CryptoKit
import Foundation
import os

// MARK: - Private DiskCache Implementation

extension MemoryCache {
    /// A disk cache implementation for persistent storage.
    ///
    /// This is an internal implementation detail of MemoryCache and should not be used
    /// directly. It provides persistent storage for data objects on disk, automatically
    /// managing the cache directory.
    ///
    /// DiskCache is designed to be Sendable to enable async file operations without
    /// blocking the MemoryCache actor. All mutable state is managed by MemoryCache,
    /// making this class stateless and thread-safe.
    ///
    /// - Important: This class is internal to the module but should only be instantiated
    ///   by MemoryCache. Direct usage will bypass thread safety guarantees.
    final class DiskCache: Sendable {
        // MARK: - Properties

        /// The directory where cache files are stored
        private let cacheFolder: URL?

        /// Logger for debugging and error reporting
        private let logger = LogContext.diskCache.logger()

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
        func getData(for key: Key) async -> Value? {
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
                data = try await readFromFile(url: cacheSource)
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
        
        /// Reads file contents asynchronously to avoid blocking the actor.
        ///
        /// Uses FileHandle's async bytes API to read files without blocking.
        /// This allows other cache operations to proceed while disk I/O occurs,
        /// significantly improving concurrent performance.
        ///
        /// - Parameter url: The file URL to read from
        /// - Returns: The complete file contents
        /// - Throws: File system errors if the read fails
        private func readFromFile(url: URL) async throws -> Data {
            let fileHandle = try FileHandle(forReadingFrom: url)
            
            defer {
                try? fileHandle.close()
            }
            
            var contents = Data()
            for try await chunk in fileHandle.bytes {
                contents.append(chunk)
            }
            
            return contents
        }

        /// Stores a value in the cache for a given key.
        ///
        /// The value's data is written to a file named using the SHA256 hash of the key.
        /// If the write operation fails, the error is logged but not thrown.
        ///
        /// - Parameters:
        ///   - value: The value to cache
        ///   - key: The key for storing the value
        ///   - cleanUpAfterSet: Whether to run cleanup after this write.
        ///     This decision is made by MemoryCache to centralize cleanup logic.
        func setValue(
            _ value: Value,
            at key: Key,
            cleanUpAfterSet: Bool
        ) {
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

            // Cleanup is triggered by MemoryCache based on write count.
            // Running it here keeps disk operations together and ensures
            // cleanup happens after the write completes.
            if cleanUpAfterSet {
                cleanup()
            }
        }

        // MARK: - Private Methods

        /// Removes cache files older than maxFileAge from the shared cache directory.
        ///
        /// This method is called:
        /// - On init to clean up old files from previous app sessions
        /// - Every 100 writes as determined by MemoryCache
        ///
        /// The 1-hour age limit is optimized for radar images which become
        /// stale after weather conditions change. This prevents unbounded
        /// disk growth while keeping recent data available.
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
