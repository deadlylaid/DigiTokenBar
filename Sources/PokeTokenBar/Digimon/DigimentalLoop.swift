import Foundation

// Digimental fragments (step 13, docs/digimon/step13-digimental-armor.md section 3).
//
// - A fragment has a Digimental kind; three of a kind make that Digimental at once.
// - Fragments come from golden bugs (about 1 bug in 100, twice as often on a bug-swarm day), visitors
//   (1 visit in 10 leaves one, a Digimon never seen always does), a full stamp card (one of the
//   user's choice) and surprise points (5 for one of the user's choice).
// - Random kinds are seeded like the day's luck (player, day, ...), so a restore gives the same ones.
// - Digimentals are spent by armor evolution (not here).
// - Golden Digimentals (Miracles, Fate; step 16, docs/digimon/step16-golden-digimentals.md) never come as
//   fragments. They come whole: a full stamp card brings one 1 time in 4 (seeded like the rest), and
//   30 surprise points buy the one the user picks. Golden fragments an old save holds stay as they are.

/// Where a fragment (or a whole golden Digimental) came from.
enum FragmentSource: String, Codable, Sendable {
    case goldenBug, visitor, stampCard, surprise
}

/// Fragments and finished Digimentals. Stored by raw value so a kind from a newer version is kept.
struct DigimentalBag: Codable, Sendable, Equatable {
    /// Fragments per Digimental, below `DigimentalRules.fragmentsPerDigimental` once combined.
    var fragments: [String: Int] = [:]
    /// Finished Digimentals per kind, used up by armor evolution.
    var owned: [String: Int] = [:]
    /// Full stamp cards whose fragment (of the user's choice) is not claimed yet.
    var stampRewards = 0
    /// Golden bugs that paid on `goldenDay` (at most `DigimentalRules.goldenPerDay`).
    var goldenDay = ""
    var goldenToday = 0

    init() {}

    private enum CodingKeys: String, CodingKey { case fragments, owned, stampRewards, goldenDay, goldenToday }

    /// Every field may be missing (a save from before a field existed).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fragments = try c.decodeIfPresent([String: Int].self, forKey: .fragments) ?? [:]
        owned = try c.decodeIfPresent([String: Int].self, forKey: .owned) ?? [:]
        stampRewards = try c.decodeIfPresent(Int.self, forKey: .stampRewards) ?? 0
        goldenDay = try c.decodeIfPresent(String.self, forKey: .goldenDay) ?? ""
        goldenToday = try c.decodeIfPresent(Int.self, forKey: .goldenToday) ?? 0
    }

    func fragments(_ d: Digimental) -> Int { fragments[d.rawValue] ?? 0 }
    func owned(_ d: Digimental) -> Int { owned[d.rawValue] ?? 0 }
    /// The fragment kinds the dex shows: the ones that can still be collected
    /// (`EvolutionEngine.fragmentKinds`), and any other kind already held. The golden ones are not among
    /// them: the dex shows those apart, always (step 16).
    func shownKinds(collectable: [Digimental]) -> [Digimental] {
        Digimental.allCases.filter { !$0.isGolden && (collectable.contains($0) || owned($0) > 0 || fragments($0) > 0) }
    }
    var fragmentTotal: Int { Digimental.allCases.reduce(0) { $0 + fragments($1) } }
    var ownedTotal: Int { Digimental.allCases.reduce(0) { $0 + owned($1) } }
    var goldenTotal: Int { Digimental.golden.reduce(0) { $0 + owned($1) } }

    /// Turns every three fragments of a kind into one Digimental. Returns one entry per Digimental made.
    /// Golden fragments (only an old save holds them) never combine: a golden Digimental comes whole.
    mutating func combine() -> [Digimental] {
        var made: [Digimental] = []
        for d in Digimental.allCases where !d.isGolden {
            let n = fragments(d) / DigimentalRules.fragmentsPerDigimental
            guard n > 0 else { continue }
            fragments[d.rawValue] = fragments(d) % DigimentalRules.fragmentsPerDigimental
            owned[d.rawValue] = min(DigimentalRules.maxOwned, owned(d) + n)
            made += Array(repeating: d, count: n)
        }
        return made
    }
}

