import Foundation

/// Turns repeated "tokens used today, per provider" snapshots into new tokens since the last
/// snapshot. Ported from `CompanionStore.update` so the Digimon side keeps the same guarantees:
/// - usage before installation is never counted (install baseline);
/// - each provider is tracked separately, and a provider first seen mid-day is seeded, not back-paid;
/// - a provider whose total goes down is re-based on its own line only;
/// - a refresh without current data (stale or empty snapshot) never moves the ledger;
/// - on a new date the whole current total counts, and providers known yesterday reopen at 0 so a
///   late recovery the same day is still counted.
struct DigimonUsageLedger: Codable, Sendable, Equatable {
    var baselineSet = false
    var claimedTodayByProvider: [String: Int] = [:]
    var lastDate = ""

    /// New tokens per provider since the previous observation (empty when nothing new).
    mutating func observe(todayTokensByProvider today: [String: Int], todayDate: String,
                          hasUsageData: Bool) -> [String: Int] {
        guard hasUsageData, !today.isEmpty else { return [:] }
        guard baselineSet else {
            baselineSet = true
            claimedTodayByProvider = today
            lastDate = todayDate
            return [:]
        }
        if todayDate != lastDate {
            lastDate = todayDate
            var ledger = Dictionary(uniqueKeysWithValues: claimedTodayByProvider.keys.map { ($0, 0) })
            for (provider, current) in today { ledger[provider] = current }
            claimedTodayByProvider = ledger
            return today.filter { $0.value > 0 }
        }
        var deltas: [String: Int] = [:]
        for (provider, current) in today {
            guard let previous = claimedTodayByProvider[provider] else {
                claimedTodayByProvider[provider] = current
                continue
            }
            if current < previous {
                claimedTodayByProvider[provider] = current
                AppLog.write("digimon usage regression provider=\(provider) date=\(todayDate) previous=\(previous) current=\(current) — rebased")
                continue
            }
            if current > previous { deltas[provider] = current - previous }
            claimedTodayByProvider[provider] = current
        }
        return deltas
    }
}

/// Counts 5-hour / weekly limits that newly reach 100% ("care mistakes"). Same edge rules as the
/// upstream candy grant (`CompanionStore.evaluateCandyGrants`): the first observation only seeds,
/// a window counts once until it drops below 100% or a new window (epoch) starts.
struct DigimonLimitWatch: Codable, Sendable, Equatable {
    var seeded = false
    var filled: [String: Bool] = [:]
    var epochs: [String: String] = [:]

    /// Number of limit windows that just became full.
    @MainActor
    mutating func observe(_ windows: [CandyWindow], limitsReady: Bool) -> Int {
        guard limitsReady else { return 0 }
        guard seeded else {
            for w in windows {
                if w.utilization >= 100 { filled[w.key] = true }
                if let epoch = w.epoch { epochs[w.key] = epoch }
            }
            seeded = true
            return 0
        }
        var hits = 0
        for w in windows {
            if let epoch = w.epoch {
                if let previous = epochs[w.key],
                   CompanionStore.isNewEpoch(previous: previous, current: epoch, kind: w.kind) {
                    filled[w.key] = nil
                }
                epochs[w.key] = epoch
            }
            guard w.utilization >= 100 else {
                filled[w.key] = nil
                continue
            }
            if filled[w.key] != true {
                filled[w.key] = true
                hits += 1
            }
        }
        return hits
    }
}
