import XCTest
@testable import PokeTokenBar

/// Using a Digimental (step 13, docs/digimon/step13-digimental-armor.md section 7): a full stage with a
/// Digimental route waits for the user only when the user owns that Digimental; using it spends one
/// and evolves into the Armor; skipping or the time running out grows as usual and keeps it.
final class DigimonArmorEvolutionTests: XCTestCase {
    private let engine = EvolutionEngine()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var catalog: DigimonCatalog { engine.catalog }

    /// `key` on `line`, its stage full, holding `owned` Digimentals.
    private func full(_ line: String, _ key: String, owned: [Digimental: Int] = [:]) -> DigimonState {
        var s = DigimonState.newEgg(lineID: line)
        let species = catalog.species(key)!
        s.partner.speciesKey = key
        s.partner.level = species.level
        s.partner.path = [key]
        s.dex = [key]
        s.partner.stageStartedAt = now.addingTimeInterval(-3 * 86_400)
        s.partner.stageExp = engine.growth.threshold(for: species.level)
        var bag = DigimentalBag()
        for (d, n) in owned { bag.owned[d.rawValue] = n }
        s.digimentals = bag
        return s
    }

    private func isArmor(_ from: String, _ to: String, on line: String) -> Bool {
        catalog.lines[line]!.digimental(from: from, to: to) != nil
    }

    // MARK: Offering

    func testWithoutTheDigimentalNothingWaits() {
        var s = full("vmon", "vmon")
        let events = engine.settle(&s, at: now)
        XCTAssertNil(s.armorWait)
        let to = try? XCTUnwrap(s.partner.speciesKey)
        XCTAssertNotEqual(to, "vmon", "it grew as usual")
        XCTAssertFalse(isArmor("vmon", to ?? "", on: "vmon"), "growth never takes an armor route")
        XCTAssertFalse(events.contains { if case .armorOffered = $0 { return true }; return false })
    }

    func testItWaitsOnlyForTheDigimentalsTheUserOwns() {
        var s = full("vmon", "vmon", owned: [.courage: 1, .hope: 3])
        let events = engine.settle(&s, at: now)
        XCTAssertEqual(s.partner.speciesKey, "vmon", "it waits")
        XCTAssertTrue(engine.isArmorOpen(s))
        XCTAssertEqual(events, [.armorOffered(options: ["fladramon"])], "Courage opens Fladramon; Friendship is not held")
        XCTAssertEqual(engine.usableArmorOptions(for: s).map(\.to), ["fladramon"])
        XCTAssertEqual(engine.armorDeadline(s), now.addingTimeInterval(engine.growth.armorWait))
    }

    // MARK: Using, skipping, timing out

    func testUsingSpendsExactlyOneAndEvolvesIntoTheArmor() throws {
        var s = full("vmon", "vmon", owned: [.courage: 2])
        engine.settle(&s, at: now)
        let events = try engine.useDigimental(&s, to: "fladramon", at: now)
        XCTAssertEqual(events.first, .armorEvolved(from: "vmon", to: "fladramon", digimental: .courage))
        XCTAssertEqual(s.digimentals?.owned(.courage), 1, "exactly one is used up")
        XCTAssertEqual(s.partner.speciesKey, "fladramon")
        XCTAssertEqual(s.partner.level, .adult)
        XCTAssertTrue(s.dex.contains("fladramon"))
        XCTAssertTrue(s.discoveredEvolutions.contains("vmon>fladramon"))
        XCTAssertNil(s.armorWait)
    }

    func testSkippingGrowsAsUsualAndKeepsTheDigimental() {
        var s = full("vmon", "vmon", owned: [.courage: 1])
        engine.settle(&s, at: now)
        engine.skipArmor(&s, at: now)
        let to = s.partner.speciesKey ?? ""
        XCTAssertNotEqual(to, "vmon")
        XCTAssertFalse(isArmor("vmon", to, on: "vmon"))
        XCTAssertEqual(s.digimentals?.owned(.courage), 1, "kept for later")
        XCTAssertNil(s.armorWait)
    }

    func testTheTimeRunningOutGrowsAsUsualAndKeepsTheDigimental() {
        var s = full("vmon", "vmon", owned: [.courage: 1])
        engine.settle(&s, at: now)
        XCTAssertEqual(engine.tick(&s, now: now.addingTimeInterval(engine.growth.armorWait - 60)), [])
        XCTAssertEqual(s.partner.speciesKey, "vmon", "still waiting a minute before the end")
        engine.tick(&s, now: now.addingTimeInterval(engine.growth.armorWait))
        XCTAssertNotEqual(s.partner.speciesKey, "vmon")
        XCTAssertFalse(isArmor("vmon", s.partner.speciesKey ?? "", on: "vmon"))
        XCTAssertEqual(s.digimentals?.owned(.courage), 1)
    }

