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

This Swift package implements a thread-safe LRU (Least Recently Used) cache with both memory and disk storage capabilities.

### Core Components

1. **MemoryCache** (`Sources/LRUActorCache/MemoryCache.swift`)
   - Actor-based thread-safe implementation
   - Cost-based eviction with configurable limits
   - LRU eviction policy using doubly-linked list
   - Automatic memory pressure handling
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
- **LRU Implementation**: Uses doubly-linked list with head/tail pointers for O(1) operations
- **Memory Pressure Handling**: Responds to system memory warnings by evicting items
- **Cost-Based Eviction**: Items have associated costs, cache has total cost limit

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