import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where Wikimon serves a file. MediaWiki puts uploads under /images/<md5[0]>/<md5[0..1]>/<name>,
/// so no API call is needed.
enum WikimonFile {
    static func url(for file: String) -> URL {
        let name = file.replacingOccurrences(of: " ", with: "_")
        let hash = Insecure.MD5.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://wikimon.net/images/\(hash.prefix(1))/\(hash.prefix(2))/\(encoded)")!
    }
}

/// Pixel-art helpers. Wikimon stores V-Pet sprites enlarged by an integer factor (3x); we keep the
/// original pixels and let the UI scale them up crisply.
enum PixelArt {
    struct Bitmap: Equatable {
        let width: Int
        let height: Int
        var rgba: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * width + x) * 4
            return Array(rgba[i..<i + 4])
        }
    }

    static func bitmap(_ image: CGImage) -> Bitmap? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Bitmap(width: w, height: h, rgba: data) : nil
    }

    static func image(_ bitmap: Bitmap) -> CGImage? {
        var data = bitmap.rgba
        return data.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                      bytesPerRow: bitmap.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// Size of one art pixel: the greatest common divisor of every horizontal run of equal pixels.
    static func blockSize(_ b: Bitmap) -> Int {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        var g = 0
        for y in 0..<b.height {
            var run = 1
            for x in 1..<max(b.width, 1) {
                if b.pixel(x, y) == b.pixel(x - 1, y) { run += 1 } else { g = gcd(g, run); run = 1 }
            }
            g = gcd(g, run)
            if g == 1 { break }
        }
        return max(g, 1)
    }

    /// Back to original pixels (one sample from the middle of each block).
    static func native(_ b: Bitmap) -> Bitmap {
        let k = blockSize(b)
        guard k > 1 else { return b }
        let w = b.width / k, h = b.height / k
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let src = b.pixel(x * k + k / 2, y * k + k / 2)
                let i = (y * w + x) * 4
                out[i..<i + 4] = src[0..<4]
            }
        }
        return Bitmap(width: w, height: h, rgba: out)
    }

    /// Square canvas with the sprite standing on the bottom edge, centered.
    static func padded(_ b: Bitmap, to side: Int) -> Bitmap {
        guard b.width != side || b.height != side else { return b }
        var out = [UInt8](repeating: 0, count: side * side * 4)
        let ox = (side - b.width) / 2, oy = side - b.height
        for y in 0..<b.height where y + oy >= 0 && y + oy < side {
            for x in 0..<b.width where x + ox >= 0 && x + ox < side {
                let s = (y * b.width + x) * 4, d = ((y + oy) * side + x + ox) * 4
                out[d..<d + 4] = b.rgba[s..<s + 4]
            }
        }
        return Bitmap(width: side, height: side, rgba: out)
    }

    static func frames(_ data: Data) -> [CGImage] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return (0..<CGImageSourceGetCount(src)).compactMap { CGImageSourceCreateImageAtIndex(src, $0, nil) }
    }

    static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

/// Downloads Digimon sprites from Wikimon the first time they are needed and keeps them in the
/// app's state folder. Nothing is bundled with the app (see docs/digimon criteria, principle 8).
/// Cached files older than `maxAge` are re-checked with If-Modified-Since, because Wikimon still
/// updates sprites from time to time.
actor DigimonSpriteStore {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let directory: URL
    private let fetch: Fetch
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date

    init(directory: URL = AppStatePaths.directory().appendingPathComponent("digimon-sprites"),
         maxAge: TimeInterval = 30 * 86_400,
         now: @escaping @Sendable () -> Date = Date.init,
         fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.directory = directory
        self.maxAge = maxAge
        self.now = now
        self.fetch = fetch
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 64x64 PNG (original pixels, standing on the bottom edge) for the popover and desktop pet.
    func largeSprite(file: String) async -> Data? {
        guard let data = await original(file), let first = PixelArt.frames(data).first,
              let bitmap = PixelArt.bitmap(first) else { return nil }
        let native = PixelArt.native(bitmap)
        let side = max(64, native.width, native.height)
        return PixelArt.image(PixelArt.padded(native, to: side)).flatMap(PixelArt.png)
    }

    /// Menu bar frames (16x16 color V-Pet sprite, usually 2). Empty when the file is missing.
    func menuFrames(file: String) async -> [Data] {
        guard !file.isEmpty, let data = await original(file) else { return [] }
        return PixelArt.frames(data).compactMap { frame in
            PixelArt.bitmap(frame).map(PixelArt.native).flatMap(PixelArt.image).flatMap(PixelArt.png)
        }
    }

    /// The Wikimon file, from the cache when fresh enough.
    func original(_ file: String) async -> Data? {
        let local = directory.appendingPathComponent(file)
        let cached = try? Data(contentsOf: local)
        let modified = (try? FileManager.default.attributesOfItem(atPath: local.path)[.modificationDate]) as? Date
        if let cached, let modified, now().timeIntervalSince(modified) < maxAge { return cached }

        var request = URLRequest(url: WikimonFile.url(for: file), timeoutInterval: 30)
        request.setValue("\(AppIdentity.name)/0.1 (personal, non-commercial)", forHTTPHeaderField: "User-Agent")
        if cached != nil, let modified {
            request.setValue(Self.httpDate(modified), forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await fetch(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 304, let cached {
                touch(local)
                return cached
            }
            guard status == 200, !data.isEmpty else { return cached }
            try data.write(to: local, options: .atomic)
            return data
        } catch {
            AppLog.write("digimon sprite download failed file=\(file): \(error)")
            return cached
        }
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
    }

    private static func httpDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.string(from: date)
    }
}
