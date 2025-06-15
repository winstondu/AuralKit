import Foundation

/// Errors that can occur during AuralKit speech recognition operations.
///
/// AuralError provides comprehensive error handling for all aspects of the
/// speech recognition pipeline, from permissions to model availability and
/// network connectivity.
///
/// ## Error Categories
/// - **Permission errors**: User has not granted microphone access
/// - **Model errors**: Speech recognition models are not available or failed to download
/// - **Recognition errors**: Speech processing has failed
/// - **Audio errors**: Audio system setup or processing has failed
/// - **Network errors**: Network connectivity issues during model download
/// - **Language errors**: Requested language is not supported
///
/// ## Example
/// ```swift
/// do {
///     let text = try await AuralKit.startTranscribing()
/// } catch let error as AuralError {
///     switch error {
///     case .permissionDenied:
///         // Show permission request UI
///     case .modelNotAvailable:
///         // Handle model download
///     default:
///         // Handle other errors
///     }
/// }
/// ```
public enum AuralError: Error, LocalizedError {
    /// Microphone permission has been denied by the user
    case permissionDenied
    
    /// Speech recognition model is not available for the requested language
    case modelNotAvailable
    
    /// Speech recognition processing has failed
    case recognitionFailed
    
    /// Audio system setup or processing has failed
    case audioSetupFailed
    
    /// Network error occurred during model download
    case networkError
    
    /// The requested language is not supported
    case unsupportedLanguage
    
    /// A localized message describing what error occurred.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .modelNotAvailable:
            return "Speech model not available for this language"
        case .recognitionFailed:
            return "Speech recognition failed"
        case .audioSetupFailed:
            return "Audio setup failed"
        case .networkError:
            return "Network error during model download"
        case .unsupportedLanguage:
            return "Language not supported"
        }
    }
}