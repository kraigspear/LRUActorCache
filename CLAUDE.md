# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the package
swift build

# Run all tests
swift test

# Run a specific test
swift test --filter TestName

# Build for release
swift build -c release

# Clean build artifacts
swift package clean
```

## Architecture Overview

This Swift package implements a thread-safe memory cache with automatic eviction and disk persistence. The cache leverages NSCache for memory management, which provides system-integrated eviction policies based on available memory rather than strict LRU behavior.

### Core Components

1. **MemoryCache** (`Sources/LRUActorCache/MemoryCache.swift`)
   - Actor-based thread-safe implementation
   - Built on NSCache for automatic memory management
   - NSCache handles eviction based on system memory pressure
   - Automatic eviction when memory is needed by the system
   - Integration with DiskCache for persistence

2. **DiskCache** (`Sources/LRUActorCache/DiskCache.swift`)
   - Persistent storage in `~/Library/Caches/DiskCache/`
   - SHA256-based file naming for cache keys
   - Generic implementation supporting any Hashable key type

3. **CachedValue Protocol**
   - Requires `cost: Int` property for memory management
   - Requires `data: Data` property for serialization
   - Requires `fromData(data:) throws -> Self` for deserialization

### Key Design Patterns

- **Actor Pattern**: Both caches use Swift actors for thread safety
- **NSCache Foundation**: Leverages NSCache's built-in memory management and eviction policies
- **Memory Pressure Handling**: NSCache automatically responds to system memory warnings
- **System Integration**: NSCache integrates with iOS/macOS memory management systems

### Platform Requirements

- iOS 18.0+
- macOS 15.0+
- Swift 6.0+

## Common Development Tasks

When making changes to the cache implementation:

1. The CachedValue protocol has been extended to support disk persistence - ensure any cached types implement the required `data` property and `fromData` method
2. The tests currently have compilation errors due to protocol conformance - fix these when updating tests
3. Use OSLog for debugging with appropriate log contexts (cache, diskCache, memoryPressure)
4. Performance monitoring is built-in using OSSignposter

## Testing Approach

The package uses Swift Testing framework (@Test attributes). Tests are located in `Tests/LRUActorCacheTests/` and cover:
- Basic cache operations (set/get/remove)
- LRU eviction behavior
- Memory pressure handling
- Cost-based eviction
- Edge cases and error handling
- Disk cache persistence