import XCTest
@testable import PokeTokenBar

final class DigimonBattleTests: XCTestCase {
    private let catalog = DigimonCatalog.mvp
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    private func fighter(_ species: String, player: String = "p1", training: Int = 50, nonce: UInt64 = 1) -> BattleFighter {
        BattleFighter(player: player, species: species, level: catalog.species(species)!.level, training: training,
                      stage: 1_793_000_000, day: "2026-11-13", nonce: nonce, issuedAt: now)
    }

    // MARK: Battle

    func testBothSidesSeeTheSameBattle() {
        for nonce in UInt64(1)...30 {
            let a = fighter("greymon", player: "alice", nonce: nonce), b = fighter("garurumon", player: "bob", nonce: nonce &* 7)
            let left = DigimonBattle.fight(me: a, foe: b, catalog: catalog)
            let right = DigimonBattle.fight(me: b, foe: a, catalog: catalog)
            XCTAssertEqual(left.won, !right.won, "exactly one side wins")
            XCTAssertEqual(left.rounds.map { ($0.attacker == .me, $0.hit) }.map(\.1), right.rounds.map(\.hit))
            XCTAssertEqual(left.rounds.map { $0.attacker == .me }, right.rounds.map { $0.attacker == .foe })
            XCTAssertEqual(left, DigimonBattle.fight(me: a, foe: b, catalog: catalog), "the same codes, the same battle")
        }
    }

    func testABattleEndsAtThreeHitsOrTwelveAttacks() {
        for nonce in UInt64(1)...50 {
            let r = DigimonBattle.fight(me: fighter("agumon", nonce: nonce), foe: fighter("gabumon", player: "p2", nonce: nonce), catalog: catalog)
            XCTAssertTrue(max(r.myHits, r.foeHits) == 3 || r.rounds.count == 12)
            XCTAssertLessThanOrEqual(r.rounds.count, 12)
            if r.myHits != r.foeHits { XCTAssertEqual(r.won, r.myHits > r.foeHits) }
        }
    }

    func testLevelTrainingAndAttributesDecideTheOdds() {
        func wins(_ me: String, _ foe: String, training: (Int, Int) = (50, 50)) -> Int {
            (UInt64(1)...200).filter { n in
                DigimonBattle.fight(me: fighter(me, player: "a", training: training.0, nonce: n),
                                    foe: fighter(foe, player: "b", training: training.1, nonce: n), catalog: catalog).won
            }.count
        }
        XCTAssertGreaterThan(wins("metalgreymon", "greymon"), 140, "a Perfect usually beats an Adult")
        XCTAssertGreaterThan(wins("agumon", "agumon", training: (100, 0)), wins("agumon", "agumon", training: (0, 100)))
        // Vaccine beats Virus: Greymon (Vaccine) against a Virus Adult of the same training.
        let virus = catalog.species.values.first { $0.level == .adult && $0.attribute == .virus }!.key
        XCTAssertEqual(catalog.species("greymon")?.attribute, .vaccine)
        XCTAssertGreaterThan(wins("greymon", virus), 100)
        XCTAssertEqual(DigimonBattle.multiplier(.virus, against: .data), 1.3)
        XCTAssertEqual(DigimonBattle.multiplier(.data, against: .vaccine), 1.3)
        XCTAssertEqual(DigimonBattle.multiplier(.vaccine, against: .data), 1)
    }

    func testAWildFoeIsAnotherDigimonOfTheSameLevel() {
        var rng = SeededGenerator(seed: 7)
        let me = fighter("greymon")
        for _ in 0..<20 {
            let foe = DigimonBattle.wildFoe(for: me, catalog: catalog, rng: &rng, at: now)
            XCTAssertEqual(foe.level, .adult)
            XCTAssertNotEqual(foe.species, "greymon")
            XCTAssertTrue((20...80).contains(foe.training))
            XCTAssertEqual(foe.player, "wild")
        }
    }

    // MARK: Codes

