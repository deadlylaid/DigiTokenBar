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

/// Where an evolution is attested. Device sources, and Wikimon's Digimental Evolution Chart for the
/// armor evolutions no card has (step 16, tools/digimon/research/digimental-chart-routes.json).
enum EvolutionSource: String, Codable, Sendable {
    case vitalBracelet, digitalMonsterColor, pendulumColor, digimentalChart
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
    /// Who each Jogress route on the card merges with (a step can also have a normal route). A friend's
    /// code that fits takes it (`EvolutionEngine.jogressOptions`).
    var jogress: [DigimonJogress] = []
    /// Steps from a Child into an Armor Digimon ("from>to") and the Digimentals that open each, any one
    /// of them (Wormmon > Kongoumon: Miracles or Fate; the others have one). Growth never takes one by
    /// itself (`EvolutionRules.isLocked`); only using a Digimental does (steps 13 and 16). A step from the
    /// Digimental chart can skip stages: the Armor keeps its card stage (V-mon > Magnamon, an Ultimate).
    var digimentalSteps: [String: [Digimental]] = [:]
    /// What the card requires for each step (not for merges). Empty = no card data (test catalogs).
    var conditions: [DigimonStepCondition] = []

    /// The line has a route that a Digimental opens (armor evolution, step 13).
    var hasArmor: Bool { !digimentalSteps.isEmpty }

    /// The Digimentals that open this step (any one of them), empty for a step growth can take (or a merge).
    func digimentals(from: String, to: String) -> [Digimental] {
        digimentalSteps["\(from)>\(to)"] ?? []
    }

    /// The first Digimental that opens this step, nil for a step growth can take (or a merge).
    func digimental(from: String, to: String) -> Digimental? {
        digimentals(from: from, to: to).first
    }
}

/// A Jogress route: the step and the partner it needs, either a named Digimon or any Digimon of one
/// of these attributes at this level ("Jogress with Vaccine or Free Adult").
struct DigimonJogress: Sendable, Hashable {
    let step: String
    let species: String?
    let level: DigimonLevel?
    let attributes: [DigimonAttribute]

    init(_ step: String, level: DigimonLevel, attributes: [DigimonAttribute]) {
        self.step = step
        species = nil
        self.level = level
        self.attributes = attributes
    }

    init(_ step: String, species: String) {
        self.step = step
        self.species = species
        level = nil
        attributes = []
    }

    var from: String { String(step.split(separator: ">").first ?? "") }
    var to: String { String(step.split(separator: ">").last ?? "") }

    func accepts(_ partner: DigimonSpecies) -> Bool {
        if let species { return partner.key == species }
        return partner.level == level && attributes.contains(partner.attribute)
    }
}

/// A Vital Bracelet card's requirement for one step, as the device states it (0 = not required).
/// The app compares them only within the routes from the same Digimon (`EvolutionEngine`).
struct DigimonStepCondition: Sendable, Hashable {
    let step: String
    /// Vital Values: on the device from steps and heart rate; in the app, hours spent coding.
    let vital: Int
    /// Trophies (PP on the BE): daily missions on the device; in the app, good days (see `trophies`).
    let trophies: Int
    /// Battles and win ratio: kept for a later battle mode, not used yet.
    let battles: Int
    let winRatio: Int
    /// Taken only when no other route is met ("0-2 trophies or 0-499 Vital Values").
    let fallback: Bool

    init(_ step: String, vital: Int, trophies: Int, battles: Int, winRatio: Int, fallback: Bool) {
        self.step = step
        self.vital = vital
        self.trophies = trophies
        self.battles = battles
        self.winRatio = winRatio
        self.fallback = fallback
    }
}

/// Evolution *data*: who can become whom. Conditions live in `EvolutionRules`.
struct DigimonCatalog: Sendable {
    let species: [String: DigimonSpecies]
    /// Every species ordered by key: a stable order for seeded draws (dictionary order changes per run).
    let sortedSpecies: [DigimonSpecies]
    let lines: [String: DigimonLine]
    private let outgoing: [String: [DigimonEvolution]]
    /// line id -> step -> the card's requirement.
    private let conditionIndex: [String: [String: DigimonStepCondition]]

    init(species: [DigimonSpecies], evolutions: [DigimonEvolution], lines: [DigimonLine]) {
        self.species = Dictionary(species.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        self.sortedSpecies = self.species.values.sorted { $0.key < $1.key }
        self.lines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.outgoing = Dictionary(grouping: evolutions, by: \.from)
        self.conditionIndex = Dictionary(lines.map { line in
            (line.id, Dictionary(line.conditions.map { ($0.step, $0) }, uniquingKeysWith: { first, _ in first }))
        }, uniquingKeysWith: { first, _ in first })
    }

    static let mvp = DigimonCatalog(species: DigimonCatalogData.species,
                                    evolutions: DigimonCatalogData.evolutions,
                                    lines: DigimonCatalogData.lines)

    func species(_ key: String) -> DigimonSpecies? { species[key] }

    /// The card's requirement for `from>to` on this line, nil when the card data has none.
    func condition(from: String, to: String, in line: DigimonLine) -> DigimonStepCondition? {
        conditionIndex[line.id]?["\(from)>\(to)"]
    }

    /// Evolutions from `key` to the next level, limited to the members and routes of `line`. A route
    /// that skips levels counts only when the card has it (D-3 White and Red: Ukkomon, a Child, becomes
    /// Big Ukkomon, an Ultimate).
    func nextEvolutions(from key: String, in line: DigimonLine) -> [DigimonEvolution] {
        guard let level = species[key]?.level, let nextLevel = level.next else { return [] }
        let members = Set(line.members)
        return (outgoing[key] ?? []).filter { evo in
            guard members.contains(evo.to), let to = species[evo.to]?.level else { return false }
            guard let steps = line.steps else { return to == nextLevel }
            return to > level && steps.contains("\(key)>\(evo.to)")
        }
    }
}