enum DigimentalRules {
    static let fragmentsPerDigimental = 3
    /// Chance that a bug the scene sends is golden: 1 in 100, 1 in 50 on a bug-swarm day.
    static func goldenBugChance(_ fortune: DigimonFortune?) -> Double { fortune == .bugSwarm ? 0.02 : 0.01 }
    /// Golden bugs that pay a fragment per day. The popover and the desktop pet each send bugs, so
    /// two open scenes would otherwise double the rate.
    static let goldenPerDay = 3
    /// One visit in this many leaves a fragment (a Digimon never seen always does).
    static let giftOneIn: UInt64 = 10
    /// Surprise points for one fragment of the user's choice.
    static let exchangeCost = 5
    /// A kind the partner can use comes this many times as often as another.
    static let preferredWeight = 3
    static let maxOwned = 99
    static let maxStampRewards = 99
    /// A full stamp card also brings a golden Digimental 1 time in this many (Miracles or Fate, half each).
    static let goldenStampOneIn: UInt64 = 4
    /// Surprise points for a golden Digimental of the user's choice.
    static let goldenTradeCost = 30
}

// MARK: Integration seam (armor data fills these from the catalog's Digimental routes)

extension EvolutionEngine {
    /// The Digimentals a fragment can be: the ones some line's Digimental route uses (every one if the
    /// catalog had none), never a golden one (step 16).
    func fragmentKinds() -> [Digimental] {
        let used = Set(catalog.lines.values.flatMap(\.digimentalSteps.values).joined())
        let kinds = Digimental.allCases.filter(used.contains)
        return (kinds.isEmpty ? Digimental.allCases : kinds).filter { !$0.isGolden }
    }

    /// The Digimentals the partner can use now or later in this life: the Digimental routes out of its
    /// species and out of every species it can still grow into on its line (an egg: the whole line).
    /// Drawn `DigimentalRules.preferredWeight` times as often.
    func preferredDigimentals(for state: DigimonState) -> Set<Digimental> {
        guard let line = catalog.lines[state.partner.lineID] else { return [] }
        var reach: Set<String> = [state.partner.speciesKey ?? line.firstBaby]
        var frontier = Array(reach)
        while let key = frontier.popLast() {
            for evo in catalog.nextEvolutions(from: key, in: line) where reach.insert(evo.to).inserted {
                frontier.append(evo.to)
            }
        }
        return Set(line.digimentalSteps.flatMap { step, ds in
            reach.contains(String(step.split(separator: ">").first ?? "")) ? ds : []
        })
    }

    /// The Digimentals the partner can use at the end of its current stage.
    func digimentalsUsableNow(for state: DigimonState) -> Set<Digimental> {
        Set(armorOptions(for: state).map(\.digimental))
    }
}

// MARK: Fragments

extension EvolutionEngine {
    /// A random fragment kind: `kinds`, with `preferred` ones weighted up.
    func drawFragment(kinds: [Digimental], preferred: Set<Digimental>,
                      rng: inout some RandomNumberGenerator) -> Digimental? {
        Self.pick(kinds.map { ($0, preferred.contains($0) ? DigimentalRules.preferredWeight : 1) }, &rng)
    }

    /// Adds a fragment of `kind` and combines. `.fragmentFound`, then `.digimentalMade` when it completed one.
    @discardableResult
    func giveFragment(_ state: inout DigimonState, _ kind: Digimental, from source: FragmentSource) -> [DigimonEvent] {
        var bag = state.digimentals ?? DigimentalBag()
        bag.fragments[kind.rawValue] = bag.fragments(kind) + 1
        let made = bag.combine()
        state.digimentals = bag
        return [.fragmentFound(kind, from: source)] + made.map { .digimentalMade($0) }
    }

    /// The scene's golden bug was defeated: a fragment (seeded by the player, the day and how many
    /// paid today), up to `goldenPerDay` a day.
    @discardableResult
    func recordGoldenBug(_ state: inout DigimonState, at now: Date) -> [DigimonEvent] {
        let day = dayKey(now)
        var bag = state.digimentals ?? DigimentalBag()
        if bag.goldenDay != day { bag.goldenDay = day; bag.goldenToday = 0 }
        guard bag.goldenToday < DigimentalRules.goldenPerDay else { return [] }
        bag.goldenToday += 1
        state.digimentals = bag
        let player = ensurePlayerID(&state)
        var rng = SeededGenerator(seed: DigimonBattle.fnv1a("golden|\(player)|\(day)|\(bag.goldenToday)"))
        guard let kind = drawFragment(kinds: fragmentKinds(), preferred: preferredDigimentals(for: state), rng: &rng)
        else { return [] }
        return giveFragment(&state, kind, from: .goldenBug)
    }

