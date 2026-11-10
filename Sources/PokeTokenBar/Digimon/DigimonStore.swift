import Foundation
import Observation

/// Owns the Digimon companion for the app: feeds usage into `EvolutionEngine`, keeps the save file,
/// and hands new events to the UI. It plugs into the same two hooks the Pokemon companion used
/// (`AppDelegate.updateCompanion` / `onStoreRefreshed`).
@MainActor
@Observable
final class DigimonStore {
    struct Saved: Codable, Equatable {
        var version = 1
        var digimon: DigimonState
        var ledger = DigimonUsageLedger()
        var limits = DigimonLimitWatch()
    }

    private(set) var saved: Saved
    /// Events not yet shown by the UI (hatch, evolution, choice, graduation).
    private(set) var pendingEvents: [DigimonEvent] = []

    let engine: EvolutionEngine
    private let fileURL: URL
    private let clock: () -> Date

    init(fileURL: URL? = nil, engine: EvolutionEngine = EvolutionEngine(),
         clock: @escaping () -> Date = Date.init, firstLine: String = "agumon") {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.engine = engine
        self.clock = clock
        self.saved = Saved(digimon: .newEgg(lineID: firstLine))
        load()
    }

    static func defaultURL() -> URL {
        AppStatePaths.directory().appendingPathComponent("digimon-state.json")
    }

    // MARK: Read-only views for the UI

    var state: DigimonState { saved.digimon }
    var line: DigimonLine? { engine.catalog.lines[state.partner.lineID] }
    var species: DigimonSpecies? { state.partner.speciesKey.flatMap(engine.catalog.species) }
    var isEgg: Bool { state.partner.speciesKey == nil }
    var threshold: Int { engine.growth.threshold(for: state.partner.level) }
    var progress: Double { min(1, Double(state.partner.stageExp) / Double(max(1, threshold))) }
    var candidates: [DigimonSpecies] {
        (state.pendingChoice?.candidates ?? []).compactMap(engine.catalog.species)
    }

    // MARK: Inputs

    /// Called on every usage refresh with today's per-provider totals.
    func update(todayTokensByProvider: [String: Int], todayDate: String, hasUsageData: Bool) {
        let before = saved
        let deltas = saved.ledger.observe(todayTokensByProvider: todayTokensByProvider,
                                          todayDate: todayDate, hasUsageData: hasUsageData)
        let now = clock()
        var events: [DigimonEvent] = []
        for (provider, tokens) in deltas.sorted(by: { $0.key < $1.key }) {
            events += engine.addUsage(&saved.digimon, tokens: tokens, provider: provider, at: now)
        }
        events += engine.tick(&saved.digimon, now: now)
        finish(events, changedFrom: before)
    }

    /// Called after limits load: newly filled 5-hour / weekly windows count as care mistakes.
    func recordLimitWindows(_ windows: [CandyWindow], limitsReady: Bool) {
        let before = saved
        let hits = saved.limits.observe(windows, limitsReady: limitsReady)
        for _ in 0..<hits { engine.recordLimitHit(&saved.digimon) }
        finish([], changedFrom: before)
    }

    func recordBugDefeated() {
        let before = saved
        engine.recordBugDefeated(&saved.digimon)
        finish([], changedFrom: before)
    }

    func choose(_ key: String) {
        let before = saved
        let events = engine.choose(&saved.digimon, key, at: clock())
        finish(events, changedFrom: before)
    }

    func consumeEvents() -> [DigimonEvent] {
        defer { pendingEvents = [] }
        return pendingEvents
    }

    // MARK: Saving

    private func finish(_ events: [DigimonEvent], changedFrom before: Saved) {
        pendingEvents += events
        for event in events { AppLog.write("digimon \(event)") }
        if saved != before { save() }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.write("digimon save failed: \(error)")
        }
    }

    /// A missing file is a fresh install. An unreadable one is kept aside before starting over,
    /// so a bad write never silently destroys progress.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            saved = try JSONDecoder().decode(Saved.self, from: data)
        } catch {
            let stamp = Int(clock().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("digimon-state.corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            AppLog.write("digimon save unreadable, backed up to \(backup.lastPathComponent): \(error)")
        }
    }
}
