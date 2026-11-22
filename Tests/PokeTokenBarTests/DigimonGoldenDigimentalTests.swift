import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Step 16 (docs/digimon/step16-golden-digimentals.md): Child -> Armor routes from Wikimon's Digimental
/// Evolution Chart that no card has. They skip stages; Kindness comes from fragments, the golden Miracles
/// and Fate only whole (a full stamp card 1 time in 4, or 30 surprise points).
final class DigimonGoldenDigimentalTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private var engine: EvolutionEngine { EvolutionEngine(calendar: calendar) }
    private var catalog: DigimonCatalog { engine.catalog }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The chart routes as listed in tools/digimon/research/digimental-chart-routes.json, per line.
    private let chartRoutes: [String: [String: [Digimental]]] = [
        "vmon": ["vmon>magnamon": [.miracles], "vmon>goldvdramon": [.fate]],
        "armadimon": ["vmon>magnamon": [.miracles]],
        "terriermon": ["terriermon>rapidmonarmor": [.fate]],
        "wormmon": ["wormmon>kongoumon": [.miracles, .fate], "wormmon>pucchiemon": [.kindness],
                    "wormmon>pucchiemongreen": [.kindness]],
    ]

    private func date(day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))!
    }

    /// `key` on `line`, its stage full (plus `extra`), holding `owned` Digimentals.
    private func full(_ line: String, _ key: String, owned: [Digimental: Int] = [:], extra: Int = 0) -> DigimonState {
        var s = DigimonState.newEgg(lineID: line)
        let species = catalog.species(key)!
        s.partner.speciesKey = key
        s.partner.level = species.level
        s.partner.path = [key]
        s.dex = [key]
        s.playerID = "golden-test"
        s.partner.stageStartedAt = now.addingTimeInterval(-3 * 86_400)
        s.partner.stageExp = engine.growth.threshold(for: species.level) + extra
        var bag = DigimentalBag()
        for (d, n) in owned { bag.owned[d.rawValue] = n }
        s.digimentals = bag
        return s
    }

    private func isChart(_ line: DigimonLine, _ step: String) -> Bool {
        let p = step.split(separator: ">").map(String.init)
        return catalog.nextEvolutions(from: p[0], in: line).first { $0.to == p[1] }?.sources == [.digimentalChart]
    }

    // MARK: Routes

    /// The chart routes are on the listed lines only, with their Digimentals, and every step a golden or
    /// Kindness Digimental opens is one of them.
    func testTheChartRoutesAreExactlyTheListedOnes() {
        var found: [String: [String: [Digimental]]] = [:]
        for line in catalog.lines.values {
            for (step, ds) in line.digimentalSteps where isChart(line, step) {
                found[line.id, default: [:]][step] = ds
            }
            for (step, ds) in line.digimentalSteps where ds.contains(where: { $0.isGolden || $0 == .kindness }) {
                XCTAssertTrue(isChart(line, step), "\(line.id): \(step) opens with \(ds) but is not a chart route")
            }
        }
        XCTAssertEqual(found, chartRoutes)
        XCTAssertEqual(found.values.reduce(0) { $0 + $1.count }, 7)
    }

    /// The Armor keeps its card stage, so a Child lands straight on a Perfect or an Ultimate.
    func testTheyLandOnTheArmorsOwnStage() {
        let stage: [String: DigimonLevel] = ["magnamon": .ultimate, "rapidmonarmor": .ultimate, "goldvdramon": .perfect,
                                             "kongoumon": .perfect, "pucchiemon": .perfect, "pucchiemongreen": .perfect]
        for (lineID, steps) in chartRoutes {
            let line = catalog.lines[lineID]!
            for step in steps.keys {
                let p = step.split(separator: ">").map(String.init)
                XCTAssertEqual(catalog.species(p[0])?.level, .child, step)
                XCTAssertEqual(catalog.species(p[1])?.level, stage[p[1]], step)
                XCTAssertTrue(catalog.nextEvolutions(from: p[0], in: line).contains { $0.to == p[1] }, "\(lineID): \(step) is a step")
            }
        }
        // Lines with V-mon but no Magnamon route stay as they were.
        for line in catalog.lines.values where line.members.contains("vmon") && chartRoutes[line.id]?["vmon>magnamon"] == nil {
            XCTAssertFalse(catalog.nextEvolutions(from: "vmon", in: line).contains { $0.to == "magnamon" }, line.id)
        }
    }

    /// However the stage went and whatever the draw, growth never takes a chart route; it waits only
    /// when the user owns a Digimental that opens it.
    func testGrowthNeverTakesThem() {
        for (lineID, steps) in chartRoutes {
            for step in steps.keys {
                let p = step.split(separator: ">").map(String.init)
                for seed in 0..<12 {
                    var s = full(lineID, p[0])
                    s.playerID = "seed\(seed)"
                    s.partner.stageSignals.battles = 50
                    s.partner.stageSignals.battleWins = 50
                    XCTAssertFalse(engine.rankedOptions(for: s).contains(p[1]), "\(lineID): \(step)")
                    XCTAssertFalse(engine.growthOptions(for: s, at: now).contains(p[1]), "\(lineID): \(step)")
                    engine.settle(&s, at: now)
                    XCTAssertNil(s.armorWait, "nothing owned: no wait")
                    XCTAssertNotEqual(s.partner.speciesKey, p[1], "\(lineID): growth took \(step)")
                    XCTAssertNotEqual(s.partner.speciesKey, p[0], "it grew as usual")
                }
            }
        }
    }

    // MARK: Using one

    /// V-mon with Miracles: one Digimental spent, straight to Magnamon, an Ultimate. Level, stage, dex,
    /// the evolution seen, the path and the event are those of the Armor; then it graduates as usual.
    func testMiraclesTakesVmonStraightToAnUltimateThatGraduates() throws {
        var s = full("vmon", "vmon", owned: [.miracles: 1], extra: 30)
        XCTAssertEqual(engine.settle(&s, at: now), [.armorOffered(options: ["magnamon"])])
        let events = try engine.useDigimental(&s, to: "magnamon", at: now)
        XCTAssertEqual(events, [.armorEvolved(from: "vmon", to: "magnamon", digimental: .miracles)])
        XCTAssertEqual(s.partner.speciesKey, "magnamon")
        XCTAssertEqual(s.partner.level, .ultimate, "two stages skipped")
        XCTAssertEqual(s.partner.stageExp, 30, "what was past the Child's bar carries over")
        XCTAssertLessThan(s.partner.stageExp, engine.growth.threshold(for: .ultimate), "the new stage is not full at once")
        XCTAssertEqual(s.partner.stageStartedAt, now)
        XCTAssertEqual(s.partner.path, ["vmon", "magnamon"])
        XCTAssertTrue(s.dex.contains("magnamon"))
        XCTAssertTrue(s.discoveredEvolutions.contains("vmon>magnamon"))
        XCTAssertEqual(s.digimentals?.owned(.miracles), 0)
        XCTAssertNil(s.armorWait)
        // The Ultimate graduates when its stage fills: the life was two stages shorter.
        s.partner.stageExp = engine.growth.threshold(for: .ultimate)
        let end = engine.settle(&s, at: now.addingTimeInterval(86_400))
        XCTAssertEqual(end.first, .graduated(lineID: "vmon", path: ["vmon", "magnamon"]))
    }

    /// Fate takes V-mon to Gold V-dramon, a Perfect, which grows on by its card's routes.
    func testFateTakesVmonToAPerfectThatGrowsOnByItsCard() throws {
        var s = full("vmon", "vmon", owned: [.fate: 1])
        engine.settle(&s, at: now)
        _ = try engine.useDigimental(&s, to: "goldvdramon", at: now)
        XCTAssertEqual(s.partner.level, .perfect)
        XCTAssertEqual(s.partner.path, ["vmon", "goldvdramon"])
        let line = catalog.lines["vmon"]!
        let onward = engine.rankedOptions(for: s)
        XCTAssertFalse(onward.isEmpty)
        XCTAssertTrue(onward.allSatisfy { catalog.species($0)?.level == .ultimate && line.digimental(from: "goldvdramon", to: $0) == nil })
        XCTAssertTrue(onward.contains("magnamon"), "the card's own Gold V-dramon > Magnamon")
        s.partner.stageExp = engine.growth.threshold(for: .perfect)
        // Its card's Jogress routes wait for a friend's code first, like any Gold V-dramon.
        let later = now.addingTimeInterval(86_400)
        XCTAssertEqual(engine.settle(&s, at: later), [.jogressOffered(options: ["ulforcevdramon", "imperialdramondragonmode"])])
        let events = engine.skipJogress(&s, at: later)
        guard case .evolved(from: "goldvdramon", let to) = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(catalog.species(to)?.level, .ultimate)
    }

    func testFateTakesTerriermonToRapidmonArmor() throws {
        var s = full("terriermon", "terriermon", owned: [.fate: 2])
        engine.settle(&s, at: now)
        XCTAssertEqual(engine.usableArmorOptions(for: s).map(\.to), ["rapidmonarmor"])
        _ = try engine.useDigimental(&s, to: "rapidmonarmor", at: now)
        XCTAssertEqual(s.partner.level, .ultimate)
        XCTAssertEqual(s.digimentals?.owned(.fate), 1)
    }

    /// Kongoumon opens with Miracles or with Fate: one choice per Digimental held, and the one picked is
    /// the one spent. The two Pucchiemon open with Kindness.
    func testKongoumonOpensWithEitherAndThePickedOneIsSpent() throws {
        var fateOnly = full("wormmon", "wormmon", owned: [.fate: 1])
        engine.settle(&fateOnly, at: now)
        XCTAssertEqual(engine.usableArmorOptions(for: fateOnly), [ArmorOption(to: "kongoumon", digimental: .fate)])

        var both = full("wormmon", "wormmon", owned: [.miracles: 1, .fate: 1, .kindness: 1])
        let offered = engine.settle(&both, at: now)
        XCTAssertEqual(Set(engine.usableArmorOptions(for: both)),
                       [ArmorOption(to: "kongoumon", digimental: .miracles), ArmorOption(to: "kongoumon", digimental: .fate),
                        ArmorOption(to: "pucchiemon", digimental: .kindness), ArmorOption(to: "pucchiemongreen", digimental: .kindness)])
        guard case .armorOffered(let options) = offered.first else { return XCTFail("\(offered)") }
        XCTAssertEqual(options.filter { $0 == "kongoumon" }.count, 1, "the notice names Kongoumon once")
        var spendFate = both
        _ = try engine.useDigimental(&spendFate, to: "kongoumon", with: .fate, at: now)
        XCTAssertEqual(spendFate.digimentals?.owned(.fate), 0)
        XCTAssertEqual(spendFate.digimentals?.owned(.miracles), 1, "the other is kept")
        XCTAssertEqual(spendFate.partner.level, .perfect)
        XCTAssertThrowsError(try engine.useDigimental(&both, to: "kongoumon", with: .kindness, at: now)) {
            XCTAssertEqual($0 as? ArmorError, .notOffered, "Kindness does not open Kongoumon")
        }
        var kind = both
        let events = try engine.useDigimental(&kind, to: "pucchiemongreen", at: now)
        XCTAssertEqual(events.first, .armorEvolved(from: "wormmon", to: "pucchiemongreen", digimental: .kindness))
        XCTAssertEqual(kind.partner.level, .perfect)
    }

    // MARK: Getting them

    /// Kindness is a fragment kind like the other eight; a golden one never is, from any source.
    func testKindnessFragmentsDropAndGoldenOnesNeverDo() {
        XCTAssertEqual(engine.fragmentKinds().count, 9)
        XCTAssertTrue(engine.fragmentKinds().contains(.kindness))
        var s = full("wormmon", "wormmon")
        XCTAssertTrue(engine.preferredDigimentals(for: s).isSuperset(of: Digimental.golden), "the partner could use them")
        var kinds = Set<Digimental>()
        for day in 0..<3000 {
            if let gift = engine.visitGift(s, species: "greymon", day: "d\(day)", firstSeen: true) { kinds.insert(gift) }
        }
        for day in 1...28 {
            for hour in [9, 13, 17] { engine.recordGoldenBug(&s, at: date(day: day, hour: hour)) }
        }
        kinds.formUnion(Digimental.allCases.filter { (s.digimentals?.fragments($0) ?? 0) + (s.digimentals?.owned($0) ?? 0) > 0 })
        XCTAssertTrue(kinds.contains(.kindness), "Kindness drops")
        XCTAssertTrue(kinds.isDisjoint(with: Digimental.golden), "no golden fragment: \(kinds)")
        XCTAssertEqual(s.digimentals?.goldenTotal, 0)

        var three = full("agumon", "agumon")
        engine.giveFragment(&three, .kindness, from: .visitor)
        engine.giveFragment(&three, .kindness, from: .visitor)
        XCTAssertEqual(engine.giveFragment(&three, .kindness, from: .visitor).last, .digimentalMade(.kindness), "three make one")
    }

    /// About 1 full stamp card in 4 brings a golden Digimental, Miracles or Fate half each; seeded by the
    /// player, the day and the card, so the same card always gives the same.
    func testAFullStampCardBringsAGoldenOneAboutOneTimeInFour() {
        let trials = 4000
        var golden = 0, miracles = 0
        for i in 0..<trials {
            var s = DigimonState.newEgg(lineID: "agumon")
            s.playerID = "player\(i)"
            guard let d = engine.stampGolden(s, day: "2026-12-07", cards: 1) else { continue }
            XCTAssertTrue(d.isGolden)
            golden += 1
            if d == .miracles { miracles += 1 }
            XCTAssertEqual(engine.stampGolden(s, day: "2026-12-07", cards: 1), d, "never rerolled")
        }
        XCTAssertEqual(Double(golden) / Double(trials), 0.25, accuracy: 0.02)
        XCTAssertEqual(Double(miracles) / Double(golden), 0.5, accuracy: 0.05)
    }

    /// End to end: the 7th coding day fills the card; a card the seed favors also brings the golden one.
    func testTheStampCardsGoldenOneArrivesWithTheCard() throws {
        func fill(_ player: String) -> (DigimonState, [DigimonEvent]) {
            var s = full("agumon", "agumon")
            s.playerID = player
            var events: [DigimonEvent] = []
            for day in 1...LuckRules.stampCard {
                engine.addUsage(&s, tokens: 1_000, provider: "claude_code", at: date(day: day, hour: 7))
                events = engine.updateLuck(&s, at: date(day: day, hour: 7))
            }
            return (s, events)
        }
        let day = engine.dayKey(date(day: LuckRules.stampCard, hour: 7))
        var probe = DigimonState.newEgg(lineID: "agumon")
        let lucky = try XCTUnwrap((0..<200).map { "p\($0)" }.first { probe.playerID = $0; return engine.stampGolden(probe, day: day, cards: 1) != nil })
        let plain = try XCTUnwrap((0..<200).map { "p\($0)" }.first { probe.playerID = $0; return engine.stampGolden(probe, day: day, cards: 1) == nil })
        probe.playerID = lucky
        let kind = try XCTUnwrap(engine.stampGolden(probe, day: day, cards: 1))

        let (won, events) = fill(lucky)
        XCTAssertTrue(events.contains(.stampCardFull))
        XCTAssertTrue(events.contains(.goldenDigimental(kind, from: .stampCard)), "\(events)")
        XCTAssertEqual(won.digimentals?.owned(kind), 1)
        XCTAssertEqual(won.digimentals?.stampRewards, 1, "the card's fragment pick is still there")

        let (missed, others) = fill(plain)
        XCTAssertTrue(others.contains(.stampCardFull))
        XCTAssertFalse(others.contains { if case .goldenDigimental = $0 { return true }; return false })
        XCTAssertEqual(missed.digimentals?.goldenTotal, 0)
        XCTAssertEqual(missed.digimentals?.stampRewards, 1)
    }

    /// Thirty surprise points buy the golden one the user picks; with fewer nothing changes.
    func testThirtySurprisePointsBuyTheGoldenOneYouPick() {
        var s = full("agumon", "agumon")
        s.luck = LuckBook()
        s.luck?.surprise = DigimentalRules.goldenTradeCost - 1
        let before = s
        XCTAssertEqual(engine.tradeForGolden(&s, .fate), [])
        XCTAssertEqual(s, before, "29 points are not enough")
        s.luck?.surprise = DigimentalRules.goldenTradeCost + 4
        XCTAssertEqual(engine.tradeForGolden(&s, .fate), [.goldenDigimental(.fate, from: .surprise)])
        XCTAssertEqual(s.luck?.surprise, 4)
        XCTAssertEqual(s.digimentals?.owned(.fate), 1)
        XCTAssertEqual(s.digimentals?.fragmentTotal, 0, "whole, not as fragments")
        var fresh = full("agumon", "agumon")
        XCTAssertEqual(engine.tradeForGolden(&fresh, .miracles), [], "no luck book yet: no points")
        XCTAssertEqual(DigimentalRules.goldenTradeCost, 30)
    }

    @MainActor
    func testTheStoreTradesAndSaves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("golden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.json")
        var s = full("wormmon", "wormmon")
        s.luck = LuckBook()
        s.luck?.surprise = 45
        try JSONEncoder().encode(DigimonStore.Saved(digimon: s)).write(to: file)
        let at = now
        let store = DigimonStore(fileURL: file, engine: engine, clock: { at })
        XCTAssertFalse(store.fragmentChoices.contains { $0.isGolden }, "the fragment pickers never offer a golden one")
        XCTAssertTrue(store.fragmentChoices.contains(.kindness))
        XCTAssertTrue(store.canTradeForGolden)
        XCTAssertTrue(store.tradeForGolden(.miracles))
        XCTAssertFalse(store.canTradeForGolden)
        XCTAssertFalse(store.tradeForGolden(.fate))
        let reopened = DigimonStore(fileURL: file, engine: engine, clock: { at })
        XCTAssertEqual(reopened.digimentalBag.owned(.miracles), 1)
        XCTAssertEqual(reopened.surprisePoints, 15)
    }

    // MARK: Old saves

    /// Golden fragments only an old save holds stay where they are: kept, counted, shown, and never
    /// turned into a Digimental, not even three of them by an import.
    func testOldGoldenFragmentsStayAndNeverCombine() throws {
        let bag = try JSONDecoder().decode(DigimentalBag.self, from: Data(#"{"fragments":{"fate":2,"miracles":1},"owned":{"fate":1}}"#.utf8))
        XCTAssertEqual(bag.fragments(.fate), 2)
        XCTAssertEqual(bag.goldenTotal, 1)
        XCTAssertEqual(bag.fragmentTotal, 3)
        var s = full("vmon", "vmon")
        var big = bag
        big.fragments["fate"] = 7
        s.digimentals = big
        let decoded = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(s))
        let clean = try XCTUnwrap(DigimonSaveIO.sanitized(decoded, catalog: catalog, growth: engine.growth).digimentals)
        XCTAssertEqual(clean.fragments(.fate), 7, "golden fragments never combine")
        XCTAssertEqual(clean.owned(.fate), 1)
        var t = full("agumon", "agumon")
        t.digimentals = clean
        engine.giveFragment(&t, .courage, from: .visitor)
        XCTAssertEqual(t.digimentals?.owned(.fate), 1, "nor when another fragment comes")
        // A save from before step 16 (no golden fields anywhere) decodes as before.
        let old = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(DigimonState.newEgg(lineID: "vmon")))
        XCTAssertNil(old.digimentals)
        XCTAssertTrue(engine.usableArmorOptions(for: old).isEmpty)
    }

    // MARK: Text

    func testTheWordsAreKoreanAndEnglish() {
        let ko = DigimonText(.ko), en = DigimonText(.en)
        XCTAssertEqual(ko.goldenTitle, "황금 디지멘탈")
        XCTAssertEqual(ko.goldenTrade, "30점으로 받기")
        XCTAssertEqual(en.goldenTrade, "Get for 30 points")
        XCTAssertEqual(ko.goldenGotTitle, "황금 디지멘탈을 받았어요!")
        XCTAssertEqual(ko.goldenGotBody(.miracles, from: .stampCard), "기적의 디지멘탈 · 도장 선물")
        XCTAssertEqual(ko.goldenArmorEvolvedTitle, "황금 아머 진화!")
        XCTAssertEqual(ko.goldenShort(2), "황금 2")
        XCTAssertTrue(ko.goldenHelp.contains("조각으로 모을 수 없어요"))
        XCTAssertTrue(ko.goldenHelp.contains("4번에 1번"))
        XCTAssertTrue(ko.goldenHelp.contains("30점"))
        XCTAssertEqual(ko.armorUseInto(.fate, name: "골드브이드라몬"), "운명의 디지멘탈로 골드브이드라몬")
    }
}

