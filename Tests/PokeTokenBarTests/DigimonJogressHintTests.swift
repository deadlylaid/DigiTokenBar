import XCTest
@testable import PokeTokenBar

/// A Jogress needed a friend's code, but nothing said which Digimon fits (user report, 2026-11-22): the home
/// listed only "백신·프리 성숙기" and a copied code was a bare "DTB1....". Now the copied code says whose it
/// is, and the needed partner comes with examples the user has met.
final class DigimonJogressHintTests: XCTestCase {
    private let catalog = EvolutionEngine().catalog
    private let ko = DigimonText(.ko), en = DigimonText(.en)

    func testACopiedCodeSaysWhoseItIsAndStillWorks() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fighter = BattleFighter(player: "friend", species: "greymon", level: .adult, training: 50, stage: 0,
                                    day: "2027-01-15", nonce: 7, issuedAt: now)
        let code = BattleCode.encode(fighter)
        let labeled = ko.labeledCode(code, species: catalog.species("greymon"))
        XCTAssertEqual(labeled, "그레이몬 · 성숙기 · 백신 | \(code)")
        XCTAssertEqual(en.labeledCode(code, species: catalog.species("greymon")), "Greymon · Adult · Vaccine | \(code)")
        XCTAssertEqual(try BattleCode.decode(labeled, catalog: catalog, now: now), fighter, "the label does not get in the way")
        XCTAssertEqual(ko.labeledCode(code, species: nil), code, "an egg's code stays bare")
    }

    func testTheNeededPartnerComesWithExamplesTheUserHasMet() {
        let vaccineOrFree = DigimonJogress("namakemon>boutmon", level: .adult, attributes: [.free, .vaccine])
        let data = DigimonJogress("namakemon>divemon", level: .adult, attributes: [.data])
        let met: Set<String> = ["greymon", "leomon", "garurumon", "birdramon", "togemon", "agumon"]
        XCTAssertEqual(ko.jogressPartnerWithExamples(vaccineOrFree, catalog: catalog, met: met),
                       "프리·백신 성숙기 (예: 가루몬, 그레이몬, 레오몬)", "three at most, in 가나다 order, Adults of those attributes only")
        XCTAssertEqual(ko.jogressPartnerWithExamples(data, catalog: catalog, met: met), "데이터 성숙기 (예: 니드몬)")
        XCTAssertEqual(ko.jogressPartnerWithExamples(data, catalog: catalog, met: ["greymon"]), "아무 데이터 성숙기",
                       "none met yet: any Digimon of that kind")
        XCTAssertEqual(en.jogressPartnerWithExamples(data, catalog: catalog, met: met), "Data Adult (e.g. Togemon)")
    }
}
