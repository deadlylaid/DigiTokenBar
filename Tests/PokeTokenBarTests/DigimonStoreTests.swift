import Observation
import XCTest
@testable import PokeTokenBar

final class DigimonUsageLedgerTests: XCTestCase {
    func testUsageBeforeInstallIsNeverCounted() {
        var ledger = DigimonUsageLedger()
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 900], todayDate: "d1", hasUsageData: true), [:])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 1_000], todayDate: "d1", hasUsageData: true),
                       ["claude": 100])
    }

    func testRefreshWithoutCurrentDataNeverMovesTheLedger() {
        var ledger = DigimonUsageLedger()
        _ = ledger.observe(todayTokensByProvider: ["claude": 100], todayDate: "d1", hasUsageData: true)
        let before = ledger
        XCTAssertEqual(ledger.observe(todayTokensByProvider: [:], todayDate: "d2", hasUsageData: true), [:])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 5], todayDate: "d2", hasUsageData: false), [:])
        XCTAssertEqual(ledger, before, "an empty or stale refresh must not consume the date boundary")
    }

    func testNewProviderMidDayIsSeededNotBackPaid() {
        var ledger = DigimonUsageLedger()
        _ = ledger.observe(todayTokensByProvider: ["claude": 100], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 100, "codex": 5_000], todayDate: "d1",
                                      hasUsageData: true), [:])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 100, "codex": 5_100], todayDate: "d1",
                                      hasUsageData: true), ["codex": 100])
    }

    func testAProviderGoingDownIsRebasedAloneAndNotRecredited() {
        var ledger = DigimonUsageLedger()
        _ = ledger.observe(todayTokensByProvider: ["claude": 1_000, "codex": 500], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 400, "codex": 600], todayDate: "d1",
                                      hasUsageData: true), ["codex": 100])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 450, "codex": 600], todayDate: "d1",
                                      hasUsageData: true), ["claude": 50])
    }

    func testAProviderMissingFromOneRefreshIsNotRecreditedWhenItReturns() {
        var ledger = DigimonUsageLedger()
        _ = ledger.observe(todayTokensByProvider: ["claude": 1_000, "codex": 500], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 1_000], todayDate: "d1", hasUsageData: true), [:])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 1_000, "codex": 500], todayDate: "d1",
                                      hasUsageData: true), [:])
    }

    func testNewDateCountsTodaysTotalsAndReopensLateProvidersAtZero() {
        var ledger = DigimonUsageLedger()
        _ = ledger.observe(todayTokensByProvider: ["claude": 9_000, "codex": 4_000], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 300], todayDate: "d2", hasUsageData: true),
                       ["claude": 300])
        XCTAssertEqual(ledger.observe(todayTokensByProvider: ["claude": 300, "codex": 200], todayDate: "d2",
                                      hasUsageData: true), ["codex": 200],
                       "codex was known yesterday, so its late first report today counts in full")
    }
}

final class DigimonLimitWatchTests: XCTestCase {
    private func window(_ util: Double, epoch: String? = "e1") -> CandyWindow {
        CandyWindow(key: "claude.session", name: "5h", kind: .session, utilization: util, epoch: epoch)
    }

    @MainActor
    func testFirstObservationOnlySeeds() {
        var watch = DigimonLimitWatch()
        XCTAssertEqual(watch.observe([window(100)], limitsReady: true), 0)
        XCTAssertEqual(watch.observe([window(100)], limitsReady: true), 0, "already full when we started")
    }

    @MainActor
    func testFillingCountsOnceUntilItDropsOrANewWindowStarts() {
        var watch = DigimonLimitWatch()
        XCTAssertEqual(watch.observe([window(40)], limitsReady: true), 0)
        XCTAssertEqual(watch.observe([window(100)], limitsReady: true), 1)
        XCTAssertEqual(watch.observe([window(100)], limitsReady: true), 0)
        XCTAssertEqual(watch.observe([window(10)], limitsReady: true), 0)
        XCTAssertEqual(watch.observe([window(100)], limitsReady: true), 1)
        XCTAssertEqual(watch.observe([window(100, epoch: "e2")], limitsReady: true), 1, "a new window re-arms")
    }

