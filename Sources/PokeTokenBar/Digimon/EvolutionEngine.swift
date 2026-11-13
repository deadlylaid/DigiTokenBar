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
    /// How many lines a new egg offers (drawn at random, lines never raised first).
    var eggOfferSize = 3
    /// The card's requirements decide which routes are open (`growthOptions`). Off = every allowed
    /// route, picked by tendency only.
    var cardConditions = true
    /// Average hours of coding per coding day that meets the hardest Vital Values route of a Digimon.
    /// Set from the user's own logs (2026-11: median 4 h, best days 6 h).
    var vitalHoursPerDay = 6.0
    /// Trophies per day of the stage that meet the hardest trophy route. A day with one tool gives at
    /// most 2 (coding, no full limit), so coding every day within limits is enough; a day with two
    /// tools gives 3 and makes up for a missed day.
    var trophiesPerDay = 2.0

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
    /// Single evolutions ("from>to") growth never takes, on every line. The card data adds its own
    /// Jogress steps per line (`DigimonLine.mergeSteps`); see `isLocked`.
    var lockedEdges: Set<String> = []
    /// Named Jogress across cards (the device's War Greymon + Metal Garurumon = Omegamon). The app has
    /// no backup slot, so the partner counts once it is in the dex (raised before). It takes the place
    /// of graduation when the stage is full.
    var specialJogress: [SpecialJogress] = []

    struct SpecialJogress: Sendable, Equatable, Hashable {
        let from: String
        let partner: String
        let to: String
    }

    static let mvp = EvolutionRules(
        hidden: [
            "blitzgreymon": .bugsDefeated(atLeast: 20),
            "cresgarurumon": .bugsDefeated(atLeast: 20),
            "donedevimon": .limitHits(atLeast: 3),
            "nidhoggmon": .limitHits(atLeast: 3),
        ],
        // A named Jogress result is reached only by that merge, never by growth.
        locked: Set(DigimonCatalogData.specialJogress.map(\.to)),
        specialJogress: DigimonCatalogData.specialJogress)

    /// The special Jogress this Digimon can do now, if any.
    func specialJogress(for state: DigimonState, in catalog: DigimonCatalog) -> SpecialJogress? {
        guard let current = state.partner.speciesKey,
              let line = catalog.lines[state.partner.lineID] else { return nil }
        return specialJogress.first {
            $0.from == current && state.dex.contains($0.partner) && line.members.contains($0.to)
                && catalog.species($0.to) != nil
        }
    }

    /// A step growth never takes on this line: a Jogress on its card, or locked everywhere.
    func isLocked(_ from: String, _ to: String, in line: DigimonLine) -> Bool {
        let step = "\(from)>\(to)"
        return lockedEdges.contains(step) || line.mergeSteps.contains(step)
    }

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
        let hour = calendar.component(.hour, from: date)
        let isNight = growth.nightHours.contains(hour)
        state.partner.stageSignals.activeHours.insert(String(format: "%@ %02d", day, hour))
        state.partner.stageSignals.toolsByDay[day, default: []].insert(provider)
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

    func recordLimitHit(_ state: inout DigimonState, at date: Date? = nil) {
        state.partner.stageSignals.limitHits += 1
        state.lifetimeSignals.limitHits += 1
        if let date { state.partner.stageSignals.limitDays.insert(dayKey(date)) }
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

    /// Picks the line the egg hatches into: one of the drawn lines, a line raised before, or the
    /// line it already shows. Allowed while it is still an egg. Closes an open egg choice, so an egg
    /// that already has enough experience hatches right away.
    @discardableResult
    func chooseEggLine(_ state: inout DigimonState, _ lineID: String, at date: Date) -> [DigimonEvent] {
        guard state.partner.speciesKey == nil, eggLineChoices(for: state).contains(lineID) else { return [] }
        var events: [DigimonEvent] = []
        if state.partner.lineID != lineID {
            state.partner.lineID = lineID
            events.append(.newEgg(lineID: lineID))
        }
        state.eggChoiceOfferedAt = nil
        return events + advance(&state, at: date)
    }

    /// Every line the current egg may take. Before a draw exists (saves from before it), any line.
    func eggLineChoices(for state: DigimonState) -> Set<String> {
        guard let offer = state.eggOffer else { return Set(catalog.lines.keys) }
        return Set(offer).union(raisedLines(for: state)).union([state.partner.lineID])
            .filter { catalog.lines[$0] != nil }
    }

    /// Lines this user has raised to graduation (they can always be picked again).
    func raisedLines(for state: DigimonState) -> Set<String> {
        Set(state.graduates.map(\.lineID)).filter { catalog.lines[$0] != nil }
    }

    /// Draws the lines a new egg offers: `eggOfferSize` lines at random, lines never raised first,
    /// raised ones only to fill up. The draw is seeded by the time and the number of graduations,
    /// so it is the same every time for the same egg and is saved until the egg hatches.
    func eggOffer(for state: DigimonState, at date: Date) -> [String] {
        let raised = raisedLines(for: state)
        var rng = SeededGenerator(seed: date.timeIntervalSince1970.bitPattern &+ UInt64(state.graduates.count))
        let all = catalog.lines.keys.sorted()
        let fresh = all.filter { !raised.contains($0) }.shuffled(using: &rng)
        let again = all.filter { raised.contains($0) }.shuffled(using: &rng)
        return Array((fresh + again).prefix(growth.eggOfferSize))
    }

    /// Opens the line pick for a new egg: draws its lines and shows the first of them.
    func offerEggLines(_ state: inout DigimonState, at date: Date) {
        let offer = eggOffer(for: state, at: date)
        state.eggOffer = offer
        state.eggChoiceOfferedAt = date
        if let first = offer.first { state.partner.lineID = first }
    }

    /// When the user did not pick: among the drawn lines, the one raised least often, the line the
    /// egg already shows on a tie.
    func autoEggLine(for state: DigimonState) -> String {
        let current = state.partner.lineID
        let graduated = Dictionary(grouping: state.graduates, by: \.lineID).mapValues(\.count)
        let pool = state.eggOffer.map { Set($0) } ?? Set(catalog.lines.keys)
        return pool.filter { catalog.lines[$0] != nil }.min { a, b in
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
        let open = catalog.nextEvolutions(from: current, in: line).filter { evo in
            !rules.locked.contains(evo.to) && !rules.isLocked(current, evo.to, in: line)
        }
        let earned = open.filter { evo in rules.hidden[evo.to].map { rules.isMet($0, by: signals) } ?? true }
        // A hidden evolution that is the only way on is the device's normal route (NeoDevimon ->
        // DoneDevimon): it opens without its condition instead of ending the line early.
        let options = earned.isEmpty ? open : earned
        let ranked = options
            .map { evo in (evo, score(evo, signals: signals, baseline: state.lifetimeSignals)) }
            .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.to < rhs.0.to }
            .map(\.0.to)
        return ranked
    }

    // MARK: Card conditions

    /// How the stage went, as the card counts it (each 0...1).
    struct StagePerformance: Equatable {
        /// Vital Values: average hours of coding per coding day, against `vitalHoursPerDay`.
        let vital: Double
        /// Trophies per day of the stage, against `trophiesPerDay`.
        let trophies: Double
        let hoursPerDay: Double
        let trophyCount: Int
    }

    /// Trophies of the stage: each day with usage gives 1, plus 1 without a filled usage limit, plus
    /// 1 with two or more tools.
    func trophies(_ signals: GrowthSignals) -> Int {
        signals.activeDays.reduce(0) { sum, day in
            sum + 1 + (signals.limitDays.contains(day) ? 0 : 1) + ((signals.toolsByDay[day]?.count ?? 0) >= 2 ? 1 : 0)
        }
    }

    func performance(for state: DigimonState, at now: Date) -> StagePerformance {
        let s = state.partner.stageSignals
        let codingDays = max(1, s.activeDays.count)
        let hoursPerDay = Double(s.activeHours.count) / Double(codingDays)
        // Days of the stage so far, counting the ones without usage (they give no trophies).
        var stageDays = codingDays
        if let start = state.partner.stageStartedAt {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            stageDays = max(codingDays, days + 1)
        }
        let count = trophies(s)
        return StagePerformance(vital: min(1, hoursPerDay / growth.vitalHoursPerDay),
                                trophies: min(1, Double(count) / Double(stageDays) / growth.trophiesPerDay),
                                hoursPerDay: hoursPerDay, trophyCount: count)
    }

    /// The forms growth may take now, best first. The card's requirements are compared only among
    /// the routes from the current Digimon: the hardest one needs a full stage (performance 1), the
    /// others their share of it. Among the met routes the tendency picks, as before. With none met,
    /// the easiest route: the card's fallback when it has one (it requires nothing), so growth never
    /// stops. The fallback is never taken while another route is met.
    func growthOptions(for state: DigimonState, at now: Date) -> [String] {
        let ranked = rankedOptions(for: state)
        // A stage that began before the app counted coding hours (no start date) evolves as before.
        guard growth.cardConditions, state.partner.stageStartedAt != nil, let current = state.partner.speciesKey,
              let line = catalog.lines[state.partner.lineID] else { return ranked }
        let conditions = ranked.compactMap { catalog.condition(from: current, to: $0, in: line) }
        let stat = conditions.filter { !$0.fallback && ($0.vital > 0 || $0.trophies > 0) }
        guard !stat.isEmpty else { return ranked }
        let maxVital = Double(stat.map(\.vital).max() ?? 0)
        let maxTrophies = Double(stat.map(\.trophies).max() ?? 0)
        func difficulty(_ c: DigimonStepCondition) -> Double {
            max(maxVital > 0 ? Double(c.vital) / maxVital : 0, maxTrophies > 0 ? Double(c.trophies) / maxTrophies : 0)
        }
        let p = performance(for: state, at: now)
        var met: [String] = []
        for key in ranked {
            guard let c = catalog.condition(from: current, to: key, in: line) else { met.append(key); continue }
            if c.fallback { continue }
            let vitalOK = maxVital == 0 || p.vital + 1e-9 >= Double(c.vital) / maxVital
            let trophiesOK = maxTrophies == 0 || p.trophies + 1e-9 >= Double(c.trophies) / maxTrophies
            // A hidden evolution already earned its own condition.
            if (vitalOK && trophiesOK) || rules.hidden[key] != nil { met.append(key) }
        }
        if !met.isEmpty { return met }
        let easiest = ranked.min { a, b in
            let ca = catalog.condition(from: current, to: a, in: line), cb = catalog.condition(from: current, to: b, in: line)
            return (ca.map(difficulty) ?? 0) < (cb.map(difficulty) ?? 0)
        }
        return easiest.map { [$0] } ?? ranked
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
        /// A route of this attribute is open now (false: the card's requirements are not met yet).
        var open = true
    }

    /// Which way it is growing: the attributes its next forms can have, how strongly the stage pulls
    /// toward each, and which one leads. Names stay hidden. Empty when there is no real fork.
    /// With `now`, the leading attribute is the one growth would take now, after the card's
    /// requirements (`growthOptions`), and the bars of routes the card keeps closed are marked. A
    /// fallback route shows only while growth would take it: more coding never opens it.
    func tendencies(for state: DigimonState, at now: Date? = nil) -> [Tendency] {
        guard let current = state.partner.speciesKey, state.partner.level != .ultimate else { return [] }
        let growingNow = now.map { growthOptions(for: state, at: $0).compactMap(catalog.species) }
        let line = catalog.lines[state.partner.lineID]
        let options = rankedOptions(for: state).filter { key in
            guard now != nil, let line, catalog.condition(from: current, to: key, in: line)?.fallback == true else { return true }
            return growingNow?.contains { $0.key == key } ?? true
        }.compactMap(catalog.species)
        let attributes = Set(options.map(\.attribute))
        let growing = growingNow ?? options
        guard attributes.count > 1, let lead = (growing.first ?? options.first)?.attribute else { return [] }
        let openAttributes = Set(growing.map(\.attribute))
        let order: [DigimonAttribute] = [.vaccine, .data, .virus, .free, .unknown]
        return order.filter(attributes.contains).map {
            Tendency(attribute: $0, pull: pull($0, signals: state.partner.stageSignals, baseline: state.lifetimeSignals),
                     leading: $0 == lead, open: openAttributes.contains($0))
        }
    }

    // MARK: Growth

    private func advance(_ state: inout DigimonState, at date: Date) -> [DigimonEvent] {
        var events: [DigimonEvent] = []
        while state.pendingChoice == nil, state.eggChoiceOfferedAt == nil,
              state.partner.stageExp >= growth.threshold(for: state.partner.level) {
            let options = Array(growthOptions(for: state, at: date).prefix(growth.maxChoices))
            if let jogress = rules.specialJogress(for: state, in: catalog) {
                events += evolve(&state, to: jogress.to, at: date)   // instead of graduating
            } else if state.partner.level == .ultimate || options.isEmpty {
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
        state.partner.stageStartedAt = date
        state.partner.path.append(key)
        state.dex.insert(key)
        state.eggOffer = nil   // hatched: the draw is used up
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
        offerEggLines(&state, at: date)   // the new egg waits for the user to pick its line
        return [.graduated(lineID: line, path: path), .newEgg(lineID: state.partner.lineID)]
    }

    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// SplitMix64: a small seeded generator, so a draw can be repeated exactly (and tested).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
