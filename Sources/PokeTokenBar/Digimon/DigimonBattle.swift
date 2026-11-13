import Foundation

/// One side of a battle, as a battle code carries it. Nothing personal: a random player number, the
/// species and level, and how well the current stage went.
struct BattleFighter: Codable, Equatable, Sendable {
    /// Random per save (`DigimonState.playerID`); "wild" for a practice opponent.
    var player: String
    var species: String
    var level: DigimonLevel
    /// How well the stage went, 0...100 (the card's Vital Values and trophies, see `StagePerformance`).
    var training: Int
    /// The stage it fights in (its start, seconds since 1970; 0 before stages had one) and the day.
    /// A player's code stays the same for both within a stage and a day.
    var stage: Int64
    var day: String
    var nonce: UInt64
    var issuedAt: Date
}

enum BattleSide: String, Equatable, Sendable { case me, foe }

struct BattleRound: Equatable, Sendable {
    let attacker: BattleSide
    let hit: Bool
}

struct BattleResult: Equatable, Sendable {
    let won: Bool
    let rounds: [BattleRound]
    var myHits: Int { rounds.filter { $0.attacker == .me && $0.hit }.count }
    var foeHits: Int { rounds.filter { $0.attacker == .foe && $0.hit }.count }
}

/// Automatic battles, like a V-Pet's: the two Digimon take turns firing their signature moves and the
/// first to land three hits wins. The result depends only on the two fighters, so two Macs that
/// paste each other's code see the same battle.
enum DigimonBattle {
    static let hitsToWin = 3
    static let maxAttacks = 12
    /// Level matters most; training adds up to half; the attribute triangle multiplies.
    static let levelPower: [DigimonLevel: Double] = [
        .digitama: 5, .babyI: 10, .babyII: 20, .child: 40, .adult: 80, .perfect: 140, .ultimate: 220,
    ]
    static let advantage = 1.3

    /// Vaccine beats Virus, Virus beats Data, Data beats Vaccine.
    static func multiplier(_ attacker: DigimonAttribute, against defender: DigimonAttribute) -> Double {
        switch (attacker, defender) {
        case (.vaccine, .virus), (.virus, .data), (.data, .vaccine): return advantage
        default: return 1
        }
    }

    static func power(_ fighter: BattleFighter, against other: BattleFighter, catalog: DigimonCatalog) -> Double {
        let base = levelPower[fighter.level] ?? 10
        let trained = base * (1 + 0.5 * Double(min(max(fighter.training, 0), 100)) / 100)
        let a = catalog.species(fighter.species)?.attribute ?? .unknown
        let b = catalog.species(other.species)?.attribute ?? .unknown
        return trained * multiplier(a, against: b)
    }

    /// The battle from `me`'s side. The fighters are put in a fixed order and the dice are seeded by
    /// both codes, so the other Mac computes the same battle from its side.
    static func fight(me: BattleFighter, foe: BattleFighter, catalog: DigimonCatalog) -> BattleResult {
        let meFirst = (me.player, me.nonce) <= (foe.player, foe.nonce)
        let first = meFirst ? me : foe, second = meFirst ? foe : me
        var rng = SeededGenerator(seed: fnv1a("\(first.player)|\(first.nonce)|\(second.player)|\(second.nonce)"))
        let powers = [power(first, against: second, catalog: catalog), power(second, against: first, catalog: catalog)]
        var hits = [0, 0]
        var rounds: [BattleRound] = []
        while hits.max()! < hitsToWin, rounds.count < maxAttacks {
            let a = rounds.count % 2
            let chance = min(0.8, max(0.2, powers[a] / (powers[a] + powers[1 - a])))
            let hit = Double(rng.next() >> 11) / Double(UInt64(1) << 53) < chance
            if hit { hits[a] += 1 }
            rounds.append(BattleRound(attacker: (a == 0) == meFirst ? .me : .foe, hit: hit))
        }
        let firstWins = hits[0] != hits[1] ? hits[0] > hits[1] : powers[0] >= powers[1]
        return BattleResult(won: firstWins == meFirst, rounds: rounds)
    }

