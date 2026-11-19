import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// The day's fortune, visitors and the stamp card (step 12). Luck is seeded by the player and the
/// day only: never by usage, never rerolled.
final class DigimonLuckTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private var engine: EvolutionEngine { EvolutionEngine(calendar: calendar) }

    private func date(day: Int, hour: Int = 8, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour, minute: minute))!
    }

    private func state(player: String = "p1", at key: String = "agumon") -> DigimonState {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = key
        s.partner.level = DigimonCatalog.mvp.species(key)!.level
        s.playerID = player
        return s
    }

    /// The first day (from day 1) whose fortune is `fortune` for this player.
    private func day(with fortune: DigimonFortune, player: String = "p1") -> Int {
        for day in 1...28 {
            var s = state(player: player)
            engine.updateLuck(&s, at: date(day: day))
            if s.luck?.fortune == fortune { return day }
        }
        XCTFail("no \(fortune) day in four weeks")
        return 1
    }

    func testTheDayIsTheSameForTheSamePlayerAndDayWhateverTheUsage() {
        var light = state(), heavy = state()
        heavy.lifetimeSignals.tokens = 900_000_000
        heavy.partner.stageExp = 40
        engine.updateLuck(&light, at: date(day: 3))
        engine.updateLuck(&heavy, at: date(day: 3, hour: 7))
        XCTAssertEqual(light.luck?.fortune, heavy.luck?.fortune)
        XCTAssertEqual(light.luck?.visits.map(\.species), heavy.luck?.visits.map(\.species), "usage never changes the luck")
        XCTAssertEqual(light.luck?.visits.map(\.at), heavy.luck?.visits.map(\.at))
        // Another player gets other days.
        let mine = (1...14).map { d -> String in var s = state(); engine.updateLuck(&s, at: date(day: d)); return s.luck!.visits[0].species }
        let theirs = (1...14).map { d -> String in var s = state(player: "p2"); engine.updateLuck(&s, at: date(day: d)); return s.luck!.visits[0].species }
        XCTAssertNotEqual(mine, theirs)
    }

    func testRestoringABackupRollsTheSameDayAgain() throws {
        let before = state()
        var first = before
        engine.updateLuck(&first, at: date(day: 5, hour: 9))
        var restored = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(before))
        engine.updateLuck(&restored, at: date(day: 5, hour: 11))
        XCTAssertEqual(restored.luck?.fortune, first.luck?.fortune)
        XCTAssertEqual(restored.luck?.visits.map(\.species), first.luck?.visits.map(\.species))
        // Later the same day nothing is rolled again.
        let rolled = first.luck
        engine.updateLuck(&first, at: date(day: 5, hour: 23))
        XCTAssertEqual(first.luck?.fortune, rolled?.fortune)
        XCTAssertEqual(first.luck?.visits.map(\.species), rolled?.visits.map(\.species))
    }

    func testAVisitorArrivesAtItsTimeOnceAndIsMet() throws {
        var s = state()
        XCTAssertEqual(engine.updateLuck(&s, at: date(day: 2, hour: 0, minute: 30)), [], "visits come from 9:00")
        let visit = try XCTUnwrap(s.luck?.visits.first)
        XCTAssertTrue(LuckRules.visitHours.contains(calendar.component(.hour, from: visit.at)))
        XCTAssertEqual(engine.updateLuck(&s, at: visit.at.addingTimeInterval(-1)), [])
        XCTAssertNil(s.sightings)
        XCTAssertEqual(engine.updateLuck(&s, at: visit.at), [.visited(species: visit.species, tier: visit.tier, firstSeen: true)])
        XCTAssertEqual(s.sightings, [visit.species], "a visitor is met (the dex shows it)")
        XCTAssertEqual(engine.updateLuck(&s, at: visit.at.addingTimeInterval(60)), [], "it comes once")
        XCTAssertNotEqual(visit.species, s.partner.speciesKey, "never the partner itself")
    }

    func testAStampPerCodingDayAndAFullCardBringsAVeryRareVisitorAtOnce() throws {
        var s = state()
        s.dex = Set(["greymon", "garurumon", "tyranomon", "metalgreymon", "wargreymon", "andromon"])
        engine.updateLuck(&s, at: date(day: 1))
        XCTAssertEqual(s.luck?.stamps, 0, "no stamp before coding")
        for day in 1...6 {
            engine.addUsage(&s, tokens: 1_000, provider: "claude_code", at: date(day: day, hour: 7))
            engine.updateLuck(&s, at: date(day: day, hour: 7))
            engine.updateLuck(&s, at: date(day: day, hour: 7, minute: 30))
            XCTAssertEqual(s.luck?.stamps, day, "one stamp per coding day, however often it refreshes")
        }
        engine.updateLuck(&s, at: date(day: 8, hour: 7))
        XCTAssertEqual(s.luck?.stamps, 6, "a day without coding gives none and takes none")
        engine.addUsage(&s, tokens: 1_000, provider: "claude_code", at: date(day: 9, hour: 7))
        let events = engine.updateLuck(&s, at: date(day: 9, hour: 7))
        XCTAssertEqual(events.first, .stampCardFull)
        guard case .visited(let species, let tier, let firstSeen)? = events.last else { return XCTFail("\(events)") }
        XCTAssertGreaterThanOrEqual(tier, .veryRare)
        XCTAssertTrue(firstSeen, "the card's visitor is always one never seen")
        XCTAssertFalse(s.dex.contains(species))
        XCTAssertTrue(s.sightings?.contains(species) ?? false)
        XCTAssertEqual(s.luck?.stamps, 0, "the card starts again")
        XCTAssertEqual(s.luck?.cardsCompleted, 1)
        XCTAssertEqual(s.luck?.visits.last?.special, true)
    }

    func testEachFortuneDoesWhatItSays() {
        var busy = state()
        engine.updateLuck(&busy, at: date(day: day(with: .busy)))
        XCTAssertEqual(busy.luck?.visits.count, 2, "a busy day brings two visitors")
        XCTAssertNotEqual(busy.luck?.visits[0].species, busy.luck?.visits[1].species)

        var meteor = state()
        engine.updateLuck(&meteor, at: date(day: day(with: .meteor)))
        XCTAssertGreaterThanOrEqual(meteor.luck?.visits.first?.tier ?? .common, .rare, "a meteor shower brings a rare visitor")

        let fighting = day(with: .fighting)
        var s = state()
        engine.updateLuck(&s, at: date(day: fighting))
        let limit = engine.growth.practiceBattlesPerDay + LuckRules.extraPractice
        XCTAssertEqual(engine.practiceLimit(s, at: date(day: fighting, hour: 12)), limit)
        var rng = SeededGenerator(seed: 1)
        var fought = 0
        while engine.practiceBattle(&s, at: date(day: fighting, hour: 12), rng: &rng) != nil { fought += 1 }
        XCTAssertEqual(fought, limit, "two more practice battles on a day of fighting spirit")
        XCTAssertEqual(engine.practiceLimit(s, at: date(day: fighting + 1, hour: 12)), engine.growth.practiceBattlesPerDay,
                       "only that day")
    }

    /// Visitors are old faces (user's decision): 99% from the dex (raised or met), 1% never seen. A new
    /// user's dex is too small to repeat, so until it holds `minKnownVisitors` any Digimon comes.
    func testVisitorsComeFromTheDexAndOneInAHundredIsNew() {
        let common = DigimonCatalog.mvp.species.values.filter { engine.visitorTier(of: $0) == .common }.map(\.key).sorted()
        var s = state()
        s.dex = Set(common.prefix(20))
        s.sightings = ["wargreymon"]
        var rng = SeededGenerator(seed: 42)
        let draws = (0..<6_000).compactMap { _ in engine.visitor(LuckRules.tiers, state: s, excluding: [], rng: &rng) }
        let met = s.dex.union(s.sightings!)
        let new = Double(draws.filter { !met.contains($0.species) }.count) / Double(draws.count)
        XCTAssertGreaterThan(new, 0.006, "about one in a hundred is never seen")
        XCTAssertLessThan(new, 0.015)
        XCTAssertTrue(draws.contains { $0.species == "wargreymon" }, "a Digimon met as a visitor comes again")

        var newUser = state()
        newUser.dex = ["greymon", "garurumon"]
        let early = (0..<500).compactMap { _ in engine.visitor(LuckRules.tiers, state: newUser, excluding: [], rng: &rng) }
        XCTAssertGreaterThan(early.filter { !newUser.dex.contains($0.species) }.count, 400, "a small dex: anyone comes")

        let fresh = (0..<200).compactMap { _ in engine.visitor(LuckRules.specialTiers, state: s, excluding: [], neverSeen: true, rng: &rng) }
        XCTAssertTrue(fresh.allSatisfy { !met.contains($0.species) && $0.tier >= .veryRare }, "the stamp card's visitor")
    }

    /// Surprise points (user's rules): +1 for a visitor at a higher stage than the partner or two or more
    /// lower, +10 for one never seen. They add up in the book and are kept per visit.
    func testSurprisePointsForFarStagesAndNewFaces() throws {
        XCTAssertEqual(engine.surprisePoints("wargreymon", partner: .child, firstSeen: false), 1, "higher")
        XCTAssertEqual(engine.surprisePoints("greymon", partner: .child, firstSeen: false), 1, "one higher is higher")
        XCTAssertEqual(engine.surprisePoints("gabumon", partner: .child, firstSeen: false), 0, "the same stage")
        XCTAssertEqual(engine.surprisePoints("greymon", partner: .ultimate, firstSeen: false), 1, "two lower")
        XCTAssertEqual(engine.surprisePoints("metalgreymon", partner: .ultimate, firstSeen: false), 0, "one lower")
        XCTAssertEqual(engine.surprisePoints("gabumon", partner: .child, firstSeen: true), 10)
        XCTAssertEqual(engine.surprisePoints("wargreymon", partner: .child, firstSeen: true), 11)
        XCTAssertEqual(engine.surprisePoints("gabumon", partner: .digitama, firstSeen: false), 1, "an egg is the lowest")

        var s = state()   // Agumon, a Child, with nothing raised or met: the first visitor is new
        engine.updateLuck(&s, at: date(day: 7, hour: 8))
        let visit = try XCTUnwrap(s.luck?.visits.first)
        engine.updateLuck(&s, at: visit.at)
        let arrived = try XCTUnwrap(s.luck?.visits.first)
        let stage = DigimonCatalog.mvp.species(visit.species)!.level.order
        let far = stage > DigimonLevel.child.order || stage <= DigimonLevel.child.order - 2
        XCTAssertTrue(arrived.firstSeen)
        XCTAssertEqual(arrived.points, 10 + (far ? 1 : 0))
        XCTAssertEqual(s.luck?.surprise, arrived.points)
    }

    func testTiersAndHowOftenTheyCome() {
        let catalog = DigimonCatalog.mvp
        XCTAssertEqual(engine.visitorTier(of: catalog.species("omegamon")!), .legendary, "growth never reaches it")
        XCTAssertEqual(engine.visitorTier(of: catalog.species("wargreymon")!), .veryRare)
        XCTAssertEqual(engine.visitorTier(of: catalog.species("metalgreymon")!), .rare)
        XCTAssertEqual(engine.visitorTier(of: catalog.species("greymon")!), .common)
        XCTAssertNil(engine.visitorTier(of: catalog.species("koromon")!), "babies stay home")
        var counts: [VisitorTier: Int] = [:]
        for day in 0..<730 {
            var s = state(player: "p\(day % 7)")
            engine.updateLuck(&s, at: date(day: 1).addingTimeInterval(TimeInterval(day) * 86_400))
            for visit in s.luck?.visits ?? [] { counts[visit.tier, default: 0] += 1 }
        }
        let total = counts.values.reduce(0, +)
        XCTAssertGreaterThan(counts[.common] ?? 0, total / 2, "most visitors are common")
        XCTAssertGreaterThan(counts[.legendary] ?? 0, 0, "a legendary one does come")
        XCTAssertLessThan(Double(counts[.legendary] ?? 0) / Double(total), 0.04)
    }

    func testASaveFromBeforeLuckAndOneFromANewerVersionStillOpen() throws {
        var s = state()
        engine.updateLuck(&s, at: date(day: 4, hour: 22))
        var json = try XCTUnwrap(String(data: JSONEncoder().encode(s), encoding: .utf8))
        let fortune = s.luck!.fortune.rawValue, tier = s.luck!.visits[0].tier.rawValue
        json = json.replacingOccurrences(of: "\"fortune\":\"\(fortune)\"", with: "\"fortune\":\"aurora\"")
            .replacingOccurrences(of: "\"tier\":\"\(tier)\"", with: "\"tier\":\"mythic\"")
        let newer = try JSONDecoder().decode(DigimonState.self, from: Data(json.utf8))
        XCTAssertEqual(newer.luck?.fortune, .clear, "an unknown fortune reads as a clear day")
        XCTAssertEqual(newer.luck?.visits.first?.tier, .common)
        XCTAssertEqual(newer.luck?.visits.first?.species, s.luck?.visits.first?.species)

        let old = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(state()))
        XCTAssertNil(old.luck)
        XCTAssertNil(old.sightings)

        // A book written with fewer fields (another version) reads with the defaults.
        let partial = try JSONDecoder().decode(LuckBook.self, from: Data(#"{"fortune":"busy"}"#.utf8))
        XCTAssertEqual(partial.fortune, .busy)
        XCTAssertEqual([partial.day, partial.stampDay], ["", ""])
        XCTAssertEqual([partial.stamps, partial.cardsCompleted, partial.visits.count], [0, 0, 0])
        let visit = try JSONDecoder().decode(DigimonVisit.self, from: Data(#"{"species":"greymon","tier":"rare","at":0}"#.utf8))
        XCTAssertEqual([visit.arrived, visit.special, visit.firstSeen], [false, false, false])
        XCTAssertEqual([visit.points, partial.surprise], [0, 0])
    }

    func testAnImportedSaveIsClampedAndKeepsOnlyVisitorsThisCatalogKnows() throws {
        var s = state()
        engine.updateLuck(&s, at: date(day: 4))
        s.luck?.stamps = 99
        s.luck?.cardsCompleted = -3
        s.luck?.surprise = -7
        s.luck?.visits.append(DigimonVisit(species: "notadigimon", tier: .legendary, at: date(day: 4, hour: 12)))
        s.sightings = ["notadigimon", "greymon"]
        let clean = try DigimonSaveIO.sanitized(s, catalog: .mvp, growth: engine.growth)
        XCTAssertEqual(clean.luck?.stamps, LuckRules.stampCard - 1)
        XCTAssertEqual(clean.luck?.cardsCompleted, 0)
        XCTAssertEqual(clean.luck?.surprise, 0)
        XCTAssertFalse(clean.luck?.visits.contains { $0.species == "notadigimon" } ?? true)
        XCTAssertEqual(clean.sightings, ["notadigimon", "greymon"], "sightings are kept like the dex")
    }

    func testTheDexShowsAVisitorItMet() {
        var s = state()
        s.sightings = ["metalgreymon"]
        let rows = DigimonDex.rows(for: DigimonCatalog.mvp.lines["agumon"]!, state: s, catalog: .mvp, rules: .mvp)
        let entry = rows.flatMap(\.entries).first { $0.id == "metalgreymon" }
        XCTAssertEqual(entry?.sighted, true)
        XCTAssertEqual(entry?.seen, false, "met is not raised")
        let raised = rows.flatMap(\.entries).first { $0.id == "agumon" }
        XCTAssertEqual(raised?.sighted, false)
    }

    @MainActor
    func testTheStoreRollsTheDayOnARefreshAndTellsTheScene() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-luck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var now = date(day: 6, hour: 8)
        let store = DigimonStore(fileURL: dir.appendingPathComponent("s.json"), engine: engine, clock: { now })
        var events: [DigimonEvent] = []
        store.onActivity = { e, _ in events += e }
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d6", hasUsageData: true)
        XCTAssertNotNil(store.todayLuck)
        XCTAssertEqual(store.visitorsToday, [])
        let visit = try XCTUnwrap(store.todayLuck?.visits.first)
        now = visit.at.addingTimeInterval(1)
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d6", hasUsageData: true)
        XCTAssertTrue(events.contains { if case .visited(visit.species, visit.tier, _) = $0 { return true } else { return false } })
        XCTAssertEqual(store.visitorsToday.map(\.species), [visit.species])
        XCTAssertEqual(store.sightingsCount, store.state.dex.contains(visit.species) ? 0 : 1)
    }
}

/// A visitor walks through the real scene script: in, a hello, out.
@MainActor
final class DigimonSceneVisitTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    private func visit(sleeping: Bool) async throws -> [String: Any] {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        let uri = "data:image/png;base64," + png.base64EncodedString()
        scene.sprite(key: "agumon", dataURI: uri)
        scene.sprite(key: "greymon", dataURI: uri)
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": sleeping, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        _ = try await js(scene, "pet.bug = null; pet.bugIn = 1e9; pet.update = pet.update.bind(pet); true")
        scene.command(["type": "visit", "visitor": "greymon", "tier": "rare", "greet": "그레이몬 왔다!"])
        try await Task.sleep(for: .milliseconds(300))
        let seen = try await js(scene, """
        (() => {
          const phases = [], callouts = [];
          let gone = -1;
          for (let i = 0; i < 900 && gone < 0; i++) {
            pet.update(33); pet.draw();
            if (pet.guest && !phases.includes(pet.guest.phase)) phases.push(pet.guest.phase);
            if (pet.callout && !callouts.includes(pet.callout.text)) callouts.push(pet.callout.text);
            if (phases.length && !pet.guest) gone = i;
          }
          return JSON.stringify({phases, callouts, gone, state: pet.state});
        })()
        """) as? String
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
    }

    func testAVisitorWalksInSaysHelloAndLeaves() async throws {
        let result = try await visit(sleeping: false)
        XCTAssertEqual(result["phases"] as? [String], ["in", "greet", "out"])
        XCTAssertTrue((result["callouts"] as? [String] ?? []).contains("그레이몬 왔다!"), "the pet greets it")
        XCTAssertGreaterThan(result["gone"] as? Int ?? -1, 0, "it leaves again")
    }

    /// A visitor that came while no scene was showing walks in when the next scene opens, and only
    /// in that one: a later scene does not replay it. The scene opens before the pet's sprite is
    /// ready, so the visit may arrive before the pet exists.
    func testAVisitorThatCameWithNoSceneOpenWalksInWhenOneOpens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-visit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "5496E6"))
        let sprites = DigimonSpriteStore(directory: dir.appendingPathComponent("sprites"), fetch: { request in
            (png, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var now = calendar.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 8))!
        let store = DigimonStore(fileURL: dir.appendingPathComponent("s.json"), engine: EvolutionEngine(calendar: calendar),
                                 clock: { now })
        let hub = DigimonSceneHub(digimon: store, sprites: sprites)
        store.onActivity = { events, fed in hub.play(events, fed: fed > 0) }
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d3", hasUsageData: true)
        let visit = try XCTUnwrap(store.todayLuck?.visits.first)
        now = visit.at.addingTimeInterval(1)
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d3", hasUsageData: true)
        XCTAssertEqual(store.visitorsToday.map(\.species), [visit.species], "it came, with no scene showing")
        // Let the hub play the arrival first (it runs on its own queue): with no scene, nothing is shown.
        try await Task.sleep(for: .milliseconds(800))

        func open() async throws -> DigimonScene {
            let scene = DigimonScene(mode: .popover)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
            window.contentView = scene.webView
            window.orderFront(nil)
            hub.register(scene)
            return scene
        }
        func guest(_ scene: DigimonScene, within seconds: Double) async throws -> Bool {
            for _ in 0..<Int(seconds * 10) {
                try await Task.sleep(for: .milliseconds(100))
                let has = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && (!!pet.guest || pet.guests.length > 0)")) as? Bool
                if has == true { return true }
            }
            return false
        }
        let first = try await open()
        let shown = try await guest(first, within: 6)
        XCTAssertTrue(shown, "the visitor walks into the scene that opened")
        let second = try await open()
        let again = try await guest(second, within: 2)
        XCTAssertFalse(again, "and is not replayed in the next one")
        first.webView.window?.close()
        second.webView.window?.close()
    }

    func testAVisitorAlsoComesByWhileThePetSleeps() async throws {
        let result = try await visit(sleeping: true)
        XCTAssertEqual(result["phases"] as? [String], ["in", "greet", "out"])
        XCTAssertFalse((result["callouts"] as? [String] ?? []).contains("그레이몬 왔다!"), "a sleeping pet does not greet")
        XCTAssertEqual(result["state"] as? String, "sleep", "and it keeps sleeping")
    }
}
