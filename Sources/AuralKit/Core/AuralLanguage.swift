import Foundation

/// Represents supported languages for speech recognition in AuralKit.
///
/// AuralLanguage provides a convenient way to specify the target language
/// for speech-to-text transcription. It includes common languages with
/// predefined locales and a custom option for specific locale requirements.
///
/// ## Example
/// ```swift
/// let auralKit = AuralKit()
///     .language(.spanish)
///     .startTranscribing()
/// ```
public enum AuralLanguage: Sendable, Hashable {
    /// English (current locale or United States) 
    case english
    
    /// Spanish (Spain) locale  
    case spanish
    
    /// French (France) locale
    case french
    
    /// German (Germany) locale
    case german
    
    /// Chinese (China) locale
    case chinese
    
    /// Custom locale for specific language requirements
    /// - Parameter locale: The specific locale to use for transcription
    case custom(Locale)
    
    /// The underlying locale for the language choice.
    ///
    /// This property provides the appropriate `Locale` instance for the
    /// selected language, which is used internally by the speech recognition
    /// system to configure language-specific models and processing.
    var locale: Locale {
        switch self {
        case .english:
            // Use BCP-47 format for Speech framework compatibility
            return Locale(identifier: "en-US")
        case .spanish:
            // Use BCP-47 format for Speech framework compatibility
            return Locale(identifier: "es-ES")
        case .french:
            // Use BCP-47 format for Speech framework compatibility
            return Locale(identifier: "fr-FR")
        case .german:
            // Use BCP-47 format for Speech framework compatibility
            return Locale(identifier: "de-DE")
        case .chinese:
            // Use BCP-47 format for Speech framework compatibility
            return Locale(identifier: "zh-CN")
        case .custom(let locale):
            return locale
        }
    }
}