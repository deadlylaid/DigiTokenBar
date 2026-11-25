import AppKit
import Observation
import XCTest
@testable import PokeTokenBar

@MainActor
final class MenuGrowthTests: XCTestCase {
    private final class ChangeFlag: @unchecked Sendable {
        var changed = false
    }

    private func observe(_ usage: UsageStore, _ digimon: DigimonStore) -> ChangeFlag {
        let flag = ChangeFlag()
        withObservationTracking {
            _ = MenuBarContent.lines(store: usage, digimon: digimon)
        } onChange: { flag.changed = true }
        return flag
    }

    private func fixture(_ body: (UsageStore, DigimonStore) throws -> Void) throws {
        let name = "ptb-menu-growth-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        let digimon = DigimonStore(fileURL: directory.appendingPathComponent("digimon-state.json"))
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        usage.showTokensInMenu = false
        usage.showCostInMenu = false
        usage.showLimitInMenu = false
        usage.showGrowthInMenu = true
        try body(usage, digimon)
    }

    /// The menu bar shows the Digimon's growth and redraws as soon as it grows, without waiting for
    /// the next usage poll. Hidden growth must not cause extra redraws.
    func testGrowthRedrawsTheMenuWithoutAUsageRefreshAndHiddenGrowthDoesNot() throws {
        try fixture { usage, digimon in
            XCTAssertEqual(MenuBarContent.lines(store: usage, digimon: digimon), ["0%"], "a new egg")
            digimon.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
            let grew = observe(usage, digimon)
            digimon.update(todayTokensByProvider: ["claude_code": 20_000_001], todayDate: "d1", hasUsageData: true)
            XCTAssertTrue(grew.changed)
            XCTAssertEqual(MenuBarContent.lines(store: usage, digimon: digimon), ["50%"],
                           "20M tokens are 100 of the egg's 200 exp")

            let toggle = observe(usage, digimon)
            usage.showGrowthInMenu = false
            XCTAssertTrue(toggle.changed)
            XCTAssertEqual(MenuBarContent.lines(store: usage, digimon: digimon), ["—"])
            let hidden = observe(usage, digimon)
            digimon.update(todayTokensByProvider: ["claude_code": 3_000_001], todayDate: "d1", hasUsageData: true)
            XCTAssertFalse(hidden.changed, "hidden growth must not cause extra menu redraws")
        }
    }

    func testNativeRendererPreservesGrowthAndLimitColorsAcrossLineChanges() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        AppDelegate.applyMenuText(["1.2M · Growth 42%", "Claude 40%"], to: button,
                                  colors: [.init(text: "Claude 40%", tier: .onPace)])
        let title = button.attributedTitle
        XCTAssertEqual(title.string, "1.2M · Growth 42%\nClaude 40%")
        let growth = (title.string as NSString).range(of: "Growth")
        let limit = (title.string as NSString).range(of: "Claude")
        XCTAssertNil(title.attribute(.foregroundColor, at: growth.location, effectiveRange: nil))
        XCTAssertEqual(title.attribute(.foregroundColor, at: limit.location, effectiveRange: nil) as? NSColor,
                       NSColor(PaceTier.onPace.color))
        AppDelegate.applyMenuText(["Growth 42%"], to: button, colors: [])
        XCTAssertEqual(button.title, " Growth 42%")
        AppDelegate.applyMenuText([], to: button, colors: [])
        XCTAssertEqual(button.title, "")
    }
}
