//
//  DiskCache.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 6/8/25.
//

import CryptoKit
import Foundation

/// A thread-safe disk cache implementation using Swift actors.
///
/// `DiskCache` provides persistent storage for data objects on disk, automatically
/// managing the cache directory in the system's caches folder. It uses URL-based
/// keys to store and retrieve data.
///
/// ## Usage
/// ```swift
/// let cache = DiskCache()
/// 
/// // Store data
/// await cache[url] = imageData
/// 
/// // Retrieve data
/// if let cachedData = await cache[url] {
///     // Use cached data
/// }
/// ```
///
/// ## Implementation Details
/// - The cache is stored in `~/Library/Caches/DiskCache/`
/// - Cache keys are derived from the URL path after "/radar/"
/// - All operations are thread-safe due to actor isolation
/// - Failed operations are logged and don't throw errors
public actor DiskCache {
    
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
                if fileManager.fileExists(atPath: cacheFolder.absoluteString) {
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
    
    // MARK: - Public API
    
    /// Retrieves data from the cache for a given URL.
    ///
    /// - Parameter url: The URL key for the cached data
    /// - Returns: The cached data if found, nil otherwise
    func getData(for url: URL) -> Data? {
        guard let cacheFolder else {
            return nil
        }
        
        let imagePath = cacheFolder.appending(path: url.cacheFileName)
        if !FileManager.default.fileExists(atPath: imagePath.path) {
            logger.debug("url: \(url) not found in cache at path: \(imagePath)")
            return nil
        }
        
        logger.debug("url: \(url) found in cache")
        
        do {
            let data = try Data(contentsOf: imagePath)
            logger.debug("success loading \(url) from cache")
            return data
        } catch {
            logger.error("Error loading \(url) from cache")
            return nil
        }
    }
    
    /// Stores data in the cache for a given URL.
    ///
    /// - Parameters:
    ///   - data: The data to cache
    ///   - url: The URL key for the data
    func setData(_ data: Data, at url: URL) {
        guard let cacheFolder else { return }
        
        let imagePath = cacheFolder.appending(path: url.cacheFileName)
        
        do {
            try data.write(to: imagePath)
        } catch {
            assertionFailure("Error writing to at path: \(imagePath) cache: \(error)")
            logger.error("Error writing to at path: \(imagePath) cache: \(error)")
        }
    }
}

// MARK: - URL Extension

private extension URL {
    var cacheFileName: String {
        // Create SHA256 hash of the URL
        let urlData = absoluteString.data(using: .utf8)!
        let hash = SHA256.hash(data: urlData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        
        // Get sanitized host
        let host = host?.replacingOccurrences(of: ".", with: "_") ?? "unknown"
        
        return "\(host)_\(hashString)"
    }
}
