import Foundation

// Luck and surprise (step 12): the day's fortune, visitors and the stamp card.
//
// Rules taken from the research in docs/digimon/step12-luck.md:
// - Luck never depends on how much the user codes (the daily experience cap's reason): the day is
//   rolled from the player's random number and the date, and a stamp is one per coding day.
// - Nothing rerolls: restarting or restoring a backup rolls the same day again.
// - Visitors are old faces: 99% come from the user's dex (raised or met), 1% are Digimon never seen
//   before (user's decision, 2026-11-19). A full stamp card guarantees one never seen (the "pity" of
//   gacha games, without buying).
// - Surprise points (user's rules): a little for a visitor at a higher stage than the partner or two
//   or more stages lower, more for one never seen.
// - Card evolution rules stay as they are: luck only adds visitors, bugs and practice battles.

/// The day's fortune: one a day per player.
enum DigimonFortune: String, Codable, Sendable, CaseIterable {
    case clear, bugSwarm, fighting, busy, meteor
}

/// How rare a visitor is, from common to legendary.
enum VisitorTier: String, Codable, Sendable, CaseIterable, Comparable {
    case common, rare, veryRare, legendary

    static func < (a: VisitorTier, b: VisitorTier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// A Digimon that comes by on a day (it never joins the user's lines).
struct DigimonVisit: Codable, Sendable, Equatable {
    var species: String
    var tier: VisitorTier
    var at: Date
    var arrived = false
    /// Brought by a full stamp card.
    var special = false
    /// Set on arrival: never raised nor met before, and the surprise points it gave.
    var firstSeen = false
    var points = 0

    init(species: String, tier: VisitorTier, at: Date, arrived: Bool = false, special: Bool = false,
         firstSeen: Bool = false, points: Int = 0) {
        self.species = species
        self.tier = tier
        self.at = at
        self.arrived = arrived
        self.special = special
        self.firstSeen = firstSeen
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case species, tier, at, arrived, special, firstSeen, points }

    /// A tier from a newer version reads as common instead of failing the whole save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        species = try c.decode(String.self, forKey: .species)
        tier = (try? c.decode(VisitorTier.self, forKey: .tier)) ?? .common
        at = try c.decode(Date.self, forKey: .at)
        arrived = try c.decodeIfPresent(Bool.self, forKey: .arrived) ?? false
        special = try c.decodeIfPresent(Bool.self, forKey: .special) ?? false
        firstSeen = try c.decodeIfPresent(Bool.self, forKey: .firstSeen) ?? false
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
    }
}

/// The day's luck and the stamp card (`EvolutionEngine.updateLuck`).
struct LuckBook: Codable, Sendable, Equatable {
    /// The day the fortune and visits are for ("yyyy-MM-dd").
    var day = ""
    var fortune: DigimonFortune = .clear
    var visits: [DigimonVisit] = []
    /// Stamps on the card (one per coding day); a full card starts again from 0.
    var stamps = 0
    /// The last day that gave a stamp.
    var stampDay = ""
    var cardsCompleted = 0
    /// Surprise points over all visits (`EvolutionEngine.surprisePoints`).
    var surprise = 0

    init() {}

    private enum CodingKeys: String, CodingKey { case day, fortune, visits, stamps, stampDay, cardsCompleted, surprise }

    /// Every field may be missing, and a fortune from a newer version reads as a clear day.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        fortune = (try? c.decode(DigimonFortune.self, forKey: .fortune)) ?? .clear
        visits = try c.decodeIfPresent([DigimonVisit].self, forKey: .visits) ?? []
        stamps = try c.decodeIfPresent(Int.self, forKey: .stamps) ?? 0
        stampDay = try c.decodeIfPresent(String.self, forKey: .stampDay) ?? ""
        cardsCompleted = try c.decodeIfPresent(Int.self, forKey: .cardsCompleted) ?? 0
        surprise = try c.decodeIfPresent(Int.self, forKey: .surprise) ?? 0
    }
}

