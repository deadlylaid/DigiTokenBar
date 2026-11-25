import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Bug hunts in the real scene script. A bug that already stood next to the Digimon (it walked up while
/// the Digimon slept, fought or evolved) took hit after hit and never died: a fast move aimed at its feet
/// passed it within one frame, and hits were checked only where the shot was at the end of each frame.
/// The burst on the ground at its feet looked like a hit.
@MainActor
final class DigimonSceneBugTests: XCTestCase {

    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
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
        NSRect(x: 12, y: 0, width: 40, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return "data:image/png;base64," + (try XCTUnwrap(rep.representation(using: .png, properties: [:]))).base64EncodedString()
    }

    /// For each shape, a Child-sized short Digimon and an Ultimate-sized tall one, at 60 and 20 frames a
    /// second: a bug standing right in front attacks... is attacked, and must die from the first shot.
    func testABugStandingRightInFrontDiesFromTheFirstHit() async throws {
        var misses: [String] = []
        for (stage, height) in [(3, 24), (6, 60)] {
            let scene = DigimonScene(mode: .popover)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
            window.contentView = scene.webView
            window.orderFront(nil)
            defer { window.close() }
            scene.sprite(key: "agumon", dataURI: try blockSprite(height: height))
            scene.apply(["key": "agumon", "line": "agumon", "stage": stage, "sleeping": false, "lang": "ko"])
            var ready = false
            for _ in 0..<100 where !ready {
                try await Task.sleep(for: .milliseconds(100))
                ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['agumon']")) as? Bool ?? false
            }
            XCTAssertTrue(ready, "the scene did not start")
            // Every shape the scene has (each has a timing), so a new shape is checked without a list here.
            let kinds = "Object.keys(TIMING)"
            let seen = try await js(scene, """
            (() => {
              const out = [], keep = MOVES.agumon.kind;
              for (const kind of \(kinds)) for (const dt of [16, 50]) for (const side of [1, -1]) {
                MOVES.agumon.kind = kind;
                pet.shots = []; pet.booms = []; pet.parts = []; pet.x = pet.center(); pet.facing = side; pet.flash = 0; pet.shake = 0;
                const b = pet.bb(), petL = pet.x + b.l, petR = pet.x + b.r;
                // Stopped where a walking bug stops: 4 pixels from the Digimon's side.
                pet.bug = {x: side > 0 ? petR + 4 : petL - 4 - 11, dir: -side, t: 0, dead: false, noticed: true, big: false, sc: 1, hp: 1, hit: 0};
                const g = pet.bug;
                pet.enter('idle', {dur: 99999});
                let shots = 0;
                const fire = pet.fire.bind(pet);
                pet.fire = (k, n) => { shots++; fire(k, n); };
                for (let i = 0; i < 8000 / dt && !g.dead; i++) pet.update(dt);
                pet.fire = fire;
                if (!g.dead || shots > (kind === 'missile' ? 2 : 1)) out.push(`${kind} at ${1000 / dt | 0} fps from ${side > 0 ? 'the right' : 'the left'}: ${g.dead ? 'dead' : 'alive'} after ${shots} shots`);
              }
              MOVES.agumon.kind = keep;
              return JSON.stringify({misses: out, shapes: \(kinds).length});
            })()
            """) as? String
            let found = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
            XCTAssertEqual(found["shapes"] as? Int, 18, "every move shape is tried (a new one needs no list here)")
            misses += (found["misses"] as? [String] ?? []).map { "stage \(stage): \($0)" }
        }
        XCTAssertEqual(misses, [], misses.joined(separator: "\n"))
    }

    /// Poop Throw is thrown, not fired: it rose over the middle and then slid on in a straight line
    /// once the drawn arc ended (user report, 2026-11-21). Now gravity pulls it all the way: every frame
    /// it falls a little faster, and with nothing to hit it lands on the ground and splats.
    func testPoopFallsAllTheWayAndLandsOnTheGround() async throws {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        scene.sprite(key: "agumon", dataURI: try blockSprite(height: 30))
        scene.apply(["key": "agumon", "line": "agumon", "stage": 4, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['agumon']")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let result = try await js(scene, """
        (() => {
          pet.bug = null; pet.bugIn = 1e9; pet.shots = []; pet.booms = []; pet.x = 40; pet.facing = 1;
          pet.enter('idle', {dur: 99999});
          pet.fire('poop');
          const s = pet.shots[0], ys = [], vys = [];
          for (let i = 0; i < 200 && pet.shots.includes(s); i++) { ys.push(s.y); vys.push(s.vy); pet.update(16); }
          const splat = pet.booms.find(b => b.kind === 'poop');
          return JSON.stringify({ys, vys, gone: !pet.shots.includes(s), splatY: splat ? splat.y : null, ground: pet.ground(),
                                 ox: s.ox, x: s.x});
        })()
        """) as? String
        let r = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(result).utf8)) as? [String: Any])
        let ys = try XCTUnwrap(r["ys"] as? [Double]), vys = try XCTUnwrap(r["vys"] as? [Double])
        XCTAssertGreaterThan(ys.count, 10, "it flew for a while")
        XCTAssertLessThan(ys.min() ?? 0, ys[0] - 5, "it rises first")
        XCTAssertTrue(zip(vys, vys.dropFirst()).allSatisfy { $1 > $0 }, "it falls faster every frame, never straight: \(vys)")
        XCTAssertEqual(r["gone"] as? Bool, true)
        let ground = try XCTUnwrap(r["ground"] as? Double), splatY = try XCTUnwrap(r["splatY"] as? Double)
        XCTAssertEqual(splatY, ground - 2, accuracy: 1, "it lands on the ground and splats there")
        XCTAssertEqual((r["x"] as? Double ?? 0) - (r["ox"] as? Double ?? 0), 70, accuracy: 12, "about 70 px ahead")
    }

    /// Issue #3: grabbing the desktop pet mid-battle turned it into 'held', which took over the state that
    /// plays the battle, so the battle stopped for good. Grabbing (and dropping, even with a shift back inside
    /// the screen) must leave a battle and a Jogress running, as it already left an evolution.
    func testGrabbingMidBattleOrJogressDoesNotStopIt() async throws {
        let scene = DigimonScene(mode: .desk)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        scene.sprite(key: "agumon", dataURI: try blockSprite(height: 30))
        scene.sprite(key: "greymon", dataURI: try blockSprite(height: 40))
        scene.apply(["key": "agumon", "line": "agumon", "stage": 4, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['agumon'] && !!assets['greymon']")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let battle = try await js(scene, """
        (() => {
          pet.bug = null; pet.bugIn = 1e9; pet.shots = []; pet.booms = []; pet.x = 140; pet.enter('idle', {dur: 99999});
          pet.duel({foe: 'greymon', rounds: [{a: 'me', hit: true}, {a: 'foe', hit: false}, {a: 'me', hit: true}], won: true});
          const xFoe = pet.fight.fx; let x0 = null, held = false, decided = false;
          for (let i = 0; i < 3000 && pet.fight; i++) {
            if (i === 60) {
              x0 = pet.x;
              pet.grab();
              for (let k = 0; k < 10; k++) { pet.dragMove(5); pet.update(16); held = held || pet.state === 'held'; }
              pet.drop(30);
            }
            pet.update(16);
            held = held || pet.state === 'held';
            // Reached the end of its rounds and showed the result, rather than the fight being dropped.
            decided = decided || (!!pet.fight && pet.fight.done > 0 && pet.fight.i === pet.fight.rounds.length);
          }
          return JSON.stringify({finished: !pet.fight, decided, held, state: pet.state,
                                 callout: pet.callout ? pet.callout.text : null, xFoe});
        })()
        """) as? String
        let b = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(battle).utf8)) as? [String: Any])
        XCTAssertEqual(b["held"] as? Bool, false, "a grab mid-battle does not lift the Digimon out of the fight")
        XCTAssertEqual(b["decided"] as? Bool, true, "every round plays and the result shows: \(b)")
        XCTAssertEqual(b["finished"] as? Bool, true, "then the fight ends: \(b)")

        let jogress = try await js(scene, """
        (() => {
          pet.shots = []; pet.booms = []; pet.enter('idle', {dur: 99999});
          pet.merge({partner: 'greymon'});
          for (let i = 0; i < 20; i++) pet.update(16);
          const before = pet.state;
          pet.grab(); pet.update(16);
          const during = pet.state;
          pet.drop(30);
          return JSON.stringify({before, during, fight: !!pet.fight});
        })()
        """) as? String
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(jogress).utf8)) as? [String: Any])
        XCTAssertEqual(j["before"] as? String, "merge")
        XCTAssertEqual(j["during"] as? String, "merge", "a grab mid-Jogress leaves the merge running")
        XCTAssertEqual(j["fight"] as? Bool, true)
    }
}
