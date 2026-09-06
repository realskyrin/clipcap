import Foundation

// MARK: - Target language

/// Languages the OCR text can be translated into. The source language is
/// detected locally before the provider request, so only the target is configurable.
enum TranslationLanguage: String, CaseIterable {
    case chinese = "zh"
    case english = "en"
    case vietnamese = "vi"
    case hindi = "hi"
    case spanish = "es"
    case french = "fr"
    case arabic = "ar"
    case bengali = "bn"
    case portuguese = "pt"
    case russian = "ru"
    case urdu = "ur"
    case indonesian = "id"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"
    case turkish = "tr"

    static var appDefault: TranslationLanguage {
        switch Defaults.language {
        case .zh: return .chinese
        case .zhTW: return .chinese
        case .en: return .english
        case .vi: return .vietnamese
        case .ja: return .japanese
        case .ko: return .korean
        case .fr: return .french
        case .ru: return .russian
        }
    }

    var displayName: String {
        switch self {
        case .chinese:    return "中文"
        case .english:    return "English"
        case .vietnamese: return "Tiếng Việt"
        case .hindi:      return "हिन्दी"
        case .spanish:    return "Español"
        case .french:     return "Français"
        case .arabic:     return "العربية"
        case .bengali:    return "বাংলা"
        case .portuguese: return "Português"
        case .russian:    return "Русский"
        case .urdu:       return "اردو"
        case .indonesian: return "Indonesia"
        case .german:     return "Deutsch"
        case .japanese:   return "日本語"
        case .korean:     return "한국어"
        case .turkish:    return "Türkçe"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .chinese:    return "zh-Hans"
        case .english:    return "en"
        case .vietnamese: return "vi"
        case .hindi:      return "hi"
        case .spanish:    return "es"
        case .french:     return "fr"
        case .arabic:     return "ar"
        case .bengali:    return "bn"
        case .portuguese: return "pt"
        case .russian:    return "ru"
        case .urdu:       return "ur"
        case .indonesian: return "id"
        case .german:     return "de"
        case .japanese:   return "ja"
        case .korean:     return "ko"
        case .turkish:    return "tr"
        }
    }

    var localizedDisplayName: String {
        let locale = Locale(identifier: Defaults.language.lprojName)
        return locale.localizedString(forIdentifier: localeIdentifier) ?? displayName
    }

}