    @MainActor
    func testNothingHappensBeforeLimitsLoad() {
        var watch = DigimonLimitWatch()
        XCTAssertEqual(watch.observe([window(100)], limitsReady: false), 0)
        XCTAssertFalse(watch.seeded)
    }
}

@MainActor
final class DigimonStoreTests: XCTestCase {
    private var dir: URL!
    private var now = Date(timeIntervalSince1970: 1_793_000_000)  // fixed clock

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> DigimonStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return DigimonStore(fileURL: dir.appendingPathComponent("digimon-state.json"),
                            engine: EvolutionEngine(calendar: calendar), clock: { [unowned self] in self.now })
    }

    func testNewTokensAfterInstallGrowTheEgg() {
        let store = makeStore()
        var activity: [([DigimonEvent], Int)] = []
        store.onActivity = { activity.append(($0, $1)) }
        store.update(todayTokensByProvider: ["claude_code": 50_000_000], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(store.state.partner.stageExp, 0, "the install baseline is not counted")
        XCTAssertTrue(activity.isEmpty, "seeding the baseline is not activity")
        store.update(todayTokensByProvider: ["claude_code": 54_000_000], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(store.state.partner.stageExp, 0)
        XCTAssertEqual(store.state.partner.speciesKey, "botamon", "4M tokens = 20 exp hatches the egg")
        XCTAssertEqual(activity.map(\.0), [[.hatched(species: "botamon")]])
        XCTAssertEqual(activity.map(\.1), [4_000_000])
        store.update(todayTokensByProvider: ["claude_code": 54_000_000], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(activity.count, 1, "nothing new, nothing reported")
    }

    /// The menu bar observes the store and calls `update` from its own refresh. An update with nothing
    /// new must not notify observers, or the two would trigger each other forever.
    func testAnUpdateWithNothingNewDoesNotNotifyObservers() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 100], todayDate: "d1", hasUsageData: true)
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking {
            _ = store.progress
            _ = store.state
        } onChange: { flag.fired = true }
        store.update(todayTokensByProvider: ["claude_code": 100], todayDate: "d1", hasUsageData: true)
        store.recordLimitWindows([], limitsReady: false)
        XCTAssertFalse(flag.fired)
        store.update(todayTokensByProvider: ["claude_code": 300_100], todayDate: "d1", hasUsageData: true)
        XCTAssertTrue(flag.fired, "a real change still notifies")
    }

    func testProgressSurvivesARestart() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 2_000_001], todayDate: "d1", hasUsageData: true)
        store.recordBugDefeated()
        let reopened = makeStore()
        XCTAssertEqual(reopened.saved, store.saved)
        XCTAssertEqual(reopened.state.partner.stageExp, 10)
    }

    func testFilledLimitsBecomeCareMistakes() {
        let store = makeStore()
        let low = CandyWindow(key: "k", name: "5h", kind: .session, utilization: 20, epoch: "e1")
        let full = CandyWindow(key: "k", name: "5h", kind: .session, utilization: 100, epoch: "e1")
        store.recordLimitWindows([low], limitsReady: true)
        store.recordLimitWindows([full], limitsReady: true)
        XCTAssertEqual(store.state.partner.stageSignals.limitHits, 1)
        XCTAssertEqual(store.state.lifetimeSignals.limitHits, 1)
    }

    func testAnUnreadableSaveIsBackedUpAndTheAppStartsFresh() throws {
        let file = dir.appendingPathComponent("digimon-state.json")
        try Data("not json".utf8).write(to: file)
        let store = makeStore()
        XCTAssertTrue(store.isEgg)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("digimon-state.corrupt-") }, "\(names)")
    }

    func testAFullStageEvolvesWithoutAChoiceAndSaves() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude_code": 0 + 1], todayDate: "d1", hasUsageData: true)
        // Two capped days: egg -> baby I -> baby II -> child, then a full child stage evolves.
        store.update(todayTokensByProvider: ["claude_code": 100_000_001], todayDate: "d1", hasUsageData: true)
        now += 86_400
        store.update(todayTokensByProvider: ["claude_code": 100_000_000], todayDate: "d2", hasUsageData: true)
        XCTAssertEqual(store.state.partner.level, .adult)
        XCTAssertTrue(store.candidates.isEmpty, "nothing to pick")
        XCTAssertEqual(makeStore().state.partner.speciesKey, store.state.partner.speciesKey)
    }
}

