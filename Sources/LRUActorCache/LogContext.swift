import os

enum LogContext: String {
    case cache = "🐏cache"
    case diskCache = "💾diskCache"
    case memoryPressure = "⚠️memoryPressure"
    #if DEBUG
    case mockMemoryPressure = "🧪⚠️mockMemoryPressure"
    #endif
    func logger() -> os.Logger {
        os.Logger(subsystem: "com.spareware.LRUActorCache", category: rawValue)
    }
}
