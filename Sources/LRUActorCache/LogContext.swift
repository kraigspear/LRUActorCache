//
//  LogContext.swift
//  LRUActorCache
//
//  Created by Kraig Spear on 10/9/24.
//

import os

enum LogContext: String {
    case cache = "💾cache"
    case memoryPressure = "⚠️memoryPressure"
    func logger() -> os.Logger {
        os.Logger(subsystem: "com.spareware.LRUActorCache", category: rawValue)
    }
}
