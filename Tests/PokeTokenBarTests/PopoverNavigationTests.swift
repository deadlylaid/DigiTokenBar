import XCTest
@testable import PokeTokenBar

// 팝오버 내비게이션 리셋 계약 — 닫혔다 열릴 때 AppDelegate.togglePopover 가 reset()을 불러
// 항상 Home 으로 돌아가게 한다(설정 화면 잔류 방지).
@MainActor
final class PopoverNavigationTests: XCTestCase {
    func testDefaultsToHome() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .home)
        XCTAssertFalse(nav.showingRecap)
    }

    func testResetReturnsToHomeFromSettings() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.tab = .collection
        nav.showingRecap = true
        nav.reset()
        XCTAssertFalse(nav.showSettings)   // 설정 화면 닫힘
        XCTAssertEqual(nav.tab, .home)     // 탭도 Home 으로
        XCTAssertFalse(nav.showingRecap)
    }

    /// #301: Hide is a right-click. Show has to live on the popover footer, bound to the same
    /// `floatingPetEnabled` the Settings checkbox already uses. Removing the button must fail this.
    func testPopoverFooterTogglesFloatingPetWithoutOpeningSettings() throws {
        let source = try String(contentsOf: Self.popoverSource, encoding: .utf8)
        let footer = try XCTUnwrap(source.range(of: "private var footer"))
        let body = String(source[footer.lowerBound...])
        XCTAssertTrue(
            body.contains("store.floatingPetEnabled.toggle()"),
            "footer must flip floatingPetEnabled — Hide already does; Show had only Settings")
        XCTAssertTrue(body.contains("l.floatingPetHideLabel"))
        XCTAssertTrue(body.contains("l.floatingPetEnableLabel"))
        XCTAssertFalse(
            body.contains("nav.showSettings = true\n            }\n            .buttonStyle(.borderless)\n            .help(l.floatingPet"),
            "the pet control must not be a second door into Settings")
    }

    private static let popoverSource: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/PopoverView.swift")
    }()
}

final class SettingsLocalizationTests: XCTestCase {
    func testGermanSettingsLabelsIncludeLatestMainStrings() {
        let l = L(.de)

        XCTAssertEqual(l.todayTokensShort, "Heutige Tokens")
        XCTAssertEqual(l.todayCost, "Heutige Kosten ($)")
        XCTAssertEqual(l.limitPercent, "Limit %")
        XCTAssertEqual(l.animationQualityLabel, "Animation")
        XCTAssertEqual(l.animationQualityHint, "Flüssigere Animationen verbrauchen mehr Batterie")
        XCTAssertEqual(l.animationPowerSaver, "Energiesparmodus")
        XCTAssertEqual(l.animationBalanced, "Ausgewogen")
        XCTAssertEqual(l.animationSmooth, "Flüssig")
    }

}
