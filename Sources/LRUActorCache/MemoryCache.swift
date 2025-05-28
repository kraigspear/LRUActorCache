
import Foundation
import os

private let logger = LogContext.cache.logger()
private let signposter = OSSignposter(logger: logger)

// MARK: - Protocols

/// A protocol representing a value that can be cached, with an associated cost.
///
/// Conforming types must provide a `cost` property, which represents the
/// relative cost of storing the value in the cache.
public protocol CachedValue {
    /// The cost of storing this value in the cache.
    var cost: Int { get }
}

// MARK: - Container Class

/// A private class used to wrap cached values in a doubly-linked list.
private final class Container<Key: Hashable, Value: CachedValue> {
    var value: Value
    var next: Container<Key, Value>?
    var previous: Container<Key, Value>?
    let key: Key
    
    init(key: Key, value: Value) {
        self.key = key
        self.value = value
    }
    
    var cost: Int {
        value.cost
    }
}

// MARK: - MemoryCache Actor

/// An actor that manages a memory cache with a maximum item count and total cost limit.
///
/// `MemoryCache` provides thread-safe access to cached values, automatically
/// removing the least recently used items when limits are exceeded.
public actor MemoryCache<Key: Hashable & CustomStringConvertible, Value: CachedValue> {
    // MARK: - Properties
    
    private var values: [Key: Container<Key, Value>] = [:]
    private let maxCount: Int
    private var count: Int { values.count }
    private var isEmpty: Bool { values.isEmpty }
    
    private var head: Container<Key, Value>?
    private var tail: Container<Key, Value>?
    
    private var totalCost = 0
    private let totalCostLimit: Int
    
    // MARK: - Initialization
    
    /// Initializes a new memory cache with the specified limits.
    ///
    /// - Parameters:
    ///   - memoryPressureNotifier: Provides notifications of memory events
    ///   - totalCostLimit: The maximum total cost of all items in the cache.
    ///   - maxCount: The maximum number of items the cache can hold.
    public init(
        totalCostLimit: Int,
        maxCount: Int = 500
    ) {
        self.totalCostLimit = totalCostLimit
        self.maxCount = maxCount
        
        Task {
            await listenForMemoryEvents()
        }
    }
    
    public init(
        totalCostInMegaBytes: Int,
        maxCount: Int = 500
    ) {
        let bytesInMegaByte = 1024 * 1024
        self.init(
            totalCostLimit: bytesInMegaByte * totalCostInMegaBytes,
            maxCount: maxCount
        )
    }
    
    deinit {
        memoryPressureSource.cancel()
    }
    
    // MARK: - Public Cache Access
    
    /// Retrieves a value from the cache for the given key.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: The cached value if found, or `nil` if not present.
    public func value(for key: Key) -> Value? {
        logger.trace("value: \(key)")
        guard let container = values[key] else {
            logger.trace("value: not found")
            return nil
        }
        logger.trace("Value found update list order")
        updateListOrder(container)
        return container.value
    }
    
    /// Checks if a value exists in the cache without affecting its LRU position.
    ///
    /// Unlike `value(for:)`, this method won't promote the item to the front of the LRU list,
    /// making it useful for cache inspection without side effects.
    ///
    /// - Parameter key: The key to look up in the cache.
    /// - Returns: `true` if the key exists in the cache, `false` otherwise.
    public func contains(_ key: Key) -> Bool {
        values[key] != nil
    }
    
    /// Sets a value in the cache for the given key.
    ///
    /// If the key already exists, the value is updated. If adding the new value
    /// would exceed the cache limits, the least recently used items are removed.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key under which to store the value.
    public func set(_ value: Value, for key: Key) {
        let intervalName: StaticString = "Set value"
        let signpostID = signposter.makeSignpostID()
        let interval = signposter.beginInterval(intervalName, id: signpostID)
        
        defer {
            signposter.endInterval(intervalName, interval)
        }
        
        if let existingContainer = values[key] {
            totalCost -= existingContainer.cost
            existingContainer.value = value
            updateListOrder(existingContainer)
        } else {
            let newContainer = Container(key: key, value: value)
            values[key] = newContainer
            addToList(newContainer)
        }
        self.totalCost += value.cost
        let totalCost = self.totalCost
        let count = self.count
        logger.debug("set cost: \(totalCost) values: \(count)")
        removeExpiredIfNeeded()
    }
    
    /// Removes and returns the value associated with the given key.
    ///
    /// - Parameter key: The key of the value to remove.
    /// - Returns: The removed value, or `nil` if the key was not found.
    @discardableResult
    private func remove(forKey key: Key) -> Value? {
        logger.debug("remove key: \(key)")
        guard let container = values.removeValue(forKey: key) else {
            logger.error("Attempted to remove item that doesn't exist: \(key)")
            assertionFailure("Attempted to remove item that doesn't exist: \(key)")
            return nil
        }
        removeFromList(container)
        totalCost -= container.cost
        return container.value
    }
    
    // MARK: - Private List Management
    
    /// Adds a container to the front of the linked list.
    ///
    /// This method is used to promote the container as the most recently used item.
    ///
    /// - Parameter container: The container to be added to the front of the list.
    private func addToList(_ container: Container<Key, Value>) {
        container.next = head
        container.previous = nil
        head?.previous = container
        head = container
        if tail == nil {
            tail = container
        }
    }
    
    /// Removes a container from the linked list.
    ///
    /// This method is used to remove a container from its current position within the list,
    /// often as part of an eviction process or reordering.
    ///
    /// - Parameter container: The container to be removed.
    private func removeFromList(_ container: Container<Key, Value>) {
        logger.trace("removeFromList")
        
        container.previous?.next = container.next
        container.next?.previous = container.previous
        
        if container === head {
            head = container.next
        }
        if container === tail {
            tail = container.previous
        }
        
        container.previous = nil
        container.next = nil
    }
    
    /// Promotes the container to the front of the linked list, marking it as the most recently used.
    ///
    /// This method is called whenever an item is accessed to ensure that it remains in the cache
    /// and adheres to the LRU caching policy.
    ///
    /// - Parameter container: The container to be promoted.
    private func updateListOrder(_ container: Container<Key, Value>) {
        logger.trace("updateListOrder")
        guard container !== head else { return }
        removeFromList(container)
        addToList(container)
    }
    
    // MARK: - Memory Notifications

    private let memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global())
    
    func handleMemoryWarning(_ event: MemoryWarning) {
        logger.trace("handleMemoryWarning: \(event)")
        switch event {
        case .critical:
            removeAll()
        case .warning:
            removePercentageOfItems(0.5)
        }
    }
    
    private func listenForMemoryEvents() {
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self else { return }
            
            Task { [self] in
                await self.handleMemoryPressureEvent()
            }
        }
        memoryPressureSource.resume()
    }
    
    private func handleMemoryPressureEvent() {
        guard let memoryWarning = MemoryWarning(
            memoryPressureEvent: memoryPressureSource.data
        ) else { return }
        handleMemoryWarning(memoryWarning)
    }
    
    // MARK: - Cache Maintenance
    
    private func removeExpiredIfNeeded() {
        while totalCost > totalCostLimit || count > maxCount, let oldestContainer = tail {
            let removedItem = remove(forKey: oldestContainer.key)
            if removedItem == nil {
                logger.fault("Failed to remove expired item: \(oldestContainer.key)")
                // We crash because if this did happen we could end up with a run away memory issue.
                // It's a serious logic flaw that would need to be fixed.
                // We can't attempt to band aid and hope for the best.
                preconditionFailure("Failed to remove expired item: \(oldestContainer.key)")
            }
            logger.debug("Removed expired item: \(oldestContainer.key)")
        }
    }
    
    /// Removes a specified percentage of items from the cache.
    ///
    /// This method is used to clear a fraction of the items in the cache, which is particularly useful
    /// for responding to memory pressure or proactively reducing cache size.
    ///
    /// - Parameter percentage: A value between `0` and `1` representing the fraction of items to remove.
    ///   - A value of `0` means no items are removed, while `1` means all items are removed.
    ///
    /// - Warning: Passing a value outside the range `[0, 1]` will trigger an assertion failure.
    private func removePercentageOfItems(_ percentage: Double) {
        guard percentage >= 0, percentage <= 1 else {
            assertionFailure("Invalid percentage: \(percentage)")
            return
        }
        let numberOfItemsToRemove = Int(Double(count) * percentage)
        logger.debug("removePercentageOfItems: \(percentage) \(numberOfItemsToRemove)")
        guard count > numberOfItemsToRemove else {
            logger.debug("Nothing to remove")
            return
        }
        for i in 0 ..< numberOfItemsToRemove {
            if let container = tail {
                remove(forKey: container.key)
                logger.trace("Removed \(i + 1)th item")
            } else {
                assertionFailure("We should have found an item to remove")
                break
            }
        }
    }
    
    /// Removes all items from the cache.
    ///
    /// This method clears all cached items, effectively resetting the cache.
    /// This can be useful for handling scenarios where memory needs to be fully reclaimed,
    /// or the cache contents are no longer valid.
    public func removeAll() {
        logger.debug("removeAll")
        values.removeAll()
        head = nil
        tail = nil
        totalCost = 0
        logger.debug("Removed all items")
    }
}
