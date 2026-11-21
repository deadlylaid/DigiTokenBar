import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Digimental fragments (step 13): golden bugs, visitors' gifts, the stamp card's pick and surprise
/// points, three of a kind making a Digimental. Seeded like the day's luck: never by usage.
final class DigimentalLoopTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private var engine: EvolutionEngine { EvolutionEngine(calendar: calendar) }

    private func date(day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))!
    }

    private func state(player: String = "p1") -> DigimonState {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = "agumon"
        s.partner.level = .child
        s.playerID = player
        s.dex = Set(DigimonCatalog.mvp.lines["agumon"]!.members)
        return s
    }

    /// Fragments of a kind counting the ones already turned into Digimentals.
    private func units(_ s: DigimonState, _ d: Digimental) -> Int {
        let bag = s.digimentals ?? DigimentalBag()
        return bag.fragments(d) + DigimentalRules.fragmentsPerDigimental * bag.owned(d)
    }

    private func isFragment(_ e: DigimonEvent, from source: FragmentSource) -> Bool {
        if case .fragmentFound(_, source) = e { return true } else { return false }
    }

    func testThreeFragmentsOfAKindMakeADigimental() {
        var s = state()
        XCTAssertEqual(engine.giveFragment(&s, .courage, from: .surprise), [.fragmentFound(.courage, from: .surprise)])
        engine.giveFragment(&s, .courage, from: .goldenBug)
        engine.giveFragment(&s, .hope, from: .goldenBug)
        XCTAssertEqual(s.digimentals?.fragments(.courage), 2)
        XCTAssertEqual(s.digimentals?.owned(.courage), 0)
        XCTAssertEqual(engine.giveFragment(&s, .courage, from: .visitor),
                       [.fragmentFound(.courage, from: .visitor), .digimentalMade(.courage)])
        XCTAssertEqual(s.digimentals?.owned(.courage), 1)
        XCTAssertEqual(s.digimentals?.fragments(.courage), 0)
        XCTAssertEqual(s.digimentals?.fragments(.hope), 1, "other kinds are not touched")
        XCTAssertEqual(s.digimentals?.ownedTotal, 1)
        XCTAssertEqual(s.digimentals?.fragmentTotal, 1)
    }

    func testGoldenBugsAreOneInAHundredTwiceOnABugSwarmDayAndPayThreeADay() {
        XCTAssertEqual(DigimentalRules.goldenBugChance(.clear), 0.01)
        XCTAssertEqual(DigimentalRules.goldenBugChance(nil), 0.01)
        XCTAssertEqual(DigimentalRules.goldenBugChance(.bugSwarm), 0.02)
        var s = state()
        for i in 1...DigimentalRules.goldenPerDay {
            let events = engine.recordGoldenBug(&s, at: date(day: 3, hour: 9 + i))
            XCTAssertTrue(events.first.map { isFragment($0, from: .goldenBug) } ?? false, "\(events)")
        }
        XCTAssertEqual(engine.recordGoldenBug(&s, at: date(day: 3, hour: 20)), [], "two open scenes cannot pay more than 3 a day")
        XCTAssertEqual(Digimental.allCases.reduce(0) { $0 + units(s, $1) }, DigimentalRules.goldenPerDay)
        XCTAssertFalse(engine.recordGoldenBug(&s, at: date(day: 4)).isEmpty, "a new day pays again")
    }

    func testFragmentKindsAreSeededAndThePartnersComeMoreOften() {
        var a = state(), b = state()
        engine.recordGoldenBug(&a, at: date(day: 5))
        engine.recordGoldenBug(&b, at: date(day: 5, hour: 18))
        XCTAssertEqual(a.digimentals?.fragments, b.digimentals?.fragments, "the same player and day give the same kind")
        var other = state(player: "p2")
        let mine = (1...20).map { day -> [String: Int] in var s = state(); engine.recordGoldenBug(&s, at: date(day: day)); return s.digimentals!.fragments }
        let theirs = (1...20).map { day -> [String: Int] in other = state(player: "p2"); engine.recordGoldenBug(&other, at: date(day: day)); return other.digimentals!.fragments }
        XCTAssertNotEqual(mine, theirs)

        var rng = SeededGenerator(seed: 42)
        let draws = 13_000
        var preferred = 0, plain = 0
        for _ in 0..<draws {
            if engine.drawFragment(kinds: Digimental.allCases, preferred: [.courage], rng: &rng) == .courage { preferred += 1 }
            if engine.drawFragment(kinds: Digimental.allCases, preferred: [], rng: &rng) == .courage { plain += 1 }
        }
        let weight = Double(DigimentalRules.preferredWeight)
        XCTAssertEqual(Double(preferred) / Double(draws), weight / (weight + 10), accuracy: 0.02, "a usable kind three times as often")
        XCTAssertEqual(Double(plain) / Double(draws), 1.0 / 11, accuracy: 0.015)
        XCTAssertEqual(engine.fragmentKinds(), Digimental.allCases, "every kind until the armor data narrows it")
    }

    func testOneVisitInTenLeavesAFragmentAndANewFaceAlwaysDoes() throws {
        let s = state()
        let trials = 4000
        let gifts = (0..<trials).filter { engine.visitGift(s, species: "greymon", day: "day-\($0)", firstSeen: false) != nil }.count
        XCTAssertEqual(Double(gifts) / Double(trials), 0.1, accuracy: 0.015)
        for i in 0..<300 {
            XCTAssertNotNil(engine.visitGift(s, species: "species\(i)", day: "2026-12-01", firstSeen: true), "a new face always leaves one")
        }
        XCTAssertEqual(engine.visitGift(s, species: "greymon", day: "day-7", firstSeen: false),
                       engine.visitGift(s, species: "greymon", day: "day-7", firstSeen: false), "seeded, never rerolled")

        // End to end: an arriving visitor with a gift adds the fragment and keeps it on the visit; one
        // without a gift adds none.
        var found = false, plainSeen = false
        for p in 0..<300 where !(found && plainSeen) {
            var t = state(player: "q\(p)")
            engine.updateLuck(&t, at: date(day: 2, hour: 0))
            guard let visit = t.luck?.visits.first else { continue }
            let events = engine.updateLuck(&t, at: visit.at)
            if let gift = t.luck?.visits.first?.gift {
                found = true
                XCTAssertTrue(events.contains(.fragmentFound(gift, from: .visitor)))
                XCTAssertEqual(units(t, gift), 1)
            } else {
                plainSeen = true
                XCTAssertFalse(events.contains { isFragment($0, from: .visitor) })
                XCTAssertNil(t.digimentals)
            }
        }
        XCTAssertTrue(found, "no visitor left a gift in many days")
    }

    func testFiveSurprisePointsBuyAFragmentOfYourChoice() {
        var s = state()
        s.luck = LuckBook()
        s.luck?.surprise = 7
        XCTAssertEqual(engine.exchangeSurprise(&s, for: .light), [.fragmentFound(.light, from: .surprise)])
        XCTAssertEqual(s.luck?.surprise, 2, "the points are spent")
        XCTAssertEqual(s.digimentals?.fragments(.light), 1)
        let before = s
        XCTAssertEqual(engine.exchangeSurprise(&s, for: .light), [])
        XCTAssertEqual(s, before, "with fewer than five points nothing changes")
        var fresh = state()
        XCTAssertEqual(engine.exchangeSurprise(&fresh, for: .hope), [], "no luck book yet: no points")
    }

    func testAFullStampCardGivesOneFragmentToPick() {
        var s = state()
        for day in 1...LuckRules.stampCard {
            engine.addUsage(&s, tokens: 1_000, provider: "claude_code", at: date(day: day, hour: 7))
            engine.updateLuck(&s, at: date(day: day, hour: 7))
        }
        XCTAssertEqual(s.luck?.cardsCompleted, 1)
        XCTAssertEqual(s.digimentals?.stampRewards, 1)
        engine.updateLuck(&s, at: date(day: LuckRules.stampCard, hour: 8))
        XCTAssertEqual(s.digimentals?.stampRewards, 1, "refreshing the same day gives no second one")
        let hope = units(s, .hope)
        XCTAssertEqual(engine.claimStampReward(&s, .hope).first, .fragmentFound(.hope, from: .stampCard))
        XCTAssertEqual(units(s, .hope), hope + 1)
        XCTAssertEqual(s.digimentals?.stampRewards, 0)
        XCTAssertEqual(engine.claimStampReward(&s, .hope), [], "one fragment per card")
        XCTAssertEqual(units(s, .hope), hope + 1)
    }

    func testASaveFromBeforeFragmentsStillOpensAndAnUnknownKindIsKept() throws {
        let old = state()
        let json = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(json.contains("digimentals"))
        XCTAssertNil(try JSONDecoder().decode(DigimonState.self, from: Data(json.utf8)).digimentals)

        let bag = try JSONDecoder().decode(DigimentalBag.self, from: Data(#"{"fragments":{"courage":2,"zeal":5},"owned":{"zeal":1}}"#.utf8))
        XCTAssertEqual(bag.fragments(.courage), 2)
        XCTAssertEqual(bag.fragments["zeal"], 5, "a kind from a newer version is kept")
        XCTAssertEqual(bag.fragmentTotal, 2)
        XCTAssertEqual(bag.ownedTotal, 0)
        XCTAssertEqual(bag.stampRewards, 0)

        let visit = try JSONDecoder().decode(DigimonVisit.self, from: Data(#"{"species":"greymon","tier":"rare","at":0,"gift":"zeal"}"#.utf8))
        XCTAssertNil(visit.gift)
        XCTAssertEqual(visit.species, "greymon")
        let older = try JSONDecoder().decode(DigimonVisit.self, from: Data(#"{"species":"greymon","tier":"rare","at":0}"#.utf8))
        XCTAssertNil(older.gift)
    }

    func testAnImportedBagIsClampedAndCombined() throws {
        var s = state()
        var bag = DigimentalBag()
        bag.fragments = ["courage": 7, "hope": -4]
        bag.owned = ["courage": 5, "light": 1_000_000]
        bag.stampRewards = -2
        bag.goldenToday = 50
        s.digimentals = bag
        let clean = try XCTUnwrap(DigimonSaveIO.sanitized(s, catalog: engine.catalog, growth: engine.growth).digimentals)
        XCTAssertEqual(clean.owned(.courage), 7, "7 fragments are 2 more Digimentals and 1 fragment")
        XCTAssertEqual(clean.fragments(.courage), 1)
        XCTAssertEqual(clean.fragments(.hope), 0)
        XCTAssertEqual(clean.owned(.light), DigimentalRules.maxOwned)
        XCTAssertEqual(clean.stampRewards, 0)
        XCTAssertEqual(clean.goldenToday, DigimentalRules.goldenPerDay)
    }

    @MainActor
    func testTheStoreSavesFragmentsAndTellsTheAppWhenADigimentalIsMade() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimental-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.json")
        var s = state()
        s.luck = LuckBook()
        s.luck?.surprise = 16
        try JSONEncoder().encode(DigimonStore.Saved(digimon: s)).write(to: file)
        let now = date(day: 9)
        let store = DigimonStore(fileURL: file, engine: engine, clock: { now })
        var seen: [DigimonEvent] = []
        store.onActivity = { events, _ in seen += events }
        XCTAssertTrue(store.canExchangeSurprise)
        for _ in 0..<3 { XCTAssertTrue(store.exchangeSurprise(for: .courage)) }
        XCTAssertTrue(seen.contains(.digimentalMade(.courage)))
        XCTAssertEqual(store.surprisePoints, 1)
        XCTAssertFalse(store.canExchangeSurprise)
        XCTAssertFalse(store.exchangeSurprise(for: .courage))
        store.recordGoldenBug()
        XCTAssertTrue(seen.contains { isFragment($0, from: .goldenBug) })

        let reopened = DigimonStore(fileURL: file, engine: engine, clock: { now })
        XCTAssertEqual(reopened.digimentalBag.owned(.courage), 1, "saved")
        XCTAssertEqual(reopened.digimentalBag.fragmentTotal, 1)
        XCTAssertEqual(DigimonText(.ko).digimentalMadeTitle(.courage), "용기의 디지멘탈을 만들었어요!")
        XCTAssertEqual(DigimonText(.en).digimentalMadeTitle(.hope), "You made the Digimental of Hope!")
        XCTAssertEqual(reopened.fragmentChoices, Digimental.allCases)
    }
}

/// The golden bug and a visitor's gift in the real scene script.
@MainActor
final class DigimentalSceneTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    private func openScene(golden: Double) async throws -> (DigimonScene, NSWindow) {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        let uri = "data:image/png;base64," + png.base64EncodedString()
        scene.sprite(key: "agumon", dataURI: uri)
        scene.sprite(key: "greymon", dataURI: uri)
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko",
                     "golden": golden, "goldenText": "디지멘탈 조각!"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        _ = try await js(scene, "pet.bug = null; pet.bugIn = 1e9; true")
        return (scene, window)
    }

    func testBugsAreGoldenAsOftenAsTheAppSaysAndAGoldenOneIsReported() async throws {
        let (never, w1) = try await openScene(golden: 0)
        defer { w1.close() }
        let none = try await js(never, "(() => { let n = 0; for (let i = 0; i < 400; i++) { pet.spawnBug(); if (pet.bug.golden) n++; } pet.bug = null; return n; })()") as? Int
        XCTAssertEqual(none, 0)

        let (half, w2) = try await openScene(golden: 0.5)
        defer { w2.close() }
        let some = try await js(half, "(() => { let n = 0; for (let i = 0; i < 1200; i++) { pet.spawnBug(); if (pet.bug.golden) n++; } pet.bug = null; return n; })()") as? Int ?? 0
        // Big bugs (1 in 6) are never golden: 1200 * 5/6 * 0.5 = 500.
        XCTAssertEqual(Double(some), 500, accuracy: 70)

        let (always, w3) = try await openScene(golden: 1)
        defer { w3.close() }
        var goldens = 0, bugs = 0
        always.onGoldenBug = { goldens += 1 }
        always.onBugDefeated = { bugs += $0 }
        let seen = try await js(always, """
        (() => {
          pet.spawnBug(); pet.bug.big = false; pet.bug.sc = 1; pet.bug.hp = 1; pet.bug.golden = true;
          const callouts = [];
          for (let i = 0; i < 1500 && pet.bug; i++) {
            pet.update(33); pet.draw();
            if (pet.callout && !callouts.includes(pet.callout.text)) callouts.push(pet.callout.text);
          }
          return JSON.stringify({callouts, left: !!pet.bug});
        })()
        """) as? String
        try await Task.sleep(for: .milliseconds(400))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
        XCTAssertEqual(result["left"] as? Bool, false, "the pet caught the bug")
        XCTAssertEqual(goldens, 1, "the app hears about the golden bug once")
        XCTAssertEqual(bugs, 1)
        XCTAssertTrue((result["callouts"] as? [String] ?? []).contains("디지멘탈 조각!"))
    }

    func testAVisitorWithAGiftLeavesItAndThePetSaysSo() async throws {
        let (scene, window) = try await openScene(golden: 0)
        defer { window.close() }
        func walk(gift: Bool) async throws -> [String] {
            scene.command(["type": "visit", "visitor": "greymon", "tier": "common", "greet": "그레이몬 왔다!",
                           "gift": gift, "giftText": "선물이다!"])
            try await Task.sleep(for: .milliseconds(300))
            let seen = try await js(scene, """
            (() => {
              const callouts = []; let started = false;
              for (let i = 0; i < 900; i++) {
                pet.update(33); pet.draw();
                if (pet.guest) started = true;
                if (pet.callout && !callouts.includes(pet.callout.text)) callouts.push(pet.callout.text);
                if (started && !pet.guest) break;
              }
              return JSON.stringify(callouts);
            })()
            """) as? String
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String])
        }
        let with = try await walk(gift: true)
        XCTAssertTrue(with.contains("그레이몬 왔다!"))
        XCTAssertTrue(with.contains("선물이다!"), "\(with)")
        let without = try await walk(gift: false)
        XCTAssertFalse(without.contains("선물이다!"), "\(without)")
    }
}
