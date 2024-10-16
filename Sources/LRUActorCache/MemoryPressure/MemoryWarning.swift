//
//  MemoryWarning.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 10/18/24.
//

import Foundation

/// Represents the different levels of memory pressure warnings
public enum MemoryWarning: Sendable, CustomStringConvertible {
    case warning
    case critical

    /// Initializes a `MemoryWarning` from a `DispatchSource.MemoryPressureEvent`
    /// - Parameter memoryPressureEvent: The memory pressure event to initialize from
    public init?(memoryPressureEvent: DispatchSource.MemoryPressureEvent) {
        switch memoryPressureEvent {
        case .warning: self = .warning
        case .critical: self = .critical
        default: return nil
        }
    }
    
    public var description: String {
        switch self {
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}