/// The desktop pet once used a global mouse-moved monitor to know when the pointer was over it.
/// macOS answered with an Input Monitoring permission prompt at launch (kTCCServiceListenEvent).
/// Nothing in the Digimon code may watch input outside the app.
final class DigimonPermissionTests: XCTestCase {
    func testDigimonCodeNeverMonitorsInputOutsideTheApp() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/PokeTokenBar/Digimon").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 5, "found the Digimon sources at \(dir.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                XCTAssertFalse(line.contains("addGlobalMonitorForEvents"), "\(file.lastPathComponent): \(line)")
                XCTAssertFalse(line.contains("CGEvent.tapCreate"), "\(file.lastPathComponent): \(line)")
            }
        }
    }
}

@MainActor
final class DigimonSaveIOTests: XCTestCase {
    private var dir: URL!
    private var now = Date(timeIntervalSince1970: 1_793_000_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(in folder: URL? = nil) -> DigimonStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let store = DigimonStore(fileURL: (folder ?? dir).appendingPathComponent("digimon-state.json"),
                                 engine: EvolutionEngine(calendar: calendar), clock: { [unowned self] in self.now })
        store.deviceName = { "Test Mac" }
        return store
    }

    /// Grows a store past Agumon: two capped days.
    private func grown(_ store: DigimonStore) {
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 100_000_001], todayDate: "d1", hasUsageData: true)
        now += 86_400
        store.update(todayTokensByProvider: ["claude_code": 100_000_000], todayDate: "d2", hasUsageData: true)
    }

    func testExportThenImportOnAnotherMacKeepsTheDigimonButNotTheLedger() throws {
        let source = makeStore()
        grown(source)
        let data = try source.exportData()

        let otherMac = dir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherMac, withIntermediateDirectories: true)
        let target = makeStore(in: otherMac)
        target.update(todayTokensByProvider: ["claude_code": 7_000_000], todayDate: "d2", hasUsageData: true)
        try target.replace(with: DigimonSaveIO.decode(data), reason: "import")

        XCTAssertEqual(target.state, source.state)
        let exp = target.state.partner.stageExp
        target.update(todayTokensByProvider: ["claude_code": 7_000_000], todayDate: "d2", hasUsageData: true)
        XCTAssertEqual(target.state.partner.stageExp, exp, "usage seen before the import is not counted again")
        XCTAssertTrue(target.backups.list().contains { $0.id.contains("before-import") }, "the old Digimon was backed up")
    }

    func testHugeOrNegativeCountsAreClampedAtTheBoundary() throws {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.partner.speciesKey = "agumon"
        state.partner.level = .ultimate          // wrong on purpose: the species decides
        state.partner.stageExp = Int.max
        state.expToday = -5
        state.tokenRemainder = Int.max
        state.lifetimeSignals.tokens = Int.max
        state.lifetimeSignals.nightTokens = Int.max
        state.lifetimeSignals.bugsDefeated = Int.min
        state.lifetimeSignals.tokensByProvider = ["claude_code": Int.max]
        state.dex = ["agumon", "someday-a-new-digimon"]
        let engine = EvolutionEngine()
        let clean = try DigimonSaveIO.sanitized(state, catalog: engine.catalog, growth: engine.growth)
        XCTAssertEqual(clean.partner.level, .child)
        XCTAssertEqual(clean.partner.stageExp, engine.growth.lifeThreshold, "never more than a whole life")
        XCTAssertEqual(clean.expToday, 0)
        XCTAssertLessThan(clean.tokenRemainder, engine.growth.tokensPerExp)
        XCTAssertEqual(clean.lifetimeSignals.tokens, DigimonSaveIO.maxCount)
        XCTAssertEqual(clean.lifetimeSignals.bugsDefeated, 0)
        XCTAssertEqual(clean.dex, state.dex, "dex entries are never dropped, even unknown ones")
        // The clamped state survives the arithmetic that would have trapped.
        var grown = clean
        _ = engine.addUsage(&grown, tokens: 1_000_000, provider: "claude_code", at: now)
        engine.recordBugDefeated(&grown)
    }

    func testAPartnerThisVersionDoesNotKnowIsRejected() {
        var state = DigimonState.newEgg(lineID: "agumon")
        state.partner.speciesKey = "gabumon"     // not in the Agumon line
        let engine = EvolutionEngine()
        XCTAssertThrowsError(try DigimonSaveIO.sanitized(state, catalog: engine.catalog, growth: engine.growth)) {
            XCTAssertEqual($0 as? DigimonSaveError, .unknownSpecies("gabumon"))
        }
        XCTAssertThrowsError(try DigimonSaveIO.decode(Data(#"{"version":1}"#.utf8))) {
            XCTAssertEqual($0 as? DigimonSaveError, .notADigimonSave)
        }
    }

    func testAHandEditedSaveFileIsClampedAtLaunchInsteadOfCrashing() throws {
        let store = makeStore()
        grown(store)
        var saved = store.saved
        saved.digimon.lifetimeSignals.tokens = Int.max
        saved.ledger.claimedTodayByProvider["claude_code"] = Int.min
        try JSONEncoder().encode(saved).write(to: dir.appendingPathComponent("digimon-state.json"))
        let reopened = makeStore()
        XCTAssertEqual(reopened.state.lifetimeSignals.tokens, DigimonSaveIO.maxCount)
        XCTAssertEqual(reopened.saved.ledger.claimedTodayByProvider["claude_code"], 0)
        reopened.update(todayTokensByProvider: ["claude_code": 5], todayDate: "d2", hasUsageData: true)
    }

    func testBackupsRunEvery12HoursAndKeepTheNewest10() throws {
        let store = makeStore()
        XCTAssertEqual(store.backups.list().count, 1, "one at launch")
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 400_001], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(store.backups.list().count, 1, "not again within 12 hours")
        for i in 1...12 {
            now += 12 * 3600
            store.update(todayTokensByProvider: ["claude_code": 400_001 + i * 200_000], todayDate: "d1", hasUsageData: true)
        }
        let list = store.backups.list()
        XCTAssertEqual(list.count, 10)
        XCTAssertEqual(list.first?.file.savedAt, now, "newest first")
        XCTAssertEqual(list.first?.file.digimon, store.state)
    }

    func testRestoringABackupBringsTheOldDigimonBack() throws {
        let store = makeStore()
        let eggBackup = try XCTUnwrap(store.backups.list().first)
        grown(store)
        XCTAssertFalse(store.isEgg)
        var changed = 0
        store.onLookChanged = { changed += 1 }
        try store.replace(with: eggBackup.file, reason: "restore")
        XCTAssertTrue(store.isEgg)
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(makeStore().state, store.state, "the restore is saved")
    }

    func testTheEggLineCanChangeOnlyWhileItIsAnEgg() {
        let store = makeStore()
        store.chooseEggLine("gabumon")
        XCTAssertEqual(store.state.partner.lineID, "gabumon")
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 4_000_001], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(store.state.partner.speciesKey, "punimon", "a Gabumon-line egg hatches into Punimon")
        store.chooseEggLine("agumon")
        XCTAssertEqual(store.state.partner.lineID, "gabumon", "too late once hatched")
    }
}

