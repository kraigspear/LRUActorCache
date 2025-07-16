# Architecture Overview

This document provides a detailed architectural overview of the LRUActorCache implementation for developers working on the codebase.

## Design Philosophy

The cache is designed around these core principles:

1. **Simplicity over complexity** - Leverage proven Foundation components (NSCache) rather than reimplementing caching logic
2. **Thread safety by default** - Use Swift actors for guaranteed thread-safe access
3. **Graceful degradation** - Operations fail silently with logging rather than throwing errors
4. **Automatic memory management** - Let the system handle memory pressure through NSCache

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MemoryCache (Actor)                   │
│                                                          │
│  ┌─────────────────┐                                    │
│  │     NSCache     │    ┌────────────────────────────┐  │
│  │  <NSString,     │    │  Private DiskCache Class   │  │
│  │   NSData>       │    │      (Sendable)            │  │
│  └────────┬────────┘    │  ┌────────────────────┐   │  │
│           │             │  │  Async FileHandle   │   │  │
│           │             │  │    Operations       │   │  │
│  ┌────────▼────────┐    │  └────────────────────┘   │  │
│  │  Auto Memory    │    │  ┌────────────────────┐   │  │
│  │  Management     │    │  │  SHA256 Hashing    │   │  │
│  └─────────────────┘    │  └────────────────────┘   │  │
│                         │  ┌────────────────────┐   │  │
│  ┌─────────────────┐    │  │  Count-Based       │   │  │
│  │  OSSignposter   │    │  │  Cleanup (100)     │   │  │
│  │  Performance    │    │  └────────────────────┘   │  │
│  └─────────────────┘    └────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### MemoryCache

The main actor that coordinates all caching operations:

- **Actor-based concurrency**: Ensures thread-safe access to all cache operations
- **Generic over Key and Value**: Supports any Hashable key and CachedValue
- **Two-tier storage**: Memory (NSCache) with automatic disk fallback

Key constraints:
- `Key` must be `Hashable`, `CustomStringConvertible`, and `Sendable`
- `Value` must conform to `CachedValue` protocol

### NSCache Integration

We use `NSCache<NSString, NSData>` as the underlying memory storage:

- **Why NSString/NSData?**: NSCache requires NSObject subclasses
- **Key conversion**: Uses `key.description` to convert to NSString
- **Value conversion**: Uses `CachedValue.data` property for serialization

Benefits of NSCache:
- Automatic response to memory warnings
- Thread-safe by design
- Integrated with iOS/macOS memory management
- Battle-tested in production apps

### DiskCache

DiskCache is now a private nested class within MemoryCache, providing persistent storage with these characteristics:

- **Private implementation detail**: Not accessible outside MemoryCache
- **Sendable conformance**: Enables async operations without blocking the actor
- **Identifier-based directories**: Multiple caches with same identifier share storage
- **SHA256 filenames**: Prevents filesystem issues with special characters
- **Count-based cleanup**: Removes old files every 100 writes (not time-based)
- **Async file operations**: Uses FileHandle's async APIs for non-blocking I/O
- **Error resilience**: Corrupted files are automatically deleted

Design decisions:
- **Nested class**: Encapsulates disk operations as implementation detail
- **Stateless design**: All mutable state managed by MemoryCache actor
- **1-hour file expiration**: Optimized for radar image use case
- **Fire-and-forget writes**: Disk writes don't block cache operations

## Data Flow

### Cache Write Operation

```
set(value, key)
    │
    ├─► Convert key to NSString
    ├─► Serialize value to NSData
    ├─► Store in NSCache
    ├─► Check if cleanup needed (every 100 writes)
    └─► Store in DiskCache (fire-and-forget)
         └─► Run cleanup if needed
```

### Cache Read Operation

```
value(for: key) [Signpost: CacheRead]
    │
    ├─► Check NSCache
    │   ├─► Found: Return value
    │   └─► Not found: Continue
    │
    └─► Check DiskCache (async)
        ├─► Found: [Signpost: DiskRead]
        │   ├─► Read file async (FileHandle.bytes)
        │   ├─► Store in NSCache (setInMemoryOnly)
        │   └─► Return value
        └─► Not found: Return nil
```

## Protocol Design

### CachedValue Protocol

```swift
public protocol CachedValue: Sendable {
    var data: Data { get }
    static func fromData(data: Data) throws -> Self
}
```

Design rationale:
- **Sendable**: Required for actor isolation
- **data property**: Enables disk persistence
- **fromData method**: Enables deserialization with error handling

### Data Extension

`Data` conforms to `CachedValue` by default, enabling direct storage of raw data without wrapper types.

## Concurrency Model

The cache uses Swift's actor model for concurrency:

1. **Actor isolation**: All mutable state is isolated within the actor
2. **Async/await**: All public methods are async
3. **No locks needed**: Actor model prevents data races
4. **DiskCache safety**: Marked `Sendable` with immutable state
5. **Non-blocking I/O**: Async file operations don't block the actor

### Performance Optimizations

- **Async disk reads**: FileHandle.bytes API allows concurrent operations
- **OSSignposter integration**: Performance profiling without production impact
- **Reduced logging**: Summary logs instead of per-operation details

## Error Handling Strategy

The cache uses a "fail silently" approach:

- **No throwing methods**: Operations return nil or log errors
- **Automatic recovery**: Corrupted disk files are deleted
- **Logging**: Comprehensive OSLog usage for debugging
- **Assertions**: Used in debug builds for programmer errors

This approach prioritizes availability over consistency - a cache miss is better than a crash.

## Memory Management

Memory is managed automatically by NSCache:

- **System integration**: Responds to memory pressure notifications
- **Automatic eviction**: Items removed based on available memory
- **No manual limits**: Simplifies API and implementation
- **Cost-based eviction**: Not implemented (NSCache decides)

## Logging Architecture

Three log contexts for different concerns:

1. **cache**: General cache operations
2. **diskCache**: Disk I/O operations  
3. **memoryPressure**: Memory-related events

Each context provides:
- **Logger**: For error and informational messages
- **Signposter**: For performance profiling with Instruments

### Performance Monitoring

OSSignposter usage for critical paths:
- **CacheRead**: Total time for cache retrieval operations
- **DiskRead**: Time spent reading from disk
- **DiskCleanup**: Time spent cleaning old files

Signposts have zero overhead in production unless actively profiling.

## Future Considerations

Areas for potential enhancement:

1. **Shared disk cache**: Could reduce disk usage across instances
2. **Metrics/monitoring**: Add cache hit/miss rates
3. **TTL support**: Add expiration times
4. **Batch operations**: Optimize multiple get/set operations
5. **Size limits**: Add configurable NSCache limits

These were intentionally omitted for simplicity but could be added if needed.