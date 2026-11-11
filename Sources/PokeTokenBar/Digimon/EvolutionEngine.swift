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
    /// False (the default, like a V-Pet): with several candidates the Digimon evolves straight into
    /// the best match for how it was raised. True brings back the choice cards.
    var userPicksEvolution = false

    static let standard = GrowthRules()

    /// Experience needed to leave each stage (ultimate = graduation).
    static let baseThresholds: [DigimonLevel: Int] = [
        .digitama: 20, .babyI: 40, .babyII: 60, .child: 120, .adult: 200, .perfect: 280, .ultimate: 300,
    ]

    func threshold(for level: DigimonLevel) -> Int {
        let base = Double(Self.baseThresholds[level] ?? 100)
        return max(1, Int((base * growthMultiplier).rounded(.up)))
    }

    /// Experience for a whole life, egg to graduation: more than this never means anything.
    var lifeThreshold: Int { DigimonLevel.allCases.reduce(0) { $0 + threshold(for: $1) } }
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
    /// Single evolutions ("from>to") that only happen as a Jogress, so growth never takes them.
    var lockedEdges: Set<String> = []

    static let mvp = EvolutionRules(
        hidden: [
            "blitzgreymon": .bugsDefeated(atLeast: 20),
            "cresgarurumon": .bugsDefeated(atLeast: 20),
            "donedevimon": .limitHits(atLeast: 3),
            "nidhoggmon": .limitHits(atLeast: 3),
        ],
        locked: ["omegamon"],
        lockedEdges: DigimonCatalogData.jogressEdges)

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

    /// Re-checks thresholds after the growth rules change (e.g. fast growth turned on): a stage that
    /// is now full evolves or offers its choice right away.
    @discardableResult
    func settle(_ state: inout DigimonState, at date: Date) -> [DigimonEvent] {
        advance(&state, at: date)
    }

    /// Call periodically: after `choiceTimeout`, picks the top evolution candidate, or the egg line.
    @discardableResult
    func tick(_ state: inout DigimonState, now: Date) -> [DigimonEvent] {
        if let offered = state.eggChoiceOfferedAt, now.timeIntervalSince(offered) >= growth.choiceTimeout {
            return chooseEggLine(&state, autoEggLine(for: state), at: now)
        }
        guard let pending = state.pendingChoice, let first = pending.candidates.first else { return [] }
        // A choice saved before choosing was turned off resolves at once.
        guard !growth.userPicksEvolution || now.timeIntervalSince(pending.offeredAt) >= growth.choiceTimeout else { return [] }
        return choose(&state, first, at: now)
    }

    /// Picks the line the egg hatches into. Allowed while it is still an egg. Closes an open egg
    /// choice, so an egg that already has enough experience hatches right away.
    @discardableResult
    func chooseEggLine(_ state: inout DigimonState, _ lineID: String, at date: Date) -> [DigimonEvent] {
        guard state.partner.speciesKey == nil, catalog.lines[lineID] != nil else { return [] }
        var events: [DigimonEvent] = []
        if state.partner.lineID != lineID {
            state.partner.lineID = lineID
            events.append(.newEgg(lineID: lineID))
        }
        state.eggChoiceOfferedAt = nil
        return events + advance(&state, at: date)
    }

    /// When the user did not pick: the line raised least often, the current one on a tie.
    func autoEggLine(for state: DigimonState) -> String {
        let current = state.partner.lineID
        let graduated = Dictionary(grouping: state.graduates, by: \.lineID).mapValues(\.count)
        return catalog.lines.keys.min { a, b in
            (graduated[a, default: 0], a == current ? 0 : 1, a) < (graduated[b, default: 0], b == current ? 0 : 1, b)
        } ?? current
    }

    // MARK: Candidates

    /// Next-stage candidates for the current partner, best first, at most `maxChoices`.
    func candidates(for state: DigimonState) -> [String] {
        Array(rankedOptions(for: state).prefix(growth.maxChoices))
    }

    /// Every next form growth can take now, best first (not cut to `maxChoices`).
    func rankedOptions(for state: DigimonState) -> [String] {
        guard let line = catalog.lines[state.partner.lineID] else { return [] }
        guard let current = state.partner.speciesKey else { return [line.firstBaby] }
        let signals = state.partner.stageSignals
        let options = catalog.nextEvolutions(from: current, in: line).filter { evo in
            if rules.locked.contains(evo.to) || rules.lockedEdges.contains("\(current)>\(evo.to)") { return false }
            if let condition = rules.hidden[evo.to] { return rules.isMet(condition, by: signals) }
            return true
        }
        let ranked = options
            .map { evo in (evo, score(evo, signals: signals, baseline: state.lifetimeSignals)) }
            .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.to < rhs.0.to }
            .map(\.0.to)
        return ranked
    }

    /// How strongly the stage's usage pulls toward this candidate.
    func score(_ evo: DigimonEvolution, signals: GrowthSignals, baseline: GrowthSignals) -> Double {
        guard let target = catalog.species(evo.to) else { return 0 }
        var value = pull(target.attribute, signals: signals, baseline: baseline)
        if evo.canon { value += 0.15 }
        // An unlocked special evolution always comes first: earning it should feel like a reward.
        if rules.hidden[evo.to] != nil { value += 2 }
        return value
    }

    /// How the stage's usage pulls toward an attribute (the part of the score the user steers).
    func pull(_ attribute: DigimonAttribute, signals: GrowthSignals, baseline: GrowthSignals) -> Double {
        switch attribute {
        case .vaccine:
            // Daytime, steady, within limits.
            return (1 - signals.nightShare) * (signals.limitHits == 0 ? 1 : 0.5)
        case .data:
            // Several tools, many active days.
            return Double(min(signals.providerCount, 3)) / 3 * 0.5
                + min(Double(signals.activeDays.count) / 3, 1) * 0.5
        case .virus:
            // More night than *usual for this user*, or limits filled.
            return max(0, signals.nightShare - baseline.nightShare) * 2
                + Double(min(signals.limitHits, 3)) * 0.3
        case .free, .unknown:
            return 0.4
        }
    }

    struct Tendency: Equatable {
        let attribute: DigimonAttribute
        let pull: Double
        /// The attribute of the candidate it would evolve into now.
        let leading: Bool
    }

    /// Which way it is growing: the attributes its next forms can have, how strongly the stage pulls
    /// toward each, and which one leads. Names stay hidden. Empty when there is no real fork.
    func tendencies(for state: DigimonState) -> [Tendency] {
        guard state.partner.speciesKey != nil, state.partner.level != .ultimate else { return [] }
        let options = rankedOptions(for: state).compactMap(catalog.species)
        let attributes = Set(options.map(\.attribute))
        guard attributes.count > 1, let lead = options.first?.attribute else { return [] }
        let order: [DigimonAttribute] = [.vaccine, .data, .virus, .free, .unknown]
        return order.filter(attributes.contains).map {
            Tendency(attribute: $0, pull: pull($0, signals: state.partner.stageSignals, baseline: state.lifetimeSignals),
                     leading: $0 == lead)
        }
    }

    // MARK: Growth

    private func advance(_ state: inout DigimonState, at date: Date) -> [DigimonEvent] {
        var events: [DigimonEvent] = []
        while state.pendingChoice == nil, state.eggChoiceOfferedAt == nil,
              state.partner.stageExp >= growth.threshold(for: state.partner.level) {
            let options = candidates(for: state)
            if state.partner.level == .ultimate || options.isEmpty {
                events += graduate(&state, at: date)
            } else if options.count == 1 || !growth.userPicksEvolution {
                events += evolve(&state, to: options[0], at: date)   // best match first
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
        state.eggChoiceOfferedAt = date   // the new egg waits for the user to pick its line
        return [.graduated(lineID: line, path: path), .newEgg(lineID: line)]
    }

    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
