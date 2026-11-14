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
    /// The shape of every move is one the scene can draw (it has colors and timing for it).
    func testEveryMoveUsesADrawnShape() throws {
        let page = DigimonSceneHTML.page
        let kinds = Set(page.matches(of: /kind: '(\w+)'\}/).map { String($0.1) })
        XCTAssertEqual(kinds, ["fire", "missile", "gaia", "claw", "ice", "bind", "melee", "beam", "electric"])
        for kind in kinds where kind != "fire" {
            XCTAssertTrue(page.contains("  \(kind): ["), "no colors for \(kind)")
        }
        for kind in kinds { XCTAssertTrue(page.contains("\(kind): ["), "no timing for \(kind)") }
    }

    /// Shapes fixed in the 2026-11-14 review (tools/digimon/research/move-shape-review.json): each
    /// was drawn as something it is not.
    func testReviewedMovesKeepTheirShapes() {
        let page = DigimonSceneHTML.page
        func kind(_ key: String) -> String? {
            page.firstMatch(of: try! Regex("\n  \(key): \\{ko: '[^\n]*?kind: '(\\w+)'"))?.output[1].substring.map(String.init)
        }
        let expected = [
            "leomon": "fire",            // a lion-head ki shot from the fist, not claws
            "hawkmon": "melee",          // pecks with its beak, not a fireball
            "vmon": "melee",             // swings both arms to punch
            "tailmon": "melee",          // Cat Punch
            "commandramon": "missile",   // an assault rifle
            "blackwargreymon": "gaia",   // Dark Gaia Force: the sphere the shape is named after
            "algomonadult": "bind",      // tentacles from its mouth
            "blucomon": "ice",           // spits icicles
            "icedevimon": "claw",        // icy claws
            "rizegreymon": "missile",    // revolver shots
            "airdramon": "claw",         // vacuum blades from its wings
            "metalseadramon": "beam",    // a beam from its snout
            "kabuterimon": "electric",   // a ball of electricity
            "wizarmon": "electric",      // lightning from a thundercloud
        ]
        for (key, shape) in expected { XCTAssertEqual(kind(key), shape, key) }
    }

    func testEveryCatalogDigimonHasANamedMove() {
        let page = DigimonSceneHTML.page
        for key in catalog.species.keys.sorted() {
            XCTAssertTrue(page.contains("\n  \(key): {ko: '"), "no move for \(key)")
        }
    }
}
