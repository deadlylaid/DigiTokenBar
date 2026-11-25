import XCTest
@testable import PokeTokenBar

final class DigimonEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private lazy var engine = EvolutionEngine(calendar: calendar)
    /// The optional mode where the user picks among the candidates (tendency only, no card conditions).
    private lazy var choosingEngine: EvolutionEngine = {
        var growth = GrowthRules.standard
        growth.userPicksEvolution = true
        growth.cardConditions = false
        return EvolutionEngine(growth: growth, calendar: calendar)
    }()
    /// Tendency only: the card's requirements are left out (see DigimonCardConditionTests).
    private lazy var tendencyEngine: EvolutionEngine = {
        var growth = GrowthRules.standard
        growth.cardConditions = false
        return EvolutionEngine(growth: growth, calendar: calendar)
    }()

    private func date(day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// A partner already sitting at `key` (no experience in the stage yet).
    private func state(at key: String, line: String = "agumon") -> DigimonState {
        var s = DigimonState.newEgg(lineID: line)
        let species = DigimonCatalog.mvp.species(key)!
        s.partner.speciesKey = key
        s.partner.level = species.level
        s.partner.path = [key]
        return s
    }

    private func attribute(_ key: String) -> DigimonAttribute { DigimonCatalog.mvp.species(key)!.attribute }

    // MARK: Catalog

    func testCatalogHas40LinesOf636SpeciesWithLargeSprites() {
        let catalog = DigimonCatalog.mvp
        XCTAssertEqual(catalog.lines.count, 40)
        XCTAssertTrue(Set(["agumon", "gabumon", "piyomon", "tentomon", "vmon", "guilmon"]).isSubset(of: catalog.lines.keys),
                      "the first six lines stay")
        // 614, then 634 with the cards' 20 Armor Digimon (step 13), 636 with Peacockmon and Rhinomon.
        XCTAssertEqual(catalog.species.count, 636)
        for species in catalog.species.values {
            XCTAssertTrue(species.vbSprite.hasSuffix("_vpet_vb.png"), species.key)
        }
    }

    func testEveryNonUltimateMemberCanGrowWithoutHiddenOrLockedEvolutions() {
        let catalog = DigimonCatalog.mvp
        let rules = EvolutionRules.mvp
        for line in catalog.lines.values {
            for key in line.members {
                guard let species = catalog.species(key), species.level != .ultimate else { continue }
                // Hidden evolutions count: when one is the only way on, it opens without its condition.
                let open = catalog.nextEvolutions(from: key, in: line)
                    .filter { !rules.locked.contains($0.to) && !rules.isLocked($0.from, $0.to, in: line) }
                let reachedOnlyByMerge = !catalog.lines.values.contains { l in
                    l.members.contains { from in
                        catalog.nextEvolutions(from: from, in: l).contains {
                            $0.to == key && !rules.isLocked(from, key, in: l) && !rules.locked.contains(key)
                        }
                    }
                } && key != line.firstBaby
                if reachedOnlyByMerge || rules.locked.contains(key) { continue }
                XCTAssertFalse(open.isEmpty, "\(line.id): \(key) has no next evolution growth can take")
            }
        }
    }

    // MARK: Experience

    /// No daily cap since 2026-11-25 (issue #4): a big day counts in full. 300M tokens = 1,500 exp, ten
    /// times the old cap, like the thresholds.
    func testABigDayCountsInFull() {
        var s = DigimonState.newEgg(lineID: "agumon")
        let events = engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 1))
        XCTAssertEqual(s.expToday, 1_500)
        // 1,500 exp = egg 200 + baby I 400 + baby II 600, with 300 left over at Child.
        XCTAssertEqual(events, [.hatched(species: "botamon"),
                                .evolved(from: "botamon", to: "koromon"),
                                .evolved(from: "koromon", to: "agumon")])
        XCTAssertEqual(s.partner.speciesKey, "agumon")
        XCTAssertEqual(s.partner.stageExp, 300)
        // Twice as much the next day gives twice as much: nothing past a cap is dropped.
        engine.addUsage(&s, tokens: 600_000_000, provider: "claude_code", at: date(day: 2))
        XCTAssertEqual(s.expToday, 3_000)
    }

    func testEveryTokenCountsAndTheRemainderCarriesIntoTheNextDay() {
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 100_100_000, provider: "claude_code", at: date(day: 1))
        XCTAssertEqual(s.expToday, 500)
        XCTAssertEqual(s.tokenRemainder, 100_000)
        engine.addUsage(&s, tokens: 100_000, provider: "claude_code", at: date(day: 2))
        XCTAssertEqual(s.expToday, 1, "yesterday's leftover 100k and today's 100k make one point")
        XCTAssertEqual(s.tokenRemainder, 0)
    }

    func testSmallUsageAccumulatesUntilItIsWorthOnePoint() {
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 150_000, provider: "codex", at: date(day: 1))
        XCTAssertEqual(s.partner.stageExp, 0)
        engine.addUsage(&s, tokens: 50_000, provider: "codex", at: date(day: 1))
        XCTAssertEqual(s.partner.stageExp, 1)
    }

    func testGrowthMultiplierScalesThresholds() {
        var slow = GrowthRules.standard
        slow.growthMultiplier = 2
        XCTAssertEqual(slow.threshold(for: .child), 2_400)
        var fast = GrowthRules.standard
        fast.growthMultiplier = 0.1
        XCTAssertEqual(fast.threshold(for: .digitama), 20, "200 × 0.1 is 20, not 21 from a float rounding up")
    }

    /// The Settings speeds: threshold = base ÷ speed, rounded up, egg to graduation 10,200 at 1×.
    func testEachGrowthSpeedDividesTheThresholds() {
        let expected: [Double: [DigimonLevel: Int]] = [
            0.5: [.digitama: 400, .child: 2_400, .ultimate: 6_000],
            1: [.digitama: 200, .child: 1_200, .ultimate: 3_000],
            1.5: [.digitama: 134, .babyI: 267, .child: 800, .perfect: 1_867, .ultimate: 2_000],
            2: [.digitama: 100, .child: 600, .ultimate: 1_500],
            5: [.digitama: 40, .child: 240, .ultimate: 600],
        ]
        for (speed, levels) in expected {
            var rules = GrowthRules.standard
            rules.speed = speed
            for (level, threshold) in levels {
                XCTAssertEqual(rules.threshold(for: level), threshold, "\(speed)× \(level)")
            }
        }
        XCTAssertEqual(GrowthRules.standard.lifeThreshold, 10_200)
        // The fast-growth switch multiplies on top of the speed.
        var both = GrowthRules.standard
        both.speed = 2
        both.growthMultiplier = 0.1
        XCTAssertEqual(both.threshold(for: .child), 60)
        XCTAssertEqual(both.threshold(for: .digitama), 10)
    }

    func testDaysWithoutCodingChangeNothing() {
        var s = state(at: "greymon")
        s.partner.stageExp = 50
        let before = s
        let usage = engine.addUsage(&s, tokens: 0, provider: "claude_code", at: date(day: 3))
        let ticked = engine.tick(&s, now: date(day: 20))
        XCTAssertEqual(usage, [])
        XCTAssertEqual(ticked, [])
        XCTAssertEqual(s, before, "no usage never shrinks or resets the partner")
    }

    // MARK: Choosing an evolution

    /// The default, like a V-Pet: no choice, it evolves at once. Which of the open routes it takes is
    /// drawn by weight since step 14 (DigimonChanceEvolutionTests). This test used to expect the best
    /// match and passed only because this stage's draw happened to land on it (two other seeds failed).
    func testAFullStageEvolvesStraightWithoutAChoice() {
        let engine = tendencyEngine
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 1))
        let routes = engine.rankedOptions(for: s)   // Agumon's routes (card conditions are off here)
        let events = engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 2))
        XCTAssertEqual(events.count, 1, "\(events)")
        guard case let .evolved(from, to)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(from, "agumon")
        XCTAssertTrue(routes.contains(to), "\(to) is one of Agumon's routes \(routes)")
        XCTAssertNil(s.pendingChoice)
        XCTAssertFalse(events.contains { if case .choiceOffered = $0 { return true } else { return false } })
        XCTAssertEqual(s.partner.stageExp, 600, "300 left from day 1 + 1,500 - 1,200: what the stage did not need carries over")
    }

    func testAChoiceSavedBeforeChoosingWasTurnedOffResolvesAtOnce() {
        var s = state(at: "agumon")
        s.partner.stageExp = 120
        s.pendingChoice = PendingChoice(candidates: ["coelamon", "greymon"], offeredAt: date(day: 1, hour: 9))
        XCTAssertEqual(engine.tick(&s, now: date(day: 1, hour: 10)), [.evolved(from: "agumon", to: "coelamon")])
    }

    func testFullChildStageOffersUpToThreeCandidatesAndHoldsTheBar() {
        let engine = choosingEngine
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 1))
        let events = engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 2))
        guard case .choiceOffered(let candidates)? = events.last else { return XCTFail("no choice: \(events)") }
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(s.pendingChoice?.candidates, candidates)
        XCTAssertEqual(s.partner.stageExp, 1_200, "experience waits at the threshold instead of overflowing")
        engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 3))
        XCTAssertEqual(s.partner.stageExp, 1_200)
        XCTAssertEqual(s.partner.speciesKey, "agumon")
    }

    func testChoosingEvolvesRecordsTheDexAndRejectsOtherKeys() {
        let engine = choosingEngine
        var s = state(at: "agumon")
        s.partner.stageExp = 120
        s.pendingChoice = PendingChoice(candidates: ["greymon", "orgemon"], offeredAt: date(day: 1))
        let rejected = engine.choose(&s, "wargreymon", at: date(day: 1))
        XCTAssertEqual(rejected, [])
        XCTAssertNotNil(s.pendingChoice)
        let chosen = engine.choose(&s, "orgemon", at: date(day: 1))
        XCTAssertEqual(chosen, [.evolved(from: "agumon", to: "orgemon")])
        XCTAssertNil(s.pendingChoice)
        XCTAssertEqual(s.partner.level, .adult)
        XCTAssertTrue(s.dex.contains("orgemon"))
        XCTAssertTrue(s.discoveredEvolutions.contains("agumon>orgemon"))
    }

    func testTopCandidateIsPickedAutomaticallyAfter24Hours() {
        let engine = choosingEngine
        var s = state(at: "agumon")
        s.partner.stageExp = 120
        s.pendingChoice = PendingChoice(candidates: ["coelamon", "greymon"], offeredAt: date(day: 1, hour: 9))
        let early = engine.tick(&s, now: date(day: 2, hour: 8))
        XCTAssertEqual(early, [])
        let onTime = engine.tick(&s, now: date(day: 2, hour: 9))
        XCTAssertEqual(onTime, [.evolved(from: "agumon", to: "coelamon")])
    }

    // MARK: Conditions

    func testMoreNightThanUsualPullsTowardVirus() {
        var s = state(at: "agumon")
        s.lifetimeSignals = GrowthSignals(tokens: 1_000, nightTokens: 200)       // usually 20% at night
        s.partner.stageSignals = GrowthSignals(tokens: 1_000, nightTokens: 800)  // this stage: 80%
        let top = engine.candidates(for: s).first!
        XCTAssertEqual(attribute(top), .virus)
    }

    func testHabitualNightCoderIsNotForcedIntoVirus() {
        var s = state(at: "agumon")
        s.lifetimeSignals = GrowthSignals(tokens: 1_000, nightTokens: 450)       // 45% at night is normal here
        s.partner.stageSignals = GrowthSignals(tokens: 1_000, nightTokens: 450)
        XCTAssertNotEqual(attribute(engine.candidates(for: s).first!), .virus)
    }

    func testSteadyDaytimeUseWithinLimitsFavorsVaccine() {
        var s = state(at: "agumon")
        s.partner.stageSignals = GrowthSignals(tokens: 1_000, nightTokens: 0, activeDays: ["2026-11-01"])
        XCTAssertEqual(engine.candidates(for: s).first, "greymon")
    }

    func testFilledLimitsCountAsCareMistakes() {
        var s = state(at: "agumon")
        s.partner.stageSignals = GrowthSignals(tokens: 1_000, nightTokens: 0, activeDays: ["2026-11-01"])
        for _ in 0..<3 { engine.recordLimitHit(&s) }
        XCTAssertEqual(attribute(engine.candidates(for: s).first!), .virus)
        XCTAssertEqual(s.lifetimeSignals.limitHits, 3)
    }

    func testHiddenEvolutionAppearsOnlyOnceItsConditionIsMet() {
        var s = state(at: "metalgreymon")
        XCTAssertFalse(engine.candidates(for: s).contains("blitzgreymon"))
        for _ in 0..<20 { engine.recordBugDefeated(&s) }
        XCTAssertEqual(engine.candidates(for: s).first, "blitzgreymon")
    }

    func testLockedJogressResultIsNeverOfferedEvenWhenTheDataLinksIt() {
        // The MVP data has no Perfect -> Omegamon edge, so build one to exercise the lock itself.
        func sp(_ key: String, _ level: DigimonLevel) -> DigimonSpecies {
            DigimonSpecies(key: key, name: key, koreanName: key, level: level, attribute: .vaccine,
                           vbSprite: "\(key)_vpet_vb.png", colorSprite: "")
        }
        let catalog = DigimonCatalog(
            species: [sp("metalgreymon", .perfect), sp("wargreymon", .ultimate), sp("omegamon", .ultimate)],
            evolutions: [DigimonEvolution(from: "metalgreymon", to: "wargreymon", sources: [.vitalBracelet], canon: true),
                         DigimonEvolution(from: "metalgreymon", to: "omegamon", sources: [.vitalBracelet], canon: false)],
            lines: [DigimonLine(id: "t", card: "t", eggColorHex: "000000", firstBaby: "metalgreymon",
                                members: ["metalgreymon", "wargreymon", "omegamon"])])
        var s = DigimonState.newEgg(lineID: "t")
        s.partner.speciesKey = "metalgreymon"
        s.partner.level = .perfect
        let locked = EvolutionEngine(catalog: catalog, rules: .mvp, calendar: calendar)
        XCTAssertEqual(locked.candidates(for: s), ["wargreymon"])
        let unlocked = EvolutionEngine(catalog: catalog, rules: EvolutionRules(hidden: [:], locked: []), calendar: calendar)
        XCTAssertTrue(unlocked.candidates(for: s).contains("omegamon"), "the lock, not the data, is what hides it")
    }

    // MARK: Graduation and saving

    func testFinishingTheUltimateStageGraduatesIntoANewEgg() {
        var s = state(at: "wargreymon")
        s.partner.path = ["botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"]
        s.dex = Set(s.partner.path)
        s.partner.stageExp = 2_999
        let events = engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: 5))
        let offer = try? XCTUnwrap(s.eggOffer)
        XCTAssertEqual(events, [.graduated(lineID: "agumon",
                                           path: ["botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"]),
                                .newEgg(lineID: s.partner.lineID)])
        XCTAssertEqual(s.partner.lineID, offer?.first, "the egg shows the first drawn line")
        XCTAssertNil(s.partner.speciesKey)
        XCTAssertEqual(s.partner.level, .digitama)
        XCTAssertEqual(s.graduates.count, 1)
        XCTAssertTrue(s.dex.contains("wargreymon"), "the dex survives graduation")
        XCTAssertEqual(s.eggChoiceOfferedAt, date(day: 5), "the new egg waits for its line")
    }

    // MARK: Egg draw

    /// A graduated egg after `graduates` (one Agumon graduation unless given).
    private func graduatedEgg(at day: Int, graduates: [String] = ["agumon"]) -> DigimonState {
        var s = state(at: "wargreymon")
        s.graduates = graduates.dropLast().map { GraduateRecord(lineID: $0, path: [], graduatedAt: date(day: 1)) }
        s.partner.lineID = graduates.last ?? "agumon"
        s.partner.stageExp = 2_999
        engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: day))
        return s
    }

    func testANewEggDrawsThreeLinesItHasNeverRaised() throws {
        let s = graduatedEgg(at: 5)
        let offer = try XCTUnwrap(s.eggOffer)
        XCTAssertEqual(offer.count, 3)
        XCTAssertEqual(Set(offer).count, 3, "no line twice")
        XCTAssertFalse(offer.contains("agumon"), "the line just raised is not drawn while others are left")
        XCTAssertTrue(offer.allSatisfy { DigimonCatalog.mvp.lines[$0] != nil })
        XCTAssertEqual(engine.eggLineChoices(for: s), Set(offer + ["agumon"]), "drawn lines plus lines raised before")
    }

    func testTheDrawFillsUpWithRaisedLinesWhenFewAreLeft() throws {
        let all = DigimonCatalog.mvp.lines.keys.sorted()
        let s = graduatedEgg(at: 5, graduates: all.filter { $0 != "vmon" })
        let offer = try XCTUnwrap(s.eggOffer)
        XCTAssertEqual(offer.first, "vmon", "the only line never raised comes first")
        XCTAssertEqual(offer.count, 3)
        XCTAssertEqual(Set(offer).count, 3)
    }

    func testTheDrawIsRandomPerEggButFixedOnceDrawn() throws {
        let offers = Set((5...14).map { graduatedEgg(at: $0).eggOffer ?? [] })
        XCTAssertGreaterThan(offers.count, 1, "different eggs draw different lines")
        var s = graduatedEgg(at: 5)
        let drawn = s.eggOffer
        engine.addUsage(&s, tokens: 1_000_000, provider: "claude_code", at: date(day: 5, hour: 18))
        XCTAssertEqual(engine.tick(&s, now: date(day: 5, hour: 20)), [])
        XCTAssertEqual(s.eggOffer, drawn, "nothing redraws a waiting egg")
        XCTAssertEqual(engine.eggOffer(for: graduatedEgg(at: 5), at: date(day: 5)), drawn, "the draw repeats exactly")
    }

    func testOnlyDrawnOrRaisedLinesCanBePicked() throws {
        var s = graduatedEgg(at: 5)
        let offer = try XCTUnwrap(s.eggOffer)
        let notAllowed = try XCTUnwrap(DigimonCatalog.mvp.lines.keys.sorted().first { !offer.contains($0) && $0 != "agumon" })
        XCTAssertEqual(engine.chooseEggLine(&s, notAllowed, at: date(day: 5)), [], "neither drawn nor raised")
        XCTAssertEqual(s.partner.lineID, offer[0])
        XCTAssertNotNil(s.eggChoiceOfferedAt, "a refused pick leaves the choice open")
        XCTAssertEqual(engine.chooseEggLine(&s, "agumon", at: date(day: 5)), [.newEgg(lineID: "agumon")],
                       "a line raised before can always be picked again")
        XCTAssertNil(s.eggChoiceOfferedAt)
    }

    func testAnEggFromBeforeTheDrawMayTakeAnyLine() {
        var s = DigimonState.newEgg(lineID: "agumon")
        XCTAssertNil(s.eggOffer)
        XCTAssertEqual(engine.eggLineChoices(for: s), Set(DigimonCatalog.mvp.lines.keys))
        XCTAssertEqual(engine.chooseEggLine(&s, "vmon", at: date(day: 5)), [.newEgg(lineID: "vmon")])
    }

    func testANewEggWaitsForItsLineAndKeepsTheExperience() throws {
        var s = graduatedEgg(at: 5)
        let events = engine.addUsage(&s, tokens: 60_000_000, provider: "claude_code", at: date(day: 5))
        XCTAssertEqual(events, [], "300 experience, but no hatching before the user picks")
        XCTAssertNil(s.partner.speciesKey)
        XCTAssertEqual(s.partner.stageExp, 300)
        let pick = try XCTUnwrap(s.eggOffer?[1])
        let baby = try XCTUnwrap(DigimonCatalog.mvp.lines[pick]?.firstBaby)
        XCTAssertEqual(engine.chooseEggLine(&s, pick, at: date(day: 5)), [.newEgg(lineID: pick), .hatched(species: baby)])
        XCTAssertNil(s.eggChoiceOfferedAt)
        XCTAssertNil(s.eggOffer, "hatching uses up the draw")
        XCTAssertEqual(s.partner.stageExp, 100, "what the egg did not need carries into the baby")
    }

    func testAnUnpickedEggTakesTheDrawnLineRaisedLeastAfterADay() {
        var s = DigimonState.newEgg(lineID: "gabumon")
        s.graduates = ["agumon", "gabumon"].map { GraduateRecord(lineID: $0, path: [], graduatedAt: date(day: 1)) }
        s.eggOffer = ["gabumon", "agumon", "tentomon"]
        s.eggChoiceOfferedAt = date(day: 5)
        XCTAssertEqual(engine.tick(&s, now: date(day: 5).addingTimeInterval(3600)), [], "still waiting")
        XCTAssertEqual(engine.tick(&s, now: date(day: 6)), [.newEgg(lineID: "tentomon")],
                       "Tentomon was never raised; Piyomon was not drawn, so it is not taken")
        XCTAssertNil(s.eggChoiceOfferedAt)
    }

    func testStateSurvivesAJSONRoundTrip() throws {
        var s = DigimonState.newEgg(lineID: "gabumon")
        engine.addUsage(&s, tokens: 300_000_000, provider: "claude_code", at: date(day: 1, hour: 2))
        engine.recordBugDefeated(&s)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DigimonState.self, from: data), s)
        XCTAssertEqual(s.partner.speciesKey, "gabumon")
    }
}
