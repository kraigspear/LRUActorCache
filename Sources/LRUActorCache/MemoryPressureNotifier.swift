import Foundation

private let logger = LogContext.memoryPressure.logger()

/// MemoryPressureNotifier is a class that monitors memory pressure events from the system and notifies the caller via an `AsyncStream`.
///
/// This class can be used to observe memory pressure warnings and critical events and take appropriate actions to reduce memory usage.
///
/// # Usage Example:
/// ```swift
/// let memoryNotifier = MemoryPressureNotifier.shared
///
/// Task {
///     guard let stream = memoryNotifier.memoryPressureStream else { return }
///     for await event in stream {
///         switch event {
///         case .warning:
///             print("Memory pressure warning received. Consider freeing up resources.")
///         case .critical:
///             print("Memory pressure critical received. Immediate action required to free memory.")
///         default:
///             break
///         }
///     }
/// }
/// ```

/// A notifier for monitoring system memory pressure events.
public final class MemoryPressureNotifier {
    // MARK: - Properties
    
    private lazy var memoryPressureSource: DispatchSourceMemoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global())
    
    /// An async stream that emits memory pressure events such as `.warning` or `.critical`.
    public lazy var memoryPressureStream: AsyncStream<DispatchSource.MemoryPressureEvent> = AsyncStream { continuation in
        memoryPressureSource.setEventHandler { [weak self] in
            guard let self else { return }
            let memoryPressureStatus = self.memoryPressureSource.data
                    
            switch memoryPressureStatus {
            case let status where status.contains(.warning):
                continuation.yield(.warning)
            case let status where status.contains(.critical):
                continuation.yield(.critical)
            default:
                break
            }
        }
                
        memoryPressureSource.setCancelHandler {
            logger.log("Memory pressure source canceled.")
            continuation.finish()
        }
                
        memoryPressureSource.resume()
    }
    
    // MARK: - Initializer
    
    /// Initializes a new instance of `MemoryPressureNotifier` and sets up the memory pressure handler.
    public init() {}
    
    // MARK: - Deinitialization
    
    deinit {
        memoryPressureSource.cancel()
    }
}
