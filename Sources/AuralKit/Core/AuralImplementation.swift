import Foundation

/// Specifies which speech recognition implementation to use.
///
/// AuralImplementation allows you to choose between different speech recognition
/// backends based on your specific needs. By default, AuralKit automatically
/// selects the best available implementation for your OS version.
///
/// ## Implementation Types
/// - **automatic**: Let AuralKit choose the best implementation (recommended)
/// - **modern**: Use the new SpeechAnalyzer API (requires iOS 26+/macOS 26+)
/// - **legacy**: Use the classic SFSpeechRecognizer API (iOS 17+/macOS 14+)
///
/// ## Example
/// ```swift
/// // Use automatic selection (default)
/// let auralKit = AuralKit()
///
/// // Force modern implementation
/// let auralKit = AuralKit(implementation: .modern)
///
/// // Force legacy implementation
/// let auralKit = AuralKit(implementation: .legacy)
/// ```
///
/// ## When to Use Each Implementation
///
/// ### Automatic (Default)
/// - Best for most use cases
/// - Ensures compatibility across OS versions
/// - Automatically uses the best available features
///
/// ### Modern Implementation
/// - Better streaming architecture
/// - Improved locale handling
/// - Direct model management
/// - Lower latency for real-time transcription
/// - Requires iOS 26+, macOS 26+, or visionOS 26+
///
/// ### Legacy Implementation
/// - Proven stability
/// - Wider OS compatibility
/// - May be preferred for specific edge cases
/// - Works on iOS 17+, macOS 14+
///
/// ## Important Notes
/// - If you force `.modern` on an older OS, initialization will fail
/// - The `.automatic` option is recommended unless you have specific requirements
/// - Both implementations provide the same API surface
public enum AuralImplementation: Sendable {
    /// Automatically select the best implementation based on OS version (recommended)
    case automatic
    
    /// Use the modern SpeechAnalyzer implementation (iOS 26+/macOS 26+)
    case modern
    
    /// Use the legacy SFSpeechRecognizer implementation (iOS 17+/macOS 14+)
    case legacy
    
    /// Check if the implementation is available on the current OS
    public var isAvailable: Bool {
        switch self {
        case .automatic:
            return true
        case .modern:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return true
            } else {
                return false
            }
        case .legacy:
            return true
        }
    }
    
    /// Get the actual implementation that will be used
    internal var resolvedImplementation: AuralImplementation {
        switch self {
        case .automatic:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return .modern
            } else {
                return .legacy
            }
        case .modern, .legacy:
            return self
        }
    }
}