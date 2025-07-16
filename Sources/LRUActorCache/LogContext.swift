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

    /// Returns a signposter for performance measurement.
    ///
    /// Use signposts to measure performance-critical operations without
    /// impacting production performance. Signposts are only active when
    /// profiling with Instruments.
    func signposter() -> os.OSSignposter {
        os.OSSignposter(logger: logger())
    }
}
