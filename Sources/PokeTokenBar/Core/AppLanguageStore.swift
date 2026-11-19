import Foundation
import Observation

/// The app's display language, saved in UserDefaults (`appLanguage`).
///
/// It used to live in the Pokémon companion's save (`companion-state.json`, field `language`). The
/// first launch without a saved value reads that one field so the user's choice carries over, and
/// leaves the file as it is. A new install starts from the system language.
@MainActor
@Observable
final class AppLanguageStore {
    static let defaultsKey = "appLanguage"

    private(set) var language: AppLanguage
    /// The whole app's UI strings; views re-render when the language changes.
    var l: L { L(language) }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard,
         legacyStateURL: URL = AppStatePaths.directory().appendingPathComponent("companion-state.json"),
         systemDefault: AppLanguage = .systemDefault) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.defaultsKey), let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = Self.legacyLanguage(at: legacyStateURL) ?? systemDefault
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
    }

    /// The language the Pokémon companion's save held, if any. Only that field is read.
    nonisolated static func legacyLanguage(at url: URL) -> AppLanguage? {
        struct Legacy: Decodable { let language: String? }
        guard let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        return legacy.language.flatMap(AppLanguage.init(rawValue:))
    }
}
