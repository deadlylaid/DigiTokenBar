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
    private let kinds = ["fire", "missile", "gaia", "claw", "ice", "bind", "melee", "beam", "electric", "gas", "wave", "wind",
                         "water", "light", "swarm", "heart", "quake"]

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
            let kinds = "[" + self.kinds.map { "'\($0)'" }.joined(separator: ",") + "]"
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
              return JSON.stringify(out);
            })()
            """) as? String
            let found = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String])
            misses += found.map { "stage \(stage): \($0)" }
        }
        XCTAssertEqual(misses, [], misses.joined(separator: "\n"))
    }
}
