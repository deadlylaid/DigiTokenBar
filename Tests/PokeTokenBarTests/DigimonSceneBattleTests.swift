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

    func testABattleThrowsEachDigimonsOwnMove() async throws {
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
        scene.sprite(key: "algomonadult", dataURI: uri)
        scene.sprite(key: "greymon", dataURI: uri)
        scene.apply(["key": "algomonadult", "line": "agumon", "stage": 4, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "!!(window.pet || (typeof pet !== 'undefined' && pet))")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let algomon = try await js(scene, "moveOf('algomonadult').kind") as? String
        let greymon = try await js(scene, "moveOf('greymon').kind") as? String
        XCTAssertEqual(algomon, "bind")
        XCTAssertEqual(greymon, "fire")

        scene.command(["type": "battle", "foe": "greymon", "won": true,
                       "rounds": [["a": "me", "hit": true], ["a": "foe", "hit": true]]])
        try await Task.sleep(for: .milliseconds(300))
        let seen = try await js(scene, """
        (() => {
          const shots = [], coils = [];
          for (let i = 0; i < 220; i++) {
            pet.update(33);
            for (const s of pet.shots) if (s.duel && !shots.includes((s.mine ? 'me:' : 'foe:') + s.kind)) shots.push((s.mine ? 'me:' : 'foe:') + s.kind);
            if (pet.booms.some(b => b.kind === 'bind') && !coils.length) coils.push('coil');
          }
          return JSON.stringify({shots, coils, state: pet.state, fight: !!pet.fight});
        })()
        """) as? String
        let result = try JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any]
        XCTAssertEqual(Set(result?["shots"] as? [String] ?? []), ["me:bind", "foe:fire"])
        XCTAssertEqual(result?["coils"] as? [String], ["coil"], "a binding hit coils around the foe")
        XCTAssertEqual(result?["fight"] as? Bool, false, "the battle ends")
        XCTAssertNotEqual(result?["state"] as? String, "duel", "back to its usual life (idle, a walk, ...)")
    }
}
