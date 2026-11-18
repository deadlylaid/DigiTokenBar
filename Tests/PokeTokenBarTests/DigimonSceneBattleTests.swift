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

    /// A line without its own fire colors fires in its egg color; a very dark egg is lightened.
    func testANewLinesFireTakesItsEggColor() async throws {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "3D6FC9"))
        scene.sprite(key: "gaomon", dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": "gaomon", "line": "gaomon", "lineColor": "3D6FC9", "stage": 3, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let fire = try await js(scene, "pet.shotFrom('fire', pet.x, pet.bb(), 1, S.line).pal[1]") as? String
        XCTAssertEqual(fire, "#3d6fc9", "Gaomon's line fires in its blue egg color")
        let beam = try await js(scene, "pet.shotFrom('beam', pet.x, pet.bb(), 1, S.line).pal[1]") as? String
        XCTAssertEqual(beam, "#3d6fc9")
        let foe = try await js(scene, "pet.shotFrom('fire', pet.x, pet.bb(), 1, '').pal[1]") as? String
        XCTAssertEqual(foe, "#ffb53b", "a foe keeps the default fire")
        let agumon = try await js(scene, "linePal('agumon')[1]") as? String
        XCTAssertEqual(agumon, "#ffb53b", "a line with its own colors keeps them")
        _ = try await js(scene, "app.apply({line: 'gabumonblack', lineColor: '2F4A6B'}); 1")
        let dark = try await js(scene, "linePal('gabumonblack')[1]") as? String
        XCTAssertNotNil(dark)
        XCTAssertNotEqual(dark, "#2f4a6b", "a dark egg is lightened so the fire glows")
        _ = try await js(scene, "app.apply({line: 'agumonblack', lineColor: '4A4038'}); 1")
        let gray = try await js(scene, "pet.shotFrom('fire', pet.x, pet.bb(), 1, S.line).pal[1]") as? String
        XCTAssertEqual(gray, "#ffb53b", "a dull dark egg keeps the usual fire")
        _ = try await js(scene, "app.apply({line: 'angoramon', lineColor: 'E9A9C8'}); 1")
        let pastel = try await js(scene, "linePal('angoramon')[1]") as? String
        XCTAssertEqual(pastel, "#e9a9c8", "a bright pastel keeps its color")
    }

    /// A missile grows with the stage of whoever fires it, and lands as an explosion.
    func testAMissileGrowsWithTheStageAndExplodes() async throws {
        let result = try await battle(me: "metalgreymon", foe: "greymon")
        XCTAssertTrue((result["shots"] as? [String] ?? []).contains("me:missile"))
        XCTAssertTrue((result["booms"] as? [String] ?? []).contains("missile"), "a missile hit explodes")

        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        scene.sprite(key: "metalgreymon", dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": "metalgreymon", "line": "agumon", "stage": 5, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let sizes = try await js(scene, "[3, 4, 5, 6].map(st => pet.shotFrom('missile', pet.x, pet.bb(), 1, S.line, 0, 0, 0, null, st).size)") as? [Double]
        XCTAssertEqual(sizes, [1, 1.3, 1.7, 2.1], "Child, Adult, Perfect, Ultimate")
    }

    /// A Jogress plays in the scene: the friend's Digimon fades in, both meet in the middle and glow,
    /// one flash, and the scene is free for the evolution the app sends next.
    func testAJogressBringsInTheFriendsDigimonAndMerges() async throws {
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
        for key in ["wargreymon", "metalgarurumon", "omegamon"] { scene.sprite(key: key, dataURI: uri) }
        scene.apply(["key": "wargreymon", "line": "agumon", "stage": 6, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        scene.command(["type": "jogress", "partner": "metalgarurumon"])
        try await Task.sleep(for: .milliseconds(300))
        let seen = try await js(scene, """
        (() => {
          const out = {start: pet.state, partner: pet.fight && pet.fight.foe, gap: 999, white: false, flash: 0};
          for (let i = 0; i < 90; i++) {
            pet.update(33);
            if (pet.fight) { out.gap = Math.min(out.gap, Math.abs(pet.fight.fx - pet.x)); out.white = out.white || pet.fight.white; }
            out.flash = Math.max(out.flash, pet.flash);
          }
          out.end = pet.state; out.fight = !!pet.fight;
          return JSON.stringify(out);
        })()
        """) as? String
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
        XCTAssertEqual(result["start"] as? String, "merge")
        XCTAssertEqual(result["partner"] as? String, "metalgarurumon")
        XCTAssertLessThan(result["gap"] as? Double ?? 999, 30, "they meet in the middle")
        XCTAssertEqual(result["white"] as? Bool, true, "both glow before merging")
        XCTAssertGreaterThan(result["flash"] as? Double ?? 0, 0.5)
        XCTAssertNotEqual(result["end"] as? String, "merge", "over: the scene is free (idle, or already walking)")
        XCTAssertEqual(result["fight"] as? Bool, false, "the friend's Digimon is gone")
        scene.command(["type": "evolve", "key": "omegamon"])
        try await Task.sleep(for: .milliseconds(200))
        let state = try await js(scene, "pet.state") as? String
        XCTAssertEqual(state, "evolve", "the evolution plays after it")
    }

    /// Every shape grows with the stage of whoever fires it, like the missile: drawn for real, an
    /// Ultimate's shot and impact cover clearly more of the scene than a Child's and reach further
    /// (wider or taller; area alone grows with thicker dots even at the same size). A foe's shot
    /// follows the foe's stage, not the user's Digimon's.
    func testEveryShapeGrowsWithTheStage() async throws {
        let scene = DigimonScene(mode: .popover)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        scene.sprite(key: "agumon", dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko"])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let seen = try await js(scene, """
        (() => {
          const kinds = ['fire', 'missile', 'gaia', 'claw', 'ice', 'bind', 'melee', 'beam', 'electric', 'gas', 'wave', 'wind',
                         'water', 'light', 'swarm', 'heart', 'quake'];
          const W = pet.worldW, rnd = Math.random;
          const cw = pet.cv.width;
          let base = null;
          // What the shot or impact painted over the empty scene: pixels, width and height.
          const paint = () => {
            pet.bug = null; pet.callout = null; pet.parts = []; pet.shake = 0; pet.flash = 0;
            Math.random = () => .5; pet.draw(); Math.random = rnd;
            const d = pet.ctx.getImageData(0, 0, cw, pet.cv.height).data;
            if (!base) { base = d; return [0, 0, 0]; }
            let n = 0, x0 = 1e9, x1 = -1, y0 = 1e9, y1 = -1;
            for (let i = 0; i < d.length; i += 4) {
              if (d[i] === base[i] && d[i + 1] === base[i + 1] && d[i + 2] === base[i + 2] && d[i + 3] === base[i + 3]) continue;
              const x = (i / 4) % cw, y = Math.floor(i / 4 / cw);
              n++; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
            }
            return n ? [n, x1 - x0 + 1, y1 - y0 + 1] : [0, 0, 0];
          };
          pet.enter('idle', {dur: 99999}); pet.shots = []; pet.booms = [];
          paint();
          const out = {sizes: {}, shot: {}, boom: {}};
          for (const kind of kinds) {
            out.sizes[kind] = [3, 4, 5, 6].map(st => pet.shotFrom(kind, pet.x, pet.bb(), 1, S.line, 0, 0, 0, null, st).size);
            for (const st of [3, 6]) {
              const s = pet.shotFrom(kind, pet.x, pet.bb(), 1, S.line, 0, 0, 0, null, st);
              s.ox = W * .45; s.x = W * .72; s.t = 120;
              pet.shots = [s]; pet.booms = [];
              (out.shot[kind] = out.shot[kind] || []).push(paint());
              pet.shots = []; pet.boom(s.x, s.y, s); pet.booms.forEach(b => b.t = (b.life || 320) * .3);
              (out.boom[kind] = out.boom[kind] || []).push(paint());
              pet.booms = [];
            }
          }
          out.foeFire = pet.shotFrom('fire', pet.x, pet.bb(), 1, '', 0, 0, 0, null, 6).r;
          return JSON.stringify(out);
        })()
        """) as? String
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
        let sizes = try XCTUnwrap(result["sizes"] as? [String: [Double]])
        let shot = try XCTUnwrap(result["shot"] as? [String: [[Double]]])
        let boom = try XCTUnwrap(result["boom"] as? [String: [[Double]]])
        /// Ultimate against Child: more pixels, and wider or taller.
        func bigger(_ m: [[Double]]) -> Bool {
            let child = m[0], ultimate = m[1]
            return ultimate[0] > child[0] * 1.5 && max(ultimate[1] / child[1], ultimate[2] / child[2]) > 1.3
        }
        XCTAssertEqual(sizes.count, 17)
        for (kind, size) in sizes {
            XCTAssertEqual(size, [1, 1.3, 1.7, 2.1], kind)
            let s = try XCTUnwrap(shot[kind]), b = try XCTUnwrap(boom[kind])
            XCTAssertGreaterThan(s[0][0], 0, "\(kind) is drawn")
            XCTAssertTrue(bigger(s), "an Ultimate's \(kind) is bigger: \(s)")
            // A tendril wraps the target's body: its coil follows the target, not the attacker.
            if kind != "bind" { XCTAssertTrue(bigger(b), "an Ultimate's \(kind) impact is bigger: \(b)") }
        }
        XCTAssertEqual(result["foeFire"] as? Double ?? 0, 3.6 * 2.1, accuracy: 0.001,
                       "an Ultimate foe's fire, while the user's Digimon is a Child")
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
        NSRect(x: 20, y: 0, width: 24, height: height).fill()   // drawn from the bottom
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// A battle shot lands on the other Digimon's body whatever their sizes. Shots used to fly level
    /// from where they started: a tall Digimon's passed over a short foe's head, and Gaia Force, made
    /// over the head, always burst in the air (the egg-art sprites in the other tests are all one size).
    func testBattleShotsLandOnTheBodyOfATallerOrShorterFoe() async throws {
        // (me, my move's shape, my height, foe, the foe's height): tall against short, and short against a
        // tall foe that fires a pair of missiles.
        for (me, myKind, myHeight, foe, foeHeight) in [("wargreymon", "gaia", 60, "blastmon", 14), ("ancientsphinxmon", "beam", 60, "keemon", 14),
                                                      ("archnemon", "bind", 60, "atlurballistamon", 14), ("keemon", "water", 14, "metalgreymon", 60)] {
            let scene = DigimonScene(mode: .popover)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 168), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            scene.webView.frame = NSRect(x: 0, y: 0, width: 360, height: 168)
            window.contentView = scene.webView
            window.orderFront(nil)
            defer { window.close() }
            scene.sprite(key: me, dataURI: try blockSprite(height: myHeight))
            scene.sprite(key: foe, dataURI: try blockSprite(height: foeHeight))
            scene.apply(["key": me, "line": "agumon", "stage": 6, "sleeping": false, "lang": "ko"])
            var ready = false
            for _ in 0..<100 where !ready {
                try await Task.sleep(for: .milliseconds(100))
                ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
            }
            XCTAssertTrue(ready, "the scene did not start")
            scene.command(["type": "battle", "foe": foe, "foeStage": 6, "won": true,
                           "rounds": [["a": "me", "hit": true], ["a": "foe", "hit": true]]])
            try await Task.sleep(for: .milliseconds(300))
            let seen = try await js(scene, """
            (() => {
              const out = [];
              const tops = () => ({me: pet.ground() - (pet.bb().b - pet.bb().t), foe: pet.ground() - (assets['\(foe)'].bb.b - assets['\(foe)'].bb.t)});
              const t = tops(), seen = new Set();
              for (let i = 0; i < 220; i++) {
                pet.update(33);
                for (const b of pet.booms) if (b.kind && !seen.has(b)) { seen.add(b); out.push({kind: b.kind, y: b.y, x: b.x}); }
              }
              return JSON.stringify({booms: out, myTop: t.me, foeTop: t.foe, ground: pet.ground(), fx: pet.fight ? pet.fight.fx : null});
            })()
            """) as? String
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
            let booms = try XCTUnwrap(result["booms"] as? [[String: Any]])
            let ground = try XCTUnwrap(result["ground"] as? Double)
            let myTop = try XCTUnwrap(result["myTop"] as? Double), foeTop = try XCTUnwrap(result["foeTop"] as? Double)
            XCTAssertEqual(booms.count, foe == "metalgreymon" ? 3 : 2, "\(me) vs \(foe): every hit lands: \(booms)")
            for boom in booms {
                let y = try XCTUnwrap(boom["y"] as? Double), kind = boom["kind"] as? String ?? ""
                let top = kind == myKind ? foeTop : myTop   // my shot hits the foe, its shot hits me
                XCTAssertTrue(y >= top - 1 && y <= ground + 1, "\(me) vs \(foe): \(kind) lands at \(y), body \(top)...\(ground)")
            }
        }
    }

    /// Settings "Stay in place": the pet never sets off on a walk, and after a battle moved it, it walks
    /// back to the middle once. Off again, it walks as before.
    func testStayingInPlaceStopsWalksAndReturnsToTheMiddle() async throws {
        let scene = DigimonScene(mode: .desk)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 440, height: 180), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(x: 0, y: 0, width: 440, height: 180)
        window.contentView = scene.webView
        window.orderFront(nil)
        defer { window.close() }
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        scene.sprite(key: "agumon", dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko", "still": true])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        let seen = try await js(scene, """
        (() => {
          const rnd = Math.random, out = {};
          Math.random = () => 0;   // the roll that always sets off on a walk
          const settle = () => { for (let i = 0; i < 200 && (pet.state === 'walk' || pet.state === 'turn'); i++) pet.update(33); };
          // A battle left it at the side: it goes back to the middle once.
          pet.x = 4; pet.next(); out.back = pet.state; settle();
          out.offCenter = Math.abs(pet.x - pet.center());
          let walks = 0;
          for (let i = 0; i < 50; i++) { pet.enter('idle', {dur: 1}); pet.next(); if (pet.state === 'walk' || pet.state === 'turn') walks++; settle(); }
          out.walks = walks; out.drift = Math.abs(pet.x - pet.center());
          app.apply({still: false}); pet.enter('idle', {dur: 1}); pet.next(); out.free = pet.state;
          Math.random = rnd;
          return JSON.stringify(out);
        })()
        """) as? String
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(seen).utf8)) as? [String: Any])
        XCTAssertTrue(["walk", "turn"].contains(result["back"] as? String ?? ""), "it walks back to the middle")
        XCTAssertLessThan(result["offCenter"] as? Double ?? 99, 1)
        XCTAssertEqual(result["walks"] as? Int, 0, "no walks while staying in place")
        XCTAssertLessThan(result["drift"] as? Double ?? 99, 1)
        XCTAssertTrue(["walk", "turn"].contains(result["free"] as? String ?? ""), "off again, it walks")
    }

    func testTheStayInPlaceSwitchIsSavedAndSentToTheScenes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "digimon-still-\(UUID().uuidString)"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("digimon-still-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let hub = DigimonSceneHub(digimon: DigimonStore(fileURL: dir.appendingPathComponent("digimon-state.json")))
        XCTAssertFalse(hub.stayInPlace)
        hub.setStayInPlace(true, defaults: defaults)
        XCTAssertTrue(hub.stayInPlace)
        XCTAssertTrue(defaults.bool(forKey: DigimonSceneHub.stayInPlaceKey))
        hub.setStayInPlace(false, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: DigimonSceneHub.stayInPlaceKey))
    }
}
