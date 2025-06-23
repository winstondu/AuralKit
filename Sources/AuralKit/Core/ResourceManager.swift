import Foundation
import OSLog

/// Manages temporary resources created during audio processing
/// Ensures proper cleanup of files and resources on all code paths
internal actor ResourceManager {
    private static let logger = Logger(subsystem: "com.auralkit", category: "ResourceManager")
    
    /// Tracks temporary files created during processing
    private var temporaryFiles: Set<URL> = []
    
    /// Tracks active resource handles for cleanup
    private var activeResources: [String: Any] = [:]
    
    /// Cleanup queue for deferred operations
    private var cleanupQueue: [@Sendable () async -> Void] = []
    
    /// Register a temporary file for automatic cleanup
    func registerTemporaryFile(_ url: URL) {
        Self.logger.debug("Registering temporary file: \(url.path)")
        temporaryFiles.insert(url)
    }
    
    /// Register a resource for cleanup
    func registerResource<T: Sendable>(_ resource: T, identifier: String, cleanup: @escaping @Sendable (T) async -> Void) {
        Self.logger.debug("Registering resource: \(identifier)")
        activeResources[identifier] = resource
        let cleanupTask: @Sendable () async -> Void = { [weak self] in
            guard let self = self else { return }
            await self.performResourceCleanup(identifier: identifier, cleanup: cleanup)
        }
        cleanupQueue.append(cleanupTask)
    }
    
    /// Perform cleanup for a specific resource
    private func performResourceCleanup<T: Sendable>(identifier: String, cleanup: @Sendable (T) async -> Void) async {
        if let res = activeResources[identifier] as? T {
            await cleanup(res)
            activeResources.removeValue(forKey: identifier)
        }
    }
    
    /// Create a temporary file URL with automatic cleanup registration
    func createTemporaryFileURL(extension fileExtension: String = "wav") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(component: "AuralKit-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        
        registerTemporaryFile(url)
        return url
    }
    
    /// Clean up a specific temporary file
    func cleanupTemporaryFile(_ url: URL) async {
        guard temporaryFiles.contains(url) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                Self.logger.debug("Cleaned up temporary file: \(url.path)")
            }
            temporaryFiles.remove(url)
        } catch {
            Self.logger.error("Failed to cleanup temporary file \(url.path): \(error)")
        }
    }
    
    /// Clean up all registered resources
    func cleanupAll() async {
        let fileCount = temporaryFiles.count
        let resourceCount = cleanupQueue.count
        Self.logger.debug("Starting cleanup of \(fileCount) files and \(resourceCount) resources")
        
        // Clean up all temporary files
        for url in temporaryFiles {
            await cleanupTemporaryFile(url)
        }
        
        // Execute all cleanup operations
        for cleanup in cleanupQueue {
            await cleanup()
        }
        
        cleanupQueue.removeAll()
        activeResources.removeAll()
        
        Self.logger.debug("Cleanup completed")
    }
    
    /// Execute a block with automatic resource cleanup
    func withCleanup<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            let result = try await operation()
            await cleanupAll()
            return result
        } catch {
            // Ensure cleanup happens even on error
            await cleanupAll()
            throw error
        }
    }
    
    deinit {
        // Last resort cleanup - should ideally never have resources here
        // Note: We can't access actor-isolated properties in deinit
        // Cleanup should have been done through performCleanup()
        Self.logger.debug("ResourceManager deallocated")
    }
}

/// Wrapper to preserve original error information
internal struct DetailedError: Error, CustomStringConvertible {
    let originalError: Error
    let context: String
    let file: String
    let line: Int
    
    init(_ error: Error, context: String, file: String = #file, line: Int = #line) {
        self.originalError = error
        self.context = context
        self.file = URL(fileURLWithPath: file).lastPathComponent
        self.line = line
    }
    
    var description: String {
        "[\(file):\(line)] \(context): \(originalError)"
    }
    
    /// Convert to AuralError while preserving original error information
    func toAuralError() -> AuralError {
        // Check if it's already an AuralError
        if let auralError = originalError as? AuralError {
            return auralError
        }
        
        // Map common errors to specific AuralError cases
        switch originalError {
        case is CancellationError:
            return .recognitionFailed
        case let nsError as NSError:
            switch nsError.domain {
            case "com.apple.speech.recognition":
                return .recognitionFailed
            case NSURLErrorDomain:
                return .networkError
            default:
                return .recognitionFailed
            }
        default:
            return .recognitionFailed
        }
    }
}