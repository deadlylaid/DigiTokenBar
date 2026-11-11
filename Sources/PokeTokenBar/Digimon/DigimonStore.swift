import Foundation
import Observation
import SystemConfiguration

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
    /// Called when the Digimon changed without an event: an import, a restore, or a new egg line.
    @ObservationIgnored var onLookChanged: @MainActor () -> Void = {}
    /// Written into exports and backups so a file says which Mac it came from. The local computer
    /// name, read without a network lookup (`Host.current()` can block on DNS; backups run at launch).
    @ObservationIgnored var deviceName: () -> String = { (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac" }

    private(set) var engine: EvolutionEngine
    let backups: DigimonBackups
    private let fileURL: URL
    private let clock: () -> Date
    @ObservationIgnored private var lastBackupAt: Date?

    /// `waitForFirstEgg`: on a fresh install the first egg also waits for the user to pick its line
    /// (the app passes true; tests that only need a growing Digimon leave it off).
    init(fileURL: URL? = nil, engine: EvolutionEngine = EvolutionEngine(),
         clock: @escaping () -> Date = Date.init, firstLine: String = "agumon", waitForFirstEgg: Bool = false) {
        let fileURL = fileURL ?? Self.defaultURL()
        self.fileURL = fileURL
        self.engine = engine
        self.clock = clock
        self.backups = DigimonBackups(directory: fileURL.deletingLastPathComponent().appendingPathComponent("digimon-backups"))
        self.saved = Saved(digimon: .newEgg(lineID: firstLine))
        let freshInstall = !FileManager.default.fileExists(atPath: fileURL.path)
        load()
        if freshInstall, waitForFirstEgg { saved.digimon.eggChoiceOfferedAt = clock() }
        lastBackupAt = backups.list().first?.file.savedAt
        backupIfDue()
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
    /// A new egg is waiting for the user to pick its line.
    var isChoosingEgg: Bool { state.eggChoiceOfferedAt != nil }
    var eggChoiceHoursLeft: Int? {
        guard let offered = state.eggChoiceOfferedAt else { return nil }
        let left = engine.growth.choiceTimeout - clock().timeIntervalSince(offered)
        return max(1, Int((left / 3600).rounded(.up)))
    }
    var lines: [DigimonLine] { engine.catalog.lines.values.sorted { $0.id < $1.id } }

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

    /// A big bug counts as several.
    func recordBugDefeated(count: Int = 1) {
        var next = saved
        for _ in 0..<max(0, min(count, 10)) { engine.recordBugDefeated(&next.digimon) }
        commit(next, [])
    }

    var tendencies: [EvolutionEngine.Tendency] { engine.tendencies(for: state) }

    func choose(_ key: String) {
        var next = saved
        let events = engine.choose(&next.digimon, key, at: clock())
        commit(next, events)
    }

    // MARK: Fast growth (for trying the app out)

    /// UserDefaults key for the Settings switch.
    static let fastGrowthKey = "digimonFastGrowth"
    /// Fast growth needs a tenth of the experience per stage: a whole life fits in one busy day.
    static let fastGrowthMultiplier = 0.1

    var isFastGrowth: Bool { engine.growth.growthMultiplier < 1 }

    /// Switches the stage thresholds. A stage that is already full under the new ones evolves (or
    /// offers its choice) right away; progress is never taken back when switching off.
    func setFastGrowth(_ fast: Bool) {
        let multiplier = fast ? Self.fastGrowthMultiplier : 1.0
        guard engine.growth.growthMultiplier != multiplier else { return }
        var growth = engine.growth
        growth.growthMultiplier = multiplier
        engine = EvolutionEngine(catalog: engine.catalog, rules: engine.rules, growth: growth, calendar: engine.calendar)
        var next = saved
        let events = engine.settle(&next.digimon, at: clock())
        commit(next, events)
    }

    /// While it is still an egg, the user picks which line it hatches into. Picking closes a waiting
    /// egg choice (the same line confirms it), so a full egg hatches at once.
    func chooseEggLine(_ lineID: String) {
        guard isEgg else { return }
        var next = saved
        let events = engine.chooseEggLine(&next.digimon, lineID, at: clock())
        commit(next, events)
    }

    // MARK: Export, import, backups

    func saveFile() -> DigimonSaveFile {
        DigimonSaveFile(savedAt: clock(), device: deviceName(), digimon: state)
    }

    func exportData() throws -> Data { try DigimonSaveIO.encode(saveFile()) }

    @discardableResult
    func backupNow(tag: String? = nil) throws -> URL {
        let file = saveFile()
        let url = try backups.write(file, tag: tag)
        lastBackupAt = file.savedAt
        return url
    }

    /// Replaces the Digimon with one from a file (import or restore). The current one is backed up
    /// first. The usage ledger and limit watch start over, so today's usage is not counted twice.
    func replace(with file: DigimonSaveFile, reason: String) throws {
        let clean = try DigimonSaveIO.sanitized(file.digimon, catalog: engine.catalog, growth: engine.growth)
        try backupNow(tag: "before-\(reason)")
        saved = Saved(digimon: clean)
        save()
        AppLog.write("digimon replaced by \(reason) from \(file.device) saved \(file.savedAt)")
        onLookChanged()
    }

    private func backupIfDue() {
        let now = clock()
        if let lastBackupAt, now.timeIntervalSince(lastBackupAt) < backups.interval { return }
        do { try backupNow() } catch { AppLog.write("digimon backup failed: \(error)") }
    }

    // MARK: Saving

    private func commit(_ next: Saved, _ events: [DigimonEvent], fed: Int = 0) {
        for event in events { AppLog.write("digimon \(event)") }
        if next != saved {
            saved = next
            save()
            backupIfDue()
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
    /// so a bad write never silently destroys progress. A readable one still goes through the
    /// sanitizing boundary: a hand-edited count must not crash every launch.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            var loaded = try JSONDecoder().decode(Saved.self, from: data)
            loaded.digimon = try DigimonSaveIO.sanitized(loaded.digimon, catalog: engine.catalog, growth: engine.growth)
            loaded.ledger.claimedTodayByProvider = loaded.ledger.claimedTodayByProvider.mapValues { DigimonSaveIO.clamp($0) }
            saved = loaded
        } catch {
            let stamp = Int(clock().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("digimon-state.corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            AppLog.write("digimon save unreadable, backed up to \(backup.lastPathComponent): \(error)")
        }
    }
}
