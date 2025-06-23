@preconcurrency import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif
import OSLog

/// Monitors memory pressure and helps manage resources during low memory conditions
internal actor MemoryPressureMonitor {
    private static let logger = Logger(subsystem: "com.auralkit", category: "MemoryPressureMonitor")
    
    /// Callbacks for memory pressure notifications
    private var memoryPressureHandlers: [@Sendable (MemoryPressureLevel) async -> Void] = []
    
    /// Memory pressure monitoring source
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    /// Current memory pressure level
    private var currentPressureLevel: MemoryPressureLevel = .normal
    
    /// Memory pressure levels
    enum MemoryPressureLevel {
        case normal
        case warning
        case urgent
        case critical
    }
    
    init() {
        Task {
            await setupMemoryPressureMonitoring()
        }
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    /// Register a handler for memory pressure changes
    func onMemoryPressure(_ handler: @escaping @Sendable (MemoryPressureLevel) async -> Void) {
        memoryPressureHandlers.append(handler)
    }
    
    /// Set up memory pressure monitoring
    private func setupMemoryPressureMonitoring() {
        // Create dispatch source for memory pressure events
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleMemoryPressureEvent()
            }
        }
        
        source.activate()
        memoryPressureSource = source
        
        Self.logger.info("Memory pressure monitoring activated")
        
        // Also monitor process info notifications on iOS
        #if os(iOS) || os(tvOS)
        Task { @MainActor in
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task {
                    await self?.handleMemoryWarning()
                }
            }
        }
        #endif
    }
    
    /// Handle memory pressure events from dispatch source
    private func handleMemoryPressureEvent() async {
        guard let source = memoryPressureSource else { return }
        
        let data = source.data
        let newLevel: MemoryPressureLevel
        
        if data.contains(.warning) {
            newLevel = .warning
            Self.logger.warning("Memory pressure warning received")
        } else if data.contains(.critical) {
            newLevel = .critical
            Self.logger.critical("Memory pressure critical received")
        } else {
            newLevel = .normal
        }
        
        if newLevel != currentPressureLevel {
            currentPressureLevel = newLevel
            await notifyHandlers(newLevel)
        }
    }
    
    /// Handle iOS memory warning
    private func handleMemoryWarning() async {
        Self.logger.warning("iOS memory warning received")
        
        // iOS memory warning is typically urgent
        if currentPressureLevel != .urgent && currentPressureLevel != .critical {
            currentPressureLevel = .urgent
            await notifyHandlers(.urgent)
        }
    }
    
    /// Notify all registered handlers of memory pressure
    private func notifyHandlers(_ level: MemoryPressureLevel) async {
        await withTaskGroup(of: Void.self) { group in
            for handler in memoryPressureHandlers {
                group.addTask {
                    await handler(level)
                }
            }
        }
    }
    
    /// Get current memory usage information
    func getMemoryInfo() -> (used: Int64, total: Int64)? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return nil }
        
        let used = Int64(info.resident_size)
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        
        return (used: used, total: total)
    }
}

/// Extension to AuralKit to handle memory pressure
internal extension AuralKit {
    /// Handle memory pressure events
    @MainActor
    func handleMemoryPressure(_ level: MemoryPressureMonitor.MemoryPressureLevel) async {
        switch level {
        case .normal:
            Self.logger.info("Memory pressure returned to normal")
            
        case .warning:
            Self.logger.warning("Memory pressure warning - reducing buffer sizes")
            // Could reduce buffer sizes or quality here
            
        case .urgent:
            Self.logger.error("Memory pressure urgent - clearing caches")
            // Clear any caches and reduce resource usage
            await engine.cleanup()
            
        case .critical:
            Self.logger.critical("Memory pressure critical - stopping transcription")
            error = .recognitionFailed
            
            // Must stop transcription to free memory
            if await stateManager.isTranscribing() {
                try? await stopTranscription()
            }
        }
    }
}
