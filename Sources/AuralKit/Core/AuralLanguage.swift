import Foundation

/// Supported languages for speech recognition
public enum AuralLanguage: String, CaseIterable, Sendable {
    // Major Languages
    case english = "en-US"
    case englishUK = "en-GB"
    case englishAustralia = "en-AU"
    case englishCanada = "en-CA"
    case englishIndia = "en-IN"
    
    case spanish = "es-ES"
    case spanishMexico = "es-MX"
    case spanishUS = "es-US"
    
    case french = "fr-FR"
    case frenchCanada = "fr-CA"
    
    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case portuguesePT = "pt-PT"
    
    case chinese = "zh-CN"
    case chineseTraditional = "zh-TW"
    case chineseHongKong = "zh-HK"
    
    case japanese = "ja-JP"
    case korean = "ko-KR"
    
    // More Languages
    case arabic = "ar-SA"
    case dutch = "nl-NL"
    case hindi = "hi-IN"
    case russian = "ru-RU"
    case swedish = "sv-SE"
    case turkish = "tr-TR"
    case polish = "pl-PL"
    case indonesian = "id-ID"
    case norwegian = "no-NO"
    case danish = "da-DK"
    case finnish = "fi-FI"
    case hebrew = "he-IL"
    case thai = "th-TH"
    case greek = "el-GR"
    case czech = "cs-CZ"
    case romanian = "ro-RO"
    case hungarian = "hu-HU"
    case catalan = "ca-ES"
    case croatian = "hr-HR"
    case malay = "ms-MY"
    case slovak = "sk-SK"
    case ukrainian = "uk-UA"
    case vietnamese = "vi-VN"
    
    /// The locale for this language
    public var locale: Locale {
        Locale(identifier: rawValue)
    }
    
    /// User-friendly name for the language
    public var displayName: String {
        locale.localizedString(forIdentifier: rawValue) ?? rawValue
    }
}