    /// The fragment a visitor leaves, if any: one visit in `giftOneIn`, always one from a Digimon never
    /// seen. Seeded by the player, the day and the visitor, so a restore gives the same.
    func visitGift(_ state: DigimonState, species: String, day: String, firstSeen: Bool) -> Digimental? {
        var rng = SeededGenerator(seed: DigimonBattle.fnv1a("gift|\(state.playerID ?? "")|\(day)|\(species)"))
        let gives = rng.next() % DigimentalRules.giftOneIn == 0
        guard gives || firstSeen else { return nil }
        return drawFragment(kinds: fragmentKinds(), preferred: preferredDigimentals(for: state), rng: &rng)
    }

    /// Claims one full stamp card's fragment as `kind`. Nothing when no card is waiting.
    @discardableResult
    func claimStampReward(_ state: inout DigimonState, _ kind: Digimental) -> [DigimonEvent] {
        guard var bag = state.digimentals, bag.stampRewards > 0 else { return [] }
        bag.stampRewards -= 1
        state.digimentals = bag
        return giveFragment(&state, kind, from: .stampCard)
    }

    /// Trades `exchangeCost` surprise points for a fragment of `kind`. Nothing with fewer points.
    @discardableResult
    func exchangeSurprise(_ state: inout DigimonState, for kind: Digimental) -> [DigimonEvent] {
        guard var book = state.luck, book.surprise >= DigimentalRules.exchangeCost else { return [] }
        book.surprise -= DigimentalRules.exchangeCost
        state.luck = book
        return giveFragment(&state, kind, from: .surprise)
    }
}

// MARK: Golden Digimentals (step 16)

extension EvolutionEngine {
    /// Adds one whole golden Digimental. `.goldenDigimental`.
    @discardableResult
    func giveGolden(_ state: inout DigimonState, _ kind: Digimental, from source: FragmentSource) -> [DigimonEvent] {
        var bag = state.digimentals ?? DigimentalBag()
        bag.owned[kind.rawValue] = min(DigimentalRules.maxOwned, bag.owned(kind) + 1)
        state.digimentals = bag
        return [.goldenDigimental(kind, from: source)]
    }

    /// The golden Digimental the `cards`-th full stamp card brings, if any: 1 card in `goldenStampOneIn`,
    /// Miracles or Fate half each. Seeded by the player, the day and the card, so a restore gives the same.
    func stampGolden(_ state: DigimonState, day: String, cards: Int) -> Digimental? {
        var rng = SeededGenerator(seed: DigimonBattle.fnv1a("golden-stamp|\(state.playerID ?? "")|\(day)|\(cards)"))
        guard rng.next() % DigimentalRules.goldenStampOneIn == 0 else { return nil }
        return Digimental.golden[Int(rng.next() % UInt64(Digimental.golden.count))]
    }

    /// Trades `goldenTradeCost` surprise points for the golden Digimental `kind` (one of
    /// `Digimental.golden`, the only ones the dex offers). Nothing with fewer points.
    @discardableResult
    func tradeForGolden(_ state: inout DigimonState, _ kind: Digimental) -> [DigimonEvent] {
        guard var book = state.luck, book.surprise >= DigimentalRules.goldenTradeCost else { return [] }
        book.surprise -= DigimentalRules.goldenTradeCost
        state.luck = book
        return giveGolden(&state, kind, from: .surprise)
    }
}

// MARK: Text

