import Testing
import Foundation

@testable import LRUActorCache

// A simple CachedValue implementation for testing
private struct TestCachedValue: CachedValue, Equatable {
    let cost: Int
    
    var data: Data {
        Data()
    }
    
    static func fromData(data: Data) throws -> TestCachedValue {
        TestCachedValue(cost: data.count)
    }
}

@Suite("CacheTest", .serialized)
struct CacheTest {
    
    private let cache: MemoryCache<String, TestCachedValue>
    
    init() {
        cache = MemoryCache<String, TestCachedValue>(
            totalCostLimit: 100,
            maxCount: 5,
            resetDiskCache: true
        )
    }
    
    @Test("Set and Retrieve Value")
    func setAndRetrieveValue() async throws {
        let key = "testKey"
        let value = TestCachedValue(cost: 10)
        await cache.set(value, for: key)
        let retrievedValue = try #require(await cache.value(for: key))
        #expect(retrievedValue == value)
    }

    @Test("Max count limit")
    func maxCountLimit() async throws {
        for i in 0..<10 {
            let key = "testKey\(i)"
            let value = TestCachedValue(cost: 1)
            await cache.set(value, for: key)
        }
        
        // Check that first 5 items were evicted from memory
        for i in 0..<5 {
            #expect(await cache.contains("testKey\(i)") == false)
        }
        
        for i in 5..<10 {
            #expect(await cache.value(for: "testKey\(i)") != nil)
        }
    }
    
    @Test("Total cost limit")
    func totalCostLimit() async throws {
        await cache.set(TestCachedValue(cost: 40), for: "key1")
        await cache.set(TestCachedValue(cost: 30), for: "key2")
        await cache.set(TestCachedValue(cost: 20), for: "key3")
        await cache.set(TestCachedValue(cost: 15), for: "key4")
        
        // Beyond cost, the first item, key1 should be removed from memory
        await cache.set(TestCachedValue(cost: 10), for: "key5")
        
        #expect(await cache.contains("key1") == false)
        
        for i in 2..<6 {
            let key = "key\(i)"
            #expect(await cache.value(for: key) != nil)
        }
    }
    
    @Test("Last recently used")
    func lastRecentlyUsed() async throws {
        await cache.set(TestCachedValue(cost: 10), for: "key1")
        await cache.set(TestCachedValue(cost: 10), for: "key2")
        await cache.set(TestCachedValue(cost: 10), for: "key3")
        await cache.set(TestCachedValue(cost: 10), for: "key4")
        await cache.set(TestCachedValue(cost: 10), for: "key5")
        
        // Making key1 the most recent accessed
        _ = await cache.value(for: "key1")
        
        // Evict key2, not 1
        await cache.set(TestCachedValue(cost: 10), for: "key6")
        #expect(await cache.value(for: "key1") != nil)
        // key2 should be evicted from memory
        #expect(await cache.contains("key2") == false)
        
        for i in 3...6 {
            let key = "key\(i)"
            #expect(await cache.value(for: key) != nil)
        }
    }
    
    @Test("Remove all")
    func removeAll() async {
        await cache.set(TestCachedValue(cost: 1), for: "key1")
        await cache.set(TestCachedValue(cost: 1), for: "key2")
        await cache.set(TestCachedValue(cost: 1), for: "key3")
        await cache.set(TestCachedValue(cost: 1), for: "key4")
        
        #expect(await cache.value(for: "key1") != nil)
        #expect(await cache.value(for: "key2") != nil)
        #expect(await cache.value(for: "key3") != nil)
        #expect(await cache.value(for: "key4") != nil)
        
        await cache.removeAll()
        
        // All items should be evicted from memory (but still on disk)
        #expect(await cache.contains("key1") == false)
        #expect(await cache.contains("key2") == false)
        #expect(await cache.contains("key3") == false)
        #expect(await cache.contains("key4") == false)
    }
    
    @Test("Critical memory warning")
    func criticalMemoryWarning() async throws {
        await cache.set(TestCachedValue(cost: 1), for: "key1")
        await cache.set(TestCachedValue(cost: 1), for: "key2")
        await cache.set(TestCachedValue(cost: 1), for: "key3")
        await cache.set(TestCachedValue(cost: 1), for: "key4")
        
        #expect(await cache.value(for: "key1") != nil)
        #expect(await cache.value(for: "key2") != nil)
        #expect(await cache.value(for: "key3") != nil)
        #expect(await cache.value(for: "key4") != nil)
        
        await cache.handleMemoryWarning(.critical)
        
        // All items should be evicted from memory on critical warning
        #expect(await cache.contains("key1") == false)
        #expect(await cache.contains("key2") == false)
        #expect(await cache.contains("key3") == false)
        #expect(await cache.contains("key4") == false)
    }
    
