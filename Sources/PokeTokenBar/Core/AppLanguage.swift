import Foundation

/// The app's display language.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja, es, fr, pt, de, ru
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語"; case .es: return "Español"; case .fr: return "Français"; case .pt: return "Português"; case .de: return "Deutsch"; case .ru: return "Русский" }
    }

    var displayLocale: Locale { Locale(identifier: rawValue) }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추(글로벌 출시: 한국어 강제 금지).
    /// ko/ja/es/fr/pt/de/ru 만 매칭, 그 외 전부 영어(fallback-of-fallback). 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        systemDefault(for: Locale.preferredLanguages.first)
    }

    /// 시스템 언어 매핑의 순수 판정 — 실제 환경을 바꾸지 않고 locale 분기를 검증할 수 있게 분리한다.
    static func systemDefault(for preferredLanguage: String?) -> AppLanguage {
        switch preferredLanguage?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        case "es": return .es
        case "fr": return .fr
        case "pt": return .pt
        case "de": return .de
        case "ru": return .ru
        default:   return .en
        }
    }
}
