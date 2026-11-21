import AppKit
import WebKit
import XCTest
@testable import PokeTokenBar

/// The desktop pet could not be dragged to the edge of the screen (user report, 2026-11-21): the
/// window is 440 points wide and the Digimon walks inside it, and a drop pulled the whole window back
/// inside the screen, so the Digimon stopped up to ~200 points short. Now the window comes back and
/// the Digimon moves the same distance inside it, keeping the spot where it was dropped.
@MainActor
final class DigimonDeskPetDropTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)

    func testTheWindowStaysOnScreenAndReportsHowFarItCameBack() {
        let w = DigimonDeskPet.size
        let pastRight = DigimonDeskPet.dropPlacement(window: NSRect(x: 1440 - w.width + 150, y: 300, width: w.width, height: w.height),
                                                     visible: screen)
        XCTAssertEqual(pastRight.origin.x, 1440 - w.width)
        XCTAssertEqual(pastRight.shift, 150, "the Digimon moves 150 points right inside the window")
        let pastLeft = DigimonDeskPet.dropPlacement(window: NSRect(x: -90, y: -40, width: w.width, height: w.height), visible: screen)
        XCTAssertEqual(pastLeft.origin, NSPoint(x: 0, y: 0))
        XCTAssertEqual(pastLeft.shift, -90)
        let inside = DigimonDeskPet.dropPlacement(window: NSRect(x: 500, y: 300, width: w.width, height: w.height), visible: screen)
        XCTAssertEqual(inside.origin, NSPoint(x: 500, y: 300))
        XCTAssertEqual(inside.shift, 0)
    }

    private func js(_ scene: DigimonScene, _ code: String) async throws -> Any? {
        try await scene.webView.evaluateJavaScript(code)
    }

    private func deskScene(still: Bool) async throws -> (DigimonScene, NSWindow) {
        let scene = DigimonScene(mode: .desk)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: DigimonDeskPet.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scene.webView.frame = NSRect(origin: .zero, size: DigimonDeskPet.size)
        window.contentView = scene.webView
        window.orderFront(nil)
        let png = try XCTUnwrap(DigimonEggArt.png(size: 64, hex: "F28C3E"))
        scene.sprite(key: "agumon", dataURI: "data:image/png;base64," + png.base64EncodedString())
        scene.apply(["key": "agumon", "line": "agumon", "stage": 3, "sleeping": false, "lang": "ko", "still": still])
        var ready = false
        for _ in 0..<100 where !ready {
            try await Task.sleep(for: .milliseconds(100))
            ready = (try? await js(scene, "typeof pet !== 'undefined' && !!pet && !!assets['agumon']")) as? Bool ?? false
        }
        XCTAssertTrue(ready, "the scene did not start")
        return (scene, window)
    }

    func testTheDigimonKeepsItsSpotWhenTheWindowComesBack() async throws {
        let (scene, window) = try await deskScene(still: true)
        defer { window.close() }
        var homes: [Double] = []
        scene.onPetHome = { homes.append($0) }
        let r = try await js(scene, """
        (() => {
          pet.bug = null; pet.bugIn = 1e9; pet.x = pet.center(); pet.enter('idle', {dur: 99999});
          const b = pet.bb(), right = pet.worldW - b.r - 2, mid = pet.x;
          pet.grab(); pet.drop(60);   // the window came back 120 points = 60 scene units
          const moved = pet.x - mid;
          pet.grab(); pet.drop(500);  // far past the edge: it stops at the window's edge, the screen's edge
          const edge = pet.x;
          for (let i = 0; i < 600; i++) pet.update(16);   // ~10 s staying in place
          return JSON.stringify({moved, edge, right, after: pet.x});
        })()
        """) as? String
        let v = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(r).utf8)) as? [String: Double])
        XCTAssertEqual(v["moved"] ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(v["edge"] ?? 0, v["right"] ?? -1, accuracy: 0.01, "dropped past the edge, it stands at the edge")
        XCTAssertEqual(v["after"] ?? 0, v["edge"] ?? -1, accuracy: 3, "staying in place, it stays where it was dropped")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(homes.count, 2, "each drop tells the app where the Digimon is")
    }

    func testTheNextLaunchPutsItBackWhereItWasDropped() async throws {
        let (scene, window) = try await deskScene(still: true)
        defer { window.close() }
        scene.command(["type": "place", "offset": -70.0])
        try await Task.sleep(for: .milliseconds(200))
        let off = try await js(scene, "pet.x - pet.center()") as? Double
        XCTAssertEqual(off ?? 0, -70, accuracy: 0.01)
    }
}