extension DigimonText {
    var digimentalsTitle: String { ko ? "디지멘탈" : "Digimentals" }
    /// The home's stamp row shows numbers only; these say what they count.
    func fragmentsHelp(_ n: Int) -> String {
        ko ? "디지멘탈 조각 \(n)개 (도감에서 볼 수 있어요)" : "\(n) Digimental fragment\(n == 1 ? "" : "s") (see the Dex)"
    }
    func ownedHelp(_ n: Int) -> String {
        ko ? "가진 디지멘탈 \(n)개" : "\(n) Digimental\(n == 1 ? "" : "s") owned"
    }
    func digimentalsSummary(owned: Int, fragments: Int) -> String {
        ko ? "가진 디지멘탈 \(owned) · 조각 \(fragments)" : "\(owned) owned · \(fragments) fragment\(fragments == 1 ? "" : "s")"
    }
    var digimentalsHelp: String {
        ko ? "같은 조각 \(DigimentalRules.fragmentsPerDigimental)개가 모이면 디지멘탈이 돼요. 황금 버그를 잡거나, 손님이 두고 가거나, 출석 도장을 다 모으거나, 놀람 점수로 바꿔 모아요."
           : "\(DigimentalRules.fragmentsPerDigimental) fragments of a kind make a Digimental. Catch golden bugs, get gifts from visitors, fill the stamp card or trade surprise points."
    }
    var claimStampReward: String { ko ? "도장 선물 받기" : "Claim stamp gift" }
    var stampRewardHelp: String {
        ko ? "출석 도장을 다 모은 선물이에요. 원하는 디지멘탈 조각을 하나 골라요." : "A gift for a full stamp card: pick the fragment you want."
    }
    var exchangeSurprise: String {
        ko ? "놀람 \(DigimentalRules.exchangeCost)점 → 조각" : "\(DigimentalRules.exchangeCost) surprise → fragment"
    }
    func exchangeHelp(_ points: Int) -> String {
        if points >= DigimentalRules.exchangeCost {
            return ko ? "놀람 점수 \(DigimentalRules.exchangeCost)점을 원하는 조각 하나로 바꿔요. (지금 \(points)점)"
                      : "Trade \(DigimentalRules.exchangeCost) surprise points for a fragment of your choice (you have \(points))."
        }
        return ko ? "놀람 점수가 \(DigimentalRules.exchangeCost)점 있어야 해요. (지금 \(points)점)"
                  : "Needs \(DigimentalRules.exchangeCost) surprise points (you have \(points))."
    }
    /// "용기 ●●○ ×1" style label pieces.
    func ownedCount(_ n: Int) -> String { "×\(n)" }
    func digimentalMadeTitle(_ d: Digimental) -> String {
        ko ? "\(digimental(d))을 만들었어요!" : "You made the \(digimental(d))!"
    }
    var digimentalMadeBody: String {
        ko ? "성장기 디지몬이 맞는 디지멘탈을 가지면 아머 진화할 수 있어요." : "A Child with the right Digimental can armor-evolve."
    }
    /// The pet's callout when a visitor leaves a fragment, and when a golden bug drops one.
    var giftCallout: String { ko ? "선물이다!" : "A gift!" }
    var goldenCallout: String { ko ? "디지멘탈 조각!" : "A fragment!" }
    // Golden Digimentals (step 16).
    var goldenTitle: String { ko ? "황금 디지멘탈" : "Golden Digimentals" }
    /// The folded Digimental line's golden count: "황금 1".
    func goldenShort(_ n: Int) -> String { ko ? "황금 \(n)" : "\(n) golden" }
    var goldenHelp: String {
        ko ? "황금 디지멘탈(기적·운명)은 조각으로 모을 수 없어요. 출석 도장 카드를 다 채우면 \(DigimentalRules.goldenStampOneIn)번에 1번꼴로 함께 오고, 놀람 점수 \(DigimentalRules.goldenTradeCost)점으로도 받을 수 있어요."
           : "Golden Digimentals (Miracles, Fate) never come as fragments. A full stamp card brings one about 1 time in \(DigimentalRules.goldenStampOneIn), and \(DigimentalRules.goldenTradeCost) surprise points buy one."
    }
    var goldenTrade: String { ko ? "\(DigimentalRules.goldenTradeCost)점으로 받기" : "Get for \(DigimentalRules.goldenTradeCost) points" }
    func goldenTradeHelp(_ points: Int) -> String {
        ko ? "놀람 점수 \(DigimentalRules.goldenTradeCost)점으로 원하는 황금 디지멘탈 하나를 받아요. (지금 \(points)점)"
           : "Trade \(DigimentalRules.goldenTradeCost) surprise points for the golden Digimental you pick (you have \(points))."
    }
    var goldenGotTitle: String { ko ? "황금 디지멘탈을 받았어요!" : "A golden Digimental!" }
    func goldenGotBody(_ d: Digimental, from source: FragmentSource) -> String {
        "\(digimental(d)) · \(fragmentSourceName(source))"
    }
    var goldenArmorEvolvedTitle: String { ko ? "황금 아머 진화!" : "Golden armor evolution!" }
    func fragmentSourceName(_ s: FragmentSource) -> String {
        switch s {
        case .goldenBug: return ko ? "황금 버그" : "Golden bug"
        case .visitor: return ko ? "손님 선물" : "Visitor's gift"
        case .stampCard: return ko ? "도장 선물" : "Stamp gift"
        case .surprise: return ko ? "놀람 점수" : "Surprise points"
        }
    }
}
