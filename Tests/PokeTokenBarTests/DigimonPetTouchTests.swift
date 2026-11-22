import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// Hands-on reactions of the desktop pet (step 15): stroking, size, double-click, boredom.
final class DigimonStrokeDetectorTests: XCTestCase {
    /// Pointer samples 10 times a second, like the pet's poll.
    private func run(_ detector: inout StrokeDetector, seconds: Double, over: Bool = true,
                     start: Double = 0, point: (Double) -> CGPoint) -> [Double] {
        var hits: [Double] = []
        var t = start
        while t < start + seconds - 1e-9 {
            if detector.feed(point(t), over: over, at: t) { hits.append(t) }
            t += 0.1
        }
        return hits
    }

    /// Back and forth about 2.5 times a second, 15 points each way.
    private func rub(_ t: Double) -> CGPoint { CGPoint(x: 100 + 15 * sin(t * 2 * .pi * 2.5), y: 50) }

    func testRubbingBackAndForthIsAStrokeWithinAboutASecond() throws {
        var d = StrokeDetector()
        let first = try XCTUnwrap(run(&d, seconds: 3, point: rub).first)
        XCTAssertLessThanOrEqual(first, 1.2, "about a second of rubbing")
        var v = StrokeDetector()
        XCTAssertFalse(run(&v, seconds: 3) { t in CGPoint(x: 60, y: 100 + 15 * sin(t * 2 * .pi * 2.5)) }.isEmpty,
                       "up and down counts too")
    }

    func testMovingOnceRestingOrJitterIsNoStroke() {
        var a = StrokeDetector(), b = StrokeDetector(), c = StrokeDetector()
        XCTAssertEqual(run(&a, seconds: 3) { t in CGPoint(x: 40 + 30 * t, y: 50) }, [], "passing across once")
        XCTAssertEqual(run(&b, seconds: 3) { _ in CGPoint(x: 80, y: 50) }, [], "resting on the pet")
        XCTAssertEqual(run(&c, seconds: 3) { t in CGPoint(x: 80 + (Int(t * 10) % 2 == 0 ? 1 : -1), y: 50) }, [],
                       "hand tremor under 3 points")
    }

    func testOnlyOverTheDigimonAndLeavingStartsOver() {
        var off = StrokeDetector()
        XCTAssertEqual(run(&off, seconds: 3, over: false, point: rub), [], "rubbing next to the pet")
        var d = StrokeDetector()
        XCTAssertEqual(run(&d, seconds: 0.5, point: rub), [])
        XCTAssertEqual(run(&d, seconds: 0.1, over: false, start: 0.5, point: rub), [])
        // The first half second was forgotten when the pointer left: a fresh second is needed again.
        let again = run(&d, seconds: 3, start: 0.6, point: rub)
        XCTAssertGreaterThanOrEqual(again.first ?? 0, 1.0)
    }

    func testAPauseBetweenStrokes() {
        var d = StrokeDetector()
        let hits = run(&d, seconds: 12, point: rub)
        XCTAssertGreaterThanOrEqual(hits.count, 2)
        for (a, b) in zip(hits, hits.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 4 - 1e-9, "4 s between strokes") }
    }

    func testDoubleClickJumpsAndASingleClickAttacks() {
        XCTAssertEqual(DigimonDeskPet.clickAction(clickCount: 1), .attack)
        XCTAssertEqual(DigimonDeskPet.clickAction(clickCount: 2), .jump)
        XCTAssertEqual(DigimonDeskPet.clickAction(clickCount: 3), .jump)
    }
}

@MainActor
final class DigimonDeskPetSizeTests: XCTestCase {
    func testThreeSizesAroundTheOldOne() {
        XCTAssertEqual(DeskPetSize.small.panelSize, NSSize(width: 330, height: 135))
        XCTAssertEqual(DeskPetSize.medium.panelSize, DigimonDeskPet.size, "medium is the size it always had")
        XCTAssertEqual(DeskPetSize.medium.panelSize, NSSize(width: 440, height: 180))
        XCTAssertEqual(DeskPetSize.large.panelSize, NSSize(width: 550, height: 225))
    }

