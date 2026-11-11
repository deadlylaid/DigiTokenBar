import XCTest
@testable import PokeTokenBar

final class DigimonEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private lazy var engine = EvolutionEngine(calendar: calendar)
    /// The optional mode where the user picks among the candidates.
    private lazy var choosingEngine: EvolutionEngine = {
        var growth = GrowthRules.standard
        growth.userPicksEvolution = true
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

    func testCatalogHasSixLinesOf106SpeciesWithLargeSprites() {
        let catalog = DigimonCatalog.mvp
        XCTAssertEqual(Set(catalog.lines.keys), ["agumon", "gabumon", "piyomon", "tentomon", "vmon", "guilmon"])
        XCTAssertEqual(catalog.species.count, 106)
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
                    .filter { !rules.locked.contains($0.to) && !rules.lockedEdges.contains("\($0.from)>\($0.to)") }
                let reachedOnlyByMerge = !catalog.lines.values.contains { l in
                    l.members.contains { from in
                        catalog.nextEvolutions(from: from, in: l).contains {
                            $0.to == key && !rules.lockedEdges.contains("\(from)>\(key)") && !rules.locked.contains(key)
                        }
                    }
                } && key != line.firstBaby
                if reachedOnlyByMerge || rules.locked.contains(key) { continue }
                XCTAssertFalse(open.isEmpty, "\(line.id): \(key) has no next evolution growth can take")
            }
        }
    }

    // MARK: Experience

    func testDailyCapStopsExperienceAt150() {
        var s = DigimonState.newEgg(lineID: "agumon")
        let events = engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 1))
        XCTAssertEqual(s.expToday, 150)
        // 150 exp = egg 20 + baby I 40 + baby II 60, with 30 left over at Child.
        XCTAssertEqual(events, [.hatched(species: "botamon"),
                                .evolved(from: "botamon", to: "koromon"),
                                .evolved(from: "koromon", to: "agumon")])
        XCTAssertEqual(s.partner.speciesKey, "agumon")
        XCTAssertEqual(s.partner.stageExp, 30)
    }

    func testTokensPastTheCapAreDroppedNotBanked() {
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 1))
        engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: 2))
        XCTAssertEqual(s.expToday, 1, "only today's 200k tokens count; yesterday's excess is gone")
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
        XCTAssertEqual(slow.threshold(for: .child), 240)
        var fast = GrowthRules.standard
        fast.growthMultiplier = 0.1
        XCTAssertEqual(fast.threshold(for: .digitama), 2)
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

    /// The default, like a V-Pet: no choice, the best match for how it was raised.
    func testAFullStageEvolvesStraightIntoTheBestMatch() {
        var s = DigimonState.newEgg(lineID: "agumon")
        engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 1))
        let best = engine.candidates(for: s).first   // still Agumon with 0 experience: same candidates
        let events = engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 2))
        XCTAssertEqual(events, [.evolved(from: "agumon", to: best!)])
        XCTAssertNil(s.pendingChoice)
        XCTAssertFalse(events.contains { if case .choiceOffered = $0 { return true } else { return false } })
        XCTAssertEqual(s.partner.stageExp, 60, "30 left from day 1 + 150 - 120: what the stage did not need carries over")
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
        engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 1))
        let events = engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 2))
        guard case .choiceOffered(let candidates)? = events.last else { return XCTFail("no choice: \(events)") }
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(s.pendingChoice?.candidates, candidates)
        XCTAssertEqual(s.partner.stageExp, 120, "experience waits at the threshold instead of overflowing")
        engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 3))
        XCTAssertEqual(s.partner.stageExp, 120)
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
        s.partner.stageExp = 299
        let events = engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: 5))
        XCTAssertEqual(events, [.graduated(lineID: "agumon",
                                           path: ["botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"]),
                                .newEgg(lineID: "agumon")])
        XCTAssertNil(s.partner.speciesKey)
        XCTAssertEqual(s.partner.level, .digitama)
        XCTAssertEqual(s.graduates.count, 1)
        XCTAssertTrue(s.dex.contains("wargreymon"), "the dex survives graduation")
        XCTAssertEqual(s.eggChoiceOfferedAt, date(day: 5), "the new egg waits for its line")
    }

    func testANewEggWaitsForItsLineAndKeepsTheExperience() {
        var s = state(at: "wargreymon")
        s.partner.stageExp = 299
        engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: 5))
        let events = engine.addUsage(&s, tokens: 6_000_000, provider: "claude_code", at: date(day: 5))
        XCTAssertEqual(events, [], "30 experience, but no hatching before the user picks")
        XCTAssertNil(s.partner.speciesKey)
        XCTAssertEqual(s.partner.stageExp, 30)
        XCTAssertEqual(engine.chooseEggLine(&s, "gabumon", at: date(day: 5)),
                       [.newEgg(lineID: "gabumon"), .hatched(species: "punimon")])
        XCTAssertNil(s.eggChoiceOfferedAt)
        XCTAssertEqual(s.partner.stageExp, 10, "what the egg did not need carries into Punimon")
    }

    func testAnUnpickedEggTakesTheLineRaisedLeastAfterADay() {
        var s = state(at: "wargreymon")
        s.partner.stageExp = 299
        engine.addUsage(&s, tokens: 200_000, provider: "claude_code", at: date(day: 5))
        XCTAssertEqual(engine.tick(&s, now: date(day: 5).addingTimeInterval(3600)), [], "still waiting")
        let events = engine.tick(&s, now: date(day: 6))
        XCTAssertEqual(events, [.newEgg(lineID: "gabumon")], "Agumon graduated once, Gabumon never")
        XCTAssertNil(s.eggChoiceOfferedAt)
    }

    func testStateSurvivesAJSONRoundTrip() throws {
        var s = DigimonState.newEgg(lineID: "gabumon")
        engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date(day: 1, hour: 2))
        engine.recordBugDefeated(&s)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(DigimonState.self, from: data), s)
        XCTAssertEqual(s.partner.speciesKey, "gabumon")
    }
}
