import Foundation

/// Configuration settings for speech recognition operations.
///
/// AuralConfiguration encapsulates all the settings needed to customize
/// the behavior of speech recognition, including language, quality,
/// and result delivery preferences.
///
/// ## Configuration Options
/// - **Language**: Target language for transcription
/// - **Quality**: Processing quality level (low, medium, high)
/// - **Partial Results**: Whether to receive provisional results for responsive UI
/// - **Timestamps**: Whether to include timing information in results
///
/// ## Example
/// ```swift
/// let config = AuralConfiguration(
///     language: .spanish,
///     quality: .high,
///     includePartialResults: true,
///     includeTimestamps: true
/// )
/// 
/// // Or using the fluent API
/// let auralKit = AuralKit()
///     .language(.spanish)
///     .quality(.high)
///     .includePartialResults()
///     .includeTimestamps()
/// ```
public struct AuralConfiguration: Sendable {
    /// Target language for speech recognition
    public let language: AuralLanguage
    
    /// Processing quality level
    public let quality: AuralQuality
    
    /// Whether to include partial (volatile) results for responsive UI
    public let includePartialResults: Bool
    
    /// Whether to include timestamp information in results
    public let includeTimestamps: Bool
    
    /// Creates a new AuralConfiguration with the specified settings.
    ///
    /// - Parameters:
    ///   - language: Target language for recognition (default: .english)
    ///   - quality: Processing quality level (default: .medium)
    ///   - includePartialResults: Whether to receive partial results (default: false)
    ///   - includeTimestamps: Whether to include timestamps (default: false)
    public init(language: AuralLanguage = .english, 
                quality: AuralQuality = .medium,
                includePartialResults: Bool = false,
                includeTimestamps: Bool = false) {
        self.language = language
        self.quality = quality
        self.includePartialResults = includePartialResults
        self.includeTimestamps = includeTimestamps
    }
}