    func testTheSizeIsSavedPerMac() throws {
        let suite = "desk-size-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DeskPetSize.saved(in: defaults), .medium)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let hub = DigimonSceneHub(digimon: DigimonStore(fileURL: dir.appendingPathComponent("s.json")))
        hub.setDeskSize(.large, defaults: defaults)
        XCTAssertEqual(hub.deskSize, .large)
        XCTAssertEqual(DeskPetSize.saved(in: defaults), .large)
        defaults.set("huge", forKey: DeskPetSize.defaultsKey)
        XCTAssertEqual(DeskPetSize.saved(in: defaults), .medium, "an unknown value falls back")
    }

    /// Bigger or smaller, the Digimon's feet stay on the same screen spot.
    func testChangingTheSizeKeepsTheFeetInPlace() {
        let window = NSRect(x: 500, y: 300, width: 440, height: 180)
        let pet = CGRect(x: 200, y: 50, width: 80, height: 122)   // top-left based, inside the window
        let feet = NSPoint(x: window.minX + pet.midX, y: window.maxY - pet.maxY)
        for size in [DeskPetSize.small, .large] {
            let f = DigimonDeskPet.resizedFrame(window: window, petRect: pet, to: size, from: .medium)
            XCTAssertEqual(f.size, size.panelSize)
            let k = size.scale / 2
            XCTAssertEqual(f.minX + pet.midX * k, feet.x, accuracy: 0.001, "\(size)")
            XCTAssertEqual(f.maxY - pet.maxY * k, feet.y, accuracy: 0.001, "\(size)")
        }
        let none = DigimonDeskPet.resizedFrame(window: window, petRect: .zero, to: .large, from: .medium)
        XCTAssertEqual(none.midX, window.midX, accuracy: 0.001)
        XCTAssertEqual(none.minY, window.minY, accuracy: 0.001, "no pet yet: the bottom middle stays")
    }

    /// Dragged past the edge at any size, the window comes back by the same amount it went over.
    func testTheDropPlacementAtEverySize() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        for size in DeskPetSize.allCases {
            let s = size.panelSize
            let placed = DigimonDeskPet.dropPlacement(window: NSRect(x: 1440 - s.width + 100, y: 200, width: s.width, height: s.height),
                                                      visible: screen)
            XCTAssertEqual(placed.origin.x, 1440 - s.width, "\(size)")
            XCTAssertEqual(placed.shift, 100, "\(size)")
        }
    }
}

/// The scene side: the scale, the shift on a drop, hearts and boredom (real scene script).
@MainActor
final class DigimonPetTouchSceneTests: XCTestCase {
    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    private func deskScene(size: DeskPetSize = .medium, egg: Bool = false) async throws -> (DigimonScene, NSWindow) {
        let scene = DigimonScene(mode: .desk)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size.panelSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(origin: .zero, size: size.panelSize)
        window.contentView = scene.webView
        window.orderFront(nil)
        scene.command(["type": "scale", "value": Double(size.scale)])
        let key = egg ? "egg_agumon" : "agumon"
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        scene.sprite(key: key, dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": key, "line": "agumon", "stage": egg ? 0 : 3, "sleeping": false, "lang": "ko", "still": true])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['\(key)']")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        _ = try await js(scene, "pet.bug = null; pet.bugIn = 1e9; pet.enter('idle', {dur: 99999}); true")
        return (scene, window)
    }