    func testTheArmorGrowsOnByItsCardRoute() throws {
        var s = full("vmon", "vmon", owned: [.courage: 1])
        engine.settle(&s, at: now)
        _ = try engine.useDigimental(&s, to: "fladramon", at: now)
        s.partner.stageStartedAt = now.addingTimeInterval(-3 * 86_400)
        s.partner.stageExp = engine.growth.threshold(for: .adult)
        engine.settle(&s, at: now)
        XCTAssertTrue(engine.isJogressOpen(s), "Fladramon's card has Jogress routes: it waits for a friend first")
        engine.skipJogress(&s, at: now)
        let next = try XCTUnwrap(s.partner.speciesKey)
        XCTAssertEqual(s.partner.level, .perfect, "it grew on to a Perfect, not stuck as the Armor")
        XCTAssertTrue(catalog.nextEvolutions(from: "fladramon", in: catalog.lines["vmon"]!).contains { $0.to == next })
        XCTAssertFalse(isArmor("fladramon", next, on: "vmon"), "no Digimental was used for this step")
    }

    func testUsingIsRefusedWhenNothingWaitsOrTheDigimentalIsGone() {
        var s = full("vmon", "vmon", owned: [.courage: 1])
        XCTAssertThrowsError(try engine.useDigimental(&s, to: "fladramon", at: now)) {
            XCTAssertEqual($0 as? ArmorError, .notOpen)
        }
        engine.settle(&s, at: now)
        XCTAssertThrowsError(try engine.useDigimental(&s, to: "lighdramon", at: now)) {
            XCTAssertEqual($0 as? ArmorError, .notOffered, "Friendship is not held")
        }
        s.digimentals?.owned[Digimental.courage.rawValue] = 0
        XCTAssertThrowsError(try engine.useDigimental(&s, to: "fladramon", at: now)) {
            XCTAssertEqual($0 as? ArmorError, .notOffered)
        }
        XCTAssertEqual(s.partner.speciesKey, "vmon")
    }

    // MARK: With a friend's Jogress

    /// V-dramon (Adult, V-mon line) has both: a Digimental route (Hope: Sagittarimon) and Jogress routes.
    /// Both waits open together and run side by side; it grows as usual once neither is open.
    func testTheArmorAndJogressWaitsOpenTogetherAndNeitherHoldsTheOtherBack() throws {
        var s = full("vmon", "vdramon", owned: [.hope: 1])
        let events = engine.settle(&s, at: now)
        XCTAssertTrue(engine.isJogressOpen(s))
        XCTAssertTrue(engine.isArmorOpen(s))
        XCTAssertTrue(events.contains(.armorOffered(options: ["sagittarimon"])))
        XCTAssertTrue(events.contains { if case .jogressOffered = $0 { return true }; return false })

        // Not using the Digimental still waits for a friend; then skipping that grows as usual.
        var a = s
        engine.skipArmor(&a, at: now)
        XCTAssertEqual(a.partner.speciesKey, "vdramon")
        XCTAssertTrue(engine.isJogressOpen(a))
        engine.skipJogress(&a, at: now)
        XCTAssertNotEqual(a.partner.speciesKey, "vdramon")
        XCTAssertFalse(isArmor("vdramon", a.partner.speciesKey ?? "", on: "vmon"))
        XCTAssertEqual(a.digimentals?.owned(.hope), 1)

        // Skipping the friend first, the Digimental can still be used.
        var b = s
        engine.skipJogress(&b, at: now)
        XCTAssertEqual(b.partner.speciesKey, "vdramon")
        XCTAssertTrue(engine.isArmorOpen(b))
        _ = try engine.useDigimental(&b, to: "sagittarimon", at: now)
        XCTAssertEqual(b.partner.speciesKey, "sagittarimon")
        XCTAssertEqual(b.digimentals?.owned(.hope), 0)

        // Using the Digimental right away ends both waits.
        var c = s
        _ = try engine.useDigimental(&c, to: "sagittarimon", at: now)
        XCTAssertNil(c.jogressWait)
        XCTAssertNil(c.armorWait)

        // Both time out together after a day.
        var d = s
        engine.tick(&d, now: now.addingTimeInterval(max(engine.growth.armorWait, engine.growth.jogressWait)))
        XCTAssertNotEqual(d.partner.speciesKey, "vdramon")
        XCTAssertEqual(d.digimentals?.owned(.hope), 1)
    }

