import Foundation

/// What happened while a Digimon was at its current stage (or over its whole life).
/// These feed the evolution conditions; none of them can be lost by not coding.
struct GrowthSignals: Codable, Sendable, Equatable {
    var tokens = 0
    var nightTokens = 0
    var tokensByProvider: [String: Int] = [:]
    var activeDays: Set<String> = []
    /// 5-hour / weekly limits filled ("care mistakes").
    var limitHits = 0
    /// Bugs defeated by the pet's attack.
    var bugsDefeated = 0
    /// Clock hours with usage, as "yyyy-MM-dd HH" (the card's Vital Values: time spent coding).
    /// Kept for the current stage only.
    var activeHours: Set<String> = []
    /// Tools used per day, and the days a usage limit filled (the card's trophies, see
    /// `EvolutionEngine.trophies`). Current stage only.
    var toolsByDay: [String: Set<String>] = [:]
    var limitDays: Set<String> = []
    /// Battles and wins, weighted: a battle with another user counts `GrowthRules.codeBattleWeight`.
    var battles = 0
    var battleWins = 0

    var nightShare: Double { tokens > 0 ? Double(nightTokens) / Double(tokens) : 0 }
    var providerCount: Int { tokensByProvider.values.filter { $0 > 0 }.count }
}

// In an extension, so the memberwise initializer stays.
extension GrowthSignals {
    private enum CodingKeys: String, CodingKey {
        case tokens, nightTokens, tokensByProvider, activeDays, limitHits, bugsDefeated, activeHours, toolsByDay, limitDays
        case battles, battleWins
    }

    /// Every field may be missing: saves from before a field existed decode with its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        nightTokens = try c.decodeIfPresent(Int.self, forKey: .nightTokens) ?? 0
        tokensByProvider = try c.decodeIfPresent([String: Int].self, forKey: .tokensByProvider) ?? [:]
        activeDays = try c.decodeIfPresent(Set<String>.self, forKey: .activeDays) ?? []
        limitHits = try c.decodeIfPresent(Int.self, forKey: .limitHits) ?? 0
        bugsDefeated = try c.decodeIfPresent(Int.self, forKey: .bugsDefeated) ?? 0
        activeHours = try c.decodeIfPresent(Set<String>.self, forKey: .activeHours) ?? []
        toolsByDay = try c.decodeIfPresent([String: Set<String>].self, forKey: .toolsByDay) ?? [:]
        limitDays = try c.decodeIfPresent(Set<String>.self, forKey: .limitDays) ?? []
        battles = try c.decodeIfPresent(Int.self, forKey: .battles) ?? 0
        battleWins = try c.decodeIfPresent(Int.self, forKey: .battleWins) ?? 0
    }
}

struct DigimonPartner: Codable, Sendable, Equatable {
    var lineID: String
    /// nil while it is still an egg.
    var speciesKey: String?
    var level: DigimonLevel
    var stageExp = 0
    var stageSignals = GrowthSignals()
    /// Species keys from the first baby to now.
    var path: [String] = []
    /// When the current stage began (hatching or the last evolution). Optional so saves from before
    /// it decode unchanged; the trophy rate then counts only the days with usage.
    var stageStartedAt: Date?
}

/// Evolution candidates waiting for the user's pick.
struct PendingChoice: Codable, Sendable, Equatable {
    var candidates: [String]
    var offeredAt: Date
}

struct GraduateRecord: Codable, Sendable, Equatable {
    var lineID: String
    var path: [String]
    var graduatedAt: Date
}

/// Everything the Digimon companion saves.
struct DigimonState: Codable, Sendable, Equatable {
    var partner: DigimonPartner
    var pendingChoice: PendingChoice?
    var lifetimeSignals = GrowthSignals()
    /// Daily experience cap bookkeeping.
    var expDay = ""
    var expToday = 0
    /// Tokens not yet worth one experience point.
    var tokenRemainder = 0
    /// Species the user has raised (the Digimon dex).
    var dex: Set<String> = []
    /// Evolution paths found so far, as "from>to".
    var discoveredEvolutions: Set<String> = []
    var graduates: [GraduateRecord] = []
    /// Set while a new egg waits for the user to pick its line: it does not hatch until then
    /// (experience keeps adding up), and the engine picks after `choiceTimeout`.
    /// Optional so saves from before it decode unchanged.
    var eggChoiceOfferedAt: Date?
    /// Lines drawn for the current egg (see `EvolutionEngine.offerEggLines`). Kept until it hatches
    /// so reopening the app never redraws them. Optional so saves from before it decode unchanged.
    var eggOffer: [String]?
    /// A random number standing for this save in battle codes (nothing personal). Made on first use.
    var playerID: String?
    /// Battle bookkeeping. Optional so saves from before battles decode unchanged.
    var battleBook: BattleBook?
    /// A full stage waiting for a friend's Jogress code (`EvolutionEngine.jogress`). nil when none.
    var jogressWait: JogressWait?
    /// Friend codes already used for a Jogress, as "player:nonce", newest last.
    var jogressCodes: [String]?
    /// The day's fortune and visitors and the stamp card (`EvolutionEngine.updateLuck`). Optional so
    /// saves from before it decode unchanged.
    var luck: LuckBook?
    /// Species met as visitors (the dex shows them as met). Optional for the same reason.
    var sightings: Set<String>?
    /// Digimental fragments and finished Digimentals (`DigimentalBag`, step 13). Optional for the same reason.
    var digimentals: DigimentalBag?

    static func newEgg(lineID: String) -> DigimonState {
        DigimonState(partner: DigimonPartner(lineID: lineID, speciesKey: nil, level: .digitama))
    }
}

struct BattleBook: Codable, Sendable, Equatable {
    /// The user's code for the current stage and day: the same every time it is copied, so both
    /// sides of a battle compute it from the same two codes.
    var myCode: BattleFighter?
    /// Codes already fought, as "player:nonce", newest last (at most `limit`).
    var fought: [String] = []
    var practiceDay = ""
    var practiceToday = 0
    static let limit = 200
}

/// A full stage that can merge, waiting for a friend's code (`GrowthRules.jogressWait`).
struct JogressWait: Codable, Sendable, Equatable {
    var openedAt: Date
    /// Skipped or timed out: the stage grows as usual.
    var over: Bool
}

/// Things the UI animates. The engine never touches the UI.
enum DigimonEvent: Equatable, Sendable {
    case hatched(species: String)
    case evolved(from: String, to: String)
    case choiceOffered(candidates: [String])
    case graduated(lineID: String, path: [String])
    case newEgg(lineID: String)
    /// A full stage can merge: it waits for a friend's code (the possible results).
    case jogressOffered(options: [String])
    /// Merged with a friend's Digimon.
    case jogressed(from: String, partner: String, to: String)
    /// A visitor came by (`EvolutionEngine.updateLuck`).
    case visited(species: String, tier: VisitorTier, firstSeen: Bool)
    /// The stamp card filled: a very rare visitor comes right away.
    case stampCardFull
    /// A Digimental fragment was found (`DigimentalLoop.swift`).
    case fragmentFound(Digimental, from: FragmentSource)
    /// Three fragments made a Digimental.
    case digimentalMade(Digimental)
}
