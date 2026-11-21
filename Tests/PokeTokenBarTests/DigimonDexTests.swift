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
    /// The shape of every move is one the scene can draw (it has colors and timing for it), and
    /// every tint has its colors.
    func testEveryMoveUsesADrawnShape() throws {
        let page = DigimonSceneHTML.page
        let kinds = Set(page.matches(of: /kind: '(\w+)'/).map { String($0.1) })
        XCTAssertEqual(kinds, ["fire", "missile", "gaia", "claw", "ice", "bind", "melee", "beam", "electric",
                               "gas", "wave", "wind", "water", "light", "swarm", "heart", "quake"])
        for kind in kinds where kind != "fire" {
            XCTAssertTrue(page.contains("  \(kind): ["), "no colors for \(kind)")
        }
        for kind in kinds { XCTAssertTrue(page.contains("\(kind): ["), "no timing for \(kind)") }
        let tints = Set(page.matches(of: /tint: '(\w+)'/).map { String($0.1) })
        XCTAssertFalse(tints.isEmpty)
        for tint in tints { XCTAssertTrue(page.contains("tint_\(tint): ["), "no colors for the tint \(tint)") }
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
            "hydramon": "gas",           // poison gas from the mouth on its chest
            "etemon": "wave",            // a song
            "terriermon": "wind",        // a tiny tornado from its ears
            "shellmon": "water",         // a high-pressure water jet
            "hououmon": "light",         // golden particles of light
            "vamdemon": "swarm",         // a swarm of bats
            "monzaemon": "heart",        // shoots hearts
            "breakdramon": "quake",      // pounds the ground
        ]
        for (key, shape) in expected { XCTAssertEqual(kind(key), shape, key) }
    }

    func testLinesAreListedByTheirShownNames() {
        let lines = ["piyomon", "agumon", "tentomon", "gabumon"].compactMap { catalog.lines[$0] }
        let ko = DigimonText(.ko).sortedLines(lines, catalog: catalog).map(\.id)
        XCTAssertEqual(ko, ["agumon", "tentomon", "gabumon", "piyomon"], "아구몬, 텐타몬, 파피몬, 피요몬")
        let en = DigimonText(.en).sortedLines(lines, catalog: catalog).map(\.id)
        XCTAssertEqual(en, ["agumon", "gabumon", "piyomon", "tentomon"])
        let agumon = catalog.lines["agumon"]!
        XCTAssertEqual(DigimonText(.ko).lineMenuName(agumon, catalog: catalog, graduated: 2), "아구몬 · 졸업 2번")
        XCTAssertEqual(DigimonText(.ko).lineMenuName(agumon, catalog: catalog, graduated: 0), "아구몬")
        XCTAssertEqual(DigimonText(.ko).sortedLines(Array(catalog.lines.values), catalog: catalog).count, catalog.lines.count)
    }

    func testEveryCatalogDigimonHasANamedMove() {
        let page = DigimonSceneHTML.page
        for key in catalog.species.keys.sorted() {
            XCTAssertTrue(page.contains("\n  \(key): {ko: '"), "no move for \(key)")
        }
    }

    // MARK: Search, filter, sort

    private func groups(_ query: DigimonDex.Query, _ state: DigimonState, language: AppLanguage = .ko,
                        lines: [DigimonLine]? = nil, rules: EvolutionRules? = nil) -> [DigimonDex.Group] {
        let text = DigimonText(language)
        return DigimonDex.search(query, lines: lines ?? text.sortedLines(Array(catalog.lines.values), catalog: catalog),
                                 state: state, catalog: catalog, rules: rules ?? engine.rules, text: text)
    }

    private func ids(_ query: DigimonDex.Query, _ state: DigimonState, language: AppLanguage = .ko) -> [String] {
        groups(query, state, language: language).flatMap(\.hits).map(\.id)
    }

    private var raisedAndMet: DigimonState {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.dex = ["agumon", "gabumon", "greymon"]
        state.sightings = ["wargreymon"]
        return state
    }

    /// The silhouettes stay secret: a name only finds Digimon the dex already names.
    func testANameOnlyFindsDigimonWhoseNameIsShown() {
        XCTAssertEqual(Set(ids(.init(text: "그레이"), raisedAndMet)), ["greymon", "wargreymon"],
                       "raised Greymon and visitor War Greymon; Metal Greymon is still a silhouette")
        XCTAssertEqual(ids(.init(text: "메탈"), raisedAndMet), [])
    }

    func testNamesMatchInEitherLanguageIgnoringCaseAndSpaces() {
        for text in ["war grey", "WARGREY", "워그레이", "워 그레이 몬"] {
            XCTAssertEqual(ids(.init(text: text), raisedAndMet), ["wargreymon"], text)
        }
    }

    func testFiltersLookThroughEveryLine() {
        let state = raisedAndMet
        XCTAssertEqual(Set(ids(.init(status: .raised), state)), ["agumon", "gabumon", "greymon"], "Gabumon is another line")
        XCTAssertEqual(ids(.init(status: .metOnly), state), ["wargreymon"])
        XCTAssertEqual(Set(ids(.init(status: .raised, level: .child), state)), ["agumon", "gabumon"])
        let unknown = groups(.init(status: .unknown), state).flatMap(\.hits)
        XCTAssertEqual(unknown.count, catalog.species.count - 4)
        XCTAssertTrue(unknown.allSatisfy { !$0.entry.seen && !$0.entry.sighted })
        XCTAssertEqual(ids(.init(level: .ultimate), state).count, catalog.species.values.filter { $0.level == .ultimate }.count)
        XCTAssertEqual(Set(ids(.init(sort: .name), state)).count, catalog.species.count, "every Digimon once")
    }

    /// A Digimon in several lines can have a secret on one and none on another. Digitamamon was a
    /// friend Jogress on the V-mon line and a plain evolution on the Espimon and Angoramon lines; since
    /// the Armor Digimon came back (step 13) Fladramon and Lighdramon also grow into it there, so the
    /// test locks those two steps to keep the V-mon line's entry a friend Jogress. Read first from
    /// V-mon, it must still come from a line where it can be reached.
    func testASharedDigimonComesFromALineWhereItCanBeReached() throws {
        var rules = engine.rules
        rules.lockedEdges = ["fladramon>digitamamon", "lighdramon>digitamamon"]
        let vmonFirst = [catalog.lines["vmon"]!] + catalog.lines.values.filter { $0.id != "vmon" }.sorted { $0.id < $1.id }
        let vmonEntry = DigimonDex.rows(for: vmonFirst[0], state: .newEgg(lineID: "agumon"), catalog: catalog, rules: rules)
            .flatMap(\.entries).first { $0.id == "digitamamon" }
        XCTAssertNotNil(vmonEntry?.secret, "the V-mon line's Digitamamon has a secret in this test")
        let hits = groups(.init(sort: .name), .newEgg(lineID: "agumon"), lines: vmonFirst, rules: rules).flatMap(\.hits)
            .filter { $0.id == "digitamamon" }
        XCTAssertEqual(hits.count, 1)
        let hit = try XCTUnwrap(hits.first)
        XCTAssertNil(hit.entry.secret)
        XCTAssertNotEqual(hit.lineID, "vmon")
    }

    func testSortByNamePutsNamedDigimonInOrderThenSilhouettesByLevel() throws {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.dex = ["koromon", "greymon", "agumon"]
        let ko = try XCTUnwrap(groups(.init(sort: .name), state).first)
        XCTAssertNil(ko.level)
        XCTAssertEqual(ko.hits.prefix(3).map(\.id), ["greymon", "agumon", "koromon"], "그레이몬, 아구몬, 코로몬")
        XCTAssertEqual(groups(.init(sort: .name), state, language: .en).first?.hits.prefix(3).map(\.id),
                       ["agumon", "greymon", "koromon"])
        let levels = ko.hits.dropFirst(3).map(\.entry.species.level)
        XCTAssertEqual(levels, levels.sorted(), "silhouettes follow the levels")
    }

    func testSortByLevelGroupsUnderLevelHeadings() {
        let levels = groups(.init(status: .raised), raisedAndMet).map(\.level)
        XCTAssertEqual(levels, [.child, .adult])
    }

    func testTheQueryIsActiveOnlyWhenSomethingIsSet() {
        XCTAssertFalse(DigimonDex.Query().isActive)
        XCTAssertFalse(DigimonDex.Query(text: "  ").isActive)
        XCTAssertTrue(DigimonDex.Query(text: "아구").isActive)
        XCTAssertTrue(DigimonDex.Query(status: .raised).isActive)
        XCTAssertTrue(DigimonDex.Query(level: .child).isActive)
        XCTAssertTrue(DigimonDex.Query(sort: .name).isActive)
        XCTAssertFalse(DigimonDex.Query(sort: .name).isFiltered, "the filter icon fills only for a filter")
    }
}
