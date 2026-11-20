import XCTest

/// The Pokémon side of the fork is gone (2026-11-20). Two leftovers were found when it was removed:
/// the usage recap still asked PokéAPI for missing dex names, and strings the Digimon app shows
/// still said "Pokémon" / "포켓몬" / "Pokédex". These scans fail if either comes back.
final class PokemonRemovalGuardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func swiftFiles(in folder: String) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: Self.root.appendingPathComponent(folder), includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testTheAppNeverTalksToPokeAPI() throws {
        let files = try swiftFiles(in: "Sources/PokeTokenBar")
        XCTAssertGreaterThan(files.count, 50, "the scan must actually read the app sources")
        let offenders = try files.filter {
            try String(contentsOf: $0, encoding: .utf8).lowercased().contains("pokeapi")
        }.map(\.lastPathComponent)
        XCTAssertEqual(offenders, [], "PokéAPI is Pokémon code; the Digimon app has no use for it")
    }

    func testShownStringsDoNotNamePokemon() throws {
        let words = ["pokémon", "pokemon", "pokédex", "포켓몬", "ポケモン", "покемон", "покедекс"]
        var offenders: [String] = []
        for file in ["Sources/PokeTokenBar/Core/Localization.swift",
                     "Sources/PokeTokenBar/Core/LocalizationErrors.swift"] {
            let lines = try String(contentsOf: Self.root.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\n")
            XCTAssertGreaterThan(lines.count, 20, file)
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                if words.contains(where: lower.contains) {
                    offenders.append("\((file as NSString).lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(offenders, [])
    }
}
