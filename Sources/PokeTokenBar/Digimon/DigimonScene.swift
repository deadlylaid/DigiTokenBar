import AppKit
import Observation
import SwiftUI
import WebKit

/// One running pet scene (a WKWebView showing `DigimonSceneHTML`). Calls made before the page is
/// ready are queued and replayed in order.
@MainActor
final class DigimonScene: NSObject {
    enum Mode: String { case popover, desk }

    let mode: Mode
    let webView: WKWebView
    var onBugDefeated: () -> Void = {}
    /// Desk only: where the pet is drawn, in the web view's top-left based points.
    var onPetRect: (CGRect) -> Void = { _ in }

    private var ready = false
    private var queued: [String] = []
    private var sentSprites: Set<String> = []

    init(mode: Mode) {
        self.mode = mode
        let config = WKWebViewConfiguration()
        let relay = ScriptRelay()
        config.userContentController.add(relay, name: "app")
        config.userContentController.addUserScript(WKUserScript(
            source: "window.SCENE_MODE = '\(mode.rawValue)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")   // transparent page over the desktop
        super.init()
        relay.scene = self
        webView.loadHTMLString(DigimonSceneHTML.page, baseURL: nil)
    }

    func sprite(key: String, dataURI: String) {
        guard sentSprites.insert(key).inserted else { return }
        call("sprite", key, dataURI)
    }

    func apply(_ state: [String: Any]) { call("apply", state) }
    func command(_ cmd: [String: Any]) { call("cmd", cmd) }

    private func call(_ function: String, _ args: Any...) {
        let encoded = args.compactMap { arg -> String? in
            if let s = arg as? String {
                return (try? JSONSerialization.data(withJSONObject: [s])).flatMap { String(data: $0, encoding: .utf8) }
                    .map { String($0.dropFirst().dropLast()) }
            }
            return (try? JSONSerialization.data(withJSONObject: arg)).flatMap { String(data: $0, encoding: .utf8) }
        }
        guard encoded.count == args.count else { return }
        let js = "window.app && app.\(function)(\(encoded.joined(separator: ",")))"
        if ready { webView.evaluateJavaScript(js, completionHandler: nil) } else { queued.append(js) }
    }

    fileprivate func receive(_ body: Any) {
        guard let body = body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "ready":
            ready = true
            let pending = queued
            queued = []
            for js in pending { webView.evaluateJavaScript(js, completionHandler: nil) }
        case "bugDefeated":
            onBugDefeated()
        case "petRect":
            let v = { (k: String) in (body[k] as? NSNumber)?.doubleValue ?? 0 }
            onPetRect(CGRect(x: v("x"), y: v("y"), width: v("w"), height: v("h")))
        default:
            break
        }
    }
}

/// Holds the scene weakly: WKUserContentController keeps its handlers alive.
@MainActor
private final class ScriptRelay: NSObject, WKScriptMessageHandler {
    weak var scene: DigimonScene?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        scene?.receive(message.body)
    }
}

/// Keeps every live scene (popover, desktop pet) in step with `DigimonStore`: it supplies sprites,
/// plays hatch/evolution/feeding events, and pushes the current look. Sprites are fetched once and
/// kept as PNG data so SwiftUI (evolution choices) can show them too.
@MainActor
@Observable
final class DigimonSceneHub {
    /// PNG data per scene key (species key, or "egg_<line>"): 64x64, standing on the bottom edge.
    private(set) var images: [String: Data] = [:]
    /// The same sprites cropped to their pixels, for SwiftUI (dex, choices). Observable so views
    /// update when a download finishes.
    private(set) var icons: [String: Data] = [:]

    @ObservationIgnored let digimon: DigimonStore
    @ObservationIgnored let sprites: DigimonSpriteStore
    @ObservationIgnored var language: AppLanguage = .ko
    @ObservationIgnored var sleeping = false
    @ObservationIgnored private var scenes: [WeakScene] = []
    @ObservationIgnored private var loading: [String: Task<Data?, Never>] = [:]
    /// Event playback runs one step at a time so an evolution never arrives before its sprite.
    @ObservationIgnored private var chain: Task<Void, Never>?

    private struct WeakScene { weak var scene: DigimonScene? }

