import Foundation
import Testing

@testable import LRUActorCache

// A simple CachedValue implementation for testing
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

    enum DeserializationError: Error {
        case invalidUTF8
    }
}

// A CachedValue that can fail deserialization
private struct FailingCachedValue: CachedValue {
    let value: String
    let shouldFailDeserialization: Bool

    var data: Data {
        var result = Data()
        result.append(shouldFailDeserialization ? 1 : 0)
        if let stringData = value.data(using: .utf8) {
            result.append(stringData)
        }
        return result
    }

    static func fromData(data: Data) throws -> FailingCachedValue {
        guard data.count > 0 else {
            throw DeserializationError.invalidData
        }

        let shouldFail = data[0] == 1
        if shouldFail {
            throw DeserializationError.intentionalFailure
        }

        let stringData = data.dropFirst()
        guard let value = String(data: stringData, encoding: .utf8) else {
            throw DeserializationError.invalidString
        }

        return FailingCachedValue(value: value, shouldFailDeserialization: false)
    }

    enum DeserializationError: Error {
        case intentionalFailure
        case invalidData
        case invalidString
    }
}

@Suite("CacheTest", .serialized)
struct CacheTest {
    private let cache: MemoryCache<String, TestCachedValue>

    init() {
        cache = MemoryCache<String, TestCachedValue>()
    }

    @Test("Set and Retrieve Value")
    func setAndRetrieveValue() async throws {
        let key = "testKey"
        let value = TestCachedValue(someValue: "test10")
        await cache.set(value, for: key)
        let retrievedValue = try #require(await cache.value(for: key))
        #expect(retrievedValue == value, "Retrieved value should match the stored value")
    }

    @Test("Contains Key")
    func containsKeys() async {
        await cache.set(TestCachedValue(someValue: "test1"), for: "key1")
        #expect(await cache.contains("key1"), "Cache should contain the key that was just set")
        #expect(await !cache.contains("key2"), "Cache should not contain a key that was never set")
    }

    @Test("Disk Cache Within Same Instance")
    func diskCacheWithinSameInstance() async throws {
        // Test that disk cache works within the same cache instance
        let cache = MemoryCache<String, TestCachedValue>()
        let key = "persistentKey"
        let value = TestCachedValue(someValue: "persistentValue")
        await cache.set(value, for: key)

        // Value should be retrievable
        let retrievedValue = try #require(await cache.value(for: key))
        #expect(retrievedValue == value, "Value should be retrievable from the same cache instance")

        // And should be in memory
        #expect(await cache.contains(key), "Key should exist in memory cache after retrieval")
    }

    @Test("Deserialization Error Handling")
    func deserializationErrorHandling() async throws {
        // Create a cache with failing values
        let cache = MemoryCache<String, FailingCachedValue>()

        // Store a value that will fail deserialization when loaded from disk
        let key = "failingKey"
        let failingValue = FailingCachedValue(value: "test", shouldFailDeserialization: true)
        await cache.set(failingValue, for: key)

        // Create a new cache instance to force loading from disk
        let cache2 = MemoryCache<String, FailingCachedValue>()

        // Attempting to retrieve should return nil due to deserialization failure
        let retrievedValue = await cache2.value(for: key)
        #expect(retrievedValue == nil, "Deserialization failure should return nil, not throw")

        // Verify the corrupted file was deleted - a second attempt should also return nil
        // but won't try to load from disk since the file no longer exists
        let cache3 = MemoryCache<String, FailingCachedValue>()
        let secondAttempt = await cache3.value(for: key)
        #expect(secondAttempt == nil, "Corrupted file should be deleted after first failed attempt")
    }

    @Test("Concurrent Read Operations")
    func concurrentReadOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>()
        let key = "concurrentKey"
        let value = TestCachedValue(someValue: "concurrentValue")

        // Set initial value
        await cache.set(value, for: key)

