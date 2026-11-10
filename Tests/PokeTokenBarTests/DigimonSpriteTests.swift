import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

final class DigimonSpriteTests: XCTestCase {
    /// A tiny sprite: `art` rows of color codes, enlarged by `scale`.
    private func sprite(_ art: [String], scale: Int) -> CGImage {
        let colors: [Character: [UInt8]] = ["R": [255, 0, 0, 255], "G": [0, 255, 0, 255], ".": [0, 0, 0, 0]]
        let h = art.count * scale, w = art[0].count * scale
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in art.enumerated() {
            for (x, ch) in row.enumerated() {
                for dy in 0..<scale { for dx in 0..<scale {
                    let i = ((y * scale + dy) * w + x * scale + dx) * 4
                    rgba[i..<i + 4] = colors[ch]![0..<4]
                }}
            }
        }
        return PixelArt.image(PixelArt.Bitmap(width: w, height: h, rgba: rgba))!
    }

    private func gif(_ frames: [CGImage]) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.gif.identifier as CFString, frames.count, nil)!
        for f in frames { CGImageDestinationAddImage(dest, f, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func testWikimonURLUsesTheMediaWikiHashPath() {
        XCTAssertEqual(WikimonFile.url(for: "Agumon_vpet_vb.png").absoluteString,
                       "https://wikimon.net/images/b/b9/Agumon_vpet_vb.png")
        XCTAssertEqual(WikimonFile.url(for: "Agumon vpet dmc.gif").absoluteString,
                       "https://wikimon.net/images/e/ed/Agumon_vpet_dmc.gif")
    }

    func testEnlargedSpriteGoesBackToOriginalPixelsStandingOnTheBottom() {
        let big = PixelArt.bitmap(sprite(["R.G", "GGR"], scale: 3))!
        XCTAssertEqual(PixelArt.blockSize(big), 3)
        let native = PixelArt.native(big)
        XCTAssertEqual([native.width, native.height], [3, 2])
        XCTAssertEqual(native.pixel(0, 0), [255, 0, 0, 255])
        let square = PixelArt.padded(native, to: 8)
        XCTAssertEqual([square.width, square.height], [8, 8])
        XCTAssertEqual(square.pixel(2, 6), [255, 0, 0, 255], "top-left art pixel lands at x=(8-3)/2, y=8-2")
        XCTAssertEqual(square.pixel(4, 7), [255, 0, 0, 255])
        XCTAssertEqual(square.pixel(0, 0)[3], 0, "the padding is transparent")
    }

    func testMenuGifIsSplitIntoNativeFrames() async throws {
        let data = gif([sprite(["RG", "GR"], scale: 3), sprite(["GR", "RG"], scale: 3)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprites-\(UUID().uuidString)")
        let store = DigimonSpriteStore(directory: dir, fetch: { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let frames = await store.menuFrames(file: "Test_vpet_dmc.gif")
        XCTAssertEqual(frames.count, 2)
        let first = try XCTUnwrap(PixelArt.frames(frames[0]).first)
        XCTAssertEqual([first.width, first.height], [2, 2])
        try? FileManager.default.removeItem(at: dir)
    }

    func testDownloadsOnceThenAsksWikimonOnlyWhenTheCopyIsOld() async throws {
        actor Log { var requests: [URLRequest] = []; func add(_ r: URLRequest) { requests.append(r) } }
        let log = Log()
        let png = PixelArt.png(sprite(["RG"], scale: 3))!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprites-\(UUID().uuidString)")
        final class Clock: @unchecked Sendable { var now = Date() }
        let clock = Clock()
        let store = DigimonSpriteStore(directory: dir, maxAge: 100, now: { clock.now }) { request in
            await log.add(request)
            let status = request.value(forHTTPHeaderField: "If-Modified-Since") == nil ? 200 : 304
            return (status == 200 ? png : Data(),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let first = await store.original("Test_vpet_vb.png")
        let second = await store.original("Test_vpet_vb.png")
        XCTAssertEqual(first, png)
        XCTAssertEqual(second, png)
        var count = await log.requests.count
        XCTAssertEqual(count, 1, "a fresh copy is served from disk")
        clock.now = clock.now.addingTimeInterval(1_000)
        let refreshed = await store.original("Test_vpet_vb.png")
        XCTAssertEqual(refreshed, png, "304 keeps the cached copy")
        count = await log.requests.count
        XCTAssertEqual(count, 2)
        let last = await log.requests.last
        XCTAssertNotNil(last?.value(forHTTPHeaderField: "If-Modified-Since"))
        try? FileManager.default.removeItem(at: dir)
    }

    func testAFailedDownloadGivesNoSpriteInsteadOfCrashing() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprites-\(UUID().uuidString)")
        let store = DigimonSpriteStore(directory: dir, fetch: { _ in throw URLError(.notConnectedToInternet) })
        let large = await store.largeSprite(file: "Missing_vpet_vb.png")
        XCTAssertNil(large)
        let frames = await store.menuFrames(file: "Missing_vpet_dmc.gif")
        XCTAssertEqual(frames, [])
        try? FileManager.default.removeItem(at: dir)
    }
}
