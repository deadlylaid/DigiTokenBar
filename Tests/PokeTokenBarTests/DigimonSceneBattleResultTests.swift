import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Issue #7: "a practice battle shows a win in the animation but is recorded as a loss". The result is decided
/// once and recorded, and the scene plays that result, but other things took the pet's state over mid-battle:
/// food on every token refresh, a coding agent's "done" cheer (a double hop with sparkles), its call, a jump,
/// sleep, an evolution, a graduation. The battle stopped before its result, and a cheer right after a hit
/// looked like a win. An older battle still waiting for its foe's sprite could also start after a newer one.
/// These tests drive the real scene script.
@MainActor
final class DigimonSceneBattleResultTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    private func json(_ scene: DigimonScene, _ code: String) async throws -> [String: Any] {
        let text = try await js(scene, code) as? String
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(text).utf8)) as? [String: Any])
    }

    /// A plain block `height` pixels tall standing at the bottom of a 64x64 sprite.
    private func blockSprite(height: Int) throws -> String {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSColor.systemGreen.setFill()
        NSRect(x: 20, y: 0, width: 24, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return "data:image/png;base64," + (try XCTUnwrap(rep.representation(using: .png, properties: [:]))).base64EncodedString()
    }

    /// A desktop scene (220 x 90 units) with a Child-sized block as the pet and a foe ready.
    private func scene(_ body: (DigimonScene) async throws -> Void) async throws {
        let scene = DigimonScene(mode: .desk)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 440, height: 180), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 440, height: 180)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        scene.sprite(key: "agumon", dataURI: try blockSprite(height: 26))
        scene.sprite(key: "greymon", dataURI: try blockSprite(height: 36))
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && ['agumon', 'greymon'].every(k => !!assets[k])")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        // A quiet scene: no bugs, no visitors, nothing in flight; the pet a little left of the middle.
        _ = try await js(scene, """
        window.resetPet = () => {
          S.still = false; S.sleeping = false; S.mood = null;
          pet.bug = null; pet.bugIn = 1e9; pet.guests = []; pet.guest = null; pet.chip = null; pet.fight = null;
          pet.parts = []; pet.callout = null; pet.working = false; pet.shots = []; pet.booms = []; pet.later = []; pet.joining = null;
          pet.enter('idle', {dur: 1e9}); pet.x = pet.center() - 20; pet.facing = 1; pet.flipX = -1;
        };
        true
        """)
        try await body(scene)
    }

    /// A lost battle (the foe lands three hits first) cut into after a few seconds by each of them: the battle
    /// still plays every round and shows "졌다…", nothing else happens while it plays, and what waited happens
    /// right after it.
    func testABattleReachesItsResultWhateverCutsIn() async throws {
        try await scene { scene in
            let r = try await json(scene, """
            (() => {
              const res = {};
              const lost = {foe: 'greymon', foeStage: 3, won: false,
                            rounds: [{a: 'me', hit: true}, {a: 'foe', hit: true}, {a: 'me', hit: true}, {a: 'foe', hit: true},
                                     {a: 'me', hit: false}, {a: 'foe', hit: true}]};
              const cuts = {
                cheer: () => pet.setAgent({react: 'done'}),
                notice: () => pet.setAgent({react: 'waiting'}),
                jump: () => pet.jump(),
                feed: () => pet.feed(),
                sleep: () => { S.sleeping = true; pet.sleep(); },
                evolve: () => pet.evolve('greymon', false),
                graduate: () => pet.graduate(),
              };
              for (const [name, cut] of Object.entries(cuts)) {
                resetPet();
                pet.duel(lost);
                let callouts = [], during = new Set(), after = new Set(), decided = false;
                for (let i = 0; i < 1500; i++) {
                  if (i === 200) cut();
                  pet.update(16);
                  (pet.fight ? during : after).add(pet.state);
                  if (pet.callout && !callouts.includes(pet.callout.text)) callouts.push(pet.callout.text);
                  if (pet.fight && pet.fight.done > 0 && pet.fight.i === pet.fight.rounds.length) decided = true;
                }
                res[name] = {decided, callouts, during: [...during], after: [...after]};
                S.sleeping = false; pet.key = 'agumon';
              }
              return JSON.stringify(res);
            })()
            """)
            let expectedAfter = ["cheer": "hop", "notice": "hop", "jump": "hop", "feed": "eat", "sleep": "sleep",
                                 "evolve": "evolve", "graduate": "hop"]
            for (name, after) in expectedAfter {
                let c = try XCTUnwrap(r[name] as? [String: Any], name)
                XCTAssertEqual(c["decided"] as? Bool, true, "\(name): every round plays and the result shows: \(c)")
                XCTAssertTrue((c["callouts"] as? [String] ?? []).contains("졌다…"), "\(name): the loss is shown: \(c)")
                XCTAssertEqual(Set(c["during"] as? [String] ?? []), ["duel", "attack"], "\(name): nothing else while it plays")
                XCTAssertTrue((c["after"] as? [String] ?? []).contains(after), "\(name): it happens after the battle: \(c)")
            }
        }
    }

    /// Battle A's foe sprite is still loading when battle B (foe ready) arrives: B starts, and A must not take
    /// over once its sprite is ready, or the scene would show A under B's result line.
    func testAnOlderBattleWaitingForItsSpriteNeverStartsAfterANewerOne() async throws {
        try await scene { scene in
            _ = try await js(scene, "resetPet(); true")
            let lost: [[String: Any]] = [["a": "me", "hit": false], ["a": "foe", "hit": true], ["a": "me", "hit": false],
                                         ["a": "foe", "hit": true], ["a": "me", "hit": false], ["a": "foe", "hit": true]]
            // The order the app sends them in: A's sprite (still decoding), A, then B whose foe is ready.
            scene.sprite(key: "gabumon", dataURI: try blockSprite(height: 30))
            scene.command(["type": "battle", "foe": "gabumon", "foeStage": 3, "won": true,
                           "rounds": [["a": "me", "hit": true], ["a": "foe", "hit": false]]])
            scene.command(["type": "battle", "foe": "greymon", "foeStage": 3, "won": false, "rounds": lost])
            var loaded = false
            for _ in 0..<50 where !loaded {
                try await Task.sleep(for: .milliseconds(100))
                loaded = (try? await js(scene, "!!assets['gabumon']")) as? Bool ?? false
            }
            XCTAssertTrue(loaded, "the older battle's sprite arrived")
            try await Task.sleep(for: .milliseconds(200))
            let foe = try await js(scene, "pet.fight ? pet.fight.foe : null") as? String
            XCTAssertEqual(foe, "greymon", "the newer battle keeps playing")
        }
    }

    /// Many real battles (`DigimonBattle.fight`: both turn orders, ties, the 12-attack limit) played by pets with
    /// different move shapes (two missiles, beams that linger, thrown poop, ground moves ...): every round's hit
    /// or miss shows as decided and on the right side, every round plays, the end says the recorded result, and
    /// only a win hops.
    func testWhatABattleShowsAlwaysMatchesItsRecordedResult() async throws {
        try await scene { scene in
            // One species per move shape, each drawn as a block.
            let keys = try await js(scene, """
            (() => { const by = {}; for (const k of Object.keys(MOVES)) { const m = moveOf(k); if (!by[m.kind]) by[m.kind] = k; }
                     return JSON.stringify(Object.values(by)); })()
            """) as? String
            let species = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(keys).utf8)) as? [String])
            XCTAssertGreaterThan(species.count, 10, "many move shapes")
            for key in species { scene.sprite(key: key, dataURI: try blockSprite(height: 30)) }
            let list = String(data: try JSONSerialization.data(withJSONObject: species), encoding: .utf8)!
            var loaded = false
            for _ in 0..<100 where !loaded {
                try await Task.sleep(for: .milliseconds(100))
                loaded = (try? await js(scene, "\(list).every(k => !!assets[k])")) as? Bool ?? false
            }
            XCTAssertTrue(loaded, "sprites loaded")

            let catalog = EvolutionEngine().catalog
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var rng = SeededGenerator(seed: 7)
            var battles: [[String: Any]] = []
            var wins = 0, ties = 0, long = 0
            for i in 0..<160 {
                let level: DigimonLevel = [.child, .adult, .perfect, .ultimate][i % 4]
                let pool = catalog.species.values.filter { $0.level == level }.map(\.key).sorted()
                let me = BattleFighter(player: i % 3 == 0 ? "zz-me" : "me", species: pool[Int(rng.next() % UInt64(pool.count))],
                                       level: level, training: Int(rng.next() % 101), stage: 0, day: "2027-01-15",
                                       nonce: rng.next(), issuedAt: now)
                let foe = BattleFighter(player: "wild", species: pool[Int(rng.next() % UInt64(pool.count))], level: level,
                                        training: 20 + Int(rng.next() % 61), stage: 0, day: "2027-01-15",
                                        nonce: rng.next(), issuedAt: now)
                let result = DigimonBattle.fight(me: me, foe: foe, catalog: catalog)
                if result.won { wins += 1 }
                if result.myHits == result.foeHits { ties += 1 }
                if result.rounds.count == DigimonBattle.maxAttacks { long += 1 }
                battles.append(["pet": species[i % species.count], "foe": species[(i * 7 + 3) % species.count],
                                "won": result.won,
                                "rounds": result.rounds.map { ["a": $0.attacker == .me ? "me" : "foe", "hit": $0.hit] }])
            }
            XCTAssertTrue(wins > 20 && wins < 140, "both results: \(wins) wins")
            let data = String(data: try JSONSerialization.data(withJSONObject: battles), encoding: .utf8)!
            let r = try await json(scene, """
            (() => {
              const battles = \(data), bad = [];
              const boom = pet.boom.bind(pet);
              let landed = [];
              pet.boom = (x, y, s) => { if (s && s.duel) landed.push({r: s._r, mine: !!s.mine}); boom(x, y, s); };
              battles.forEach((b, n) => {
                resetPet(); pet.key = b.pet; landed = [];
                pet.duel({foe: b.foe, foeStage: 3, won: b.won, rounds: b.rounds});
                let end = null, hopped = false;
                for (let frame = 0; frame < 4000 && pet.fight; frame++) {
                  const F = pet.fight;
                  pet.update(16);
                  for (const s of pet.shots) if (s.duel && s._r === undefined) s._r = F.i - 1;
                  if (F.done > 0 && F.i === F.rounds.length && pet.callout && end === null) end = pet.callout.text;
                  if (F.done > 0 && F.done < 900 && pet.y > .5) hopped = true;
                }
                const problems = [];
                if (pet.fight) problems.push('never ended');
                if (end !== (b.won ? '이겼다!' : '졌다…')) problems.push('end ' + end);
                if (hopped !== b.won) problems.push('hop ' + hopped);
                b.rounds.forEach((round, i) => {
                  const shown = landed.filter(l => l.r === i);
                  if (round.hit !== (shown.length > 0)) problems.push('round ' + i + (round.hit ? ' hit not shown' : ' miss shown as hit'));
                  if (shown.some(l => l.mine !== (round.a === 'me'))) problems.push('round ' + i + ' wrong side');
                });
                if (problems.length) bad.push({n, pet: b.pet, foe: b.foe, won: b.won, problems});
              });
              pet.boom = boom; pet.key = 'agumon';
              return JSON.stringify({bad: bad.slice(0, 8), count: bad.length});
            })()
            """)
            XCTAssertEqual(r["count"] as? Int, 0, "what is shown disagrees with the record: \(r["bad"] ?? "")")
            XCTAssertGreaterThan(ties + long, 0, "the set includes ties or the 12-attack limit")
        }
    }

    // MARK: Jogress (merge) — the same protection, with its evolution first

    /// Drives a Jogress the way the app sends it: the merge, then the evolution about 2.2 s later (`evolveAt`,
    /// in 16 ms frames; earlier when the scene's frames lag behind the app's clock), with `cut` arriving at frame
    /// `cutAt`. Returns the states in order (repeats folded) and the final look.
    private func jogress(_ scene: DigimonScene, cut: String, cutAt: Int, evolveAt: Int, frames: Int = 900) async throws -> [String: Any] {
        try await json(scene, """
        (() => {
          resetPet(); pet.key = 'agumon';
          const cuts = {
            none: () => {},
            cheer: () => pet.setAgent({react: 'done'}),
            notice: () => pet.setAgent({react: 'waiting'}),
            jump: () => pet.jump(),
            feed: () => pet.feed(),
            sleep: () => { S.sleeping = true; pet.sleep(); },
            graduate: () => pet.graduate(),
            battle: () => pet.duel({foe: 'greymon', foeStage: 3, won: true, rounds: [{a: 'me', hit: true}]}),
          };
          pet.merge({partner: 'greymon'});
          const states = [];
          let flashed = false;
          for (let i = 0; i < \(frames); i++) {
            if (i === \(cutAt)) cuts['\(cut)']();
            if (i === \(evolveAt)) pet.evolve('omnimon', false);
            pet.update(16);
            if (states[states.length - 1] !== pet.state) states.push(pet.state);
            if (pet.state === 'merge' && pet.d.flashed) flashed = true;
          }
          const out = {states, key: pet.key, flashed, joining: !!pet.joining, later: pet.later.length};
          S.sleeping = false;
          return JSON.stringify(out);
        })()
        """)
    }

    private func withOmnimon(_ scene: DigimonScene) async throws {
        scene.sprite(key: "omnimon", dataURI: try blockSprite(height: 40))
        var loaded = false
        for _ in 0..<50 where !loaded {
            try await Task.sleep(for: .milliseconds(100))
            loaded = (try? await js(scene, "!!assets['omnimon']")) as? Bool ?? false
        }
        XCTAssertTrue(loaded)
    }

    /// Anything the app or the coding agent sends mid-merge (food, cheer, call, jump, sleep, graduation, a battle)
    /// used to cut the Jogress short. Now the merge plays to its flash, its evolution follows, and only then does
    /// the thing that cut in happen.
    func testAJogressPlaysThroughThenItsEvolutionThenWhatWaited() async throws {
        try await scene { scene in
            try await withOmnimon(scene)
            let after = ["cheer": "hop", "notice": "hop", "jump": "hop", "feed": "eat", "sleep": "sleep",
                         "graduate": "hop", "battle": "duel"]
            for (cut, expected) in after {
                let r = try await jogress(scene, cut: cut, cutAt: 60, evolveAt: 140)
                let states = r["states"] as? [String] ?? []
                XCTAssertEqual(states.first, "merge", "\(cut): \(r)")
                XCTAssertEqual(r["flashed"] as? Bool, true, "\(cut): the merge reaches its flash: \(r)")
                let evolve = try XCTUnwrap(states.firstIndex(of: "evolve"), "\(cut): \(r)")
                XCTAssertEqual(Set(states[0..<evolve]).subtracting(["idle"]), ["merge"],
                               "\(cut): nothing but the merge (and the wait for the app) before the evolution: \(r)")
                let waited = try XCTUnwrap(states.lastIndex(of: expected), "\(cut): it happens in the end: \(r)")
                XCTAssertGreaterThan(waited, evolve, "\(cut): only after the evolution: \(r)")
                if cut != "battle" { XCTAssertEqual(r["key"] as? String, "omnimon", "\(cut): the Jogress result stays: \(r)") }
                XCTAssertEqual(r["joining"] as? Bool, false, "\(cut): the Jogress is over: \(r)")
            }
        }
    }

    /// The Jogress's own evolution is never queued behind food or a cheer that came first: when the scene's
    /// frames lag behind the app's 2.2 s and the evolution arrives mid-merge, it waits for the merge's end and
    /// plays first; what came before it plays after it.
    func testTheJogressEvolutionGoesFirstEvenWhenItArrivesMidMerge() async throws {
        try await scene { scene in
            try await withOmnimon(scene)
            for cut in ["feed", "cheer"] {
                let r = try await jogress(scene, cut: cut, cutAt: 30, evolveAt: 60)
                let states = r["states"] as? [String] ?? []
                let evolve = try XCTUnwrap(states.firstIndex(of: "evolve"), "\(cut): \(r)")
                let waited = try XCTUnwrap(states.lastIndex(of: cut == "feed" ? "eat" : "hop"), "\(cut): \(r)")
                XCTAssertLessThan(evolve, waited, "\(cut): the evolution before what arrived first: \(r)")
                XCTAssertEqual(r["flashed"] as? Bool, true, "\(cut): the merge was not cut by its own early evolution: \(r)")
                XCTAssertEqual(r["key"] as? String, "omnimon")
            }
        }
    }

    /// A Jogress sent while a battle plays waits for the battle's result (it used to replace the battle), and its
    /// evolution queues behind it. If the evolution never comes (the app sends none when the sprite fails), what
    /// waited still runs after a short wait.
    func testAJogressWaitsForABattleAndNothingWaitsForever() async throws {
        try await scene { scene in
            try await withOmnimon(scene)
            let r = try await json(scene, """
            (() => {
              resetPet(); pet.key = 'agumon';
              pet.duel({foe: 'greymon', foeStage: 3, won: false, rounds: [{a: 'me', hit: false}, {a: 'foe', hit: true}]});
              const states = []; let decided = false;
              for (let i = 0; i < 1400; i++) {
                if (i === 40) pet.merge({partner: 'greymon'});
                if (i === 180) pet.evolve('omnimon', false);
                pet.update(16);
                if (pet.fight && !pet.fight.merge && pet.fight.done > 0) decided = true;
                if (states[states.length - 1] !== pet.state) states.push(pet.state);
              }
              const battle = {states, decided, key: pet.key};
              resetPet(); pet.key = 'agumon';
              pet.merge({partner: 'greymon'});
              const waits = [];
              for (let i = 0; i < 700; i++) {
                if (i === 30) pet.feed();
                pet.update(16);
                if (waits[waits.length - 1] !== pet.state) waits.push(pet.state);
              }
              return JSON.stringify({battle, noEvolution: {states: waits, joining: !!pet.joining, key: pet.key}});
            })()
            """)
            let b = try XCTUnwrap(r["battle"] as? [String: Any]), states = b["states"] as? [String] ?? []
            XCTAssertEqual(b["decided"] as? Bool, true, "the battle shows its result first: \(b)")
            let duel = try XCTUnwrap(states.firstIndex(of: "duel"), "\(b)")
            let merge = try XCTUnwrap(states.firstIndex(of: "merge"), "\(b)")
            let evolve = try XCTUnwrap(states.firstIndex(of: "evolve"), "\(b)")
            XCTAssertLessThan(duel, merge)
            XCTAssertLessThan(merge, evolve)
            XCTAssertEqual(b["key"] as? String, "omnimon")
            let n = try XCTUnwrap(r["noEvolution"] as? [String: Any])
            XCTAssertTrue((n["states"] as? [String] ?? []).contains("eat"), "food runs once the wait gives up: \(n)")
            XCTAssertEqual(n["joining"] as? Bool, false)
            XCTAssertEqual(n["key"] as? String, "agumon", "no evolution came, the look stays")
        }
    }

    /// Same class, outside a Jogress: a battle pressed right as the Digimon evolves used to cut the evolution.
    /// It now waits for the evolution, then plays through to its result.
    func testABattleWaitsForAnEvolution() async throws {
        try await scene { scene in
            try await withOmnimon(scene)
            let r = try await json(scene, """
            (() => {
              resetPet(); pet.key = 'agumon';
              pet.evolve('omnimon', false);
              const states = []; let decided = false;
              for (let i = 0; i < 1400; i++) {
                if (i === 30) pet.duel({foe: 'greymon', foeStage: 3, won: true, rounds: [{a: 'me', hit: true}, {a: 'foe', hit: false}]});
                pet.update(16);
                if (pet.fight && pet.fight.done > 0) decided = true;
                if (states[states.length - 1] !== pet.state) states.push(pet.state);
              }
              return JSON.stringify({states, decided, key: pet.key});
            })()
            """)
            let states = r["states"] as? [String] ?? []
            let evolve = try XCTUnwrap(states.firstIndex(of: "evolve"), "\(r)"), duel = try XCTUnwrap(states.firstIndex(of: "duel"), "\(r)")
            XCTAssertLessThan(evolve, duel, "the evolution first: \(r)")
            XCTAssertEqual(r["key"] as? String, "omnimon", "the evolution finished: \(r)")
            XCTAssertEqual(r["decided"] as? Bool, true, "then the battle reaches its result: \(r)")
        }
    }
}
