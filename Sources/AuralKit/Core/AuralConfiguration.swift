import Foundation

/// Simple configuration for speech recognition
public struct AuralConfiguration: Sendable {
    /// Target locale for speech recognition
    public let locale: Locale
    
    /// Whether to include partial (volatile) results
    public let includePartialResults: Bool
    
    /// Whether to include timestamp information in results
    public let includeTimestamps: Bool
    
    /// Creates a new configuration
    public init(
        locale: Locale = .current,
        includePartialResults: Bool = true,
        includeTimestamps: Bool = false
    ) {
        self.locale = locale
        self.includePartialResults = includePartialResults
        self.includeTimestamps = includeTimestamps
    }
}