//
//  MemoryPressure.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 10/17/24.
//

import Foundation

public typealias OnMemoryWarningHandler = (@Sendable (MemoryWarning) -> Void)

// MARK: - MemoryPressureNotifying Protocol

/// Protocol for notifying about memory pressure events
protocol MemoryPressureNotifying: AnyObject {
    func setEventHandler(_ handler: @escaping OnMemoryWarningHandler)
}

// MARK: - MemoryPressure Class

/// Class responsible for monitoring memory pressure events
final class MemoryPressure: MemoryPressureNotifying {
    // MARK: - Properties
    
    /// Dispatch source to monitor memory pressure events
    private let memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global())

    /// Closure to handle memory warning events
    private var _onMemoryWarning: (@Sendable (MemoryWarning) -> Void)?
    
    // MARK: - Initializer
    
    init() {
        initMemoryPressureSource()
    }
    
    func setEventHandler(_ handler: @escaping OnMemoryWarningHandler) {
        assert(_onMemoryWarning == nil, "Already assigned")
        _onMemoryWarning = handler
    }
    
    // MARK: - Private Methods
    
    /// Initializes the memory pressure source and sets up the event handler
    private func initMemoryPressureSource() {
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self else { return }
            guard let memoryWarning = MemoryWarning(
                memoryPressureEvent: memoryPressureSource.data
            ) else { return }
            
            _onMemoryWarning?(memoryWarning)
        }
        memoryPressureSource.resume()
    }
}
