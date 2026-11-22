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

    /// Both waits open together and run side by side; it grows as usual once neither is open. Since only
    /// a Child armor-evolves with a Digimental (2026-11-21), no Digimon on the cards has both a Digimental
    /// route and a friend's Jogress any more (Child Jogress routes do not exist on these cards). The order
    /// still matters if a card ever has one, so the test gives V-mon a Jogress route of its own.
    func testTheArmorAndJogressWaitsOpenTogetherAndNeitherHoldsTheOtherBack() throws {
        let base = DigimonCatalog.mvp
        let lines = base.lines.values.map { line -> DigimonLine in
            guard line.id == "vmon" else { return line }
            var l = line
            l.jogress.append(DigimonJogress("vmon>vdramon", level: .child, attributes: [.vaccine]))
            return l
        }
        let merging = EvolutionEngine(catalog: DigimonCatalog(species: DigimonCatalogData.species,
                                                              evolutions: DigimonCatalogData.evolutions, lines: lines))
        let real = engine.jogressOptions(for: full("vmon", "vmon"))
        XCTAssertTrue(real.isEmpty, "the real V-mon has no Jogress route: this case is made up for the test")
        var s = full("vmon", "vmon", owned: [.courage: 1])
        let events = merging.settle(&s, at: now)
        XCTAssertTrue(merging.isJogressOpen(s))
        XCTAssertTrue(merging.isArmorOpen(s))
        XCTAssertTrue(events.contains(.armorOffered(options: ["fladramon"])))
        XCTAssertTrue(events.contains { if case .jogressOffered = $0 { return true }; return false })

        // Not using the Digimental still waits for a friend; then skipping that grows as usual.
        var a = s
        merging.skipArmor(&a, at: now)
        XCTAssertEqual(a.partner.speciesKey, "vmon")
        XCTAssertTrue(merging.isJogressOpen(a))
        merging.skipJogress(&a, at: now)
        XCTAssertNotEqual(a.partner.speciesKey, "vmon")
        XCTAssertFalse(isArmor("vmon", a.partner.speciesKey ?? "", on: "vmon"))
        XCTAssertEqual(a.digimentals?.owned(.courage), 1)

        // Skipping the friend first, the Digimental can still be used.
        var b = s
        merging.skipJogress(&b, at: now)
        XCTAssertEqual(b.partner.speciesKey, "vmon")
        XCTAssertTrue(merging.isArmorOpen(b))
        _ = try merging.useDigimental(&b, to: "fladramon", at: now)
        XCTAssertEqual(b.partner.speciesKey, "fladramon")
        XCTAssertEqual(b.digimentals?.owned(.courage), 0)

        // Using the Digimental right away ends both waits.
        var c = s
        _ = try merging.useDigimental(&c, to: "fladramon", at: now)
        XCTAssertNil(c.jogressWait)
        XCTAssertNil(c.armorWait)

        // Both time out together after a day.
        var d = s
        merging.tick(&d, now: now.addingTimeInterval(max(merging.growth.armorWait, merging.growth.jogressWait)))
        XCTAssertNotEqual(d.partner.speciesKey, "vmon")
        XCTAssertEqual(d.digimentals?.owned(.courage), 1)
    }

    // MARK: Saves

    /// Kindness, Miracles and Fate lost their routes when only a Child kept its Digimental (2026-11-21). A
    /// save from before may hold some: they are kept, still shown in the dex and survive an import, but
    /// no new fragment of them drops and nothing can spend them.
    func testOldKindnessMiraclesAndFateItemsAreKeptAndStillShown() throws {
        let collectable = engine.fragmentKinds()
        XCTAssertTrue(Set(collectable).isDisjoint(with: [.kindness, .miracles, .fate]))
        XCTAssertEqual(DigimentalBag().shownKinds(collectable: collectable), collectable, "a new player sees the eight")
        var bag = DigimentalBag()
        bag.owned[Digimental.miracles.rawValue] = 1
        bag.fragments[Digimental.fate.rawValue] = 2
        XCTAssertEqual(bag.shownKinds(collectable: collectable), collectable + [.miracles, .fate])
        var s = full("vmon", "vmon")
        s.digimentals = bag
        let decoded = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(s))
        let imported = try DigimonSaveIO.sanitized(decoded, catalog: catalog, growth: engine.growth)
        XCTAssertEqual(imported.digimentals?.owned(.miracles), 1)
        XCTAssertEqual(imported.digimentals?.fragments(.fate), 2)
        XCTAssertTrue(engine.usableArmorOptions(for: imported).isEmpty, "nothing spends them")
    }

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
        XCTAssertEqual(egg, [.courage, .friendship], "V-mon's two; the line's later Armors grow by the card")
        XCTAssertTrue(engine.preferredDigimentals(for: .newEgg(lineID: "agumon")).isEmpty, "no armor on the Agumon line")
        XCTAssertFalse(catalog.lines["agumon"]!.hasArmor)
        XCTAssertFalse(catalog.lines["tinkermon"]!.hasArmor, "Peacockmon grows from an Adult: no Digimental, no mark")
        XCTAssertFalse(catalog.lines["gabumonblack"]!.hasArmor, "so does Rhinomon")
        let child = full("vmon", "vmon")
        XCTAssertEqual(engine.digimentalsUsableNow(for: child), [.courage, .friendship])
        XCTAssertEqual(engine.preferredDigimentals(for: child), [.courage, .friendship])
        let adult = full("vmon", "vdramon")
        XCTAssertTrue(engine.preferredDigimentals(for: adult).isEmpty, "V-mon's routes are behind it; nothing later needs one")
        let armadimon = engine.preferredDigimentals(for: .newEgg(lineID: "armadimon"))
        XCTAssertEqual(armadimon, [.knowledge, .reliability, .hope, .courage, .friendship], "three Children on that card")
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
