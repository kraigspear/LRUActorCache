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
/// let cache = DiskCache()
/// 
/// // Store data
/// cache.setValue(imageData, at: key)
/// 
/// // Retrieve data
/// if let cachedData = cache.getData(for: key) {
///     // Use cached data
/// }
/// ```
///
/// ## Implementation Details
/// - The cache is stored in `~/Library/Caches/DiskCache/`
/// - Cache keys are hashed using SHA256 for filesystem compatibility
/// - Thread safety must be managed by the caller (e.g., MemoryCache actor)
/// - Failed operations are logged and don't throw errors
final class DiskCache<Key: Hashable & CustomStringConvertible, Value: CachedValue>: Sendable {
    
    // MARK: - Properties
    
    /// The directory where cache files are stored
    private let cacheFolder: URL?
    
    /// Logger for debugging and error reporting
    private let logger = LogContext.diskCache.logger()
    
    // MARK: - Initialization
    
    /// Creates a new disk cache instance.
    ///
    /// The initializer attempts to create a cache directory in the system's
    /// caches folder. If creation fails, the cache operates in a degraded
    /// mode where all operations become no-ops.
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
        
        let cacheFolder = cachePath.appending(path: "DiskCache")
        
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
    
    /// Retrieves data from the cache for a given URL.
    ///
    /// - Parameter url: The URL key for the cached data
    /// - Returns: The cached data if found, nil otherwise
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
            return nil
        }
        
        do {
            let value = try Value.fromData(data: data)
            logger.debug("success loading \(key) from cache")
            return value
        } catch {
            logger.error("Error decoding \(key) from cache")
            return nil
        }
        
    }
    
    /// Stores data in the cache for a given URL.
    ///
    /// - Parameters:
    ///   - data: The data to cache
    ///   - url: The URL key for the data
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
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        // map each byte to a two‐digit hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
