import XCTest
@testable import PokeTokenBar

final class DigimonDexTests: XCTestCase {
    private let engine = EvolutionEngine()
    private var catalog: DigimonCatalog { engine.catalog }
    private var agumonLine: DigimonLine { catalog.lines["agumon"]! }

    func testRowsFollowTheLevelsAndHoldEveryMemberOnce() {
        let rows = DigimonDex.rows(for: agumonLine, state: .newEgg(lineID: "agumon"), catalog: catalog, rules: engine.rules)
        XCTAssertEqual(rows.map(\.level), [.babyI, .babyII, .child, .adult, .perfect, .ultimate])
        XCTAssertEqual(rows.flatMap(\.entries).map(\.id).sorted(), agumonLine.members.sorted())
        XCTAssertTrue(rows.flatMap(\.entries).allSatisfy { !$0.seen }, "a new egg has seen nothing")
    }

    func testRaisedDigimonAndWitnessedEvolutionsAreRevealed() {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.dex = ["botamon", "koromon", "agumon", "greymon"]
        state.discoveredEvolutions = ["botamon>koromon", "koromon>agumon", "agumon>greymon"]
        let entries = DigimonDex.rows(for: agumonLine, state: state, catalog: catalog, rules: engine.rules).flatMap(\.entries)
        let agumon = entries.first { $0.id == "agumon" }!
        XCTAssertTrue(agumon.seen)
        XCTAssertEqual(agumon.previous, [DigimonDex.Link(key: "koromon", discovered: true)])
        XCTAssertTrue(agumon.next.contains(DigimonDex.Link(key: "greymon", discovered: true)))
        XCTAssertTrue(agumon.next.contains { !$0.discovered }, "other branches stay unknown")
        XCTAssertFalse(entries.first { $0.id == "metalgreymon" }!.seen)
    }

    func testSecretsShowHintsForHiddenAndLockedDigimon() {
        let entries = DigimonDex.rows(for: agumonLine, state: .newEgg(lineID: "agumon"), catalog: catalog, rules: engine.rules)
            .flatMap(\.entries)
        XCTAssertEqual(entries.first { $0.id == "blitzgreymon" }?.secret, .hidden(.bugsDefeated(atLeast: 20)))
        XCTAssertEqual(entries.first { $0.id == "donedevimon" }?.secret, .hidden(.limitHits(atLeast: 3)))
        XCTAssertEqual(entries.first { $0.id == "omegamon" }?.secret, .specialJogress(partners: ["metalgarurumon", "wargreymon"]))
        XCTAssertNil(entries.first { $0.id == "wargreymon" }?.secret)
    }

    func testProgressCountsSharedDigimonOnceAndIgnoresUnknownKeys() {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.dex = ["agumon", "algomonadult", "from-a-newer-version"]
        let progress = DigimonDex.progress(state: state, catalog: catalog)
        XCTAssertEqual(progress.total, catalog.species.count, "shared Digimon (Algomon, Omegamon) count once")
        XCTAssertEqual(progress.seen, 2)
    }

    /// Every Digimon must have its own named attack in the pet scene, so a catalog change cannot
    /// silently fall back to the plain "Attack".
    func testEveryCatalogDigimonHasANamedMove() {
        let page = DigimonSceneHTML.page
        for key in catalog.species.keys.sorted() {
            XCTAssertTrue(page.contains("\n  \(key): {ko: '"), "no move for \(key)")
        }
    }
}
