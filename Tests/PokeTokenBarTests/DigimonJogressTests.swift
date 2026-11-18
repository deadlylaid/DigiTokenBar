import XCTest
@testable import PokeTokenBar

/// A friend's code (the battle code) for `species`, as the friend's app would make it.
func friendCode(_ species: String, player: String = "friend01", nonce: UInt64 = 1, at date: Date) -> String {
    let level = DigimonCatalog.mvp.species(species)!.level
    return BattleCode.encode(BattleFighter(player: player, species: species, level: level, training: 50, stage: 0,
                                           day: "2026-11-14", nonce: nonce, issuedAt: date))
}

/// Jogress with a friend's code: a full stage with a Jogress route on its card waits for a fitting
/// partner's code, then merges; without one it grows as usual (skipped or after the wait).
final class DigimonJogressTests: XCTestCase {
    private var engine: EvolutionEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return EvolutionEngine(calendar: calendar)
    }
    private var catalog: DigimonCatalog { engine.catalog }
    /// 2026-11-14 12:00 in Seoul.
    private let t0 = Date(timeIntervalSince1970: 1_794_625_200)
    private let tokens = 200_000

    private func full(_ key: String, line: String, path: [String] = []) -> DigimonState {
        var s = DigimonState.newEgg(lineID: line)
        s.partner.speciesKey = key
        s.partner.level = catalog.species(key)!.level
        s.partner.path = path.isEmpty ? [key] : path
        s.partner.stageStartedAt = t0.addingTimeInterval(-3 * 24 * 3600)
        s.partner.stageExp = engine.growth.threshold(for: s.partner.level) - 1
        s.dex = Set(s.partner.path)
        return s
    }

    private func wait(_ key: String, line: String) -> DigimonState {
        var s = full(key, line: line)
        engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0)
        return s
    }

    // MARK: Data

    func testJogressPartnersComeFromTheCardResearch() {
        func routes(_ line: String, _ step: String) -> [DigimonJogress] { catalog.lines[line]!.jogress.filter { $0.step == step } }
        XCTAssertEqual(routes("agumon", "greymon>andromon"), [.init("greymon>andromon", level: .adult, attributes: [.data, .free])])
        XCTAssertEqual(routes("agumon", "algomonadult>andromon"), [.init("algomonadult>andromon", level: .adult, attributes: [.free, .vaccine])])
        XCTAssertEqual(routes("armadimon", "ankylomon>shakkoumon"), [.init("ankylomon>shakkoumon", species: "angemon")])
        XCTAssertEqual(routes("hawkmon", "aquilamon>silphymon"), [.init("aquilamon>silphymon", species: "tailmon")])
        // "Stage 15 cleared, Jogress with Virus Perfect": the adventure part is not used.
        XCTAssertEqual(routes("agumon", "metalgreymon>donedevimon"), [.init("metalgreymon>donedevimon", level: .perfect, attributes: [.virus])])
        let all = catalog.lines.values.flatMap(\.jogress)
        // 352, then 363 (2026-11-19): eleven "Stage 15 cleared, Jogress ..." routes were Adventure routes.
        // 476 with the six Frontier cards.
        XCTAssertEqual(all.count, 476)
        for line in catalog.lines.values {
            for route in line.jogress {
                XCTAssertTrue(line.steps?.contains(route.step) ?? false, "\(line.id): \(route.step) is one of its steps")
                XCTAssertTrue(catalog.species.values.contains { route.accepts($0) }, "\(line.id): \(route.step) has a possible partner")
            }
        }
        for step in catalog.lines.values.flatMap({ line in line.mergeSteps.map { (line, $0) } }) {
            XCTAssertTrue(step.0.jogress.contains { $0.step == step.1 }, "\(step.0.id): merge-only \(step.1) has a partner")
        }
    }

    /// The friend's code picks the result: no Digimon has two results that one partner fits. A card
    /// that adds one needs a rule for which wins first.
    func testAPartnerFitsAtMostOneResult() {
        for line in catalog.lines.values {
            for member in line.members {
                let routes = line.jogress.filter { $0.from == member }
                for partner in catalog.species.values {
                    let results = Set(routes.filter { $0.accepts(partner) }.map(\.to))
                    XCTAssertLessThanOrEqual(results.count, 1, "\(line.id): \(member) + \(partner.key) -> \(results)")
                }
            }
        }
    }

    func testAPartnerFitsByAttributeAndLevelOrByName() {
        let virusAdult = DigimonJogress("greymon>neodevimon", level: .adult, attributes: [.virus])
        XCTAssertTrue(virusAdult.accepts(catalog.species("devimon")!))
        XCTAssertFalse(virusAdult.accepts(catalog.species("angemon")!), "a Vaccine Adult")
        XCTAssertFalse(virusAdult.accepts(catalog.species("neodevimon")!), "a Virus Perfect")
        let named = DigimonJogress("ankylomon>shakkoumon", species: "angemon")
        XCTAssertTrue(named.accepts(catalog.species("angemon")!))
        XCTAssertFalse(named.accepts(catalog.species("tailmon")!))
    }

    // MARK: The wait

    func testAFullStageWithAJogressRouteWaitsForAFriendsCode() {
        var s = full("greymon", line: "agumon")
        let events = engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0)
        guard case .jogressOffered(let options)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(Set(options), ["andromon", "neodevimon"], "Greymon's Jogress routes on the Agumon card")
        XCTAssertEqual(s.partner.speciesKey, "greymon", "it waits instead of evolving")
        XCTAssertTrue(engine.isJogressOpen(s))
        XCTAssertEqual(engine.jogressDeadline(s), t0.addingTimeInterval(24 * 3600))
        XCTAssertEqual(engine.tick(&s, now: t0.addingTimeInterval(23 * 3600)), [], "still waiting")
        XCTAssertEqual(engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0.addingTimeInterval(3600)), [])
    }

    func testAStageWithoutAJogressRouteEvolvesAtOnce() {
        var s = full("agumon", line: "agumon")
        XCTAssertTrue(engine.jogressOptions(for: s).isEmpty)
        let events = engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0)
        guard case .evolved(from: "agumon", _)? = events.first else { return XCTFail("\(events)") }
        XCTAssertNil(s.jogressWait)
    }

    func testAFittingFriendsCodeMerges() throws {
        var s = wait("greymon", line: "agumon")
        let (partner, events) = try engine.jogress(&s, code: "hi! " + friendCode("devimon", at: t0), at: t0.addingTimeInterval(60))
        XCTAssertEqual(partner.species, "devimon")
        XCTAssertEqual(events, [.jogressed(from: "greymon", partner: "devimon", to: "neodevimon")], "the Virus Adult route")
        XCTAssertEqual(s.partner.speciesKey, "neodevimon")
        XCTAssertTrue(s.dex.contains("neodevimon"))
        XCTAssertTrue(s.discoveredEvolutions.contains("greymon>neodevimon"))
        var other = wait("greymon", line: "agumon")
        XCTAssertEqual(try engine.jogress(&other, code: friendCode("tyranomon", at: t0), at: t0).events.first,
                       .jogressed(from: "greymon", partner: "tyranomon", to: "andromon"), "a Data Adult")
        XCTAssertNil(s.jogressWait)
        XCTAssertNil(engine.jogressDeadline(s), "no wait, no deadline")
        XCTAssertEqual(s.jogressCodes, ["friend01:1"])
    }

    func testAPartnerThatDoesNotFitIsRefused() {
        var s = wait("greymon", line: "agumon")
        let before = s
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("angemon", at: t0), at: t0)) {
            XCTAssertEqual($0 as? JogressError, .partnerDoesNotFit(species: "angemon"), "a Vaccine Adult fits no route")
        }
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("agumon", at: t0), at: t0)) {
            XCTAssertEqual($0 as? JogressError, .partnerDoesNotFit(species: "agumon"), "a Child")
        }
        XCTAssertEqual(s, before, "nothing changes")
    }

    func testOwnUsedBrokenAndOldCodesAreRefused() throws {
        var s = wait("greymon", line: "agumon")
        s.playerID = "me000001"
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("devimon", player: "me000001", at: t0), at: t0)) {
            XCTAssertEqual($0 as? BattleCodeError, .ownCode)
        }
        XCTAssertThrowsError(try engine.jogress(&s, code: "no code here", at: t0)) {
            XCTAssertEqual($0 as? BattleCodeError, .notACode)
        }
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("devimon", at: t0), at: t0.addingTimeInterval(8 * 24 * 3600))) {
            XCTAssertEqual($0 as? BattleCodeError, .expired)
        }
        // A code merges once: the same friend's code in a later wait is refused.
        let code = friendCode("devimon", at: t0)
        _ = try engine.jogress(&s, code: code, at: t0)
        var later = wait("greymon", line: "agumon")
        later.jogressCodes = s.jogressCodes
        XCTAssertThrowsError(try engine.jogress(&later, code: code, at: t0)) {
            XCTAssertEqual($0 as? JogressError, .alreadyUsed)
        }
    }

    func testNoJogressWhenNothingIsWaiting() {
        var s = full("greymon", line: "agumon")
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("devimon", at: t0), at: t0)) {
            XCTAssertEqual($0 as? JogressError, .notOpen, "the stage is not full yet")
        }
        engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0)
        engine.skipJogress(&s, at: t0)
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("devimon", at: t0), at: t0)) {
            XCTAssertEqual($0 as? JogressError, .notOpen, "skipped: it already evolved")
        }
    }

    func testWithoutACodeItGrowsAsUsualOnceTheWaitIsOver() {
        var s = wait("greymon", line: "agumon")
        let usual = engine.growthOptions(for: s, at: t0)
        let events = engine.tick(&s, now: t0.addingTimeInterval(24 * 3600))
        guard case .evolved(from: "greymon", let to)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(to, usual.first)
        XCTAssertNil(s.jogressWait)
    }

    func testSkippingGrowsAsUsualNow() {
        var s = wait("greymon", line: "agumon")
        let usual = engine.growthOptions(for: s, at: t0)
        let events = engine.skipJogress(&s, at: t0.addingTimeInterval(60))
        XCTAssertEqual(events, [.evolved(from: "greymon", to: usual.first!)])
        XCTAssertEqual(engine.skipJogress(&s, at: t0), [], "nothing left to skip")
    }

    /// Usage while waiting is not lost: it carries into the next stage, but never fills it at once.
    func testExperienceWhileWaitingCarriesOverButNeverFillsTheNextStage() throws {
        var s = wait("greymon", line: "agumon")
        let adult = engine.growth.threshold(for: .adult)
        engine.addUsage(&s, tokens: 149 * tokens, provider: "claude_code", at: t0.addingTimeInterval(3600))
        XCTAssertEqual(s.partner.stageExp, adult + 149)
        engine.addUsage(&s, tokens: 150 * tokens, provider: "claude_code", at: t0.addingTimeInterval(13 * 3600))   // the next day
        XCTAssertEqual(s.partner.stageExp, 2 * adult - 1, "at most one stage's worth past the bar")
        let (_, events) = try engine.jogress(&s, code: friendCode("devimon", at: t0), at: t0.addingTimeInterval(14 * 3600))
        XCTAssertEqual(events.count, 1, "no second evolution")
        XCTAssertEqual(s.partner.stageExp, adult - 1)
        XCTAssertLessThan(s.partner.stageExp, engine.growth.threshold(for: .perfect))
    }

    func testTheWaitSurvivesSavingAndAnOldSaveHasNone() throws {
        let s = wait("greymon", line: "agumon")
        let back = try JSONDecoder().decode(DigimonState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.jogressWait, s.jogressWait)
        XCTAssertTrue(engine.isJogressOpen(back))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(full("greymon", line: "agumon"))) as? [String: Any])
        json["jogressWait"] = nil
        json["jogressCodes"] = nil
        let old = try JSONDecoder().decode(DigimonState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.jogressWait)
    }

    // MARK: Named Ultimate merges

    /// War Greymon + Metal Garurumon = Omegamon: Metal Garurumon raised before, and a friend's code
    /// for it once War Greymon's stage is full.
    func testANamedUltimateMergeNeedsTheRaisedPartnerAndAFriendsCode() throws {
        let path = ["botamon", "koromon", "agumon", "greymon", "metalgreymon", "wargreymon"]
        var alone = full("wargreymon", line: "agumon", path: path)
        let graduated = engine.addUsage(&alone, tokens: tokens, provider: "claude_code", at: t0)
        XCTAssertTrue(graduated.contains { if case .graduated = $0 { return true } else { return false } },
                      "without Metal Garurumon raised there is nothing to wait for")

        var s = full("wargreymon", line: "agumon", path: path)
        s.dex.insert("metalgarurumon")
        XCTAssertEqual(engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0), [.jogressOffered(options: ["omegamon"])])
        XCTAssertThrowsError(try engine.jogress(&s, code: friendCode("blackwargreymon", at: t0), at: t0)) {
            XCTAssertEqual($0 as? JogressError, .partnerDoesNotFit(species: "blackwargreymon"), "only Metal Garurumon")
        }
        let (_, events) = try engine.jogress(&s, code: friendCode("metalgarurumon", at: t0), at: t0)
        XCTAssertEqual(events, [.jogressed(from: "wargreymon", partner: "metalgarurumon", to: "omegamon")])
        XCTAssertTrue(s.discoveredEvolutions.contains("wargreymon>omegamon"))

        s.partner.stageExp = engine.growth.threshold(for: .ultimate) - 1
        let after = engine.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0)
        guard case .graduated(_, let graduatedPath)? = after.first else { return XCTFail("Omegamon graduates: \(after)") }
        XCTAssertEqual(graduatedPath.suffix(2), ["wargreymon", "omegamon"])

        var noFriend = full("wargreymon", line: "agumon", path: path)
        noFriend.dex.insert("metalgarurumon")
        engine.addUsage(&noFriend, tokens: tokens, provider: "claude_code", at: t0)
        let late = engine.tick(&noFriend, now: t0.addingTimeInterval(24 * 3600))
        XCTAssertTrue(late.contains { if case .graduated = $0 { return true } else { return false } },
                      "no friend's code: it graduates once the wait is over")
    }

    /// With friends' codes off, a named merge happens by itself once the partner was raised, and the
    /// card's merges are never waited for (the behavior before friend Jogress).
    func testWithFriendJogressOffNamedMergesHappenByThemselves() {
        var rules = EvolutionRules.mvp
        rules.friendJogress = false
        let solo = EvolutionEngine(catalog: catalog, rules: rules, growth: engine.growth, calendar: engine.calendar)
        var s = full("wargreymon", line: "agumon")
        s.dex.insert("metalgarurumon")
        XCTAssertEqual(solo.addUsage(&s, tokens: tokens, provider: "claude_code", at: t0), [.evolved(from: "wargreymon", to: "omegamon")])
        var greymon = full("greymon", line: "agumon")
        guard case .evolved? = solo.addUsage(&greymon, tokens: tokens, provider: "claude_code", at: t0).first else {
            return XCTFail("no wait without friends' codes")
        }
    }
}
