import XCTest
@testable import PokeTokenBar

/// Step 13: the Vital Bracelet cards' Armor Digimon are back on their lines, and a step into one from
/// another level opens only with a Digimental (docs/digimon/step13-digimental-armor.md).
final class DigimonArmorTests: XCTestCase {
    private let engine = EvolutionEngine()
    private var catalog: DigimonCatalog { engine.catalog }
    private var lines: [DigimonLine] { catalog.lines.values.sorted { $0.id < $1.id } }
    /// Every Digimon a Digimental step leads into.
    private var armor: Set<String> { Set(lines.flatMap { $0.digimentalSteps.keys.map { String($0.split(separator: ">")[1]) } }) }

    private func split(_ step: String) -> (String, String) {
        let p = step.split(separator: ">").map(String.init)
        return (p[0], p[1])
    }

    /// The research (tools/digimon/research/armor-routes.json) gives these; a smaller number means
    /// routes were lost on the way into the catalog.
    func testTheCardsArmorDigimonAreOnTheirLines() {
        XCTAssertEqual(armor.count, 20)
        XCTAssertEqual(lines.reduce(0) { $0 + $1.digimentalSteps.count }, 32)
        XCTAssertEqual(lines.filter { !$0.digimentalSteps.isEmpty }.map(\.id),
                       ["armadimon", "blucomon", "hawkmon", "piyomon", "renamon", "sunarizamon", "terriermon", "vmon", "wormmon"])
        let vmon = catalog.lines["vmon"]!
        XCTAssertEqual(vmon.digimental(from: "vmon", to: "fladramon"), .courage)
        XCTAssertEqual(vmon.digimental(from: "vmon", to: "lighdramon"), .friendship)
        XCTAssertEqual(catalog.lines["armadimon"]!.digimental(from: "armadimon", to: "submarimon"), .reliability)
        XCTAssertEqual(catalog.lines["hawkmon"]!.digimental(from: "hawkmon", to: "shurimon"), .purity)
        XCTAssertNil(vmon.digimental(from: "vmon", to: "vdramon"), "an ordinary step needs nothing")
    }

    func testEveryDigimentalStepIsAStepOfItsLineAndItsArmorGrowsOn() {
        for line in lines {
            for (step, _) in line.digimentalSteps {
                let (from, to) = split(step)
                XCTAssertTrue(line.steps?.contains(step) == true, "\(line.id): \(step) is not a step of the line")
                XCTAssertFalse(line.mergeSteps.contains(step), "\(line.id): \(step) is a merge")
                guard let level = catalog.species(to)?.level else { return XCTFail("\(line.id): no species \(to)") }
                XCTAssertNotNil(catalog.species(from), "\(line.id): no species \(from)")
                if level != .ultimate {
                    let onward = catalog.nextEvolutions(from: to, in: line).filter { !engine.rules.isLocked(to, $0.to, in: line) }
                    XCTAssertFalse(onward.isEmpty, "\(line.id): the Armor Digimon \(to) cannot grow on")
                }
            }
        }
    }

    /// Only a Digimental (or a merge, which needs its partner) leads into an Armor Digimon from
    /// another level: growth alone must never get there.
    func testNoGrowthStepGoesIntoAnArmorDigimonWithoutADigimental() {
        let armor = armor
        for line in lines {
            for step in line.steps ?? [] {
                let (from, to) = split(step)
                guard armor.contains(to), !armor.contains(from), !line.mergeSteps.contains(step) else { continue }
                XCTAssertNotNil(line.digimentalSteps[step], "\(line.id): \(step) reaches an Armor Digimon without a Digimental")
            }
        }
    }

    func testEachArmorDigimonAsksForOneDigimentalOnEveryLine() {
        var seen: [String: Digimental] = [:]
        for line in lines {
            for (step, d) in line.digimentalSteps {
                let to = split(step).1
                XCTAssertEqual(seen[to, default: d], d, "\(to) asks for two Digimentals")
                seen[to] = d
            }
        }
        XCTAssertEqual(seen["goldvdramon"], .fate)
        XCTAssertEqual(seen["magnamon"], .miracles)
    }

