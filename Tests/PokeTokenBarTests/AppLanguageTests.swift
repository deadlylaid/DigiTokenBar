import XCTest
@testable import PokeTokenBar

final class AppLanguageTests: XCTestCase {
    func testGermanLanguageMetadata() {
        XCTAssertEqual(AppLanguage.de.rawValue, "de")
        XCTAssertEqual(AppLanguage.de.label, "Deutsch")
    }

    func testGermanPreferredLanguagesMapToGerman() {
        for identifier in ["de", "de-DE", "de-AT", "DE-de"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: identifier), .de, identifier)
        }
        XCTAssertEqual(AppLanguage.systemDefault(for: "it-IT"), .en)
        XCTAssertEqual(AppLanguage.systemDefault(for: nil), .en)
    }

    func testRussianLanguageMetadata() {
        XCTAssertEqual(AppLanguage.ru.rawValue, "ru")
        XCTAssertEqual(AppLanguage.ru.label, "Русский")
    }

    func testRussianPreferredLanguagesMapToRussian() {
        for identifier in ["ru", "ru-RU", "ru-KZ", "RU-ru"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: identifier), .ru, identifier)
        }
        XCTAssertEqual(AppLanguage.systemDefault(for: "uk-UA"), .en)
    }
}

/// 앱 언어와 시스템 로케일이 다를 때 `Text(_, style: .relative)` 같은 자동 문장이 시스템을 따라가면
/// 한 화면에 두 언어가 섞인다(한국어 Mac + 영어 앱 → "Catch log" 옆에 "3시간 46분").
/// 팝오버 루트가 `\.locale` 로 앱 언어를 내려주므로, 그 매핑이 실제로 해당 언어의 상대 시각을
/// 만들어내는지까지 고정한다 — 코드만 비교하면 잘못 매핑해도 통과한다.
final class DisplayLocaleTests: XCTestCase {
    func testDisplayLocaleMatchesLanguageCode() {
        XCTAssertEqual(AppLanguage.ko.displayLocale.identifier, "ko")
        XCTAssertEqual(AppLanguage.en.displayLocale.identifier, "en")
        XCTAssertEqual(AppLanguage.ja.displayLocale.identifier, "ja")
        XCTAssertEqual(AppLanguage.de.displayLocale.identifier, "de")
        XCTAssertEqual(AppLanguage.ru.displayLocale.identifier, "ru")
    }

    func testRelativeTimeFollowsAppLanguageNotSystem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3 * 3600)

        func relative(_ lang: AppLanguage) -> String {
            let f = RelativeDateTimeFormatter()
            f.locale = lang.displayLocale
            return f.localizedString(for: past, relativeTo: now)
        }

        XCTAssertTrue(relative(.en).contains("hour"), "영어: \(relative(.en))")
        XCTAssertTrue(relative(.ko).contains("시간"), "한국어: \(relative(.ko))")
        XCTAssertTrue(relative(.ja).contains("時間"), "일본어: \(relative(.ja))")
        XCTAssertTrue(relative(.de).lowercased().contains("stund"), "독일어: \(relative(.de))")
        XCTAssertTrue(relative(.ru).contains("час"), "러시아어: \(relative(.ru))")
        // 다섯 언어가 서로 달라야 한다 — 하나로 고정돼 있으면 매핑이 죽은 것이다.
        XCTAssertEqual(Set([relative(.en), relative(.ko), relative(.ja), relative(.de), relative(.ru)]).count, 5)
    }
}
