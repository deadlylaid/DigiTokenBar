import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Runs the real scene script: a battle must throw each Digimon's own move, the same shape it uses
/// against bugs (the first battle version drew every move as a plain ball). Sprites are the
/// code-drawn egg, so no network is needed.
@MainActor
final class DigimonSceneBattleTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    /// Plays a battle between `me` and `foe` in the real scene script and reports what flew and
    /// what it left: shots as "me:<kind>" / "foe:<kind>", impact kinds, held lines, and the end state.
    private func battle(me: String, foe: String) async throws -> [String: Any] {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        let uri = "data:image/png;base64," + png.base64EncodedString()
        scene.sprite(key: me, dataURI: uri)
        scene.sprite(key: foe, dataURI: uri)
        scene.apply(["key": me, "line": "agumon", "stage": 4, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        scene.command(["type": "battle", "foe": foe, "won": true,
                       "rounds": [["a": "me", "hit": true], ["a": "foe", "hit": true]]])
        try await Task.sleep(for: .milliseconds(300))
        let seen = try await js(scene, """
        (() => {
          const shots = [], booms = [], held = [];
          for (let i = 0; i < 220; i++) {
            pet.update(33);
            for (const s of pet.shots) {
              const tag = (s.mine ? 'me:' : 'foe:') + s.kind;
              if (s.duel && !shots.includes(tag)) shots.push(tag);
              if (s.duel && s.hold !== undefined && !held.includes(s.kind)) held.push(s.kind);
            }
            for (const b of pet.booms) if (b.kind && !booms.includes(b.kind)) booms.push(b.kind);
          }
          return JSON.stringify({shots, booms, held, state: pet.state, fight: !!pet.fight});
        })()
        """) as? String
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
    }

    func testABattleThrowsEachDigimonsOwnMove() async throws {
        let result = try await battle(me: "algomonadult", foe: "greymon")
        XCTAssertEqual(Set(result["shots"] as? [String] ?? []), ["me:bind", "foe:fire"])
        XCTAssertTrue((result["booms"] as? [String] ?? []).contains("bind"), "a binding hit coils around the foe")
        XCTAssertEqual(result["fight"] as? Bool, false, "the battle ends")
        XCTAssertNotEqual(result["state"] as? String, "duel", "back to its usual life (idle, a walk, ...)")
    }

    /// The three shapes added for punches, beams and lightning fly and land in a battle.
    func testMeleeBeamAndElectricMovesFlyAndLand() async throws {
        let punchVsBolt = try await battle(me: "vmon", foe: "kabuterimon")
        XCTAssertEqual(Set(punchVsBolt["shots"] as? [String] ?? []), ["me:melee", "foe:electric"])
        XCTAssertTrue((punchVsBolt["booms"] as? [String] ?? []).contains("melee"), "a punch lands as an impact star")
        XCTAssertEqual(punchVsBolt["held"] as? [String], ["electric"], "a bolt stays a moment where it struck")
        let beam = try await battle(me: "hiandromon", foe: "vmon")
        XCTAssertEqual(Set(beam["shots"] as? [String] ?? []), ["me:beam", "foe:melee"])
        XCTAssertEqual(beam["held"] as? [String], ["beam"], "a beam stays a moment where it struck")
        XCTAssertEqual(beam["fight"] as? Bool, false)
    }

    /// The shapes for gas, waves, wind, water, light, flocks, hearts and quakes fly and land.
    func testTheOtherShapesFlyAndLand() async throws {
        for (me, foe, mine, theirs) in [("hydramon", "etemon", "gas", "wave"), ("kyukimon", "shellmon", "wind", "water"),
                                         ("hououmon", "vamdemon", "light", "swarm"), ("monzaemon", "breakdramon", "heart", "quake")] {
            let result = try await battle(me: me, foe: foe)
            XCTAssertEqual(Set(result["shots"] as? [String] ?? []), ["me:\(mine)", "foe:\(theirs)"], "\(me) vs \(foe)")
            let booms = Set(result["booms"] as? [String] ?? [])
            XCTAssertTrue(booms.isSuperset(of: [mine, theirs]), "\(me) vs \(foe): each lands with its own effect, got \(booms)")
            XCTAssertEqual(result["fight"] as? Bool, false, "\(me) vs \(foe) ends")
        }
    }
}
