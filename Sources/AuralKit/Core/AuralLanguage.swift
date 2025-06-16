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
public enum AuralLanguage: Sendable {
    /// English (United States) locale
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
            return Locale(identifier: "en-US")
        case .spanish:
            return Locale(identifier: "es-ES")
        case .french:
            return Locale(identifier: "fr-FR")
        case .german:
            return Locale(identifier: "de-DE")
        case .chinese:
            return Locale(identifier: "zh-CN")
        case .custom(let locale):
            return locale
        }
    }
}