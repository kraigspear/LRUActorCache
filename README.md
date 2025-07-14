# Swift Memory Cache

A thread-safe memory cache implementation with automatic eviction and disk persistence. Built on NSCache for reliable system-integrated memory management.

## Features

- 🔒 Thread-safe implementation using Swift actors
- 📱 Built on NSCache for automatic memory management
- 🗑️ Automatic eviction based on system memory pressure
- 💾 Persistent disk storage with automatic fallback
- 📝 Comprehensive logging for debugging
- 🔐 SHA256-based disk cache file naming

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
    let imageData: Data
    
    // Required for serialization
    var data: Data { imageData }
    
    static func fromData(data: Data) throws -> CachedImage {
        CachedImage(imageData: data)
    }
}

// Create a cache instance
let cache = MemoryCache<String, CachedImage>()

// Store a value
let imageData = Data() // Your image data
let cachedImage = CachedImage(imageData: imageData)
await cache.set(cachedImage, for: "profile-picture")

// Retrieve a value
if let image = await cache.value(for: "profile-picture") {
    // Use the cached image
}
```

### Advanced Usage

```swift
// Check if a value exists in memory
let exists = await cache.contains("profile-picture")

// Store Data directly (Data conforms to CachedValue)
let rawData = "Hello, World!".data(using: .utf8)!
await cache.set(rawData, for: "text-data")

// Retrieve from disk if not in memory
// The cache automatically checks disk storage when a value isn't in memory
let cachedValue = await cache.value(for: "some-key")
```

## Memory Management

The cache uses NSCache which automatically handles memory pressure:
- Responds to system memory warnings
- Evicts items based on available memory
- Integrates with iOS/macOS memory management

Items persist to disk and are automatically loaded when:
- Requested items are not in memory
- The cache can restore them from disk storage

## Protocol Requirements

To store a value in the cache, it must conform to the `CachedValue` protocol:

```swift
public protocol CachedValue: Sendable {
    var data: Data { get }
    static func fromData(data: Data) throws -> Self
}
```

The protocol requires:
- `data`: Serialized representation for disk persistence
- `fromData`: Deserialization from disk storage
- `Sendable`: Thread-safety requirement for actors

Note: `Data` already conforms to `CachedValue`, so you can store raw data directly.

## Thread Safety

The cache is implemented as an actor, ensuring thread-safe access to all operations. Always use `await` when calling cache methods:

```swift
await cache.set(value, for: key)
await cache.value(for: key)
```

## Logging

The cache includes logging using `OSLog` for debugging:
- Cache operations (hits/misses)
- Disk storage operations
- Error conditions

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
