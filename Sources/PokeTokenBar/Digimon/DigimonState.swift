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

    var nightShare: Double { tokens > 0 ? Double(nightTokens) / Double(tokens) : 0 }
    var providerCount: Int { tokensByProvider.values.filter { $0 > 0 }.count }
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

    static func newEgg(lineID: String) -> DigimonState {
        DigimonState(partner: DigimonPartner(lineID: lineID, speciesKey: nil, level: .digitama))
    }
}

/// Things the UI animates. The engine never touches the UI.
enum DigimonEvent: Equatable, Sendable {
    case hatched(species: String)
    case evolved(from: String, to: String)
    case choiceOffered(candidates: [String])
    case graduated(lineID: String, path: [String])
    case newEgg(lineID: String)
}