    @Test("Memory Warning")
    func memoryWarning() async {
        await cache.set(TestCachedValue(cost: 1), for: "key1")
        await cache.set(TestCachedValue(cost: 1), for: "key2")
        await cache.set(TestCachedValue(cost: 1), for: "key3")
        await cache.set(TestCachedValue(cost: 1), for: "key4")
        
        await cache.handleMemoryWarning(.warning)

        await halfShouldBeRemoved()
        
        func halfShouldBeRemoved() async {
            // First half should be evicted from memory
            #expect(await cache.contains("key1") == false)
            #expect(await cache.contains("key2") == false)
            #expect(await cache.value(for: "key3") != nil)
            #expect(await cache.value(for: "key4") != nil)
        }
    }
    
    @Test("Contains Key")
    func containsKeys() async {
        await cache.set(TestCachedValue(cost: 1), for: "key1")
        #expect(await cache.contains("key1"))
        #expect(await !cache.contains("key2"))
    }
    
    @Test("Update existing key with different cost")
    func updateExistingKeyWithDifferentCost() async throws {
        // Test that updating an existing key's cost works correctly
        await cache.set(TestCachedValue(cost: 10), for: "key1")
        
        // Verify initial value
        var value = await cache.value(for: "key1")
        #expect(value?.cost == 10)
        
        // Update with different cost
        await cache.set(TestCachedValue(cost: 25), for: "key1")
        
        // Verify update
        value = await cache.value(for: "key1")
        #expect(value?.cost == 25)
        
        // Test eviction behavior with updated costs
        await cache.set(TestCachedValue(cost: 20), for: "key2")
        await cache.set(TestCachedValue(cost: 20), for: "key3")
        await cache.set(TestCachedValue(cost: 20), for: "key4")
        
        // Total is now 85, still under limit of 100
        #expect(await cache.value(for: "key1") != nil)
        #expect(await cache.value(for: "key2") != nil)
        #expect(await cache.value(for: "key3") != nil)
        #expect(await cache.value(for: "key4") != nil)
        
        // Add one more to trigger eviction
        await cache.set(TestCachedValue(cost: 20), for: "key5")
        
        // Should have evicted key1 from memory (oldest untouched)
        #expect(await cache.contains("key1") == false)
        #expect(await cache.value(for: "key5") != nil)
    }
    
    @Test("Zero cost items")
    func zeroCostItems() async {
        // Fill cache with zero-cost items
        for i in 0..<10 {
            await cache.set(TestCachedValue(cost: 0), for: "key\(i)")
        }
        
        // Should respect max count limit (5) even with zero cost - first 5 evicted from memory
        for i in 0..<5 {
            #expect(await cache.contains("key\(i)") == false)
        }
        
        for i in 5..<10 {
            #expect(await cache.value(for: "key\(i)") != nil)
        }
        
        // Add item with actual cost
        await cache.set(TestCachedValue(cost: 50), for: "costlyKey")
        
        // Should still have the costly item and 4 zero-cost items
        #expect(await cache.value(for: "costlyKey") != nil)
        #expect(await cache.contains("key5") == false) // Evicted from memory due to max count
    }
    
    @Test("Concurrent access")
    func concurrentAccess() async throws {
        // Test concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    await cache.set(TestCachedValue(cost: 1), for: "key\(i)")
                }
            }
            
            // Readers
            for i in 0..<50 {
                group.addTask {
                    _ = await self.cache.value(for: "key\(i)")
                }
            }
            
            // Contains checks
            for i in 0..<50 {
                group.addTask {
                    _ = await self.cache.contains("key\(i)")
                }
            }
        }
        
        // Verify cache state after concurrent access
        var foundCount = 0
        for i in 0..<50 {
            if await cache.contains("key\(i)") {
                foundCount += 1
            }
        }
        
        // Should have at most maxCount items in memory
        #expect(foundCount <= 5)
    }
    
}