    func testACodeRoundTripsAndSurvivesTextAroundIt() throws {
        let f = fighter("wargreymon", player: "4F1C2A", training: 77, nonce: 123_456_789)
        let code = BattleCode.encode(f)
        XCTAssertTrue(code.hasPrefix("DTB1."))
        XCTAssertLessThan(code.count, 260, "short enough for a chat message")
        XCTAssertEqual(try BattleCode.decode(code, catalog: catalog, now: now), f)
        XCTAssertEqual(try BattleCode.decode("배틀하자!\n\(code)\n고고", catalog: catalog, now: now), f)
    }

    func testADamagedOrForeignCodeIsRefused() {
        let code = BattleCode.encode(fighter("greymon"))
        XCTAssertThrowsError(try BattleCode.decode("hello", catalog: catalog, now: now)) { XCTAssertEqual($0 as? BattleCodeError, .notACode) }
        var damaged = Array(code)
        damaged[10] = damaged[10] == "A" ? "B" : "A"
        XCTAssertThrowsError(try BattleCode.decode(String(damaged), catalog: catalog, now: now)) {
            XCTAssertEqual($0 as? BattleCodeError, .damaged)
        }
    }

    func testACodeIsCheckedAgainstTheCatalog() {
        var wrong = fighter("greymon")
        wrong.level = .ultimate   // Greymon is an Adult
        XCTAssertThrowsError(try BattleCode.decode(BattleCode.encode(wrong), catalog: catalog, now: now)) {
            XCTAssertEqual($0 as? BattleCodeError, .unknownDigimon)
        }
        var unknown = fighter("greymon")
        unknown.species = "notadigimon"
        XCTAssertThrowsError(try BattleCode.decode(BattleCode.encode(unknown), catalog: catalog, now: now)) {
            XCTAssertEqual($0 as? BattleCodeError, .unknownDigimon)
        }
        var strong = fighter("greymon")
        strong.training = 10_000
        XCTAssertEqual(try BattleCode.decode(BattleCode.encode(strong), catalog: catalog, now: now).training, 100, "clamped")
    }

    func testAnOldCodeExpires() {
        let code = BattleCode.encode(fighter("greymon"))
        XCTAssertNoThrow(try BattleCode.decode(code, catalog: catalog, now: now.addingTimeInterval(6 * 24 * 3600)))
        XCTAssertThrowsError(try BattleCode.decode(code, catalog: catalog, now: now.addingTimeInterval(8 * 24 * 3600))) {
            XCTAssertEqual($0 as? BattleCodeError, .expired)
        }
        XCTAssertThrowsError(try BattleCode.decode(code, catalog: catalog, now: now.addingTimeInterval(-2 * 24 * 3600))) {
            XCTAssertEqual($0 as? BattleCodeError, .expired, "dated in the future")
        }
    }
}

