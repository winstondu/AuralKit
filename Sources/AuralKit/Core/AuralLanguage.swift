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
            // Use Locale.Components as shown in Apple's sample code
            return Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
        case .spanish:
            // Use Locale.Components for Spanish
            return Locale(components: .init(languageCode: .spanish, script: nil, languageRegion: .spain))
        case .french:
            // Use Locale.Components for French
            return Locale(components: .init(languageCode: .french, script: nil, languageRegion: .france))
        case .german:
            // Use Locale.Components for German
            return Locale(components: .init(languageCode: .german, script: nil, languageRegion: .germany))
        case .chinese:
            // Use Locale.Components for Chinese
            return Locale(components: .init(languageCode: .chinese, script: nil, languageRegion: .chinaMainland))
        case .custom(let locale):
            return locale
        }
    }
}