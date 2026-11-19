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
    /// Each battle, to play it in the scenes.
    @ObservationIgnored var onBattle: @MainActor (_ foe: BattleFighter, _ result: BattleResult) -> Void = { _, _ in }
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
        var digimon = saved.digimon
        if freshInstall, waitForFirstEgg {
            engine.offerEggLines(&digimon, at: clock())
        } else {
            ensureEggOffer(&digimon)
        }
        if digimon != saved.digimon {
            saved.digimon = digimon
            save()   // the draw must not change if the app quits before the pick
        }
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
    /// Bugs caught in this stage, as the home shows them: back to 0 when it evolves (or hatches) and
    /// when it graduates. The hidden "20 bugs" evolutions count the same way. The lifetime total stays
    /// in the save (`lifetimeSignals`) but is not shown.
    var bugsThisStage: Int { state.partner.stageSignals.bugsDefeated }
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
    /// The lines drawn for the current egg, in the order drawn.
    var eggOfferLines: [DigimonLine] { (state.eggOffer ?? []).compactMap { engine.catalog.lines[$0] } }
    /// The other lines the egg may take: lines raised before (and the line it shows, if not drawn).
    var otherEggLines: [DigimonLine] {
        let offered = Set(state.eggOffer ?? [])
        return engine.eggLineChoices(for: state).subtracting(offered)
            .compactMap { engine.catalog.lines[$0] }.sorted { $0.id < $1.id }
    }
    var canChooseEggLine: Bool { isEgg && engine.eggLineChoices(for: state).count > 1 }

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
        events += engine.updateLuck(&next.digimon, at: now)
        commit(next, events, fed: deltas.values.reduce(0, +))
    }

    /// Called after limits load: newly filled 5-hour / weekly windows count as care mistakes.
    func recordLimitWindows(_ windows: [CandyWindow], limitsReady: Bool) {
        var next = saved
        let hits = next.limits.observe(windows, limitsReady: limitsReady)
        for _ in 0..<hits { engine.recordLimitHit(&next.digimon, at: clock()) }
        commit(next, [])
    }

    /// A big bug counts as several.
    func recordBugDefeated(count: Int = 1) {
        var next = saved
        for _ in 0..<max(0, min(count, 10)) { engine.recordBugDefeated(&next.digimon) }
        commit(next, [])
    }

    var tendencies: [EvolutionEngine.Tendency] { engine.tendencies(for: state, at: clock()) }
    /// The stage as the card counts it; nil when card conditions do not apply (off, an egg, or a stage
    /// that began before the app counted coding hours).
    var stagePerformance: EvolutionEngine.StagePerformance? {
        guard engine.growth.cardConditions, !isEgg, state.partner.stageStartedAt != nil else { return nil }
        return engine.performance(for: state, at: clock())
    }
    /// A full stage will merge by itself (named Jogress without friends' codes) instead of graduating.
    var canSpecialJogress: Bool {
        !engine.rules.friendJogress && engine.rules.specialJogress(for: state, in: engine.catalog) != nil
    }

    // MARK: Jogress with a friend's code

    /// A full stage is waiting for a friend's code.
    var isJogressOpen: Bool { engine.isJogressOpen(state) }
    /// What the open wait can merge into, and with whom.
    var jogressOptions: [DigimonJogress] { isJogressOpen ? engine.jogressOptions(for: state) : [] }
    /// When the wait ends and it grows as usual.
    var jogressDeadline: Date? { engine.jogressDeadline(state) }

    /// Merges with the friend's Digimon in the first code in `text`. Returns the friend's species.
    @discardableResult
    func jogress(withCode text: String) throws -> String {
        var next = saved
        let (partner, events) = try engine.jogress(&next.digimon, code: text, at: clock())
        commit(next, events)
        return partner.species
    }

    /// Grows as usual now instead of waiting for a friend's code.
    func skipJogress() {
        var next = saved
        let events = engine.skipJogress(&next.digimon, at: clock())
        commit(next, events)
    }

    func choose(_ key: String) {
        var next = saved
        let events = engine.choose(&next.digimon, key, at: clock())
        commit(next, events)
    }

    // MARK: Battles

    struct BattleOutcome: Equatable {
        let foe: BattleFighter
        let result: BattleResult
        /// Against another user's code (false: practice).
        let withCode: Bool
    }

    /// The last battle this run, for the result line on Home.
    private(set) var lastBattle: BattleOutcome?

    var practiceLeft: Int { engine.practiceLeft(state, at: clock()) }
    /// Practice battles allowed today (more on a day of fighting spirit).
    var practiceLimit: Int { engine.practiceLimit(state, at: clock()) }

    // MARK: Luck (the day's fortune, visitors, stamps)

    /// Today's book; nil before the first refresh of the day rolled it.
    var todayLuck: LuckBook? { state.luck?.day == engine.dayKey(clock()) ? state.luck : nil }
    /// Visitors that came today, in the order they came.
    var visitorsToday: [DigimonVisit] { (todayLuck?.visits ?? []).filter(\.arrived) }
    /// Visitors still to come today (who they are stays a surprise).
    var visitorsToCome: Int { (todayLuck?.visits ?? []).filter { !$0.arrived }.count }
    var stamps: Int { state.luck?.stamps ?? 0 }
    var stampCardsCompleted: Int { state.luck?.cardsCompleted ?? 0 }
    /// Species met as visitors, not counting the ones also raised.
    var sightingsCount: Int { (state.sightings ?? []).subtracting(state.dex).count }
    var canBattle: Bool { !isEgg }

    /// The user's battle code for today and this stage (saved, so it stays the same when copied again).
    func myBattleCode() -> String? {
        var next = saved
        guard let fighter = engine.myFighter(&next.digimon, at: clock()) else { return nil }
        commit(next, [])
        return BattleCode.encode(fighter)
    }

    /// A practice battle against a wild Digimon. nil when today's practice is used up (or an egg).
    @discardableResult
    func practiceBattle() -> BattleOutcome? {
        var next = saved
        var rng = SystemRandomNumberGenerator()
        guard let (foe, result) = engine.practiceBattle(&next.digimon, at: clock(), rng: &rng) else { return nil }
        commit(next, [])
        return finish(BattleOutcome(foe: foe, result: result, withCode: false))
    }

    /// A battle with the first battle code in `text` (what the user pasted or copied).
    @discardableResult
    func battle(withCode text: String) throws -> BattleOutcome {
        var next = saved
        let (foe, result) = try engine.codeBattle(&next.digimon, code: text, at: clock())
        commit(next, [])
        return finish(BattleOutcome(foe: foe, result: result, withCode: true))
    }

    private func finish(_ outcome: BattleOutcome) -> BattleOutcome {
        lastBattle = outcome
        AppLog.write("digimon battle \(outcome.withCode ? "code" : "practice") vs \(outcome.foe.species) won=\(outcome.result.won)")
        onBattle(outcome.foe, outcome.result)
        return outcome
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
        var clean = try DigimonSaveIO.sanitized(file.digimon, catalog: engine.catalog, growth: engine.growth)
        ensureEggOffer(&clean)
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

    /// Every egg in the store has its drawn lines. An egg from an older save gets a draw here,
    /// keeping the line it shows (that line stays pickable).
    private func ensureEggOffer(_ digimon: inout DigimonState) {
        guard digimon.partner.speciesKey == nil, digimon.eggOffer == nil else { return }
        digimon.eggOffer = engine.eggOffer(for: digimon, at: clock())
    }

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