/// Battles in the engine: what they record and the limits around them.
final class DigimonBattleEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private lazy var engine = EvolutionEngine(calendar: calendar)

    private func date(day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func partner(_ key: String, player: String) -> DigimonState {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = key
        s.partner.level = DigimonCatalog.mvp.species(key)!.level
        s.partner.stageStartedAt = date(day: 10, hour: 0)
        s.playerID = player
        return s
    }

    func testMyCodeStaysTheSameWithinADayAndAStage() throws {
        var s = partner("greymon", player: "alice")
        let first = try XCTUnwrap(engine.myFighter(&s, at: date(day: 12, hour: 9)))
        s.partner.stageSignals.battles = 10   // training changes later in the day...
        XCTAssertEqual(engine.myFighter(&s, at: date(day: 12, hour: 20)), first, "...but the code does not")
        XCTAssertNotEqual(engine.myFighter(&s, at: date(day: 13))?.nonce, first.nonce, "a new day, a new code")
        var egg = DigimonState.newEgg(lineID: "agumon")
        XCTAssertNil(engine.myFighter(&egg, at: date(day: 12)), "an egg does not battle")
    }

    func testAPlayerNumberIsMadeOnFirstUse() throws {
        var s = partner("greymon", player: "x")
        s.playerID = nil
        let f = try XCTUnwrap(engine.myFighter(&s, at: date(day: 12)))
        XCTAssertEqual(f.player.count, 12)
        XCTAssertEqual(s.playerID, f.player)
    }

    func testPracticeCountsOnceAndStopsAtFiveADay() {
        var s = partner("greymon", player: "alice")
        var rng = SeededGenerator(seed: 1)
        var wins = 0
        for i in 0..<5 {
            let r = engine.practiceBattle(&s, at: date(day: 12, hour: 9 + i), rng: &rng)
            XCTAssertNotNil(r)
            if r?.result.won == true { wins += 1 }
        }
        XCTAssertNil(engine.practiceBattle(&s, at: date(day: 12, hour: 20), rng: &rng), "five a day")
        XCTAssertEqual(s.partner.stageSignals.battles, 5)
        XCTAssertEqual(s.partner.stageSignals.battleWins, wins)
        XCTAssertEqual(s.lifetimeSignals.battles, 5)
        XCTAssertEqual(engine.practiceLeft(s, at: date(day: 12)), 0)
        XCTAssertEqual(engine.practiceLeft(s, at: date(day: 13)), 5)
        XCTAssertNotNil(engine.practiceBattle(&s, at: date(day: 13), rng: &rng), "a new day")
    }

    func testTwoUsersRecordTheSameBattleFromBothSides() throws {
        var alice = partner("greymon", player: "alice"), bob = partner("garurumon", player: "bob")
        let aliceCode = BattleCode.encode(try XCTUnwrap(engine.myFighter(&alice, at: date(day: 12))))
        let bobCode = BattleCode.encode(try XCTUnwrap(engine.myFighter(&bob, at: date(day: 12))))
        let a = try engine.codeBattle(&alice, code: bobCode, at: date(day: 12, hour: 15))
        let b = try engine.codeBattle(&bob, code: aliceCode, at: date(day: 12, hour: 18))
        XCTAssertEqual(a.result.won, !b.result.won)
        XCTAssertEqual(a.result.rounds.count, b.result.rounds.count)
        XCTAssertEqual(alice.partner.stageSignals.battles, 3, "a battle with another user counts three")
        XCTAssertEqual(alice.partner.stageSignals.battleWins + bob.partner.stageSignals.battleWins, 3)
    }

    func testACodeCountsOnceAndYourOwnDoesNotCount() throws {
        var alice = partner("greymon", player: "alice"), bob = partner("garurumon", player: "bob")
        let bobCode = BattleCode.encode(try XCTUnwrap(engine.myFighter(&bob, at: date(day: 12))))
        _ = try engine.codeBattle(&alice, code: bobCode, at: date(day: 12))
        XCTAssertThrowsError(try engine.codeBattle(&alice, code: bobCode, at: date(day: 12, hour: 16))) {
            XCTAssertEqual($0 as? BattleCodeError, .alreadyFought)
        }
        XCTAssertEqual(alice.partner.stageSignals.battles, 3)
        let own = BattleCode.encode(try XCTUnwrap(engine.myFighter(&alice, at: date(day: 12))))
        XCTAssertThrowsError(try engine.codeBattle(&alice, code: own, at: date(day: 12))) {
            XCTAssertEqual($0 as? BattleCodeError, .ownCode)
        }
    }

    func testOldSavesWithoutBattlesDecode() throws {
        var s = partner("greymon", player: "alice")
        s.playerID = nil
        s.battleBook = nil
        let data = try JSONEncoder().encode(s)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "playerID"); json.removeValue(forKey: "battleBook")
        var partner = try XCTUnwrap(json["partner"] as? [String: Any])
        var signals = try XCTUnwrap(partner["stageSignals"] as? [String: Any])
        signals.removeValue(forKey: "battles"); signals.removeValue(forKey: "battleWins")
        partner["stageSignals"] = signals; json["partner"] = partner
        let old = try JSONDecoder().decode(DigimonState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.partner.stageSignals.battles, 0)
        XCTAssertNil(old.battleBook)
    }
}
