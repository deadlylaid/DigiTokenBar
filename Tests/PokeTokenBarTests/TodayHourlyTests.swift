import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// "Today by hour" (#6): `LocalUsageReader.hourlySeries` → `ProviderEnrichment.todayHourly` →
/// `UsageStore.todayHourlyTotals` → `TodayHourlyChart`.
///
/// The traps: an hour taken in the wrong zone (UTC instead of the zone that made `localDay`), a DST
/// day with a missing or doubled hour, a series from before midnight shown as today, an average of
/// averages across providers, and today's hours drifting from today's total.

private enum HourlyStubError: Error { case unavailable }
private struct HourlyNoClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw HourlyStubError.unavailable }
}
private struct HourlyNoCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct HourlyNoAntigravityLimits: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus { throw HourlyStubError.unavailable }
}
private struct HourlyNoStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private final class HourlyProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let reportsCost: Bool
    let daily: DailyUsage?
    let enrichment: ProviderEnrichment
    init(id: String, daily: DailyUsage?, enrichment: ProviderEnrichment, reportsCost: Bool = true) {
        self.id = id; self.displayName = id; self.reportsCost = reportsCost
        self.daily = daily; self.enrichment = enrichment
    }
    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

final class TodayHourlyTests: XCTestCase {
    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    private func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func date(_ zone: TimeZone, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    /// An entry whose `localDay` comes from `zone`, as the readers make it.
    private func entry(_ id: String, _ at: Date, _ zone: TimeZone, tokens: Int = 100,
                       cost: Double? = nil) -> LocalUsageReader.Entry {
        LocalUsageReader.Entry(id: id, date: at, localDay: LocalUsageReader.localDayFormatter(timeZone: zone).string(from: at),
                               model: "test-model", input: tokens, output: 0, cacheWrite: 0, cacheRead: 0,
                               explicitCost: cost)
    }

    private func tokens(_ series: HourlySeries) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: series.hours.filter { $0.totalTokens > 0 }.map { ($0.hour, $0.totalTokens) })
    }

    // MARK: Bucketing

    /// :59 stays in its hour, :00 opens the next; 23:59 is the day's last hour and 00:00 belongs to
    /// the next day, not to today's hour 0.
    func testHourBoundariesAndMidnight() {
        let now = date(la, 2026, 11, 18, 23, 59, 59)
        let entries = [
            entry("a", date(la, 2026, 11, 18, 13, 59, 59), la),
            entry("b", date(la, 2026, 11, 18, 14, 0, 0), la),
            entry("c", date(la, 2026, 11, 18, 0, 0, 0), la),
            entry("d", date(la, 2026, 11, 18, 23, 59, 59), la),
            entry("e", date(la, 2026, 11, 19, 0, 0, 0), la),     // tomorrow: not in today
            entry("f", date(la, 2026, 11, 17, 23, 59, 59), la),  // yesterday: only in the average
        ]
        let series = LocalUsageReader.hourlySeries(entries: entries, now: now, timeZone: la)
        XCTAssertEqual(series.day, "2026-11-18")
        XCTAssertEqual(series.hours.count, 24)
        XCTAssertEqual(series.hours.map(\.hour), Array(0..<24))
        XCTAssertEqual(tokens(series), [0: 100, 13: 100, 14: 100, 23: 100])
        XCTAssertEqual(series.earlierTokens[23], 100, "yesterday's 23:59 is an earlier day's hour 23")
        XCTAssertEqual(series.earlierActiveDays, ["2026-11-17"])
    }

    /// The hour comes from the zone that made `localDay`, not UTC: the same instants land in other
    /// hours in another zone.
    func testTheHourFollowsTheLocalZone() {
        let instant = date(seoul, 2026, 11, 18, 9, 30)   // 09:30 in Seoul is 00:30 UTC
        let seoulSeries = LocalUsageReader.hourlySeries(entries: [entry("a", instant, seoul)],
                                                        now: date(seoul, 2026, 11, 18, 22), timeZone: seoul)
        XCTAssertEqual(tokens(seoulSeries), [9: 100])
        let laNow = date(la, 2026, 11, 17, 22)
        let laSeries = LocalUsageReader.hourlySeries(entries: [entry("a", instant, la)], now: laNow, timeZone: la)
        XCTAssertEqual(laSeries.day, "2026-11-17")
        XCTAssertEqual(tokens(laSeries), [16: 100], "the same instant is 16:30 the day before in Los Angeles")
    }

    /// Fall back (1 a.m. happens twice): both go to slot 1. Spring forward (no 2 a.m.): slot 2 stays
    /// empty. Either way there are 24 slots and nothing is lost.
    func testDSTDaysKeepTwentyFourSlotsAndLoseNothing() {
        let fallBack = calendar(la).date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let firstOneThirty = fallBack.addingTimeInterval(90 * 60)          // 01:30 PDT
        let secondOneThirty = firstOneThirty.addingTimeInterval(3600)      // 01:30 PST
        let fall = LocalUsageReader.hourlySeries(entries: [entry("a", firstOneThirty, la), entry("b", secondOneThirty, la)],
                                                 now: date(la, 2026, 11, 1, 20), timeZone: la)
        XCTAssertEqual(fall.hours.count, 24)
        XCTAssertEqual(tokens(fall), [1: 200], "the repeated hour adds up in its one slot")

        let springStart = calendar(la).date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
        let beforeJump = springStart.addingTimeInterval(119 * 60)           // 01:59 PST
        let afterJump = beforeJump.addingTimeInterval(60)                   // 03:00 PDT
        let spring = LocalUsageReader.hourlySeries(entries: [entry("a", beforeJump, la), entry("b", afterJump, la)],
                                                   now: date(la, 2026, 3, 8, 20), timeZone: la)
        XCTAssertEqual(spring.hours.count, 24)
        XCTAssertEqual(tokens(spring), [1: 100, 3: 100], "no 2 a.m. on this day")
    }

    /// Today's slots sum to today's total exactly — the same entries through the same bucket — and
    /// cost and its coverage come along per hour.
    func testTodaysHoursSumToTodaysTotal() {
        let now = date(la, 2026, 11, 18, 15)
        var entries: [LocalUsageReader.Entry] = []
        for hour in 0...15 {
            entries.append(entry("t\(hour)", date(la, 2026, 11, 18, hour, 10), la, tokens: 1_000 + hour * 37, cost: 0.25))
        }
        entries.append(entry("zero", date(la, 2026, 11, 18, 3), la, tokens: 0))
        entries.append(entry("old", date(la, 2026, 11, 10, 3), la, tokens: 9_999))   // outside the 7 days
        let series = LocalUsageReader.hourlySeries(entries: entries, now: now, timeZone: la)
        let daily = LocalUsageReader.daily(entries: entries, localDay: "2026-11-18")
        XCTAssertEqual(series.totalTokens, daily?.totalTokens)
        XCTAssertEqual(series.hours.reduce(0.0) { $0 + $1.totalCost }, daily?.totalCost ?? -1, accuracy: 1e-9)
        XCTAssertEqual(series.hours[5].costCoverage, .source)
        XCTAssertTrue(series.earlierActiveDays.isEmpty, "11-10 is more than 7 days back")
    }

    /// The average divides by the earlier days that had usage, not by the calendar days.
    func testTheAverageCountsOnlyActiveEarlierDays() {
        let now = date(la, 2026, 11, 18, 12)
        let entries = [
            entry("a", date(la, 2026, 11, 17, 10), la, tokens: 300),
            entry("b", date(la, 2026, 11, 15, 10), la, tokens: 100),
            entry("c", date(la, 2026, 11, 15, 11), la, tokens: 50),
        ]
        let series = LocalUsageReader.hourlySeries(entries: entries, now: now, timeZone: la)
        XCTAssertEqual(series.earlierActiveDays, ["2026-11-17", "2026-11-15"])
        XCTAssertEqual(series.averageTokens[10], 200, accuracy: 1e-9)
        XCTAssertEqual(series.averageTokens[11], 25, accuracy: 1e-9)
        XCTAssertEqual(HourlySeries.empty(day: "x").averageTokens, Array(repeating: 0, count: 24))
    }

    // MARK: Across providers

    @MainActor
    private func store(_ providers: [HourlyProvider]) -> UsageStore {
        UsageStore(providers: providers,
                   claudeLimitsProvider: HourlyNoClaudeLimits(), codexLimitsProvider: HourlyNoCodexLimits(),
                   antigravityLimitsProvider: HourlyNoAntigravityLimits(), statusProvider: HourlyNoStatus(),
                   autoRefresh: false,
                   defaults: UserDefaults(suiteName: "TodayHourlyTests.\(UUID().uuidString)")!)
    }

    /// Two providers fed from real entries: the merged hours add up to the popover's today total,
    /// cost comes only from providers that report it, and the average divides by the union of
    /// active days — not each provider by its own.
    @MainActor
    func testProvidersAddUpToTodaysTotalAndAverageOverTheUnionOfDays() async throws {
        let zone = TimeZone.current
        let now = Date()
        let cal = calendar(zone)
        let start = cal.startOfDay(for: now)
        let hour = cal.component(.hour, from: now)
        func at(_ h: Int, minute: Int = 5) -> Date { start.addingTimeInterval(TimeInterval(h * 3600 + minute * 60)) }
        let yesterday = cal.date(byAdding: .day, value: -1, to: start)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: start)!
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: start)!

        let a = [entry("a1", at(0), zone, tokens: 500, cost: 1.0), entry("a2", at(hour, minute: 0), zone, tokens: 70, cost: 0.5),
                 entry("a3", yesterday.addingTimeInterval(9 * 3600), zone, tokens: 600),
                 entry("a4", twoDaysAgo.addingTimeInterval(9 * 3600), zone, tokens: 300)]
        let b = [entry("b1", at(0, minute: 30), zone, tokens: 40, cost: 9.0),
                 entry("b2", twoDaysAgo.addingTimeInterval(9 * 3600 + 60), zone, tokens: 0),   // no use: not an active day
                 entry("b3", threeDaysAgo.addingTimeInterval(9 * 3600), zone, tokens: 900)]
        let today = LocalUsageReader.todayKey()
        let providers = [
            HourlyProvider(id: "a", daily: LocalUsageReader.daily(entries: a, localDay: today),
                           enrichment: .local(entries: a, now: now)),
            HourlyProvider(id: "b", daily: LocalUsageReader.daily(entries: b, localDay: today),
                           enrichment: .local(entries: b, now: now), reportsCost: false),
        ]
        let store = store(providers)
        await store.refresh(scheduleEmptyRetry: false)

        let merged = store.todayHourlyTotals(today: today)
        XCTAssertEqual(merged.day, today)
        XCTAssertEqual(merged.totalTokens, store.todayTotalTokens, "the chart and the today total agree")
        XCTAssertEqual(merged.totalTokens, 610)
        XCTAssertEqual(merged.hours[0].totalTokens, hour == 0 ? 610 : 540)
        XCTAssertEqual(merged.hours[0].totalCost, hour == 0 ? 1.5 : 1.0, accuracy: 1e-9,
                       "a provider that does not report cost adds tokens only")
        XCTAssertEqual(merged.earlierActiveDays.count, 3, "yesterday, two and three days ago")
        XCTAssertEqual(merged.averageTokens[9], (600 + 300 + 900) / 3.0, accuracy: 1e-9)
    }

    /// A series from another day (phase 2 not rerun since midnight) is not today's and stays out.
    @MainActor
    func testASeriesFromAnotherDayIsLeftOut() async {
        var stale = ProviderEnrichment()
        stale.periodsOK = true
        var old = HourlySeries.empty(day: "2000-01-01")
        old.hours[3].totalTokens = 777
        stale.todayHourly = old
        stale.lastUsage = Date()
        let store = store([HourlyProvider(id: "stale", daily: nil, enrichment: stale)])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNotNil(store.snapshots.first?.todayHourly, "the snapshot carries it")
        XCTAssertEqual(store.todayHourlyTotals().totalTokens, 0)
        XCTAssertEqual(store.todayHourlyTotals(today: "2000-01-01").totalTokens, 777)
    }

    // MARK: Chart words and marks

    func testAxisMarksNeverCrowdTheCurrentHour() {
        let labels = (0..<24).compactMap { TodayHourlyMetrics.axisLabel(hour: $0, currentHour: 13) }
        XCTAssertEqual(labels, ["0", "6", "13", "18"], "12 gives way to 13")
        XCTAssertEqual((0..<24).compactMap { TodayHourlyMetrics.axisLabel(hour: $0, currentHour: 0) }, ["0", "6", "12", "18"])
        XCTAssertEqual(TodayHourlyMetrics.range(23), "23:00–24:00")
    }

    func testTooltipAndPeak() {
        var series = HourlySeries.empty(day: "2026-11-18")
        series.hours[9].totalTokens = 2_000_000
        series.hours[9].totalCost = 1.25
        series.hours[9].costCoverage = .source
        let l = L(.en)
        XCTAssertNil(TodayHourlyMetrics.peakHour(series), "one hour used: the readout already says it")
        series.hours[10].totalTokens = 3_000_000
        XCTAssertEqual(TodayHourlyMetrics.peakHour(series), 10)
        let average = Array(repeating: 0.0, count: 20) + [500_000, 0, 0, 0]
        XCTAssertNil(TodayHourlyMetrics.tooltip(series, average: average, hour: 21, currentHour: 12, showsCost: true, l: l),
                     "a later hour with no earlier use has nothing to say")
        let later = TodayHourlyMetrics.tooltip(series, average: average, hour: 20, currentHour: 12, showsCost: true, l: l)
        XCTAssertNil(later?.tokens, "a later hour shows no number for today")
        XCTAssertNotNil(later?.average)
        let past = TodayHourlyMetrics.tooltip(series, average: average, hour: 9, currentHour: 12, showsCost: true, l: l)
        XCTAssertEqual(past?.range, "09:00–10:00")
        XCTAssertNotNil(past?.cost)
        XCTAssertEqual(TodayHourlyMetrics.peak(series, average: average), 3_000_000)
    }

    /// The new view joins the cycle after the existing ones; the default does not move.
    func testTheVisualizationJoinsTheCycleAfterTheOthers() {
        XCTAssertEqual(ActivityVisualization.allCases, [.monthlyBars, .recentHeatmap, .todayByHour])
        XCTAssertEqual(ActivityVisualization.default, .monthlyBars)
        XCTAssertEqual(ActivityVisualization.recentHeatmap.next, .todayByHour)
        XCTAssertEqual(ActivityVisualization.todayByHour.next, .monthlyBars)
        for lang in AppLanguage.allCases {
            XCTAssertTrue(L(lang).hourlyAverageLegend(days: 4, window: 7).contains("4"), lang.rawValue)
        }
    }

    // MARK: Drawing (see below)

    @MainActor
    private func pixels(_ view: some View, width: CGFloat = 330) throws -> Data {
        let host = NSHostingView(rootView: view.frame(width: width).padding(4)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: width + 8, height: 90)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Empty, one hour and every hour draw without trouble, and the panel draws the same chart it
    /// wraps — a dropped `hourly` argument would compile and show an empty day.
    @MainActor
    func testTheChartDrawsForEmptyOneAndAllHoursAndThePanelPassesTheSeries() throws {
        let l = L(.en)
        var one = HourlySeries.empty(day: "2026-11-18")
        one.hours[8].totalTokens = 1_000
        var all = HourlySeries.empty(day: "2026-11-18")
        for h in 0..<24 { all.hours[h].totalTokens = (h + 1) * 1_000 }
        all.earlierTokens = (0..<24).map { $0 * 500 }
        all.earlierActiveDays = ["2026-11-17"]
        for series in [HourlySeries.empty(day: "2026-11-18"), one, all] {
            for hour in [0, 13, 23] {
                XCTAssertFalse(try pixels(TodayHourlyChart(series: series, showsCost: true, currentHour: hour, l: l)).isEmpty)
            }
        }
        let direct = try pixels(TodayHourlyChart(series: all, showsCost: false, currentHour: 15, l: l,
                                                 trailing: AnyView(PageDots(current: .todayByHour))))
        let panel = try pixels(ActivityPanel(visualization: .todayByHour, series: [], showsCost: false,
                                             hourly: all, currentHour: 15, today: "2026-11-18", l: l, onCycle: {}))
        let emptyPanel = try pixels(ActivityPanel(visualization: .todayByHour, series: [], showsCost: false,
                                                  currentHour: 15, today: "2026-11-18", l: l, onCycle: {}))
        XCTAssertNotEqual(direct, emptyPanel, "data must change the drawing, or this proves nothing")
        XCTAssertEqual(panel, direct, "the panel dropped the hourly series")
    }
}

