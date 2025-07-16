# Implementation Details

This document provides a detailed walkthrough of the codebase implementation for developers who need to understand or modify the code.

## File Structure

```
Sources/LRUActorCache/
├── MemoryCache.swift            # Main cache actor and CachedValue protocol
├── MemoryCache+DiskCache.swift  # Private DiskCache nested class
└── LogContext.swift             # Logging and performance monitoring

Tests/LRUActorCacheTests/
└── LRUActorCacheTests.swift     # All test suites (21 tests)
```

## MemoryCache Implementation

### Actor Declaration

```swift
public actor MemoryCache<Key: Hashable & CustomStringConvertible & Sendable, Value: CachedValue>
```

**Generic constraints explained:**
- `Key: Hashable` - Required for dictionary/set operations
- `Key: CustomStringConvertible` - Needed to convert to NSString for NSCache
- `Key: Sendable` - Required for actor isolation
- `Value: CachedValue` - Ensures values can be serialized

### Internal Storage

```swift
private let values = NSCache<NSString, NSData>()
private let diskCache: DiskCache
private var numberOfWrites = 0  // Track writes for cleanup
```

**Why NSString/NSData?**
- NSCache requires NSObject subclasses
- We convert: Key → String → NSString
- We convert: Value → Data → NSData

### Key Methods

#### `value(for:)` - Cache Retrieval

```swift
public func value(for key: Key) async -> Value?
```

**Implementation flow:**
1. Convert key to NSString using `key.description`
2. Check NSCache for the value
3. If found, deserialize using `Value.fromData(data:)`
4. If not found, check DiskCache
5. If found on disk, store in memory cache for next time
6. Return the value or nil

**Edge cases handled:**
- Deserialization failures trigger assertion in debug
- Disk cache errors fail silently

#### `set(_:for:)` - Cache Storage

```swift
public func set(_ value: Value, for key: Key) async
```

**Implementation flow:**
1. Convert key to NSString
2. Serialize value to NSData using `value.data`
3. Store in NSCache (overwrites existing)
4. Store in DiskCache (fire-and-forget)

**Important notes:**
- No error handling - operations cannot fail from caller's perspective
- Disk write includes cleanup check every 100 writes
- Cleanup decision passed to DiskCache to keep disk operations together

#### `contains(_:)` - Existence Check

```swift
public func contains(_ key: Key) -> Bool
```

**Key characteristics:**
- Only checks memory cache, not disk
- Doesn't affect any internal state
- Synchronous (not async) since it's read-only

## DiskCache Implementation

DiskCache is now a private nested class within MemoryCache:

```swift
extension MemoryCache {
    final class DiskCache: Sendable {
        // All properties are immutable for Sendable conformance
        private let cacheFolder: URL?
        private let logger = LogContext.diskCache.logger()
        private let signposter = LogContext.diskCache.signposter()
    }
}
```

### Directory Management

```swift
init(identifier: String) {
    // Create directory based on identifier: ~/Library/Caches/DiskCache-{identifier}/
    let cacheFolder = cachePath.appending(path: "DiskCache-\(identifier)")
}
```

**Design decisions:**
- Identifier-based directories enable sharing between instances
- Uses system caches directory (cleaned by OS if needed)
- Directory created on init, cleanup runs on init/deinit and every 100 writes
- Files older than 1 hour are removed (optimized for radar images)

### File Naming

```swift
private func cacheFileName(for key: Key) -> String {
    key.description.cacheFileName
}

private extension String {
    var cacheFileName: String {
        let data = Data(utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

**Why SHA256?**
- Prevents filesystem issues with special characters
- Fixed length filenames
- No collisions in practice
- Deterministic (same key → same filename)

### Async File Operations

```swift
func getData(for key: Key) async -> Value? {
    // Async file reading for non-blocking I/O
    do {
        data = try await readFromFile(url: cacheSource)
    } catch {
        // Delete corrupted file
        try? FileManager.default.removeItem(at: cacheSource)
        return nil
    }
    
    // Try to deserialize
    do {
        let value = try Value.fromData(data: data)
        return value
    } catch {
        // Delete corrupted file
        try? FileManager.default.removeItem(at: cacheSource)
        return nil
    }
}

