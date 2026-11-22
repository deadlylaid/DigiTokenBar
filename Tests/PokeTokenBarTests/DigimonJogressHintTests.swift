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

    /// The partner is said in words ("백신 또는 프리 속성의 성숙기 디지몬"), not a bare "프리·백신 성숙기" that did not
    /// read as "whose code to get" (user report, 2026-11-22).
    func testThePartnerIsSaidInWords() {
        let vaccineOrFree = DigimonJogress("namakemon>boutmon", level: .adult, attributes: [.free, .vaccine])
        XCTAssertEqual(ko.jogressNeed(vaccineOrFree, catalog: catalog), "백신 또는 프리 속성의 성숙기 디지몬")
        XCTAssertEqual(en.jogressNeed(vaccineOrFree, catalog: catalog), "a Vaccine or Free Adult")
        XCTAssertEqual(ko.jogressPartnerRow("백신 또는 프리 속성의 성숙기 디지몬", results: ["???"]),
                       "짝: 백신 또는 프리 속성의 성숙기 디지몬  →  ???")
    }

    /// Three examples always: met ones first, then well-known ones, each fitting the level and attributes.
    func testThreeExamplesThatFitMetOnesFirst() {
        let vaccineOrFree = DigimonJogress("namakemon>boutmon", level: .adult, attributes: [.free, .vaccine])
        let data = DigimonJogress("namakemon>divemon", level: .adult, attributes: [.data])
        let cases: [(DigimonJogress, Set<String>)] = [(vaccineOrFree, ["leomon", "togemon", "agumon"]), (vaccineOrFree, []),
                                                        (data, ["greymon"])]
        for (jogress, met) in cases {
            let names = ko.jogressExamples(jogress, catalog: catalog, met: met)
            XCTAssertEqual(names.count, 3, "\(jogress.step) \(met)")
            XCTAssertEqual(Set(names).count, 3, "no repeats")
            for n in names {
                let s = catalog.species.values.first { ko.name($0) == n }
                XCTAssertEqual(s?.level, DigimonLevel.adult, n)
                XCTAssertTrue(s.map { jogress.attributes.contains($0.attribute) } ?? false, "\(n) fits \(jogress.attributes)")
            }
        }
        XCTAssertEqual(ko.jogressExamples(vaccineOrFree, catalog: catalog, met: ["leomon", "togemon"]).first, "레오몬",
                       "a Digimon the user has met comes first")
        XCTAssertEqual(ko.jogressExamples(DigimonJogress("x>y", species: "greymon"), catalog: catalog, met: []), [],
                       "a named partner needs no examples")
    }
}
