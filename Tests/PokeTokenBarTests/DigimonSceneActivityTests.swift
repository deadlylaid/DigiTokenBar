import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Idle activities in the real scene script (issue #5: "it does not do much"): wash, cook, climb, nap, ball
/// and code. Each starts with its props, ends by itself, and anything else (a grab, a battle, a bug) ends it
/// with its props gone; none for an egg or while asleep; staying in place never runs around; they stay rare.
@MainActor
final class DigimonSceneActivityTests: XCTestCase {
    private static let kinds = ["wash", "cook", "climb", "nap", "ball", "code"]

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

    /// A desktop scene (220 x 90 units) with a Child-sized block as the pet, a foe and an egg ready.
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
        scene.sprite(key: "egg_agumon", dataURI: try blockSprite(height: 14))
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && ['agumon', 'greymon', 'egg_agumon'].every(k => !!assets[k])")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        // A quiet scene: no bugs, no visitors; the pet a little left of the middle, facing right.
        _ = try await js(scene, """
        window.resetPet = () => {
          S.still = false; S.sleeping = false; S.mood = null;
          pet.bug = null; pet.bugIn = 1e9; pet.guests = []; pet.guest = null; pet.chip = null; pet.fight = null;
          pet.parts = []; pet.callout = null; pet.working = false;
          pet.enter('idle', {dur: 1e9}); pet.x = pet.center() - 20; pet.facing = 1; pet.flipX = -1;
        };
        // Painted pixels (alpha > 0) inside a scene-unit rectangle of the canvas.
        window.painted = (x, y, w, h) => {
          const k = pet.scale * DPR, d = pet.ctx.getImageData(Math.round(x * k), Math.round(y * k), Math.max(1, Math.round(w * k)), Math.max(1, Math.round(h * k))).data;
          let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++; return n;
        };
        // The scene-unit rectangle of the activity's main prop.
        window.propRect = () => {
          const a = pet.act, gy = pet.ground();
          if (!a) return null;
          if (a.kind === 'ball') return [a.ball.x - a.ball.r, a.ball.y - a.ball.r, 2 * a.ball.r, 2 * a.ball.r];
          if (a.kind === 'nap') { const nb = pet.noseAt(); return [nb.x - nb.r, nb.y - nb.r, 2 * nb.r, 2 * nb.r]; }
          if (a.kind === 'climb') return [a.px + a.pw - 3 * a.P, gy - a.wallH, 3 * a.P, a.wallH];   // the part beside the pet
          return [a.px, gy - 6 * a.P, a.pw, 6 * a.P];
        };
        true
        """)
        try await body(scene)
    }

    func testEveryActivityShowsItsPropsAndEndsByItself() async throws {
        try await scene { scene in
            for kind in Self.kinds {
                let r = try await json(scene, """
                (() => {
                  resetPet(); pet.working = '\(kind)' === 'code';
                  const started = pet.startActivity('\(kind)');
                  // Into the middle of it, where its prop is surely out.
                  const mid = {wash: 600, cook: 1500, climb: 1200, nap: 3500, ball: 120, code: 1500}['\(kind)'];
                  for (let i = 0; i < 400 && pet.state === 'act' && pet.t < mid; i++) pet.update(16);
                  // The same frame with and without the props: the difference is the props alone (the pet
                  // leaning into a laptop or under a nose bubble paints that spot too).
                  const rect = propRect(), stateMid = pet.state;
                  pet.draw();
                  const withProps = rect ? painted(...rect) : 0;
                  const drawAct = pet.drawAct; pet.drawAct = () => {}; pet.draw(); pet.drawAct = drawAct;
                  const shown = withProps - (rect ? painted(...rect) : 0);
                  let frames = 0;
                  while (pet.state === 'act' && frames < 3000) { pet.update(16); frames++; }
                  return JSON.stringify({started, stateMid, shown, frames, after: pet.state, act: !!pet.act, actAt: pet.actAt});
                })()
                """)
                XCTAssertEqual(r["started"] as? Bool, true, kind)
                XCTAssertEqual(r["stateMid"] as? String, "act", kind)
                XCTAssertGreaterThan(r["shown"] as? Int ?? 0, 4, "\(kind): its prop is drawn: \(r)")
                XCTAssertLessThan(r["frames"] as? Int ?? 9999, 3000, "\(kind) ends by itself")
                XCTAssertNotEqual(r["after"] as? String, "act")
                XCTAssertEqual(r["act"] as? Bool, false, "\(kind): its props are gone")
            }
        }
    }

    func testGrabbingABattleOrABugEndsAnActivityWithItsProps() async throws {
        try await scene { scene in
            let grab = try await json(scene, """
            (() => {
              resetPet(); pet.startActivity('wash');
              for (let i = 0; i < 40; i++) pet.update(16);
              pet.grab();
              return JSON.stringify({state: pet.state, act: !!pet.act});
            })()
            """)
            XCTAssertEqual(grab["state"] as? String, "held", "a grab is the user's hand: it wins")
            XCTAssertEqual(grab["act"] as? Bool, false, "the bowl does not stay behind")

            let battle = try await json(scene, """
            (() => {
              resetPet(); pet.startActivity('cook');
              for (let i = 0; i < 60; i++) pet.update(16);
              pet.duel({foe: 'greymon', rounds: [{a: 'me', hit: true}, {a: 'foe', hit: false}], won: true});
              const act = !!pet.act; let decided = false;
              for (let i = 0; i < 3000 && pet.fight; i++) {
                pet.update(16);
                decided = decided || (!!pet.fight && pet.fight.done > 0 && pet.fight.i === pet.fight.rounds.length);
              }
              return JSON.stringify({act, decided});
            })()
            """)
            XCTAssertEqual(battle["act"] as? Bool, false, "the pot goes when a battle starts")
            XCTAssertEqual(battle["decided"] as? Bool, true, "and the battle plays to its end")

            let bug = try await json(scene, """
            (() => {
              resetPet(); pet.startActivity('nap');
              for (let i = 0; i < 30; i++) pet.update(16);
              pet.bugIn = 0;   // a bug comes now
              const states = [];
              for (let i = 0; i < 1500 && pet.act; i++) { pet.update(16); if (!states.includes(pet.state)) states.push(pet.state); }
              return JSON.stringify({act: !!pet.act, states, bug: !!pet.bug});
            })()
            """)
            XCTAssertEqual(bug["act"] as? Bool, false, "a bug arriving ends the nap: \(bug)")
            XCTAssertTrue((bug["states"] as? [String] ?? []).contains("alert"), "it turns to the bug: \(bug)")
        }
    }

    func testNoneForAnEggOrWhileAsleepAndCodeOnlyWhileTheAgentWorks() async throws {
        try await scene { scene in
            let r = try await json(scene, """
            (() => {
              resetPet();
              const awake = pet.actChoices().map(c => c[0]);
              pet.working = true;
              const working = pet.actChoices().map(c => c[0]);
              resetPet(); S.sleeping = true; pet.enter('idle', {dur: 1e9});
              const asleep = pet.actChoices().length, asleepTry = pet.tryActivity(true);
              resetPet(); pet.setNow('egg_agumon'); pet.enter('idle', {dur: 1e9});
              const egg = pet.actChoices().length, eggTry = pet.tryActivity(true);
              pet.setNow('agumon');
              resetPet(); pet.working = true; pet.startActivity('code');
              for (let i = 0; i < 30; i++) pet.update(16);
              pet.setAgent({working: false});
              pet.update(16);
              return JSON.stringify({awake, working, asleep, asleepTry, egg, eggTry, afterWork: pet.state, act: !!pet.act});
            })()
            """)
            XCTAssertEqual(Set(r["awake"] as? [String] ?? []), Set(["wash", "cook", "climb", "nap", "ball"]))
            XCTAssertTrue((r["working"] as? [String] ?? []).contains("code"), "coding along only while the agent works")
            XCTAssertEqual(r["asleep"] as? Int, 0, "never while asleep")
            XCTAssertTrue(r["asleepTry"] is NSNull)
            XCTAssertEqual(r["egg"] as? Int, 0, "never for an egg")
            XCTAssertTrue(r["eggTry"] is NSNull)
            XCTAssertEqual(r["afterWork"] as? String, "stretch", "work done: it stretches and leaves the laptop")
            XCTAssertEqual(r["act"] as? Bool, false)
        }
    }

    /// "Stay in place" (Settings) never makes it run around: no ball, and nothing else moves it sideways.
    func testStayingInPlaceNeverRunsAround() async throws {
        try await scene { scene in
            let r = try await json(scene, """
            (() => {
              const kinds = [], moved = [];
              for (let n = 0; n < 60; n++) {
                resetPet(); S.still = true; pet.working = n % 2 === 0;
                const x0 = pet.x, kind = pet.tryActivity(true);
                kinds.push(kind);
                let far = 0;
                for (let i = 0; i < 3000 && pet.state === 'act'; i++) { pet.update(16); far = Math.max(far, Math.abs(pet.x - x0)); }
                if (far > .5) moved.push(kind + ':' + far.toFixed(1));
              }
              return JSON.stringify({kinds, moved});
            })()
            """)
            let kinds = Set(r["kinds"] as? [String] ?? [])
            XCTAssertFalse(kinds.contains("ball"), "no ball while staying in place: \(kinds)")
            XCTAssertGreaterThanOrEqual(kinds.count, 4, "the others still come: \(kinds)")
            XCTAssertEqual(r["moved"] as? [String], [], "nothing moved it sideways")
        }
    }

    /// Rare by design: never within the quiet time after one (even when the dice say yes), and only on a
    /// small chance after it (ACT_CHANCE), so most idle picks stay the usual walks and stretches.
    func testTheyStayRare() async throws {
        try await scene { scene in
            let r = try await json(scene, """
            (() => {
              const real = Math.random;
              resetPet(); pet.actAt = pet.clock;              // one just ended
              Math.random = () => 0;                          // the dice always say yes
              const inQuiet = pet.tryActivity();
              pet.clock += ACT_GAP[VIEW] + 1;                 // the quiet time is over
              const afterQuiet = pet.tryActivity();
              resetPet(); pet.actAt = -1e9;
              Math.random = () => ACT_CHANCE[VIEW] + .001;    // the dice just miss
              const missed = pet.tryActivity();
              Math.random = real;
              // From next(): over many idle picks with the quiet time ignored, about ACT_CHANCE of them.
              let started = 0; const N = 4000;
              for (let i = 0; i < N; i++) { resetPet(); pet.actAt = -1e9; if (pet.tryActivity()) started++; }
              return JSON.stringify({inQuiet, afterQuiet, missed, share: started / N, chance: ACT_CHANCE[VIEW], gap: ACT_GAP[VIEW]});
            })()
            """)
            XCTAssertTrue(r["inQuiet"] is NSNull, "never right after one")
            XCTAssertNotNil(r["afterQuiet"] as? String, "after the quiet time it can come")
            XCTAssertTrue(r["missed"] is NSNull)
            let share = r["share"] as? Double ?? 1, chance = r["chance"] as? Double ?? 0
            XCTAssertEqual(share, chance, accuracy: 0.015, "about one idle pick in \(Int(1 / chance))")
            XCTAssertEqual(r["gap"] as? Double, 60000, "a minute of quiet on the desktop")
        }
    }
}
