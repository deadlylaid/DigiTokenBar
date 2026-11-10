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
    /// Called after every input with what happened (hatch, evolution, choice, graduation) and how
    /// many new tokens were fed, so the scenes can play it. Not called when nothing happened.
    @ObservationIgnored var onActivity: @MainActor (_ events: [DigimonEvent], _ fedTokens: Int) -> Void = { _, _ in }

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

    var expToday: Int { state.expDay == engine.dayKey(clock()) ? state.expToday : 0 }
    /// Hours left before the engine picks for the user (at least 1 while a choice is open).
    var choiceHoursLeft: Int? {
        guard let pending = state.pendingChoice else { return nil }
        let left = engine.growth.choiceTimeout - clock().timeIntervalSince(pending.offeredAt)
        return max(1, Int((left / 3600).rounded(.up)))
    }
    var menuGrowthText: String { "\(Int(progress * 100))%" }

    // MARK: Inputs
    //
    // Every input works on a copy and writes `saved` back only when it changed. The menu bar
    // observes this store and calls `update` from its own refresh. Mutating `saved` in place
    // (`saved.ledger.observe(...)`) notifies observers even when nothing changes, which would make
    // the two trigger each other forever (`testAnUpdateWithNothingNewDoesNotNotifyObservers`).

    /// Called on every usage refresh with today's per-provider totals.
    func update(todayTokensByProvider: [String: Int], todayDate: String, hasUsageData: Bool) {
        var next = saved
        let deltas = next.ledger.observe(todayTokensByProvider: todayTokensByProvider,
                                         todayDate: todayDate, hasUsageData: hasUsageData)
        let now = clock()
        var events: [DigimonEvent] = []
        for (provider, tokens) in deltas.sorted(by: { $0.key < $1.key }) {
            events += engine.addUsage(&next.digimon, tokens: tokens, provider: provider, at: now)
        }
        events += engine.tick(&next.digimon, now: now)
        commit(next, events, fed: deltas.values.reduce(0, +))
    }

    /// Called after limits load: newly filled 5-hour / weekly windows count as care mistakes.
    func recordLimitWindows(_ windows: [CandyWindow], limitsReady: Bool) {
        var next = saved
        let hits = next.limits.observe(windows, limitsReady: limitsReady)
        for _ in 0..<hits { engine.recordLimitHit(&next.digimon) }
        commit(next, [])
    }

    func recordBugDefeated() {
        var next = saved
        engine.recordBugDefeated(&next.digimon)
        commit(next, [])
    }

    func choose(_ key: String) {
        var next = saved
        let events = engine.choose(&next.digimon, key, at: clock())
        commit(next, events)
    }

    // MARK: Saving

    private func commit(_ next: Saved, _ events: [DigimonEvent], fed: Int = 0) {
        for event in events { AppLog.write("digimon \(event)") }
        if next != saved {
            saved = next
            save()
        }
        if !events.isEmpty || fed > 0 { onActivity(events, fed) }
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
