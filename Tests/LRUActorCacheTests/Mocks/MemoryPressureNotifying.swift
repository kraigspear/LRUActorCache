//
//  MemoryPressureNotifying.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 10/18/24.
//

@testable import LRUActorCache

/// Mock implementation for memory pressure events, for testing purposes
final class MockMemoryPressure: MemoryPressureNotifying, @unchecked Sendable {
    
    // MARK: - Properties

    /// Closure to handle memory warning events
    private var _onMemoryWarning: (@Sendable (MemoryWarning) -> Void)?
    
    public func setEventHandler(_ handler: @escaping LRUActorCache.OnMemoryWarningHandler) {
        _onMemoryWarning = handler
    }

    // MARK: - Initializer
    public init() {}
    
    // MARK: - Methods

    /// Method to simulate a memory warning event
    /// - Parameter event: The memory pressure event to simulate
    public func simulateMemoryWarning(event: MemoryWarning) {
        _onMemoryWarning?(event)
    }
}
