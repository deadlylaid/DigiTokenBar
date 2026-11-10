import Foundation

/// Growth numbers. Defaults follow docs/digimon/step2-engine-design.md.
struct GrowthRules: Sendable, Equatable {
    /// 200,000 tokens = 1 experience point.
    var tokensPerExp = 200_000
    /// Experience stops at this many points per day, so heavier token use earns nothing extra.
    var dailyExpCap = 150
    /// Same idea as PokeTokenBar's growth difficulty: 0.1 (fast) ... 2.0 (slow).
    var growthMultiplier = 1.0
    /// Local hours counted as "night".
    var nightHours = 0..<6
    /// Auto-pick the top candidate when the user has not chosen within this time.
    var choiceTimeout: TimeInterval = 24 * 60 * 60
    var maxChoices = 3

    static let standard = GrowthRules()

    /// Experience needed to leave each stage (ultimate = graduation).
    static let baseThresholds: [DigimonLevel: Int] = [
        .digitama: 20, .babyI: 40, .babyII: 60, .child: 120, .adult: 200, .perfect: 280, .ultimate: 300,
    ]

    func threshold(for level: DigimonLevel) -> Int {
        let base = Double(Self.baseThresholds[level] ?? 100)
        return max(1, Int((base * growthMultiplier).rounded(.up)))
    }
}

/// Evolution *conditions*, kept apart from the evolution data in `DigimonCatalog`.
struct EvolutionRules: Sendable {
    enum HiddenCondition: Sendable, Equatable {
        /// Limits filled while at the current stage (care mistakes).
        case limitHits(atLeast: Int)
        /// Bugs defeated while at the current stage.
        case bugsDefeated(atLeast: Int)
    }

    /// Special evolutions that only appear as candidates once their condition is met.
    var hidden: [String: HiddenCondition]
    /// Never offered by normal growth (e.g. Jogress results, added after the MVP).
    var locked: Set<String>

    static let mvp = EvolutionRules(
        hidden: [
            "blitzgreymon": .bugsDefeated(atLeast: 20),
            "cresgarurumon": .bugsDefeated(atLeast: 20),
            "donedevimon": .limitHits(atLeast: 3),
            "nidhoggmon": .limitHits(atLeast: 3),
        ],
        locked: ["omegamon"])

    func isMet(_ condition: HiddenCondition, by signals: GrowthSignals) -> Bool {
        switch condition {
        case .limitHits(let n): signals.limitHits >= n
        case .bugsDefeated(let n): signals.bugsDefeated >= n
        }
    }
}

/// Pure growth logic: no UI, no clock, no disk. Every input carries its own date.
struct EvolutionEngine: Sendable {
    let catalog: DigimonCatalog
    let rules: EvolutionRules
    let growth: GrowthRules
    let calendar: Calendar

    init(catalog: DigimonCatalog = .mvp, rules: EvolutionRules = .mvp,
         growth: GrowthRules = .standard, calendar: Calendar = .current) {
        self.catalog = catalog
        self.rules = rules
        self.growth = growth
        self.calendar = calendar
    }

    // MARK: Inputs

    /// New tokens from one provider. Returns what happened (hatch, evolution, choice, graduation).
    @discardableResult
    func addUsage(_ state: inout DigimonState, tokens: Int, provider: String, at date: Date) -> [DigimonEvent] {
        guard tokens > 0 else { return [] }
        let day = dayKey(date)
        if state.expDay != day {
            state.expDay = day
            state.expToday = 0
        }
        let isNight = growth.nightHours.contains(calendar.component(.hour, from: date))
        for keyPath in [\DigimonState.partner.stageSignals, \DigimonState.lifetimeSignals] {
            state[keyPath: keyPath].tokens += tokens
            if isNight { state[keyPath: keyPath].nightTokens += tokens }
            state[keyPath: keyPath].tokensByProvider[provider, default: 0] += tokens
            state[keyPath: keyPath].activeDays.insert(day)
        }

        let room = max(0, growth.dailyExpCap - state.expToday)
        let total = state.tokenRemainder + tokens
        let earned = min(total / growth.tokensPerExp, room)
        // Tokens past the daily cap are dropped, not banked for tomorrow.
        state.tokenRemainder = earned < room ? total % growth.tokensPerExp : 0
        state.expToday += earned
        state.partner.stageExp += earned
        if state.pendingChoice != nil {
            // Waiting for the user's pick: keep the bar full, don't overflow.
            state.partner.stageExp = min(state.partner.stageExp, growth.threshold(for: state.partner.level))
        }
        return advance(&state, at: date)
    }

    func recordLimitHit(_ state: inout DigimonState) {
        state.partner.stageSignals.limitHits += 1
        state.lifetimeSignals.limitHits += 1
    }

