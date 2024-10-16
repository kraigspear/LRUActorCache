import Testing

@testable import LRUActorCache

// A simple CachedValue implementation for testing
private struct TestCachedValue: CachedValue, Equatable {
    let cost: Int
}

struct CacheTest {
    
    private let cache: MemoryCache<String, TestCachedValue>
    
    init() {
        cache = MemoryCache<String, TestCachedValue>(
            totalCostLimit: 100,
            maxCount: 5
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
        
        for i in 0..<5 {
            #expect(await cache.value(for: "testKey\(i)") == nil)
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
        
        // Beyond cost, the first item, key1 should be removed
        await cache.set(TestCachedValue(cost: 10), for: "key5")
        
        #expect(await cache.value(for: "key1") == nil)
        
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
        #expect(await cache.value(for: "key2") == nil)
        
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
        
        #expect(await cache.value(for: "key1") == nil)
        #expect(await cache.value(for: "key2") == nil)
        #expect(await cache.value(for: "key3") == nil)
        #expect(await cache.value(for: "key4") == nil)
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
        
        #expect(await cache.value(for: "key1") == nil)
        #expect(await cache.value(for: "key2") == nil)
        #expect(await cache.value(for: "key3") == nil)
        #expect(await cache.value(for: "key4") == nil)
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
            #expect(await cache.value(for: "key1") == nil)
            #expect(await cache.value(for: "key2") == nil)
            #expect(await cache.value(for: "key3") != nil)
            #expect(await cache.value(for: "key4") != nil)
        }
    }
    
}