/// The golden sparkle of an armor evolution with a golden Digimental, in the real scene script.
@MainActor
final class DigimonGoldenSparkleSceneTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    func testTheEvolveCommandSaysGoldenOnlyForAGoldenDigimental() {
        XCTAssertEqual(DigimonSceneHub.evolveCommand(key: "magnamon", golden: true)["golden"] as? Bool, true)
        XCTAssertNil(DigimonSceneHub.evolveCommand(key: "fladramon", golden: false)["golden"])
        XCTAssertEqual(DigimonSceneHub.evolveCommand(key: "fladramon", golden: false)["type"] as? String, "evolve")
    }

    /// A golden evolution twinkles in gold while it flickers and bursts in gold at the change; a plain one
    /// has no gold at all. Counted from the particles the scene makes.
    func testAGoldenEvolutionSparklesInGoldAndAPlainOneDoesNot() async throws {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "6B5BD6"))
        let uri = "data:image/png;base64," + png.base64EncodedString()
        for key in ["vmon", "magnamon", "fladramon"] { scene.sprite(key: key, dataURI: uri) }
        scene.apply(["key": "vmon", "line": "vmon", "stage": 3, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['magnamon'] && !!assets['fladramon']")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        func run(_ to: String, golden: Bool) async throws -> [String: Int] {
            let out = try await js(scene, """
            (() => {
              pet.bug = null; pet.bugIn = 1e9; pet.guests = []; pet.parts = []; pet.key = 'vmon'; pet.enter('idle', {dur: 99999});
              app.cmd({type: 'evolve', key: '\(to)', golden: \(golden)});
              let before = 0, at = 0, total = 0, swapped = false;
              for (let i = 0; i < 90; i++) {
                const n = pet.parts.length;
                pet.update(33);
                const fresh = pet.parts.slice(n).filter(p => GOLD_SPARK.includes(p.c)).length;
                total += fresh;
                if (pet.state === 'evolve' && pet.d.swapped && !swapped) { swapped = true; at = fresh; } else if (!swapped) before += fresh;
              }
              return JSON.stringify({before, at, total, key: pet.key});
            })()
            """) as? String
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(out).utf8)) as? [String: Any])
                .compactMapValues { $0 as? Int ?? ($0 as? String == to ? 1 : nil) }
        }
        let gold = try await run("magnamon", golden: true)
        XCTAssertGreaterThan(gold["before"] ?? 0, 0, "gold twinkles while it flickers: \(gold)")
        XCTAssertEqual(gold["at"], 14, "a gold burst at the change: \(gold)")
        XCTAssertEqual(gold["key"], 1, "it became Magnamon")
        XCTAssertLessThan(gold["total"] ?? 0, 40, "kept modest: \(gold)")
        let plain = try await run("fladramon", golden: false)
        XCTAssertEqual(plain["total"], 0, "no gold for a plain armor evolution: \(plain)")
        XCTAssertEqual(plain["key"], 1)
    }
}
