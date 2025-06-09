import Testing
import Foundation

@testable import LRUActorCache

@Suite("DiskCacheTests", .serialized)
struct DiskCacheTests {
    
    // MARK: - Test Properties
    
    private let testData = "Test data content".data(using: .utf8)!
    private let testURL = URL(string: "https://example.com/radar/test/image.png")!
    
    // MARK: - Basic Operations Tests
    
    @Test("Store and retrieve data from disk cache")
    func storeAndRetrieveData() async throws {
        let cache = DiskCache(reset: true)
        // Store data
        await cache.setData(testData, at: testURL)
        
        // Retrieve data
        let retrievedData = await cache.getData(for: testURL)
        #expect(retrievedData == testData)
    }
    
    @Test("Retrieve non-existent data returns nil")
    func retrieveNonExistentData() async {
        let cache = DiskCache(reset: true)
        let nonExistentURL = URL(string: "https://example.com/radar/nonexistent.png")!
        let data = await cache.getData(for: nonExistentURL)
        #expect(data == nil)
    }
    
    @Test("Overwrite existing data")
    func overwriteExistingData() async throws {
        let cache = DiskCache(reset: true)
        // Store initial data
        await cache.setData(testData, at: testURL)
        
        // Verify initial data
        var retrievedData = await cache.getData(for: testURL)
        #expect(retrievedData == testData)
        
        // Overwrite with new data
        let newData = "New test data".data(using: .utf8)!
        await cache.setData(newData, at: testURL)
        
        // Verify updated data
        retrievedData = await cache.getData(for: testURL)
        #expect(retrievedData == newData)
    }
    
    // MARK: - Cache Key Tests
    
    @Test("URLs with radar path generate valid cache keys")
    func urlsWithRadarPath() async {
        let cache = DiskCache(reset: true)
        let urls = [
            URL(string: "https://example.com/radar/weather/map.png")!,
            URL(string: "https://example.com/radar/satellite/view.jpg")!,
            URL(string: "https://api.weather.com/radar/current/overlay.gif")!
        ]
        
        for (index, url) in urls.enumerated() {
            let data = "Test \(index)".data(using: .utf8)!
            await cache.setData(data, at: url)
            
            let retrievedData = await cache.getData(for: url)
            #expect(retrievedData == data)
        }
    }
    
    @Test("Complex radar paths are handled correctly")
    func complexRadarPaths() async {
        let cache = DiskCache(reset: true)
        let complexURL = URL(string: "https://example.com/api/v1/radar/region/north-america/layer/precipitation/tile/123/456.png")!
        let data = "Complex path data".data(using: .utf8)!
        
        // Store and retrieve
        await cache.setData(data, at: complexURL)
        let retrievedData = await cache.getData(for: complexURL)
        #expect(retrievedData == data)
    }
    
    // MARK: - Large Data Tests
    
    @Test("Store and retrieve large data")
    func largeDataHandling() async throws {
        let cache = DiskCache(reset: true)
        // Create 1MB of data
        let largeData = Data(repeating: 0xFF, count: 1024 * 1024)
        let largeDataURL = URL(string: "https://example.com/radar/large-file.bin")!
        
        // Store large data
        await cache.setData(largeData, at: largeDataURL)
        
        // Retrieve and verify
        let retrievedData = await cache.getData(for: largeDataURL)
        #expect(retrievedData == largeData)
    }
    
    // MARK: - Concurrent Access Tests
    
    @Test("Concurrent read and write operations")
    func concurrentAccess() async throws {
        let cache = DiskCache(reset: true)
        await withTaskGroup(of: Void.self) { group in
            // Concurrent writes
            for i in 0..<10 {
                group.addTask {
                    let url = URL(string: "https://example.com/radar/concurrent/image\(i).png")!
                    let data = "Concurrent data \(i)".data(using: .utf8)!
                    await cache.setData(data, at: url)
                }
            }
            
            // Concurrent reads
            for i in 0..<10 {
                group.addTask {
                    let url = URL(string: "https://example.com/radar/concurrent/image\(i).png")!
                    _ = await cache.getData(for: url)
                }
            }
        }
        
        // Verify all data was written correctly
        for i in 0..<10 {
            let url = URL(string: "https://example.com/radar/concurrent/image\(i).png")!
            let expectedData = "Concurrent data \(i)".data(using: .utf8)!
            let retrievedData = await cache.getData(for: url)
            #expect(retrievedData == expectedData)
        }
    }
    
    @Test("Concurrent writes to same URL")
    func concurrentWritesToSameURL() async {
        let cache = DiskCache(reset: true)
        let sharedURL = URL(string: "https://example.com/radar/shared.png")!
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let data = "Concurrent write \(i)".data(using: .utf8)!
                    await cache.setData(data, at: sharedURL)
                }
            }
        }
        
        // Should have some data (last write wins)
        let finalData = await cache.getData(for: sharedURL)
        #expect(finalData != nil)
    }
    
    // MARK: - Special Characters Tests
    
    @Test("URLs with special characters in path")
    func specialCharactersInPath() async {
        let cache = DiskCache(reset: true)
        let specialURLs = [
            URL(string: "https://example.com/radar/region%20name/image.png")!,
            URL(string: "https://example.com/radar/file%20with%20spaces.png")!,
            URL(string: "https://example.com/radar/special-chars_123.png")!,
            URL(string: "https://example.com/radar/unicode-文件.png")!
        ]
        
        for url in specialURLs {
            let data = "Special char data".data(using: .utf8)!
            await cache.setData(data, at: url)
            
            let retrievedData = await cache.getData(for: url)
            #expect(retrievedData == data)
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance with many files")
    func performanceWithManyFiles() async throws {
        let cache = DiskCache(reset: true)
        let startTime = Date()
        
        // Write 100 files
        for i in 0..<100 {
            let url = URL(string: "https://example.com/radar/perf/image\(i).png")!
            let data = "Performance test \(i)".data(using: .utf8)!
            await cache.setData(data, at: url)
        }
        
        // Read all files
        for i in 0..<100 {
            let url = URL(string: "https://example.com/radar/perf/image\(i).png")!
            _ = await cache.getData(for: url)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should complete in reasonable time (< 5 seconds)
        #expect(elapsed < 5.0)
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty data handling")
    func emptyDataHandling() async {
        let cache = DiskCache(reset: true)
        let emptyData = Data()
        let url = URL(string: "https://example.com/radar/empty.dat")!
        
        // Store empty data
        await cache.setData(emptyData, at: url)
        
        // Should retrieve empty data (not nil)
        let retrievedData = await cache.getData(for: url)
        #expect(retrievedData == emptyData)
        #expect(retrievedData?.count == 0)
    }
    
    @Test("URL with query parameters")
    func urlWithQueryParameters() async {
        let cache = DiskCache(reset: true)
        let url = URL(string: "https://example.com/radar/image.png?timestamp=123456&quality=high")!
        let data = "Query param data".data(using: .utf8)!
        
        await cache.setData(data, at: url)
        let retrievedData = await cache.getData(for: url)
        #expect(retrievedData == data)
    }
    
    @Test("URL with fragment")
    func urlWithFragment() async {
        let cache = DiskCache(reset: true)
        let url = URL(string: "https://example.com/radar/image.png#section1")!
        let data = "Fragment data".data(using: .utf8)!
        
        await cache.setData(data, at: url)
        let retrievedData = await cache.getData(for: url)
        #expect(retrievedData == data)
    }
}