@MainActor
final class DigimonFastGrowthTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-fast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFastGrowthNeedsATenthAndAFullStageMovesOnRightAway() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let store = DigimonStore(fileURL: dir.appendingPathComponent("s.json"), clock: { now })
        var activity: [DigimonEvent] = []
        store.onActivity = { events, _ in activity += events }
        // One capped day: Agumon with 30 of 120 experience.
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 100_000_001], todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(store.state.partner.speciesKey, "agumon")
        XCTAssertEqual(store.threshold, 120)
        XCTAssertNil(store.state.pendingChoice)

        store.setFastGrowth(true)
        XCTAssertTrue(store.isFastGrowth)
        XCTAssertEqual(store.state.partner.level, .adult, "30 of 12: it evolves at once")
        XCTAssertTrue(activity.contains { if case .evolved(from: "agumon", _) = $0 { return true } else { return false } })
        let adult = store.state.partner.speciesKey

        store.setFastGrowth(false)
        XCTAssertEqual(store.threshold, 200)
        XCTAssertEqual(store.state.partner.speciesKey, adult, "switching back never takes progress away")
    }
}

@MainActor
final class DigimonAgentBubbleTests: XCTestCase {
    private let ko = DigimonText(.ko)

    private func event(_ state: String, label: String? = nil, message: String? = nil) -> AgentActivityEvent {
        var c = URLComponents()
        c.scheme = AppIdentity.urlScheme
        c.host = "agent"
        c.queryItems = [URLQueryItem(name: "state", value: state)]
            + (label.map { [URLQueryItem(name: "label", value: $0)] } ?? [])
            + (message.map { [URLQueryItem(name: "message", value: $0)] } ?? [])
        return AgentActivityEvent(url: c.url!)!
    }

