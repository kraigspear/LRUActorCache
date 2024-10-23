# Swift Memory Cache

A thread-safe, cost-based memory cache implementation with LRU (Least Recently Used) eviction policy. This cache is designed to handle memory pressure gracefully and provides detailed logging and performance monitoring through signposts.

## Features

- 🔒 Thread-safe implementation using Swift actors
- 📊 Cost-based storage limits
- ⚡️ LRU (Least Recently Used) eviction policy
- 🗑️ Automatic cleanup under memory pressure
- 📝 Comprehensive logging and performance monitoring
- 💾 Configurable maximum item count and total cost limits

## Installation

Add this package to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/kraigspear/LRUActorCache.git", from: "0.1.0")
]
```

## Usage

### Basic Example

```swift
// Define a cached value type
struct CachedImage: CachedValue {
    let data: Data
    var cost: Int { data.count }
}

// Create a cache instance (10MB limit, max 500 items)
let cache = MemoryCache<String, CachedImage>(totalCostInMegaBytes: 10)

// Store a value
let imageData = Data() // Your image data
let cachedImage = CachedImage(data: imageData)
await cache.set(cachedImage, for: "profile-picture")

// Retrieve a value
if let image = await cache.value(for: "profile-picture") {
    // Use the cached image
}
```

### Advanced Usage

```swift
// Check if a value exists without affecting LRU order
let exists = await cache.contains("profile-picture")

// Clear the entire cache
await cache.removeAll()

// Create a cache with custom limits
let customCache = MemoryCache<String, CachedImage>(
    totalCostLimit: 1024 * 1024 * 20, // 20MB
    maxCount: 1000
)
```

## Memory Management

The cache automatically handles memory pressure events:
- On memory warning: Removes 50% of cached items
- On critical memory warning: Removes all cached items

Items are automatically evicted when:
- Total cost exceeds the specified limit
- Item count exceeds the maximum count
- System sends memory pressure notifications

## Protocol Requirements

To store a value in the cache, it must conform to the `CachedValue` protocol:

```swift
public protocol CachedValue {
    var cost: Int { get }
}
```

The `cost` property determines how much space the value takes in the cache. For example:
- For images: use the size of the image data
- For objects: use the estimated memory footprint
- For collections: use the count or total size of elements

## Thread Safety

The cache is implemented as an actor, ensuring thread-safe access to all operations. Always use `await` when calling cache methods:

```swift
await cache.set(value, for: key)
await cache.value(for: key)
```

## Logging and Performance Monitoring

The cache includes comprehensive logging using `OSLog` and performance monitoring with `OSSignposter`. This helps track:
- Cache operations
- Memory usage
- Eviction events
- Performance metrics

## License

MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