/// The default activity chart (Settings, 2026-11-28): every opening starts at it, a click cycles for
/// that opening only, and the old "last clicked" value carries over once as the default.
@MainActor
final class DefaultActivityChartTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "DefaultActivityChartTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func store(_ defaults: UserDefaults) -> UsageStore {
        UsageStore(providers: [],
                   claudeLimitsProvider: HourlyNoClaudeLimits(), codexLimitsProvider: HourlyNoCodexLimits(),
                   antigravityLimitsProvider: HourlyNoAntigravityLimits(), statusProvider: HourlyNoStatus(),
                   autoRefresh: false, defaults: defaults)
    }

    func testOpeningsStartAtTheDefaultAndClicksAreNotSaved() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(ActivityVisualization.recentHeatmap.rawValue, forKey: UsageStore.defaultActivityVisualizationKey)
        let first = store(defaults)
        XCTAssertEqual(first.activityVisualization, .recentHeatmap, "the popover opens on the default")

        first.cycleActivityVisualization()
        XCTAssertEqual(first.activityVisualization, .todayByHour, "a click shows the next chart")
        XCTAssertEqual(first.defaultActivityVisualization, .recentHeatmap, "but the default stays")
        XCTAssertEqual(defaults.string(forKey: UsageStore.defaultActivityVisualizationKey), "recentHeatmap",
                       "and nothing is saved")
        XCTAssertNil(defaults.string(forKey: UsageStore.legacyActivityVisualizationKey),
                     "the old last-clicked key is not written any more")

        first.beginActivitySession()
        XCTAssertEqual(first.activityVisualization, .recentHeatmap, "the next opening is back at the default")
        first.cycleActivityVisualization()
        XCTAssertEqual(store(defaults).activityVisualization, .recentHeatmap, "a relaunch too")
    }

    func testChoosingTheDefaultSavesItAndShowsItNow() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let s = store(defaults)
        XCTAssertEqual(s.defaultActivityVisualization, .default)
        for choice in ActivityVisualization.allCases {
            s.defaultActivityVisualization = choice
            XCTAssertEqual(s.activityVisualization, choice)
            XCTAssertEqual(store(defaults).defaultActivityVisualization, choice)
        }
    }

    /// Existing users saw the last chart they clicked; that value becomes their default once.
    func testTheLastClickedChartCarriesOverOnceAsTheDefault() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("recentHeatmap", forKey: UsageStore.legacyActivityVisualizationKey)
        XCTAssertEqual(store(defaults).activityVisualization, .recentHeatmap, "nothing changes on update")
        XCTAssertEqual(defaults.string(forKey: UsageStore.defaultActivityVisualizationKey), "recentHeatmap")
        defaults.set("monthlyBars", forKey: UsageStore.legacyActivityVisualizationKey)
        XCTAssertEqual(store(defaults).defaultActivityVisualization, .recentHeatmap, "the carry-over runs once")
    }

    func testUnknownStoredValuesFallBackToTheDefault() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("someChartFromTheFuture", forKey: UsageStore.legacyActivityVisualizationKey)
        XCTAssertEqual(UsageStore.storedDefaultActivityVisualization(defaults), .default)
        defaults.set("anotherChartFromTheFuture", forKey: UsageStore.defaultActivityVisualizationKey)
        XCTAssertEqual(store(defaults).activityVisualization, .default, "never an empty popover")
    }

    /// The picker lists `allCases` with each case's own title, so a chart added later is offered.
    func testThePickerOffersEveryChartWithItsTitle() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let titles = ActivityVisualization.allCases.map { $0.title(l) }
            XCTAssertEqual(Set(titles).count, titles.count, "\(lang.rawValue): two charts share a title")
            XCTAssertFalse(l.defaultActivityView.isEmpty)
            XCTAssertFalse(l.defaultActivityViewHint.isEmpty)
        }
    }
}
