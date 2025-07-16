# Contributing Guide

Welcome! This guide will help you get started with contributing to the LRUActorCache project.

## Development Setup

### Prerequisites

- Xcode 16.0 or later
- Swift 6.0 or later
- macOS 15.0+ or iOS 18.0+ for testing

### Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/kraigspear/LRUActorCache.git
   cd LRUActorCache
   ```

2. Open in Xcode:
   ```bash
   open Package.swift
   ```

3. Build and test:
   ```bash
   swift build
   swift test
   ```

## Code Style Guidelines

### General Principles

- **Clarity over cleverness**: Write code that's easy to understand
- **Fail silently**: Cache operations should return nil rather than throw
- **Comprehensive logging**: Use OSLog for debugging
- **Test everything**: Especially edge cases and concurrent operations

### Swift Style

We follow standard Swift conventions:

```swift
// MARK: - Section Headers
// Use MARK comments to organize code into logical sections

// Property ordering
public actor MemoryCache {
    // Public properties first
    public let configuration: Config
    
    // Private properties after
    private let cache = NSCache<NSString, NSData>()
    
    // MARK: - Initialization
    
    // MARK: - Public Methods
    
    // MARK: - Private Methods
}
```

### Naming Conventions

- **Types**: `UpperCamelCase` (e.g., `MemoryCache`, `CachedValue`)
- **Methods/Properties**: `lowerCamelCase` (e.g., `value(for:)`, `diskCache`)
- **Generic Parameters**: Single letter or descriptive (e.g., `Key`, `Value`)

### Documentation

All public APIs must have documentation comments following the standards in CLAUDE.md:

```swift
/// Retrieves a value from the cache for the given key.
///
/// This method first checks the memory cache, then falls back to disk storage
/// if the value is not found in memory. The disk read operation is performed
/// asynchronously without blocking the actor.
///
/// - Parameter key: The key to look up in the cache.
/// - Returns: The cached value if found, or `nil` if not present.
public func value(for key: Key) async -> Value?
```

**Important**: Focus on WHY not HOW in comments. See CLAUDE.md for detailed documentation standards.

## Architecture Guidelines

### Actor Isolation

- All mutable state must be isolated within actors
- Public methods should be `async` when accessing actor state
- Use `Sendable` constraints for thread safety

### Error Handling

Follow the "fail silently" principle:

```swift
// Good: Return nil on error
func getData(for key: Key) -> Value? {
    do {
        let data = try Data(contentsOf: url)
        return try Value.fromData(data: data)
    } catch {
        logger.error("Failed to load data: \(error)")
        return nil
    }
}

// Bad: Throwing errors from cache operations
func getData(for key: Key) throws -> Value  // Don't do this
```

### Logging and Performance Monitoring

Use the established LogContext pattern:

```swift
private let logger = LogContext.cache.logger()
private let signposter = LogContext.cache.signposter()

// Log levels:
// - debug: Useful debugging info (avoid verbose per-operation logs)
// - info: Important events (e.g., cleanup summaries)
// - error: Errors that are handled gracefully
// - critical: Serious issues that may affect functionality

// Performance monitoring with signposts:
let signpostID = signposter.makeSignpostID()
let state = signposter.beginInterval("OperationName", id: signpostID)
defer { signposter.endInterval("OperationName", state) }
```

**Note**: Avoid excessive debug logging in hot paths. Use signposts for performance monitoring instead.

## Testing Guidelines

### Test Structure

```swift
@Suite("FeatureName", .serialized)  // Use .serialized for disk operations
struct FeatureNameTests {
    @Test("Descriptive test name")
    func testSpecificBehavior() async throws {
        // Arrange
        let cache = MemoryCache<String, TestValue>()
        
        // Act
        await cache.set(testValue, for: "key")
        
        // Assert
        #expect(await cache.contains("key"))
    }
}
```

### Test Coverage

Ensure tests cover:
- ✅ Happy path scenarios
- ✅ Error conditions
- ✅ Edge cases (empty data, nil values)
- ✅ Concurrent operations
- ✅ Memory pressure (if applicable)

### Test Helpers

Create test-specific types that are simple and focused:

```swift
private struct TestCachedValue: CachedValue, Equatable {
    let value: String
    
    var data: Data { 
        value.data(using: .utf8)! 
    }
    
    static func fromData(data: Data) throws -> Self {
        // Implementation
    }
}
```

## Making Changes

### Before You Start

1. Check existing issues and PRs
2. For major changes, open an issue first to discuss
3. Ensure your change aligns with the project's philosophy

### Development Workflow

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the guidelines above

3. Ensure all tests pass:
   ```bash
   swift test
   ```

4. Update documentation if needed:
   - API documentation in code (following CLAUDE.md standards)
   - README.md for user-facing changes
   - Docs/ folder for implementation changes:
     - ARCHITECTURE.md for structural changes
     - IMPLEMENTATION.md for code organization
     - TEST_NOTES.md for test coverage updates

5. Commit with clear messages:
   ```bash
   git commit -m "Add feature: brief description"
   ```

### Pull Request Guidelines

1. **Title**: Clear and descriptive
2. **Description**: Explain what and why
3. **Tests**: Include tests for new functionality
4. **Documentation**: Update as needed
5. **Breaking Changes**: Clearly marked

Example PR description:
```
## Summary
Add batch operations for improved performance when caching multiple values.

## Changes
- Added `setValues(_:)` method to MemoryCache
- Optimized disk writes to batch operations
- Added tests for concurrent batch operations

## Performance
Batch operations are ~3x faster for 100+ items.
```

## Project Structure

```
Sources/LRUActorCache/
├── MemoryCache.swift           # Main actor implementation
├── MemoryCache+DiskCache.swift # Private DiskCache nested class
└── LogContext.swift            # Logging and performance monitoring

Tests/LRUActorCacheTests/
└── LRUActorCacheTests.swift    # All test suites

Docs/
├── ARCHITECTURE.md             # High-level design
├── IMPLEMENTATION.md           # Code organization details
├── TEST_NOTES.md               # Test coverage documentation
└── CONTRIBUTING.md             # This file
```

## Common Tasks

### Adding a New Feature

1. Discuss in an issue first
2. Consider API design carefully (we value stability)
3. Implement with tests
4. Update documentation
5. Submit PR

### Fixing a Bug

1. Add a failing test that reproduces the bug
2. Fix the bug
3. Ensure test now passes
4. Submit PR with test and fix

### Improving Performance

1. Benchmark current performance
2. Make improvements
3. Benchmark again to verify
4. Document the improvements
5. Ensure no functionality is broken

## Release Process

Releases follow semantic versioning:

- **Patch** (0.0.x): Bug fixes, documentation
- **Minor** (0.x.0): New features, backwards compatible
- **Major** (x.0.0): Breaking changes

## Questions?

- Open an issue for questions
- Check existing documentation in Docs/
- Review test cases for usage examples

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow

Thank you for contributing! 🎉