    /// Until the user uses a Digimental, nothing changes: the stage's candidates never hold an Armor
    /// Digimon, however the stage went.
    func testGrowthNeverTakesADigimentalStep() {
        for line in lines {
            for (step, _) in line.digimentalSteps {
                let (from, to) = split(step)
                var state = DigimonState.newEgg(lineID: line.id)
                state.partner.speciesKey = from
                state.partner.level = catalog.species(from)!.level
                // A stage that meets every card requirement.
                state.partner.stageSignals.battles = 50
                state.partner.stageSignals.battleWins = 50
                XCTAssertFalse(engine.rankedOptions(for: state).contains(to), "\(line.id): growth took \(step)")
                XCTAssertTrue(engine.armorOptions(for: state).contains { $0.to == to }, "\(line.id): \(step) is not offered")
            }
        }
    }

    func testArmorOptionsListTheChildsDigimentalSteps() {
        var state = DigimonState.newEgg(lineID: "armadimon")
        state.partner.speciesKey = "armadimon"
        state.partner.level = .child
        XCTAssertEqual(engine.armorOptions(for: state).map(\.to).sorted(), ["digmon", "submarimon"])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: engine.armorOptions(for: state).map { ($0.to, $0.digimental) }),
                       ["digmon": .knowledge, "submarimon": .reliability])
        state.partner.speciesKey = "ankylomon"
        state.partner.level = .adult
        XCTAssertTrue(engine.armorOptions(for: state).isEmpty, "Ankylomon has no Armor evolution")
    }

    func testTheDexHintsAtTheDigimental() throws {
        let rows = DigimonDex.rows(for: catalog.lines["vmon"]!, state: .newEgg(lineID: "vmon"), catalog: catalog, rules: engine.rules)
        let entries = rows.flatMap(\.entries)
        XCTAssertEqual(entries.first { $0.id == "fladramon" }?.secret, .digimental(.courage))
        XCTAssertEqual(entries.first { $0.id == "sagittarimon" }?.secret, .digimental(.hope))
        let vmon = try XCTUnwrap(entries.first { $0.id == "vmon" })
        XCTAssertTrue(vmon.next.contains { $0.key == "fladramon" }, "the Armor evolution is listed under V-mon")
        XCTAssertEqual(DigimonText(.ko).secretHint(.digimental(.courage), catalog: catalog), "용기의 디지멘탈이 있으면 진화할 수 있어요.")
        XCTAssertEqual(DigimonText(.en).secretHint(.digimental(.courage), catalog: catalog), "Evolves with the Digimental of Courage.")
        XCTAssertEqual(DigimonDexView.secretIcon(.digimental(.courage)), "shield.lefthalf.filled")
        // Kongoumon is also a merge on the Primeval Warriors card; the Digimental is the hint.
        let wormmon = DigimonDex.rows(for: catalog.lines["wormmon"]!, state: .newEgg(lineID: "wormmon"), catalog: catalog,
                                      rules: engine.rules).flatMap(\.entries)
        XCTAssertEqual(wormmon.first { $0.id == "kongoumon" }?.secret, .digimental(.miracles))
    }

    func testEveryArmorDigimonHasANameAndAMove() {
        let page = DigimonSceneHTML.page
        for key in armor.sorted() {
            let species = catalog.species(key)
            XCTAssertNotNil(species, key)
            XCTAssertNotEqual(species?.koreanName, species?.name, "\(key) has no Korean name")
            XCTAssertTrue(page.contains("\n  \(key): {ko: '"), "no move for \(key)")
        }
        XCTAssertEqual(catalog.species("rapidmonarmor")?.koreanName, "래피드몬(아머체)", "told apart from the Perfect Rapidmon")
        XCTAssertNotEqual(catalog.species("rapidmonarmor")?.koreanName, catalog.species("rapidmonperfect")?.koreanName)
    }
}