enum LuckRules {
    /// Stamps for a full card.
    static let stampCard = 7
    static let fortunes: [(DigimonFortune, Int)] = [(.clear, 35), (.bugSwarm, 20), (.fighting, 20), (.busy, 15), (.meteor, 10)]
    static let tiers: [(VisitorTier, Int)] = [(.common, 64), (.rare, 26), (.veryRare, 9), (.legendary, 1)]
    /// A meteor shower brings a rare visitor or better.
    static let meteorTiers: [(VisitorTier, Int)] = [(.rare, 60), (.veryRare, 32), (.legendary, 8)]
    /// A full stamp card: very rare or better, and never seen before.
    static let specialTiers: [(VisitorTier, Int)] = [(.veryRare, 85), (.legendary, 15)]
    /// Percent of visitors that are Digimon never seen; the rest come from the dex (raised or met), even
    /// when it holds a single one (user's decision: the same old face keeps coming).
    static let unknownPercent: UInt64 = 1
    /// Surprise points: a visitor at a higher stage than the partner, or two or more stages lower...
    static let surpriseStage = 1
    /// ...and one never seen before.
    static let surpriseFirstSeen = 10
    /// Practice battles added on a day of fighting spirit.
    static let extraPractice = 2
    /// Visits come between these hours (local time).
    static let visitHours = 9..<21
    /// A save keeps at most this many visits for a day.
    static let maxVisits = 4
}

extension EvolutionEngine {
    /// The visitor tier of a species: babies, Child and Adult common, Perfect rare, Ultimate very rare,
    /// and the Digimon growth never reaches (merge results such as Omegamon) legendary. Babies visit too
    /// (user's decision): once it grows past them, the ones it was come by.
    func visitorTier(of species: DigimonSpecies) -> VisitorTier? {
        visitorTier(of: species, legendary: legendaryVisitors)
    }

    /// The Digimon growth never reaches: merge results such as Omegamon.
    private var legendaryVisitors: Set<String> { rules.locked.union(rules.specialJogress.map(\.to)) }

    private func visitorTier(of species: DigimonSpecies, legendary: Set<String>) -> VisitorTier? {
        if legendary.contains(species.key) { return .legendary }
        switch species.level {
        case .babyI, .babyII, .child, .adult: return .common
        case .perfect: return .rare
        case .ultimate: return .veryRare
        case .digitama: return nil
        }
    }

    /// Call on every refresh. Rolls the day once (fortune and visits), gives the day's stamp once the
    /// user has coded today, and lets each visitor arrive when its time comes (it joins the
    /// sightings). Returns `.visited` per arrival and `.stampCardFull` when the card fills.
    @discardableResult
    func updateLuck(_ state: inout DigimonState, at now: Date) -> [DigimonEvent] {
        var events: [DigimonEvent] = []
        let day = dayKey(now)
        var book = state.luck.flatMap { $0.day == day ? $0 : nil } ?? rolledDay(&state, day: day, at: now)
        if state.lifetimeSignals.activeDays.contains(day), book.stampDay != day {
            book.stampDay = day
            book.stamps += 1
            if book.stamps >= LuckRules.stampCard {
                book.stamps = 0
                book.cardsCompleted += 1
                events.append(.stampCardFull)
                if let visit = specialVisit(state, visitsToday: book.visits, cards: book.cardsCompleted, day: day, at: now) {
                    book.visits.append(visit)
                }
            }
        }
        var sightings = state.sightings ?? []
        for i in book.visits.indices where !book.visits[i].arrived && book.visits[i].at <= now {
            let species = book.visits[i].species
            let firstSeen = !state.dex.contains(species) && !sightings.contains(species)
            let points = surprisePoints(species, partner: state.partner.level, firstSeen: firstSeen)
            book.visits[i].arrived = true
            book.visits[i].firstSeen = firstSeen
            book.visits[i].points = points
            book.surprise += points
            sightings.insert(species)
            events.append(.visited(species: species, tier: book.visits[i].tier, firstSeen: firstSeen))
        }
        state.luck = book
        if sightings != (state.sightings ?? []) { state.sightings = sightings }
        return events
    }

    /// Surprise points for a visitor (user's rules): `surpriseStage` when it stands at a higher stage
    /// than the partner (an egg counts as the lowest) or two or more stages lower, plus
    /// `surpriseFirstSeen` when it was never raised nor met.
    func surprisePoints(_ visitor: String, partner level: DigimonLevel, firstSeen: Bool) -> Int {
        guard let stage = catalog.species(visitor)?.level.order else { return 0 }
        let far = stage > level.order || stage <= level.order - 2
        return (far ? LuckRules.surpriseStage : 0) + (firstSeen ? LuckRules.surpriseFirstSeen : 0)
    }

    /// The practice battles allowed today: one fortune adds two.
    func practiceLimit(_ state: DigimonState, at now: Date) -> Int {
        let fighting = state.luck?.day == dayKey(now) && state.luck?.fortune == .fighting
        return growth.practiceBattlesPerDay + (fighting ? LuckRules.extraPractice : 0)
    }