    private func json(_ scene: DigimonScene, _ code: String) async throws -> [String: Any] {
        let r = try await js(scene, "JSON.stringify((() => { \(code) })())") as? String
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(r).utf8)) as? [String: Any])
    }

    /// The scene keeps 220 x 90 units: a size is only a scale, and a drop's shift (points) is turned into
    /// units with it, so the Digimon keeps its screen spot at every size. The pet rect the app tests the
    /// pointer against scales the same way.
    func testScaleShiftAndPetRectFollowTheSize() async throws {
        for size in DeskPetSize.allCases {
            let (scene, window) = try await deskScene(size: size)
            let r = try await json(scene, """
            pet.x = pet.center(); const x0 = pet.x;
            app.cmd({type: 'drop', shift: 30});
            const b = assets[pet.key].bb;
            return {scale: pet.scale, worldW: pet.worldW, moved: pet.x - x0, rectW: (b.r - b.l) * pet.scale};
            """)
            window.close()
            XCTAssertEqual(r["scale"] as? Double ?? 0, Double(size.scale), accuracy: 0.001, "\(size)")
            XCTAssertEqual(r["worldW"] as? Double ?? 0, 220, accuracy: 0.5, "\(size)")
            XCTAssertEqual(r["moved"] as? Double ?? 0, 30 / Double(size.scale), accuracy: 0.001, "\(size)")
            XCTAssertGreaterThan(r["rectW"] as? Double ?? 0, 0)
        }
    }

    func testAStrokeSendsHeartsAHopAndTheBubble() async throws {
        let (scene, window) = try await deskScene()
        defer { window.close() }
        let r = try await json(scene, """
        app.cmd({type: 'pat', text: '좋아!'});
        const hearts = pet.loves.length, state = pet.state, text = pet.callout && pet.callout.text;
        const y0 = pet.loves.map(h => h.y);
        for (let i = 0; i < 20; i++) pet.update(30);
        const risen = pet.loves.length > 0 && pet.loves.every((h, i) => h.y < y0[i] - 5);
        return {hearts, state, text, risen};
        """)
        XCTAssertEqual(r["hearts"] as? Int, 3)
        XCTAssertEqual(r["state"] as? String, "hop")
        XCTAssertEqual(r["text"] as? String, "좋아!")
        XCTAssertEqual(r["risen"] as? Bool, true)
        let asleep = try await json(scene, """
        pet.sleep(); pet.callout = null; pet.loves = [];
        app.cmd({type: 'pat', text: '좋아!'});
        return {hearts: pet.loves.length, state: pet.state, bubble: !!pet.callout};
        """)
        XCTAssertEqual(asleep["hearts"] as? Int, 3, "a sleeping Digimon gets the hearts")
        XCTAssertEqual(asleep["state"] as? String, "sleep", "and sleeps on")
        XCTAssertEqual(asleep["bubble"] as? Bool, false)
    }

    /// Boredom only after 20 minutes without a touch, never on the popover, and a touch resets it.
    func testBoredomComesOnlyAfterTwentyMinutesAlone() async throws {
        let (scene, window) = try await deskScene()
        defer { window.close() }
        let r = try await json(scene, """
        const rnd = Math.random; Math.random = () => .05;   // every roll picks the first, rarest branch
        const pick = () => { pet.callout = null; pet.enter('idle', {dur: 99999}); pet.next(); return [pet.state, pet.callout && pet.callout.text]; };
        pet.touched = pet.clock - 19 * 60 * 1000; const before = pick();
        pet.touched = pet.clock - 21 * 60 * 1000; const after = pick();
        app.cmd({type: 'attack'}); const touched = pet.bored();
        pet.touched = pet.clock - 21 * 60 * 1000; S.mood = 'sleepy'; const moody = pet.bored(); S.mood = null;
        Math.random = rnd;
        return {before, after, touched, moody};
        """)
        XCTAssertNotEqual((r["before"] as? [Any])?.first as? String, "stretch", "19 minutes: not yet")
        XCTAssertEqual((r["after"] as? [Any])?.first as? String, "stretch", "21 minutes: a yawn")
        XCTAssertEqual((r["after"] as? [Any])?.last as? String, "심심해…")
        XCTAssertEqual(r["touched"] as? Bool, false, "a click is a touch")
        XCTAssertEqual(r["moody"] as? Bool, false, "a sleepy or sick mood has its own behavior")
    }
}