    // MARK: Saves

    func testOldSavesDecodeAndAnOpenWaitIsSaved() throws {
        var s = full("vmon", "vmon", owned: [.courage: 1])
        engine.settle(&s, at: now)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DigimonState.self, from: data).armorWait, s.armorWait)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["armorWait"] = nil
        object["digimentals"] = nil
        let old = try JSONDecoder().decode(DigimonState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.armorWait)
        XCTAssertTrue(engine.usableArmorOptions(for: old).isEmpty, "a save from before holds no Digimental")
    }

    @MainActor
    func testTheStoreSavesTheArmorEvolution() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("armor-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("digimon-state.json")
        var s = full("vmon", "vmon", owned: [.courage: 1])
        engine.settle(&s, at: now)
        try JSONEncoder().encode(DigimonStore.Saved(digimon: s)).write(to: file)
        let store = DigimonStore(fileURL: file, clock: { self.now })
        XCTAssertTrue(store.isArmorOpen)
        XCTAssertEqual(store.armorChoices.map(\.to), ["fladramon"])
        try store.useDigimental(to: "fladramon")
        let reopened = DigimonStore(fileURL: file, clock: { self.now })
        XCTAssertEqual(reopened.state.partner.speciesKey, "fladramon")
        XCTAssertEqual(reopened.digimentalBag.owned(.courage), 0)
        XCTAssertFalse(reopened.isArmorOpen)
    }

    // MARK: Seams for the fragment loop

    func testFragmentsAreOnlyKindsSomeRouteUses() {
        let used = Set(catalog.lines.values.flatMap(\.digimentalSteps.values))
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(Set(engine.fragmentKinds()), used)
    }

    func testPreferredKindsAreTheOnesThisLifeCanStillUse() {
        let egg = engine.preferredDigimentals(for: .newEgg(lineID: "vmon"))
        XCTAssertTrue(egg.isSuperset(of: [.courage, .friendship, .hope, .fate, .miracles]), "\(egg)")
        XCTAssertTrue(engine.preferredDigimentals(for: .newEgg(lineID: "agumon")).isEmpty, "no armor on the Agumon line")
        XCTAssertFalse(catalog.lines["agumon"]!.hasArmor)
        let child = full("vmon", "vmon")
        XCTAssertEqual(engine.digimentalsUsableNow(for: child), [.courage, .friendship])
        XCTAssertTrue(engine.preferredDigimentals(for: child).isSuperset(of: [.courage, .friendship, .hope]))
        let adult = full("vmon", "vdramon")
        XCTAssertFalse(engine.preferredDigimentals(for: adult).contains(.courage), "V-mon's routes are behind it")
        XCTAssertTrue(engine.preferredDigimentals(for: adult).contains(.hope))
    }

    // MARK: Text

    func testLinesWithArmorAreMarkedAndUnmetArmorsStayNameless() {
        let ko = DigimonText(.ko)
        let vmon = catalog.lines["vmon"]!
        XCTAssertEqual(ko.lineMenuName(vmon, catalog: catalog, graduated: 0, armor: vmon.hasArmor), "브이몬 ◆")
        XCTAssertEqual(ko.lineMenuName(vmon, catalog: catalog, graduated: 1, armor: true), "브이몬 ◆ · 졸업 1번")
        XCTAssertEqual(ko.armorUse(.courage), "용기의 디지멘탈로 아머 진화")
        XCTAssertFalse(ko.armorUse(.courage).contains(ko.name(catalog.species("fladramon"))))
        XCTAssertEqual(DigimonText(.en).armorUse(.courage), "Armor-evolve with the Digimental of Courage")
        XCTAssertEqual(ko.partnerDigimentals(now: [.courage], later: [], canUse: [.courage]), "이번 단계를 채우면 쓸 수 있어요: 용기")
        XCTAssertEqual(ko.partnerDigimentals(now: [.courage], later: [.hope], canUse: [], open: true),
                       "지금 쓸 수 있어요: 용기\n나중에 쓸 수 있어요: 희망")
        XCTAssertEqual(ko.partnerDigimentals(now: [], later: [], canUse: []), "지금 줄기에는 아머 진화가 없어요.")
    }
}