    /// The player's random number (battle codes, luck), made on first use.
    func ensurePlayerID(_ state: inout DigimonState) -> String {
        let player = state.playerID ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
        state.playerID = player
        return player
    }

    /// The fortune and the visits of a day, seeded by the player and the day only. The stamp card
    /// carries over from the book before.
    private func rolledDay(_ state: inout DigimonState, day: String, at now: Date) -> LuckBook {
        let player = ensurePlayerID(&state)
        var rng = SeededGenerator(seed: DigimonBattle.fnv1a("luck|\(player)|\(day)"))
        var book = state.luck ?? LuckBook()
        book.day = day
        book.fortune = Self.pick(LuckRules.fortunes, &rng) ?? .clear
        let start = calendar.startOfDay(for: now)
        let window = UInt64(LuckRules.visitHours.count * 3600)
        let times = (0..<(book.fortune == .busy ? 2 : 1)).map { _ in
            start.addingTimeInterval(TimeInterval(LuckRules.visitHours.lowerBound * 3600) + TimeInterval(rng.next() % window))
        }.sorted()
        var chosen: Set<String> = []
        book.visits = times.compactMap { at in
            let tiers = book.fortune == .meteor ? LuckRules.meteorTiers : LuckRules.tiers
            guard let (species, tier) = visitor(tiers, state: state, excluding: chosen, rng: &rng) else { return nil }
            chosen.insert(species)
            return DigimonVisit(species: species, tier: tier, at: at)
        }
        return book
    }

    /// The visitor a full stamp card brings, arriving now.
    private func specialVisit(_ state: DigimonState, visitsToday: [DigimonVisit], cards: Int, day: String,
                              at now: Date) -> DigimonVisit? {
        var rng = SeededGenerator(seed: DigimonBattle.fnv1a("stamp|\(state.playerID ?? "")|\(day)|\(cards)"))
        guard let (species, tier) = visitor(LuckRules.specialTiers, state: state, excluding: Set(visitsToday.map(\.species)),
                                            neverSeen: true, rng: &rng) else { return nil }
        return DigimonVisit(species: species, tier: tier, at: now, special: true)
    }

    /// Who visits, and its tier: a Digimon from the dex (raised or met) 99% of the time, however few it
    /// holds; one never seen `unknownPercent`; only never seen ones with `neverSeen` (a full stamp card).
    /// Never the partner, nor one already coming today. nil when the dex has none that can visit (a new
    /// user before a Child joins it): no visitor that day. The tier is drawn from `tiers` among those the
    /// pool has (a meteor shower prefers rare ones); with none of them, from any tier it has.
    func visitor(_ tiers: [(VisitorTier, Int)], state: DigimonState, excluding: Set<String>, neverSeen: Bool = false,
                 rng: inout some RandomNumberGenerator) -> (species: String, tier: VisitorTier)? {
        let met = state.dex.union(state.sightings ?? []), legendary = legendaryVisitors
        let eligible = catalog.sortedSpecies.compactMap { species -> (String, VisitorTier)? in
            guard let tier = visitorTier(of: species, legendary: legendary), species.key != state.partner.speciesKey,
                  !excluding.contains(species.key) else { return nil }
            return (species.key, tier)
        }
        let known = eligible.filter { met.contains($0.0) }, unknown = eligible.filter { !met.contains($0.0) }
        var pool: [(String, VisitorTier)]
        if neverSeen, !unknown.isEmpty { pool = unknown }
        else if !unknown.isEmpty, rng.next() % 100 < LuckRules.unknownPercent { pool = unknown }
        else { pool = known }
        var weights = tiers.filter { t in pool.contains { $0.1 == t.0 } }
        if weights.isEmpty { weights = LuckRules.tiers.filter { t in pool.contains { $0.1 == t.0 } } }
        guard let tier = Self.pick(weights, &rng) else { return nil }
        let choices = pool.filter { $0.1 == tier }.map(\.0)
        guard !choices.isEmpty else { return nil }
        return (choices[Int(rng.next() % UInt64(choices.count))], tier)
    }

    static func pick<T>(_ weighted: [(T, Int)], _ rng: inout some RandomNumberGenerator) -> T? {
        let total = weighted.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return nil }
        var roll = Int(rng.next() % UInt64(total))
        for (value, weight) in weighted where weight > 0 {
            if roll < weight { return value }
            roll -= weight
        }
        return weighted.last?.0
    }
}