    init(digimon: DigimonStore, sprites: DigimonSpriteStore = DigimonSpriteStore()) {
        self.digimon = digimon
        self.sprites = sprites
    }

    static func sceneKey(_ partner: DigimonPartner) -> String {
        partner.speciesKey ?? "egg_\(partner.lineID)"
    }

    var currentKey: String { Self.sceneKey(digimon.state.partner) }

    func register(_ scene: DigimonScene) {
        scenes.removeAll { $0.scene == nil }
        scenes.append(WeakScene(scene: scene))
        scene.onBugDefeated = { [weak self] in self?.digimon.recordBugDefeated() }
        enqueue { hub in
            let key = hub.currentKey
            if let data = await hub.image(for: key) { scene.sprite(key: key, dataURI: Self.dataURI(data)) }
            scene.apply(hub.sceneState())
        }
    }

    /// Play what just happened in every scene, then show the current look.
    func play(_ events: [DigimonEvent], fed: Bool) {
        guard !events.isEmpty || fed else { return }
        enqueue { hub in
            if fed { hub.broadcast(["type": "feed"]) }
            for event in events {
                let target: String?
                switch event {
                case .hatched(let species): target = species
                case .evolved(_, let to): target = to
                case .newEgg(let line): target = "egg_\(line)"
                case .graduated:
                    // A send-off before it turns back into an egg.
                    hub.broadcast(["type": "graduate"])
                    try? await Task.sleep(for: .seconds(1.8))
                    target = nil
                case .choiceOffered: target = nil
                }
                guard let target, let data = await hub.image(for: target) else { continue }
                hub.liveScenes.forEach { $0.sprite(key: target, dataURI: Self.dataURI(data)) }
                hub.broadcast(["type": "evolve", "key": target])
            }
            hub.pushState()
        }
    }

    /// Re-send the current look (sleep, language, or a change with no event).
    func refresh() {
        enqueue { hub in
            let key = hub.currentKey
            if let data = await hub.image(for: key) {
                hub.liveScenes.forEach { $0.sprite(key: key, dataURI: Self.dataURI(data)) }
            }
            hub.pushState()
        }
    }

    func broadcast(_ cmd: [String: Any]) { liveScenes.forEach { $0.command(cmd) } }

    /// The sprite for a scene key, downloaded on first use. nil while offline and not cached.
    func image(for key: String) async -> Data? {
        if let data = images[key] { return data }
        if let running = loading[key] { return await running.value }
        let task = Task { [sprites, digimon] () -> Data? in
            if key.hasPrefix("egg_") {
                let line = String(key.dropFirst(4))
                return DigimonEggArt.png(size: 64, hex: digimon.engine.catalog.lines[line]?.eggColorHex ?? "999999")
            }
            guard let species = digimon.engine.catalog.species(key) else { return nil }
            return await sprites.largeSprite(file: species.vbSprite)
        }
        loading[key] = task
        let data = await task.value
        loading[key] = nil
        if let data {
            images[key] = data
            icons[key] = PixelArt.bitmap(from: data).map(PixelArt.trimmed).flatMap(PixelArt.image).flatMap(PixelArt.png) ?? data
        }
        return data
    }

    // MARK: Private

    private var liveScenes: [DigimonScene] {
        scenes.removeAll { $0.scene == nil }
        return scenes.compactMap(\.scene)
    }

    private func sceneState() -> [String: Any] {
        let partner = digimon.state.partner
        return ["key": currentKey, "line": partner.lineID, "stage": partner.level.order,
                "sleeping": sleeping, "lang": language == .ko ? "ko" : "en"]
    }

    private func pushState() {
        let state = sceneState()
        liveScenes.forEach { $0.apply(state) }
    }

    private func enqueue(_ step: @escaping @MainActor (DigimonSceneHub) async -> Void) {
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await step(self)
        }
    }

    private static func dataURI(_ data: Data) -> String {
        "data:image/png;base64," + data.base64EncodedString()
    }
}

/// The popover's pet scene. The web view is created per popover opening and dropped on close.
@MainActor
struct DigimonSceneView: NSViewRepresentable {
    let hub: DigimonSceneHub

    final class Coordinator {
        var scene: DigimonScene?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let scene = DigimonScene(mode: .popover)
        context.coordinator.scene = scene
        hub.register(scene)
        return scene.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
