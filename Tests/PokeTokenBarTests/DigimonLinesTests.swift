import XCTest
@testable import PokeTokenBar

/// Tendency, jogress locks, moods and the six lines.
final class DigimonLinesTests: XCTestCase {
    private let engine = EvolutionEngine()
    private var catalog: DigimonCatalog { engine.catalog }

    private func state(at key: String, line: String) -> DigimonState {
        var s = DigimonState.newEgg(lineID: line)
        s.partner.speciesKey = key
        s.partner.level = catalog.species(key)!.level
        return s
    }

    func testEveryLineIsWellFormed() {
        XCTAssertEqual(catalog.lines.keys.sorted(), ["agumon", "gabumon", "guilmon", "piyomon", "tentomon", "vmon"])
        for line in catalog.lines.values {
            XCTAssertEqual(catalog.species(line.firstBaby)?.level, .babyI, line.id)
            XCTAssertEqual(catalog.species(line.id)?.level, .child, "\(line.id) names its line after a Child on the card")
            XCTAssertTrue(line.members.allSatisfy { catalog.species($0) != nil }, line.id)
        }
    }

    /// Capped days from a picked egg to graduation: a line must never get stuck, and growth must
    /// stay inside the line.
    func testEveryLineGrowsFromEggToGraduation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let engine = EvolutionEngine(calendar: calendar)
        for lineID in catalog.lines.keys.sorted() {
            var s = DigimonState.newEgg(lineID: lineID)
            var graduated: [String]?
            for day in 1...30 where graduated == nil {
                let date = calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: 14))!
                for event in engine.addUsage(&s, tokens: 100_000_000, provider: "claude_code", at: date) {
                    if case .graduated(_, let path) = event { graduated = path }
                }
            }
            guard let path = graduated else { XCTFail("\(lineID) never graduated: stuck at \(s.partner)"); continue }
            XCTAssertEqual(path.first, catalog.lines[lineID]!.firstBaby)
            XCTAssertTrue(path.allSatisfy { catalog.lines[lineID]!.members.contains($0) }, "\(lineID): \(path)")
        }
    }

    func testJogressOnlyStepsAreLockedButTheDataKeepsThem() {
        XCTAssertFalse(DigimonCatalogData.jogressEdges.isEmpty)
        XCTAssertEqual(EvolutionRules.mvp.lockedEdges, DigimonCatalogData.jogressEdges)
        // Lock a normal step the same way: the candidate disappears, the evolution data does not.
        let s = state(at: "agumon", line: "agumon")
        var rules = EvolutionRules.mvp
        rules.lockedEdges.insert("agumon>greymon")
        let locked = EvolutionEngine(rules: rules)
        XCTAssertTrue(engine.candidates(for: s).contains("greymon"))
        XCTAssertFalse(locked.candidates(for: s).contains("greymon"))
        XCTAssertTrue(catalog.nextEvolutions(from: "agumon", in: catalog.lines["agumon"]!).contains { $0.to == "greymon" })
    }

    /// Wikimon writes a Vital Bracelet merge as "(with a ... Adult ...)" without the word Jogress;
    /// the first data build missed that, so Algomon could grow into Andromon on its own.
    func testVitalBraceletMergeNotesAreLockedButOptionalPartnersAreNot() {
        for step in ["algomonadult>andromon", "algomonadult>anomalocarimon", "algomonadult>parrotmon",
                     "algomonadult>valvemon", "neodevimon>wargreymon"] {
            XCTAssertTrue(DigimonCatalogData.jogressEdges.contains(step), step)
        }
        // Wikimon writes these "(with or without ...)" because other games need no partner; on these
        // exact cards they are a Jogress (tools/digimon/research).
        for step in ["coelamon>metaltyranomon", "greymon>andromon", "mamemon>wargreymon", "bigmamemon>metalgarurumon",
                     "paildramon>ulforcevdramon", "xvmon>aerovdramon", "megalogrowmon>dukemonxantibody",
                     "megalogrowmonorange>dukemon", "megalogrowmonorange>megidramon"] {
            XCTAssertTrue(DigimonCatalogData.jogressEdges.contains(step), "\(step) is a Jogress on its card")
        }
        XCTAssertFalse(DigimonCatalogData.jogressEdges.contains("andromon>wargreymon"), "(with or without Cyberdramon)")
        let algomon = state(at: "algomonadult", line: "agumon")
        XCTAssertEqual(Set(engine.candidates(for: algomon)), ["mamemon", "metalgreymon", "metaltyranomon"])
    }

    func testAHiddenEvolutionThatIsTheOnlyWayOnOpensWithoutItsCondition() {
        let neo = state(at: "neodevimon", line: "agumon")
        XCTAssertEqual(Set(engine.candidates(for: neo)), ["donedevimon", "blitzgreymon"],
                       "no limits hit and no bugs, yet its only (hidden) routes open instead of a dead end")
        let andromon = state(at: "andromon", line: "agumon")
        XCTAssertFalse(engine.candidates(for: andromon).contains("blitzgreymon"), "still hidden where there is another way")
    }

    func testTheDexMarksMergeOnlyDigimon() {
        let rows = DigimonDex.rows(for: catalog.lines["vmon"]!, state: .newEgg(lineID: "vmon"), catalog: catalog, rules: engine.rules)
        XCTAssertEqual(rows.flatMap(\.entries).first { $0.id == "digitamamon" }?.secret, .mergeOnly)
        XCTAssertNil(rows.flatMap(\.entries).first { $0.id == "vdramon" }?.secret)
    }

    func testTendencyFollowsHowTheStageWasUsed() {
        var day = state(at: "agumon", line: "agumon")
        day.partner.stageSignals.tokens = 1_000_000
        let daytime = engine.tendencies(for: day)
        XCTAssertEqual(Set(daytime.map(\.attribute)),
                       Set(engine.rankedOptions(for: day).compactMap { catalog.species($0)?.attribute }))
        XCTAssertEqual(daytime.first(where: \.leading)?.attribute, .vaccine, "daytime use leans Vaccine")

        var night = day
        night.partner.stageSignals.nightTokens = 1_000_000
        night.partner.stageSignals.limitHits = 2
        let late = engine.tendencies(for: night)
        XCTAssertEqual(Set(late.map(\.attribute)), Set(daytime.map(\.attribute)),
                       "every possible direction stays listed, even one that is not in the top three now")
        XCTAssertEqual(late.first(where: \.leading)?.attribute, .virus, "late nights and full limits lean Virus")
        XCTAssertEqual(late.first(where: \.leading)?.attribute,
                       catalog.species(engine.candidates(for: night).first!)?.attribute,
                       "the leading bar is where it would evolve now")
        XCTAssertTrue(engine.tendencies(for: .newEgg(lineID: "agumon")).isEmpty, "no tendency for an egg")
        XCTAssertTrue(engine.tendencies(for: state(at: "wargreymon", line: "agumon")).isEmpty, "nor for the last stage")
    }

    func testMoodSickWhileALimitIsFullSleepyAtNightNothingWhileAsleep() {
        let night = 0..<6
        XCTAssertEqual(DigimonSceneHub.mood(sleeping: false, hour: 14, nightHours: night, limitFull: false), nil)
        XCTAssertEqual(DigimonSceneHub.mood(sleeping: false, hour: 3, nightHours: night, limitFull: false), "sleepy")
        XCTAssertEqual(DigimonSceneHub.mood(sleeping: false, hour: 3, nightHours: night, limitFull: true), "sick")
        XCTAssertEqual(DigimonSceneHub.mood(sleeping: true, hour: 3, nightHours: night, limitFull: true), nil)
    }

    @MainActor
    func testABigBugCountsAsThree() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-bugs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DigimonStore(fileURL: dir.appendingPathComponent("s.json"))
        store.recordBugDefeated(count: 3)
        store.recordBugDefeated()
        XCTAssertEqual(store.state.lifetimeSignals.bugsDefeated, 4)
        store.recordBugDefeated(count: 1_000)
        XCTAssertEqual(store.state.lifetimeSignals.bugsDefeated, 14, "a page cannot claim more than 10 at once")
    }
}