    func recordBugDefeated(_ state: inout DigimonState) {
        state.partner.stageSignals.bugsDefeated += 1
        state.lifetimeSignals.bugsDefeated += 1
    }

    /// The user picks one of the offered candidates.
    @discardableResult
    func choose(_ state: inout DigimonState, _ key: String, at date: Date) -> [DigimonEvent] {
        guard let pending = state.pendingChoice, pending.candidates.contains(key) else { return [] }
        state.pendingChoice = nil
        var events = evolve(&state, to: key, at: date)
        events += advance(&state, at: date)
        return events
    }

    /// Call periodically: auto-picks the top candidate after `choiceTimeout`.
    @discardableResult
    func tick(_ state: inout DigimonState, now: Date) -> [DigimonEvent] {
        guard let pending = state.pendingChoice, let first = pending.candidates.first,
              now.timeIntervalSince(pending.offeredAt) >= growth.choiceTimeout else { return [] }
        return choose(&state, first, at: now)
    }

    // MARK: Candidates

    /// Next-stage candidates for the current partner, best first, at most `maxChoices`.
    func candidates(for state: DigimonState) -> [String] {
        guard let line = catalog.lines[state.partner.lineID] else { return [] }
        guard let current = state.partner.speciesKey else { return [line.firstBaby] }
        let signals = state.partner.stageSignals
        let options = catalog.nextEvolutions(from: current, in: line).filter { evo in
            if rules.locked.contains(evo.to) { return false }
            if let condition = rules.hidden[evo.to] { return rules.isMet(condition, by: signals) }
            return true
        }
        let ranked = options
            .map { evo in (evo, score(evo, signals: signals, baseline: state.lifetimeSignals)) }
            .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.to < rhs.0.to }
            .map(\.0.to)
        return Array(ranked.prefix(growth.maxChoices))
    }

    /// How strongly the stage's usage pulls toward this candidate.
    func score(_ evo: DigimonEvolution, signals: GrowthSignals, baseline: GrowthSignals) -> Double {
        guard let target = catalog.species(evo.to) else { return 0 }
        var value: Double
        switch target.attribute {
        case .vaccine:
            // Daytime, steady, within limits.
            value = (1 - signals.nightShare) * (signals.limitHits == 0 ? 1 : 0.5)
        case .data:
            // Several tools, many active days.
            value = Double(min(signals.providerCount, 3)) / 3 * 0.5
                + min(Double(signals.activeDays.count) / 3, 1) * 0.5
        case .virus:
            // More night than *usual for this user*, or limits filled.
            value = max(0, signals.nightShare - baseline.nightShare) * 2
                + Double(min(signals.limitHits, 3)) * 0.3
        case .free, .unknown:
            value = 0.4
        }
        if evo.canon { value += 0.15 }
        // An unlocked special evolution always comes first: earning it should feel like a reward.
        if rules.hidden[evo.to] != nil { value += 2 }
        return value
    }

    // MARK: Growth

    private func advance(_ state: inout DigimonState, at date: Date) -> [DigimonEvent] {
        var events: [DigimonEvent] = []
        while state.pendingChoice == nil,
              state.partner.stageExp >= growth.threshold(for: state.partner.level) {
            let options = candidates(for: state)
            if state.partner.level == .ultimate || options.isEmpty {
                events += graduate(&state, at: date)
            } else if options.count == 1 {
                events += evolve(&state, to: options[0], at: date)
            } else {
                state.pendingChoice = PendingChoice(candidates: options, offeredAt: date)
                state.partner.stageExp = growth.threshold(for: state.partner.level)
                events.append(.choiceOffered(candidates: options))
            }
        }
        return events
    }

    private func evolve(_ state: inout DigimonState, to key: String, at date: Date) -> [DigimonEvent] {
        guard let species = catalog.species(key) else { return [] }
        let previous = state.partner.speciesKey
        let leftover = max(0, state.partner.stageExp - growth.threshold(for: state.partner.level))
        state.partner.speciesKey = key
        state.partner.level = species.level
        state.partner.stageExp = leftover
        state.partner.stageSignals = GrowthSignals()
        state.partner.path.append(key)
        state.dex.insert(key)
        if let previous {
            state.discoveredEvolutions.insert("\(previous)>\(key)")
            return [.evolved(from: previous, to: key)]
        }
        return [.hatched(species: key)]
    }

    private func graduate(_ state: inout DigimonState, at date: Date) -> [DigimonEvent] {
        let line = state.partner.lineID
        let path = state.partner.path
        state.graduates.append(GraduateRecord(lineID: line, path: path, graduatedAt: date))
        state.partner = DigimonPartner(lineID: line, speciesKey: nil, level: .digitama)
        state.pendingChoice = nil
        return [.graduated(lineID: line, path: path), .newEgg(lineID: line)]
    }

    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
