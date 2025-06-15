import Foundation

/// Represents the result of a speech recognition operation.
///
/// AuralResult contains the transcribed text along with metadata about
/// the recognition quality, timing, and whether the result is partial
/// (volatile) or final.
///
/// ## Result Types
/// - **Partial results**: Early, less accurate transcriptions delivered quickly for responsive UI
/// - **Final results**: Complete, accurate transcriptions that won't change
///
/// ## Metadata
/// - **Confidence**: A value between 0.0 and 1.0 indicating recognition confidence
/// - **Timestamp**: When the spoken audio occurred in the input stream
///
/// ## Example
/// ```swift
/// AuralKit.startLiveTranscription { result in
///     if result.isPartial {
///         // Show provisional text with lighter styling
///         provisionalLabel.text = result.text
///         provisionalLabel.alpha = 0.6
///     } else {
///         // Show final text with full styling
///         finalLabel.text = result.text
///         finalLabel.alpha = 1.0
///     }
/// }
/// ```
public struct AuralResult: Sendable {
    /// The transcribed text content
    public let text: String
    
    /// Confidence score from 0.0 (low) to 1.0 (high)
    public let confidence: Double
    
    /// Whether this is a partial (volatile) or final result
    public let isPartial: Bool
    
    /// Timestamp indicating when this audio occurred
    public let timestamp: TimeInterval
    
    /// Creates a new AuralResult.
    ///
    /// - Parameters:
    ///   - text: The transcribed text content
    ///   - confidence: Recognition confidence from 0.0 to 1.0 (default: 1.0)
    ///   - isPartial: Whether this is a partial result (default: false)
    ///   - timestamp: Audio timestamp (default: 0)
    public init(text: String, confidence: Double = 1.0, isPartial: Bool = false, timestamp: TimeInterval = 0) {
        self.text = text
        self.confidence = confidence
        self.isPartial = isPartial
        self.timestamp = timestamp
    }
}