    func testWorkingShowsDotsWithoutABubble() {
        var tracker = AgentActivityTracker()
        tracker.apply(event("working", label: "digimon-tokenbar"), now: Date())
        let view = DigimonDeskPet.agentScene(tracker.summary, text: ko)
        XCTAssertTrue(view.working)
        XCTAssertNil(view.bubble)
    }

    func testAFinishedAgentComesBeforeOneWaitingAndThenGivesWay() {
        let start = Date()
        var tracker = AgentActivityTracker()
        tracker.apply(event("waiting", label: "app"), now: start)
        tracker.apply(event("waiting", label: "api"), now: start)
        tracker.apply(event("done", label: "web", message: "Build passed"), now: start)
        XCTAssertEqual(DigimonDeskPet.agentScene(tracker.summary, text: ko).bubble, "web: Build passed")
        tracker.expire(now: start.addingTimeInterval(AgentActivityTracker.doneDuration + 1))
        XCTAssertEqual(DigimonDeskPet.agentScene(tracker.summary, text: ko).bubble, "api: 확인이 필요해요 외 1개",
                       "the latest question, and how many more wait behind it")
    }

    func testAnUnlabeledAgentGetsNoPrefix() {
        var tracker = AgentActivityTracker()
        tracker.apply(event("done"), now: Date())
        XCTAssertEqual(DigimonDeskPet.agentScene(tracker.summary, text: ko).bubble, "다 했어요!")
        XCTAssertEqual(DigimonDeskPet.agentScene(tracker.summary, text: DigimonText(.en)).bubble, "all done!")
    }
}

@MainActor
final class DigimonFirstEggTests: XCTestCase {
    func testOnAFreshInstallTheFirstEggWaitsForItsLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let store = DigimonStore(fileURL: dir.appendingPathComponent("s.json"), clock: { now }, waitForFirstEgg: true)
        XCTAssertTrue(store.isChoosingEgg)
        XCTAssertEqual(store.eggChoiceHoursLeft, 24)
        store.update(todayTokensByProvider: ["claude_code": 1], todayDate: "d1", hasUsageData: true)
        store.update(todayTokensByProvider: ["claude_code": 5_000_001], todayDate: "d1", hasUsageData: true)
        XCTAssertTrue(store.isEgg, "no hatching before the pick")
        var played: [DigimonEvent] = []
        store.onActivity = { events, _ in played += events }
        store.chooseEggLine("agumon")
        XCTAssertEqual(played, [.hatched(species: "botamon")], "confirming the current line hatches it")
        XCTAssertFalse(store.isChoosingEgg)
        let reopened = DigimonStore(fileURL: dir.appendingPathComponent("s.json"), clock: { now }, waitForFirstEgg: true)
        XCTAssertFalse(reopened.isChoosingEgg, "only a fresh install asks")
    }
}