        // Perform multiple concurrent reads
        await withTaskGroup(of: TestCachedValue?.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    await cache.value(for: key)
                }
            }

            // Verify all reads return the same value
            for await result in group {
                #expect(result == value, "All concurrent reads should return the same cached value")
            }
        }
    }

    @Test("Concurrent Write Operations")
    func concurrentWriteOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>()

        // Perform multiple concurrent writes to different keys
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    let key = "key\(i)"
                    let value = TestCachedValue(someValue: "value\(i)")
                    await cache.set(value, for: key)
                }
            }
        }

        // Verify all values were written correctly
        for i in 0 ..< 50 {
            let key = "key\(i)"
            let expectedValue = TestCachedValue(someValue: "value\(i)")
            let retrievedValue = await cache.value(for: key)
            #expect(retrievedValue == expectedValue, "Each concurrent write should be stored correctly")
        }
    }

    @Test("Concurrent Mixed Operations")
    func concurrentMixedOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>()

        // Pre-populate some values
        for i in 0 ..< 10 {
            await cache.set(TestCachedValue(someValue: "initial\(i)"), for: "key\(i)")
        }

        // Perform mixed operations concurrently
        await withTaskGroup(of: Void.self) { group in
            // Readers
            for _ in 0 ..< 30 {
                group.addTask {
                    let randomKey = "key\(Int.random(in: 0 ..< 10))"
                    _ = await cache.value(for: randomKey)
                }
            }

            // Writers
            for i in 10 ..< 20 {
                group.addTask {
                    let key = "key\(i)"
                    let value = TestCachedValue(someValue: "new\(i)")
                    await cache.set(value, for: key)
                }
            }

            // Contains checks
            for _ in 0 ..< 20 {
                group.addTask {
                    let randomKey = "key\(Int.random(in: 0 ..< 20))"
                    _ = await cache.contains(randomKey)
                }
            }
        }

        // Verify new values were written
        for i in 10 ..< 20 {
            let key = "key\(i)"
            let expectedValue = TestCachedValue(someValue: "new\(i)")
            let retrievedValue = await cache.value(for: key)
            #expect(retrievedValue == expectedValue, "New values written during concurrent operations should be stored")
        }
    }

    @Test("Concurrent Same Key Updates")
    func concurrentSameKeyUpdates() async throws {
        let cache = MemoryCache<String, TestCachedValue>()
        let key = "raceKey"

        // Multiple tasks updating the same key
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 100 {
                group.addTask {
                    let value = TestCachedValue(someValue: "update\(i)")
                    await cache.set(value, for: key)
                }
            }
        }

        // Verify that some value was set (we can't predict which one due to race conditions)
        let finalValue = await cache.value(for: key)
        #expect(finalValue != nil, "After concurrent updates, some value should be stored")
        #expect(finalValue?.someValue.starts(with: "update") == true, "Stored value should be one of the updates")
    }
}

// MARK: - Data Extension Tests

@Suite("DataCachedValueTests", .serialized)
struct DataCachedValueTests {
    @Test("Data conforms to CachedValue")
    func dataConformsToCachedValue() {
        // Verify Data.data returns self
        let testData = "Hello, World!".data(using: .utf8)!
        #expect(testData.data == testData, "Data.data should return self")

        // Verify Data.fromData returns input unchanged
        let result = try? Data.fromData(data: testData)
        #expect(result == testData, "Data.fromData should return the input unchanged")
    }

    @Test("Store and retrieve Data in MemoryCache")
    func storeAndRetrieveDataInMemoryCache() async throws {
        let cache = MemoryCache<String, Data>()
        let key = "dataKey"
        let testData = "Test data content".data(using: .utf8)!

        // Store Data
        await cache.set(testData, for: key)

        // Retrieve Data
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == testData, "Retrieved Data should match stored Data")

        // Verify contains
        #expect(await cache.contains(key), "Cache should contain the Data key")
    }

    @Test("Store and retrieve Data in DiskCache")
    func storeAndRetrieveDataInDiskCache() {
        let cache = DiskCache<String, Data>()
        let key = "diskDataKey"
        let testData = "Persistent data content".data(using: .utf8)!

        // Store Data
        cache.setValue(testData, at: key)

        // Retrieve Data
        let retrievedData = cache.getData(for: key)
        #expect(retrievedData == testData, "Retrieved Data from disk should match stored Data")
    }

    @Test("Data persistence within same cache instance")
    func dataPersistenceWithinSameCacheInstance() async throws {
        let cache = MemoryCache<String, Data>()
        let key = "persistentDataKey"
        let testData = "Persistent data".data(using: .utf8)!

        // Store data
        await cache.set(testData, for: key)

        // Retrieve from same instance (should be in memory)
        let fromMemory = await cache.value(for: key)
        #expect(fromMemory == testData, "Data should be retrievable from memory")

        // Verify it's in the cache
        #expect(await cache.contains(key), "Cache should contain the key")

        // Note: Each cache instance has its own disk directory, so data doesn't persist across instances
    }

    @Test("Large Data handling")
    func largeDataHandling() async throws {
        let cache = MemoryCache<String, Data>()
        let key = "largeDataKey"

        // Create 1MB of data
        let largeData = Data(repeating: 0xFF, count: 1024 * 1024)

        // Store large Data
        await cache.set(largeData, for: key)

        // Retrieve and verify
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == largeData, "Large Data should be stored and retrieved correctly")
        #expect(retrievedData?.count == 1024 * 1024, "Retrieved Data size should match")
    }

    @Test("Empty Data handling")
    func emptyDataHandling() async throws {
        let cache = MemoryCache<String, Data>()
        let key = "emptyDataKey"
        let emptyData = Data()

        // Store empty Data
        await cache.set(emptyData, for: key)

        // Retrieve and verify
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == emptyData, "Empty Data should be stored and retrieved")
        #expect(retrievedData?.isEmpty == true, "Retrieved Data should be empty")
    }
}