    /// A practice opponent: a Digimon of the same level from any line, trained 20-80%.
    static func wildFoe(for me: BattleFighter, catalog: DigimonCatalog, rng: inout some RandomNumberGenerator,
                        at date: Date) -> BattleFighter {
        let pool = catalog.species.values.filter { $0.level == me.level && $0.key != me.species }.map(\.key).sorted()
        let species = pool.randomElement(using: &rng) ?? me.species
        return BattleFighter(player: "wild", species: species, level: me.level, training: Int.random(in: 20...80, using: &rng),
                             stage: 0, day: me.day, nonce: rng.next(), issuedAt: date)
    }

    /// FNV-1a: a stable hash (Swift's `Hasher` changes between runs, so it cannot seed a shared battle).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

enum BattleCodeError: Error, Equatable {
    /// No "DTB1." code in the text.
    case notACode
    /// Changed or cut off on the way (the check digits do not match).
    case damaged
    /// From another version of the app.
    case unsupported
    /// A Digimon this catalog does not know, or at another level than it says.
    case unknownDigimon
    /// Older than `BattleCode.maxAge`, or dated in the future.
    case expired
    /// The user's own code.
    case ownCode
    /// Already fought with this code.
    case alreadyFought
}

/// The text two users send each other: "DTB1.<data>.<check>". It holds only a `BattleFighter`.
/// Codes from other people are untrusted: every field is checked against the catalog and clamped.
enum BattleCode {
    static let prefix = "DTB1."
    static let maxAge: TimeInterval = 7 * 24 * 3600

    private struct Payload: Codable {
        var p: String
        var s: String
        var l: DigimonLevel
        var t: Int
        var st: Int64
        var d: String
        var n: UInt64
        var i: Int64
    }

    static func encode(_ f: BattleFighter) -> String {
        let payload = Payload(p: f.player, s: f.species, l: f.level, t: f.training, st: f.stage, d: f.day, n: f.nonce,
                              i: Int64(f.issuedAt.timeIntervalSince1970))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = base64URL((try? encoder.encode(payload)) ?? Data())
        return prefix + body + "." + check(body)
    }

    /// Reads the first code in `text` (a message may carry words around it).
    static func decode(_ text: String, catalog: DigimonCatalog, now: Date) throws -> BattleFighter {
        guard let match = text.range(of: #"DTB1\.[A-Za-z0-9_-]{8,2000}\.[0-9a-f]{6}"#, options: .regularExpression) else {
            throw BattleCodeError.notACode
        }
        let parts = text[match].split(separator: ".")
        let body = String(parts[1]), sum = String(parts[2])
        guard check(body) == sum, let data = fromBase64URL(body) else { throw BattleCodeError.damaged }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { throw BattleCodeError.unsupported }
        guard let species = catalog.species(p.s), species.level == p.l, p.l != .digitama else {
            throw BattleCodeError.unknownDigimon
        }
        let issued = Date(timeIntervalSince1970: TimeInterval(p.i))
        guard now.timeIntervalSince(issued) <= maxAge, issued.timeIntervalSince(now) <= 24 * 3600 else {
            throw BattleCodeError.expired
        }
        let player = String(p.p.prefix(64))
        guard !player.isEmpty, player != "wild" else { throw BattleCodeError.unsupported }
        return BattleFighter(player: player, species: species.key, level: species.level, training: min(max(p.t, 0), 100),
                             stage: p.st, day: String(p.d.prefix(10)), nonce: p.n, issuedAt: issued)
    }

    private static func check(_ body: String) -> String {
        String(format: "%06llx", DigimonBattle.fnv1a("dtb|" + body) & 0xFF_FFFF)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fromBase64URL(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
