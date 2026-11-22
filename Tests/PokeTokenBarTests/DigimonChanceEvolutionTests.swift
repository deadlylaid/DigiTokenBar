import XCTest
@testable import PokeTokenBar

/// Step 14 (docs/digimon/step14-chance-evolution.md, user decisions 2026-11-21): the card still
/// decides which routes are open, but among them growth draws by weight instead of always taking
/// the best. Weight = 0.2 + the stage's tendency toward the attribute + 0.5 for keeping the current
/// Digimon's attribute + 0.15 for a canon route. Seeded, so the same stage always gives the same one.
final class DigimonChanceEvolutionTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    private lazy var engine = EvolutionEngine(calendar: calendar)
    /// Tendency only (every allowed route open), to look at the draw itself.
    private lazy var tendencyEngine: EvolutionEngine = {
        var growth = GrowthRules.standard
        growth.cardConditions = false
        return EvolutionEngine(growth: growth, calendar: calendar)
    }()

    private func date(day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Agumon (Vaccine) in a stage that began on day 1, coding much more at night than usual (Virus).
    private func agumon(player: String) -> DigimonState {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = "agumon"
        s.partner.level = .child
        s.partner.path = ["agumon"]
        s.partner.stageStartedAt = date(day: 1)
        s.playerID = player
        s.lifetimeSignals = GrowthSignals(tokens: 1_000, nightTokens: 200)
        s.partner.stageSignals = GrowthSignals(tokens: 1_000, nightTokens: 800)
        return s
    }

    private func share(_ keys: [String], of options: [String], players: Int, engine: EvolutionEngine,
                       state: DigimonState) -> [String: Double] {
        var counts: [String: Int] = [:]
        for i in 0..<players {
            var s = state
            s.playerID = "player-\(i)"
            counts[engine.drawEvolution(from: options, for: s), default: 0] += 1
        }
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, Double(counts[$0, default: 0]) / Double(players)) })
    }

    /// The weight as the user decided it, worked out here (not by the engine), with or without the
    /// bonus for keeping Agumon's attribute (Vaccine).
    private func expectedWeight(_ key: String, _ s: DigimonState, bonus: Bool = true) -> Double {
        let catalog = DigimonCatalog.mvp
        let target = catalog.species(key)!
        let canon = catalog.nextEvolutions(from: "agumon", in: catalog.lines["agumon"]!).first { $0.to == key }?.canon == true
        return 0.2 + tendencyEngine.pull(target.attribute, signals: s.partner.stageSignals, baseline: s.lifetimeSignals)
            + (bonus && target.attribute == .vaccine ? 0.5 : 0) + (canon ? 0.15 : 0)
    }

    func testTheWeightIsBaseTendencySameAttributeAndCanon() throws {
        let s = agumon(player: "p")
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        XCTAssertGreaterThan(Set(options.compactMap { DigimonCatalog.mvp.species($0)?.attribute }).count, 1, "a real fork")
        for key in options {
            XCTAssertEqual(tendencyEngine.drawWeight(key, for: s), expectedWeight(key, s), accuracy: 1e-9, key)
        }
    }

    func testTheDrawFollowsTheWeights() {
        let s = agumon(player: "p")
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        let weights = options.map { tendencyEngine.drawWeight($0, for: s) }
        let total = weights.reduce(0, +)
        let measured = share(options, of: options, players: 4_000, engine: tendencyEngine, state: s)
        for (key, weight) in zip(options, weights) {
            XCTAssertEqual(measured[key] ?? 0, weight / total, accuracy: 0.03, key)
        }
    }

    /// The +0.5 for keeping the attribute shows in the result: a Vaccine Agumon pushed toward Virus by
    /// its nights still becomes a Vaccine Digimon clearly more often than the tendency alone would give.
    func testKeepingTheCurrentAttributeRaisesItsShare() {
        let s = agumon(player: "p")
        let catalog = DigimonCatalog.mvp
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        let vaccine = options.filter { catalog.species($0)?.attribute == .vaccine }
        XCTAssertFalse(vaccine.isEmpty)
        func vaccineShare(bonus: Bool) -> Double {
            let weights = options.map { expectedWeight($0, s, bonus: bonus) }
            return zip(options, weights).filter { vaccine.contains($0.0) }.map(\.1).reduce(0, +) / weights.reduce(0, +)
        }
        let withBonus = vaccineShare(bonus: true), without = vaccineShare(bonus: false)
        XCTAssertGreaterThan(withBonus - without, 0.1, "the bonus is worth a visible share")
        let measured = share(options, of: options, players: 4_000, engine: tendencyEngine, state: s)
            .filter { vaccine.contains($0.key) }.values.reduce(0, +)
        XCTAssertEqual(measured, withBonus, accuracy: 0.03, "Vaccine \(measured), expected \(withBonus), without the bonus \(without)")
    }

    func testTheSameStageDrawsTheSameDigimonEveryTime() throws {
        let s = agumon(player: "fixed")
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        let first = tendencyEngine.drawEvolution(from: options, for: s)
        for _ in 0..<20 { XCTAssertEqual(tendencyEngine.drawEvolution(from: options, for: s), first) }
        // Saved and loaded again (an app restart, a backup restore).
        let copy = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(tendencyEngine.drawEvolution(from: options, for: copy), first)
        // Not one fixed answer for everybody.
        let others = Set((0..<60).map { i -> String in
            var o = s
            o.playerID = "p\(i)"
            return tendencyEngine.drawEvolution(from: options, for: o)
        })
        XCTAssertGreaterThan(others.count, 1)
    }

    /// Growth itself takes the drawn Digimon, and different players get different ones.
    func testAFullStageEvolvesIntoTheDrawnDigimon() {
        var results = Set<String>()
        for i in 0..<40 {
            var s = agumon(player: "grow-\(i)")
            let expected = tendencyEngine.drawEvolution(from: tendencyEngine.growthOptions(for: s, at: date(day: 2)), for: s)
            s.partner.stageExp = tendencyEngine.growth.threshold(for: .child)
            let events = tendencyEngine.settle(&s, at: date(day: 2))
            XCTAssertEqual(events.first, .evolved(from: "agumon", to: expected), "grow-\(i)")
            results.insert(expected)
        }
        XCTAssertGreaterThan(results.count, 1, "growth no longer always takes the same one")
    }

    /// The card still decides which routes are open: a closed route is never drawn, whatever the seed.
    func testTheCardKeepsClosedRoutesOutOfTheDraw() throws {
        var s = agumon(player: "p")
        // A moderate stage: some of Agumon's card routes are met, the harder ones are not.
        s.partner.stageSignals.activeDays = ["2026-11-01", "2026-11-02"]
        s.partner.stageSignals.activeHours = ["2026-11-01 10", "2026-11-01 11", "2026-11-02 10"]
        let open = engine.growthOptions(for: s, at: date(day: 2))
        let all = engine.rankedOptions(for: s)
        let closed = Set(all).subtracting(open)
        XCTAssertFalse(closed.isEmpty, "the setup needs a route the card keeps closed")
        for i in 0..<80 {
            var o = s
            o.playerID = "gate-\(i)"
            o.partner.stageExp = engine.growth.threshold(for: .child)
            _ = engine.settle(&o, at: date(day: 2))
            let grown = try XCTUnwrap(o.partner.speciesKey)
            XCTAssertTrue(open.contains(grown), "gate-\(i) grew into \(grown), closed: \(closed.sorted())")
        }
    }

    /// An earned hidden evolution is a reward: always taken, never drawn.
    func testAnEarnedHiddenEvolutionStaysCertain() {
        var s = DigimonState.newEgg(lineID: "agumon")
        s.partner.speciesKey = "metalgreymon"
        s.partner.level = .perfect
        s.partner.path = ["metalgreymon"]
        s.partner.stageStartedAt = date(day: 1)
        for _ in 0..<20 { engine.recordBugDefeated(&s) }
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        XCTAssertTrue(options.contains("blitzgreymon"))
        XCTAssertGreaterThan(options.count, 1)
        for i in 0..<60 {
            var o = s
            o.playerID = "hidden-\(i)"
            XCTAssertEqual(tendencyEngine.drawEvolution(from: options, for: o), "blitzgreymon")
        }
    }

    func testOneRouteOrAStageWithoutAStartTimeTakesTheBest() {
        var s = agumon(player: "p")
        XCTAssertEqual(tendencyEngine.drawEvolution(from: ["greymon"], for: s), "greymon")
        s.partner.stageStartedAt = nil   // a stage from before stages were timed
        let options = tendencyEngine.growthOptions(for: s, at: date(day: 2))
        for i in 0..<30 {
            var o = s
            o.playerID = "old-\(i)"
            XCTAssertEqual(tendencyEngine.drawEvolution(from: options, for: o), options[0])
        }
    }
}
