import Foundation
import Testing

@testable import LRUActorCache

// Test implementation of CachedValue for DiskCache tests
private struct TestDiskCachedValue: CachedValue, Equatable {
    let content: String

    var data: Data {
        content.data(using: .utf8) ?? Data()
    }

    static func fromData(data: Data) throws -> TestDiskCachedValue {
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TestDiskCachedValue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode data"])
        }
        return TestDiskCachedValue(content: content)
    }
}

@Suite("DiskCacheTests", .serialized)
struct DiskCacheTests {
    // MARK: - Test Properties

    private let testValue = TestDiskCachedValue(content: "Test data content")
    private let testKey = "https://example.com/radar/test/image.png"

    // MARK: - Basic Operations Tests

    @Test("Store and retrieve data from disk cache")
    func storeAndRetrieveData() throws {
        let cache = DiskCache<String, TestDiskCachedValue>()
        // Store data
        cache.setValue(testValue, at: testKey)

        // Retrieve data
        let retrievedValue = cache.getData(for: testKey)
        #expect(retrievedValue == testValue, "Retrieved value should match the stored value")
    }

    @Test("Retrieve non-existent data returns nil")
    func retrieveNonExistentData() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let nonExistentKey = "https://example.com/radar/nonexistent.png"
        let value = cache.getData(for: nonExistentKey)
        #expect(value == nil, "Non-existent key should return nil")
    }

    @Test("Overwrite existing data")
    func overwriteExistingData() throws {
        let cache = DiskCache<String, TestDiskCachedValue>()
        // Store initial data
        cache.setValue(testValue, at: testKey)

        // Verify initial data
        var retrievedValue = cache.getData(for: testKey)
        #expect(retrievedValue == testValue, "Initial value should be stored correctly")

        // Overwrite with new data
        let newValue = TestDiskCachedValue(content: "New test data")
        cache.setValue(newValue, at: testKey)

        // Verify updated data
        retrievedValue = cache.getData(for: testKey)
        #expect(retrievedValue == newValue, "Cache should return the updated value after overwrite")
    }

    // MARK: - Cache Key Tests

    @Test("URLs with radar path generate valid cache keys")
    func urlsWithRadarPath() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let keys = [
            "https://example.com/radar/weather/map.png",
            "https://example.com/radar/satellite/view.jpg",
            "https://api.weather.com/radar/current/overlay.gif",
        ]

        for (index, key) in keys.enumerated() {
            let value = TestDiskCachedValue(content: "Test \(index)")
            cache.setValue(value, at: key)

            let retrievedValue = cache.getData(for: key)
            #expect(retrievedValue == value, "Each URL key should store and retrieve its corresponding value")
        }
    }

    @Test("Complex radar paths are handled correctly")
    func complexRadarPaths() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let complexKey = "https://example.com/api/v1/radar/region/north-america/layer/precipitation/tile/123/456.png"
        let value = TestDiskCachedValue(content: "Complex path data")

        // Store and retrieve
        cache.setValue(value, at: complexKey)
        let retrievedValue = cache.getData(for: complexKey)
        #expect(retrievedValue == value, "Complex URL paths should be handled correctly as cache keys")
    }

    // MARK: - Large Data Tests

    @Test("Store and retrieve large data")
    func largeDataHandling() throws {
        let cache = DiskCache<String, TestDiskCachedValue>()
        // Create 1MB of text data
        let largeContent = String(repeating: "X", count: 1024 * 1024)
        let largeValue = TestDiskCachedValue(content: largeContent)
        let largeDataKey = "https://example.com/radar/large-file.bin"

        // Store large data
        cache.setValue(largeValue, at: largeDataKey)

        // Retrieve and verify
        let retrievedValue = cache.getData(for: largeDataKey)
        #expect(retrievedValue == largeValue, "Large data (1MB) should be stored and retrieved correctly")
    }

    // MARK: - Concurrent Access Tests

    @Test("Concurrent read and write operations")
    func concurrentAccess() async throws {
        let cache = DiskCache<String, TestDiskCachedValue>()
        await withTaskGroup(of: Void.self) { group in
            // Concurrent writes
            for i in 0 ..< 10 {
                group.addTask {
                    let key = "https://example.com/radar/concurrent/image\(i).png"
                    let value = TestDiskCachedValue(content: "Concurrent data \(i)")
                    cache.setValue(value, at: key)
                }
            }

            // Concurrent reads
            for i in 0 ..< 10 {
                group.addTask {
                    let key = "https://example.com/radar/concurrent/image\(i).png"
                    _ = cache.getData(for: key)
                }
            }
        }

        // Verify all data was written correctly
        for i in 0 ..< 10 {
            let key = "https://example.com/radar/concurrent/image\(i).png"
            let expectedValue = TestDiskCachedValue(content: "Concurrent data \(i)")
            let retrievedValue = cache.getData(for: key)
            #expect(retrievedValue == expectedValue, "All concurrent writes should complete successfully")
        }
    }

    @Test("Concurrent writes to same URL")
    func concurrentWritesToSameURL() async {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let sharedKey = "https://example.com/radar/shared.png"

        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    let value = TestDiskCachedValue(content: "Concurrent write \(i)")
                    cache.setValue(value, at: sharedKey)
                }
            }
        }

        // Should have some data (last write wins)
        let finalValue = cache.getData(for: sharedKey)
        #expect(finalValue != nil, "Concurrent writes to same key should result in some value being stored")
    }

    // MARK: - Special Characters Tests

    @Test("URLs with special characters in path")
    func specialCharactersInPath() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let specialKeys = [
            "https://example.com/radar/region%20name/image.png",
            "https://example.com/radar/file%20with%20spaces.png",
            "https://example.com/radar/special-chars_123.png",
            "https://example.com/radar/unicode-文件.png",
        ]

        for key in specialKeys {
            let value = TestDiskCachedValue(content: "Special char data")
            cache.setValue(value, at: key)

            let retrievedValue = cache.getData(for: key)
            #expect(retrievedValue == value, "URLs with special characters should be valid cache keys")
        }
    }

    // MARK: - Performance Tests

    @Test("Performance with many files")
    func performanceWithManyFiles() throws {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let startTime = Date()

        // Write 100 files
        for i in 0 ..< 100 {
            let key = "https://example.com/radar/perf/image\(i).png"
            let value = TestDiskCachedValue(content: "Performance test \(i)")
            cache.setValue(value, at: key)
        }

        // Read all files
        for i in 0 ..< 100 {
            let key = "https://example.com/radar/perf/image\(i).png"
            _ = cache.getData(for: key)
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete in reasonable time (< 5 seconds)
        #expect(elapsed < 5.0, "Writing and reading 100 files should complete within 5 seconds")
    }

    // MARK: - Edge Cases

    @Test("Empty data handling")
    func emptyDataHandling() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let emptyValue = TestDiskCachedValue(content: "")
        let key = "https://example.com/radar/empty.dat"

        // Store empty data
        cache.setValue(emptyValue, at: key)

        // Should retrieve empty data (not nil)
        let retrievedValue = cache.getData(for: key)
        #expect(retrievedValue == emptyValue, "Empty data should be stored and retrieved successfully")
        #expect(retrievedValue?.content == "", "Retrieved content should be empty string")
    }

    @Test("URL with query parameters")
    func urlWithQueryParameters() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let key = "https://example.com/radar/image.png?timestamp=123456&quality=high"
        let value = TestDiskCachedValue(content: "Query param data")

        cache.setValue(value, at: key)
        let retrievedValue = cache.getData(for: key)
        #expect(retrievedValue == value, "URLs with query parameters should work as cache keys")
    }

    @Test("URL with fragment")
    func urlWithFragment() {
        let cache = DiskCache<String, TestDiskCachedValue>()
        let key = "https://example.com/radar/image.png#section1"
        let value = TestDiskCachedValue(content: "Fragment data")

        cache.setValue(value, at: key)
        let retrievedValue = cache.getData(for: key)
        #expect(retrievedValue == value, "URLs with fragments should work as cache keys")
    }
}
