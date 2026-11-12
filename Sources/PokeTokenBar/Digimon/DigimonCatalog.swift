import Foundation

/// Growth stages, in order. `digitama` is the egg.
enum DigimonLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case digitama, babyI, babyII, child, adult, perfect, ultimate

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
    var next: DigimonLevel? { order + 1 < Self.allCases.count ? Self.allCases[order + 1] : nil }
}

enum DigimonAttribute: String, Codable, Sendable {
    case vaccine, data, virus, free, unknown
}

struct DigimonSpecies: Sendable, Hashable {
    let key: String
    let name: String
    let koreanName: String
    let level: DigimonLevel
    let attribute: DigimonAttribute
    /// Wikimon file name of the 64x64 Vital Bracelet sprite (popover / desktop pet).
    let vbSprite: String
    /// Wikimon file name of the 16x16 color V-Pet sprite (menu bar). Empty when there is none.
    let colorSprite: String
}

/// Where an evolution is attested. Only device sources are kept in the catalog.
enum EvolutionSource: String, Codable, Sendable {
    case vitalBracelet, digitalMonsterColor, pendulumColor
}

struct DigimonEvolution: Sendable, Hashable {
    let from: String
    let to: String
    let sources: [EvolutionSource]
    /// Marked in bold on Wikimon: the main anime evolution.
    let canon: Bool
}

/// One raisable line = one Vital Bracelet card roster.
struct DigimonLine: Sendable, Hashable {
    let id: String
    let card: String
    /// Spot color of the code-drawn egg.
    let eggColorHex: String
    let firstBaby: String
    let members: [String]
    /// The card's own evolutions as "from>to". Growth follows only these; nil = every evolution
    /// between members (test catalogs). The same two Digimon can be linked on one card and not another.
    var steps: Set<String>? = nil
    /// Steps that are a Jogress (a merge) on this card: kept in the data, never taken by growth.
    var mergeSteps: Set<String> = []
}

/// Evolution *data*: who can become whom. Conditions live in `EvolutionRules`.
struct DigimonCatalog: Sendable {
    let species: [String: DigimonSpecies]
    let lines: [String: DigimonLine]
    private let outgoing: [String: [DigimonEvolution]]

    init(species: [DigimonSpecies], evolutions: [DigimonEvolution], lines: [DigimonLine]) {
        self.species = Dictionary(species.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        self.lines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.outgoing = Dictionary(grouping: evolutions, by: \.from)
    }

    static let mvp = DigimonCatalog(species: DigimonCatalogData.species,
                                    evolutions: DigimonCatalogData.evolutions,
                                    lines: DigimonCatalogData.lines)

    func species(_ key: String) -> DigimonSpecies? { species[key] }

    /// Evolutions from `key` to the next level, limited to the members of `line`.
    func nextEvolutions(from key: String, in line: DigimonLine) -> [DigimonEvolution] {
        guard let level = species[key]?.level, let nextLevel = level.next else { return [] }
        let members = Set(line.members)
        return (outgoing[key] ?? []).filter { evo in
            members.contains(evo.to) && species[evo.to]?.level == nextLevel
                && line.steps.map { $0.contains("\(key)>\(evo.to)") } ?? true
        }
    }
}
