import XCTest
@testable import PokeTokenBar

/// The app language moved out of the Pokémon companion's save: the user's choice must carry over.
@MainActor
final class AppLanguageStoreTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "lang-\(UUID().uuidString)")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private var legacy: URL { dir.appendingPathComponent("companion-state.json") }

    func testTheLanguageInTheOldPokemonSaveCarriesOverOnceAndTheFileStays() throws {
        let old = #"{"language":"ko","dex":[],"spentTokens":3}"#
        try Data(old.utf8).write(to: legacy)
        let store = AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .en)
        XCTAssertEqual(store.language, .ko, "the saved choice, not the system language")
        XCTAssertEqual(defaults.string(forKey: AppLanguageStore.defaultsKey), "ko", "saved on its own now")
        XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), old, "the old file is left as it is")
        // Once saved, the old file no longer decides.
        try Data(#"{"language":"ja"}"#.utf8).write(to: legacy)
        XCTAssertEqual(AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .en).language, .ko)
    }

    func testANewInstallStartsFromTheSystemLanguage() {
        XCTAssertEqual(AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .ja).language, .ja)
    }

    func testAnUnreadableOrUnknownOldLanguageFallsBackToTheSystem() throws {
        try Data("not json".utf8).write(to: legacy)
        XCTAssertEqual(AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .de).language, .de)
        let other = UserDefaults(suiteName: "lang-\(UUID().uuidString)")!
        try Data(#"{"language":"tlh"}"#.utf8).write(to: legacy)
        XCTAssertEqual(AppLanguageStore(defaults: other, legacyStateURL: legacy, systemDefault: .fr).language, .fr)
    }

    func testAChangeIsSavedAndSurvivesARestart() {
        let store = AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .en)
        store.setLanguage(.ko)
        XCTAssertEqual(store.language, .ko)
        XCTAssertEqual(store.l.home, L(.ko).home)
        XCTAssertEqual(AppLanguageStore(defaults: defaults, legacyStateURL: legacy, systemDefault: .en).language, .ko)
    }
}
