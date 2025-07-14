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
│  ┌─────────────────┐           ┌────────────────────┐   │
│  │     NSCache     │           │     DiskCache      │   │
│  │  <NSString,     │           │                    │   │
│  │   NSData>       │           │  ┌──────────────┐  │   │
│  └────────┬────────┘           │  │ FileManager  │  │   │
│           │                    │  └──────────────┘  │   │
│           │                    │                    │   │
│  ┌────────▼────────┐           │  ┌──────────────┐  │   │
│  │  Auto Memory    │           │  │   SHA256     │  │   │
│  │  Management     │           │  │   Hashing    │  │   │
│  └─────────────────┘           │  └──────────────┘  │   │
│                                └────────────────────┘   │
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

Provides persistent storage with these characteristics:

- **Unique directories**: Each cache instance creates its own directory
- **SHA256 filenames**: Prevents filesystem issues with special characters
- **Automatic cleanup**: Directory removed on deallocation
- **Error resilience**: Corrupted files are automatically deleted

Design decisions:
- Not shared between instances (intentional isolation)
- No expiration/TTL (simplicity)
- Synchronous I/O (called from async context)

## Data Flow

### Cache Write Operation

```
set(value, key)
    │
    ├─► Convert key to NSString
    ├─► Serialize value to NSData
    ├─► Store in NSCache
    └─► Store in DiskCache (fire-and-forget)
```

### Cache Read Operation

```
value(for: key)
    │
    ├─► Check NSCache
    │   ├─► Found: Return value
    │   └─► Not found: Continue
    │
    └─► Check DiskCache
        ├─► Found: Store in NSCache, return value
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
4. **DiskCache safety**: Marked `Sendable` and designed for concurrent use

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

Each logger includes appropriate metadata for filtering and debugging.

## Future Considerations

Areas for potential enhancement:

1. **Shared disk cache**: Could reduce disk usage across instances
2. **Metrics/monitoring**: Add cache hit/miss rates
3. **TTL support**: Add expiration times
4. **Batch operations**: Optimize multiple get/set operations
5. **Size limits**: Add configurable NSCache limits

These were intentionally omitted for simplicity but could be added if needed.