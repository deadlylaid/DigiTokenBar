import Foundation
import XCTest
@testable import PokeTokenBar

/// Issue #4 (2026-11-25): no daily experience cap, every stage needs ten times the experience, and the
/// pace is a Settings choice (0.5×, 1×, 1.5×, 2×, 5×). Saves from before keep their bar: their
/// experience is scaled once by the same ten.
@MainActor
final class DigimonGrowthSpeedTests: XCTestCase {
    private var dir: URL!
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private var defaults: UserDefaults!
    private let suite = "DigimonGrowthSpeedTests-\(UUID().uuidString)"

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("growth-speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStore() -> DigimonStore {
        DigimonStore(fileURL: dir.appendingPathComponent("digimon-state.json"), clock: { [now] in now })
    }

    /// An Agumon (Child) with `exp` experience.
    private func agumon(exp: Int) -> DigimonState {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = "agumon"
        s.partner.level = .child
        s.partner.path = ["botamon", "koromon", "agumon"]
        s.dex = Set(s.partner.path)
        s.partner.stageStartedAt = now.addingTimeInterval(-86_400)
        s.partner.stageExp = exp
        return s
    }

    /// The JSON an app from before 2026-11-25 wrote: the same state without `expScale`.
    private func withoutScale(_ data: Data, at path: [String]) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func strip(_ object: [String: Any], _ rest: ArraySlice<String>) -> [String: Any] {
            var object = object
            guard let key = rest.first else { object.removeValue(forKey: "expScale"); return object }
            object[key] = strip(object[key] as? [String: Any] ?? [:], rest.dropFirst())
            return object
        }
        root = strip(root, path[...])
        return try JSONSerialization.data(withJSONObject: root)
    }

    // MARK: Speed setting

    func testTheSpeedIsSavedAppliedAndOnlyKnownSpeedsCount() {
        XCTAssertEqual(DigimonStore.growthSpeeds, [0.5, 1, 1.5, 2, 5])
        XCTAssertEqual(DigimonStore.savedGrowthSpeed(defaults), 1, "nothing saved: 1×")
        defaults.set(2.0, forKey: DigimonStore.growthSpeedKey)
        XCTAssertEqual(DigimonStore.savedGrowthSpeed(defaults), 2)
        defaults.set(3.0, forKey: DigimonStore.growthSpeedKey)
        XCTAssertEqual(DigimonStore.savedGrowthSpeed(defaults), 1, "a speed Settings does not offer falls back to 1×")

        let store = makeStore()
        store.setGrowthSpeed(2)
        XCTAssertEqual(store.growthSpeed, 2)
        XCTAssertEqual(store.threshold, 100, "an egg needs 200 at 1×, 100 at 2×")
        store.setGrowthSpeed(7)
        XCTAssertEqual(store.growthSpeed, 1, "unknown speeds are 1×")
        XCTAssertEqual(store.threshold, 200)
    }

    /// Settings writes the speed back whenever the picker redraws; the same speed must not rebuild the
    /// engine, or every observer of the store (the menu bar, the home) would redraw for nothing.
    func testTheSameSpeedAgainChangesNothing() {
        let store = makeStore()
        store.setGrowthSpeed(2)
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking { _ = store.threshold } onChange: { flag.fired = true }
        store.setGrowthSpeed(2)
        XCTAssertFalse(flag.fired)
        store.setGrowthSpeed(1)
        XCTAssertTrue(flag.fired, "a real change still notifies")
    }

    func testAFasterSpeedEvolvesAFullStageAtOnceAndASlowerOneKeepsTheExperience() throws {
        try JSONEncoder().encode(DigimonStore.Saved(digimon: agumon(exp: 700)))
            .write(to: dir.appendingPathComponent("digimon-state.json"))
        let store = makeStore()
        store.setGrowthSpeed(0.5)
        XCTAssertEqual(store.state.partner.speciesKey, "agumon")
        XCTAssertEqual(store.threshold, 2_400)
        XCTAssertEqual(store.state.partner.stageExp, 700, "slower only makes the bar look less full")
        store.setGrowthSpeed(2)
        XCTAssertEqual(store.state.partner.level, .adult, "700 of 600: it evolves at once")
    }

    /// The fast-growth label follows the switch only: a 2× or 5× speed is not "fast growth (testing)".
    func testFastGrowthIsTheSwitchNotAnySpeedAboveOne() {
        let store = makeStore()
        store.setGrowthSpeed(5)
        XCTAssertFalse(store.isFastGrowth, "5× speed is not the testing switch")
        store.setFastGrowth(true)
        XCTAssertTrue(store.isFastGrowth)
        XCTAssertEqual(store.threshold, 4, "egg 200 ÷ 5 × 0.1")
        XCTAssertEqual(store.growthSpeed, 5, "the switch keeps the speed")
        store.setFastGrowth(false)
        XCTAssertFalse(store.isFastGrowth)
        XCTAssertEqual(store.threshold, 40)
    }

    // MARK: Migration of saves from before the ×10 thresholds

    /// An old Agumon at 90 of 120 (75%) opens at 900 of 1,200: the bar stays at 75%. Today's experience
    /// is scaled too, and opening again (or saving) never scales twice.
    func testAnOldSaveKeepsItsBarAndIsScaledOnlyOnce() throws {
        var old = agumon(exp: 90)
        old.expDay = "2026-11-24"
        old.expToday = 40
        let file = dir.appendingPathComponent("digimon-state.json")
        try withoutScale(JSONEncoder().encode(DigimonStore.Saved(digimon: old)), at: ["digimon"]).write(to: file)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("expScale"), "the file is an old one")

        let store = makeStore()
        XCTAssertEqual(store.state.expScale, GrowthRules.expScale)
        XCTAssertEqual(store.state.partner.stageExp, 900)
        XCTAssertEqual(store.state.expToday, 400)
        XCTAssertEqual(store.progress, 0.75, accuracy: 0.0001)

        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("expScale"),
                      "opening rewrites the file in the new unit at once")
        XCTAssertEqual(makeStore().state.partner.stageExp, 900, "reopening never scales twice")
        XCTAssertEqual(makeStore().state.expToday, 400)
    }

    /// Exports and backups from before go through the same boundary when imported or restored.
    func testImportingAnOldExportScalesItsExperience() throws {
        let store = makeStore()
        let oldFile = DigimonSaveFile(savedAt: now, device: "Mac", digimon: agumon(exp: 60))
        let data = try withoutScale(DigimonSaveIO.encode(oldFile), at: ["digimon"])
        let decoded = try DigimonSaveIO.decode(data)
        XCTAssertNil(decoded.digimon.expScale, "an old export has no scale")
        try store.replace(with: decoded, reason: "import")
        XCTAssertEqual(store.state.partner.stageExp, 600)
        XCTAssertEqual(store.state.expScale, GrowthRules.expScale)

        let current = DigimonSaveFile(savedAt: now, device: "Mac", digimon: agumon(exp: 600))
        try store.replace(with: DigimonSaveIO.decode(DigimonSaveIO.encode(current)), reason: "import")
        XCTAssertEqual(store.state.partner.stageExp, 600, "a file already in the new unit is left as it is")
    }

    func testANewEggStartsInTheNewUnit() {
        XCTAssertEqual(DigimonState.newEgg(lineID: "agumon").expScale, GrowthRules.expScale)
    }
}
