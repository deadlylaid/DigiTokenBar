import Foundation

/// A Digimon save as a file, for export and automatic backups. Only the Digimon travels: the usage
/// ledger and the limit watch describe this Mac's logs, so they start fresh after an import or a
/// restore (the next refresh seeds them without crediting anything).
struct DigimonSaveFile: Codable, Equatable {
    static let formatName = "digitokenbar-save"

    var format = Self.formatName
    var version = 1
    var savedAt: Date
    var device: String
    var digimon: DigimonState
}

enum DigimonSaveError: Error, Equatable, LocalizedError {
    case notADigimonSave
    case unknownLine(String)
    case unknownSpecies(String)

    var errorDescription: String? {
        switch self {
        case .notADigimonSave: return "This file is not a DigiTokenBar save."
        case .unknownLine(let line): return "Unknown Digimon line: \(line)"
        case .unknownSpecies(let key): return "Unknown Digimon: \(key)"
        }
    }
}

enum DigimonSaveIO {
    /// Upper bound for every stored count. Far above any real use, and small enough that the sums
    /// the engine does (tokens + night tokens, counters + 1) can never overflow.
    static let maxCount = 1 << 50

    static func encode(_ file: DigimonSaveFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> DigimonSaveFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(DigimonSaveFile.self, from: data),
              file.format == DigimonSaveFile.formatName else { throw DigimonSaveError.notADigimonSave }
        return file
    }

    /// The one boundary for a Digimon state this run did not just compute (a file from another Mac,
    /// a backup, or the save file at launch). Numbers are clamped so later arithmetic cannot trap,
    /// and the partner must be a Digimon this catalog knows. The dex, discovered paths and graduates
    /// are kept as they are, even entries this version does not know: dropping them would lose data.
    static func sanitized(_ input: DigimonState, catalog: DigimonCatalog, growth: GrowthRules) throws -> DigimonState {
        var state = input
        guard let line = catalog.lines[state.partner.lineID] else {
            throw DigimonSaveError.unknownLine(state.partner.lineID)
        }
        if let key = state.partner.speciesKey {
            guard let species = catalog.species(key), line.members.contains(key) else {
                throw DigimonSaveError.unknownSpecies(key)
            }
            state.partner.level = species.level
        } else {
            state.partner.level = .digitama
        }
        // Up to a whole life: an egg waiting for its line keeps collecting experience.
        state.partner.stageExp = clamp(state.partner.stageExp, max: growth.lifeThreshold)
        state.expToday = clamp(state.expToday, max: growth.dailyExpCap)
        state.tokenRemainder = clamp(state.tokenRemainder, max: growth.tokensPerExp - 1)
        clampSignals(&state.partner.stageSignals)
        clampSignals(&state.lifetimeSignals)
        if let offer = state.eggOffer {
            let known = offer.filter { catalog.lines[$0] != nil }
            state.eggOffer = state.partner.speciesKey == nil && !known.isEmpty ? known : nil
        }
        if let pending = state.pendingChoice {
            let known = pending.candidates.filter { catalog.species($0) != nil && line.members.contains($0) }
            state.pendingChoice = known.isEmpty ? nil : PendingChoice(candidates: known, offeredAt: pending.offeredAt)
        }
        return state
    }

    static func clamp(_ value: Int, max upper: Int = maxCount) -> Int {
        Swift.min(Swift.max(value, 0), upper)
    }

    private static func clampSignals(_ signals: inout GrowthSignals) {
        signals.tokens = clamp(signals.tokens)
        signals.nightTokens = clamp(signals.nightTokens, max: signals.tokens)
        signals.tokensByProvider = signals.tokensByProvider.mapValues { clamp($0) }
        signals.limitHits = clamp(signals.limitHits)
        signals.bugsDefeated = clamp(signals.bugsDefeated)
    }
}

/// Automatic backups next to the save: one when the app starts and then every 12 hours while it
/// changes, plus one before an import or restore replaces the Digimon. The newest 10 are kept.
struct DigimonBackups {
    struct Entry: Identifiable, Equatable {
        var id: String { url.lastPathComponent }
        let url: URL
        let file: DigimonSaveFile
    }

    static let prefix = "digimon-backup-"

    let directory: URL
    var keep = 10
    var interval: TimeInterval = 12 * 3600

    /// Newest first. Files that cannot be read are skipped, not deleted.
    func list() -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.prefix) && $0.hasSuffix(".json") }
            .compactMap { name -> Entry? in
                let url = directory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url), let file = try? DigimonSaveIO.decode(data) else { return nil }
                return Entry(url: url, file: file)
            }
            .sorted { ($0.file.savedAt, $0.id) > ($1.file.savedAt, $1.id) }
    }

    func isDue(now: Date) -> Bool {
        guard let newest = list().first else { return true }
        return now.timeIntervalSince(newest.file.savedAt) >= interval
    }

    @discardableResult
    func write(_ file: DigimonSaveFile, tag: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        var name = Self.prefix + f.string(from: file.savedAt)
        if let tag { name += "-" + tag }
        var url = directory.appendingPathComponent(name + ".json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name)-\(n).json")
            n += 1
        }
        try DigimonSaveIO.encode(file).write(to: url, options: .atomic)
        prune()
        return url
    }

    private func prune() {
        for old in list().dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }
}