private func readFromFile(url: URL) async throws -> Data {
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("DiskRead", id: signpostID)
    defer { signposter.endInterval("DiskRead", state) }
    
    // Use FileHandle for async reading
    let fileHandle = try FileHandle(forReadingFrom: url)
    defer { try? fileHandle.close() }
    
    var contents = Data()
    for try await chunk in fileHandle.bytes {
        contents.append(chunk)
    }
    return contents
}
```

**Resilience features:**
- Corrupted files are automatically deleted
- All errors logged but not thrown
- Cache continues functioning even if disk fails
- Async operations don't block the actor
- Cleanup runs periodically to prevent unbounded growth

## Protocol Implementation

### CachedValue Protocol

The protocol enables generic caching with serialization:

```swift
public protocol CachedValue: Sendable {
    var data: Data { get }
    static func fromData(data: Data) throws -> Self
}
```

### Data Conformance

```swift
extension Data: CachedValue {
    public var data: Data { self }
    public static func fromData(data: Data) throws -> Data { data }
}
```

**Why this matters:**
- Users can cache raw Data without wrapper types
- Zero-cost abstraction (returns self)
- Enables caching images, JSON, etc. directly

## Testing Strategy

### Test Helpers

```swift
private struct TestCachedValue: CachedValue, Equatable {
    let someValue: String
    
    var data: Data {
        someValue.data(using: .utf8)!
    }
    
    static func fromData(data: Data) throws -> TestCachedValue {
        guard let someValue = String(data: data, encoding: .utf8) else {
            throw DeserializationError.invalidUTF8
        }
        return TestCachedValue(someValue: someValue)
    }
}
```

### Test Categories

1. **Basic Operations**: Set, get, contains
2. **Concurrency**: Parallel reads/writes
3. **Error Handling**: Deserialization failures
4. **Data Extension**: Direct Data storage
5. **Edge Cases**: Empty data, large data

### Important Test Patterns

**Concurrency testing:**
```swift
await withTaskGroup(of: Void.self) { group in
    for i in 0..<100 {
        group.addTask {
            await cache.set(value, for: key)
        }
    }
}
```

**Disk persistence testing:**
```swift
// Caches with same identifier share disk storage
let cache1 = MemoryCache<String, TestValue>(identifier: "shared")
await cache1.set(value, for: key)

let cache2 = MemoryCache<String, TestValue>(identifier: "shared")
let retrieved = await cache2.value(for: key)
// retrieved will contain the value (shared disk directory)

// Different identifiers have isolated storage
let cacheA = MemoryCache<String, TestValue>(identifier: "A")
let cacheB = MemoryCache<String, TestValue>(identifier: "B")
// These caches don't share data
```

## Performance Considerations

### Memory Usage

- NSCache automatically manages memory
- No explicit size tracking
- Values stored as NSData (potential overhead)

### Disk I/O

- Async file read operations using FileHandle.bytes
- Synchronous writes (fire-and-forget from actor)
- No batching or write coalescing
- Each set triggers immediate disk write
- Cleanup runs every 100 writes to manage disk usage

### Key Generation

- String description can be expensive for complex keys
- SHA256 hashing on every disk operation
- Consider caching the hash if performance critical

## Common Pitfalls

1. **Assuming LRU behavior**: NSCache doesn't guarantee LRU eviction
2. **Key description**: Must be stable across app launches
3. **Large values**: No built-in size limits
4. **Error handling**: Cache operations don't throw
5. **Cleanup timing**: Based on write count, not time
6. **Shared storage**: Instances with same identifier share disk

## Debugging Tips

### Enable Logging

```swift
// LogContext creates loggers with appropriate subsystem/category
private let logger = LogContext.cache.logger()
```

### Log Points

- Errors during file operations
- Cleanup summaries (number of files removed)
- Deserialization failures

### Performance Monitoring

Use Instruments with signposts:
- `CacheRead` - Total cache retrieval time
- `DiskRead` - Async file read operations
- `DiskCleanup` - Cleanup operation duration

### Using Console.app

Filter by subsystem: `com.spareware.LRUActorCache`

Categories:
- `🐏cache` - General operations
- `💾diskCache` - Disk I/O
- `⚠️memoryPressure` - Memory events (not currently used)

## Extension Points

### Custom CachedValue Types

```swift
struct ImageWrapper: CachedValue {
    let image: UIImage
    
    var data: Data {
        image.pngData() ?? Data()
    }
    
    static func fromData(data: Data) throws -> ImageWrapper {
        guard let image = UIImage(data: data) else {
            throw ImageError.invalidData
        }
        return ImageWrapper(image: image)
    }
}
```

### Monitoring

You could add cache statistics:

```swift
public actor MemoryCache {
    private var hitCount = 0
    private var missCount = 0
    
    public var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0
    }
}
```

## Implementation Gotchas

1. **NSCache eviction**: Not predictable or controllable
2. **Actor reentrancy**: Awaiting can allow other operations to interleave
3. **Disk space**: Managed by cleanup every 100 writes
4. **Key collisions**: Technically possible with SHA256 (but extremely unlikely)
5. **Thread safety**: DiskCache is Sendable with immutable state
6. **Async operations**: DiskCache reads don't block the actor
7. **Cleanup**: Runs on init, deinit, and periodically during writes