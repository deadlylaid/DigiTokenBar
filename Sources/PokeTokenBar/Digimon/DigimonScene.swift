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
    /// How many bugs one kill was worth (a big bug counts as several).
    var onBugDefeated: (Int) -> Void = { _ in }
    /// A golden bug was defeated: it drops a Digimental fragment (step 13).
    var onGoldenBug: () -> Void = {}
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
            onBugDefeated((body["count"] as? NSNumber)?.intValue ?? 1)
            if (body["golden"] as? NSNumber)?.boolValue == true { onGoldenBug() }
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
    /// "sleepy", "sick" or nil: how the pet behaves (see `mood(sleeping:hour:nightHours:limitFull:)`).
    @ObservationIgnored var mood: String?
    /// UserDefaults key for the Settings switch "Stay in place".
    static let stayInPlaceKey = "digimonStayInPlace"
    /// The pet stays in the middle of every scene instead of walking around (Settings).
    private(set) var stayInPlace = false
    @ObservationIgnored private var scenes: [WeakScene] = []
    @ObservationIgnored private var loading: [String: Task<Data?, Never>] = [:]
    /// Event playback runs one step at a time so an evolution never arrives before its sprite.
    @ObservationIgnored private var chain: Task<Void, Never>?
    /// Today's visits already walked through a live scene this run ("day|species"). A visit that
    /// came while no scene was showing plays when the next one opens.
    @ObservationIgnored private var playedVisits: Set<String> = []

    private struct WeakScene { weak var scene: DigimonScene? }

    init(digimon: DigimonStore, sprites: DigimonSpriteStore = DigimonSpriteStore()) {
        self.digimon = digimon
        self.sprites = sprites
    }

    /// Sick while a usage limit is full (it hurts more than being tired), sleepy in the small hours.
    /// Asleep (no usage for a while) shows no mood.
    nonisolated static func mood(sleeping: Bool, hour: Int, nightHours: Range<Int>, limitFull: Bool) -> String? {
        if sleeping { return nil }
        if limitFull { return "sick" }
        return nightHours.contains(hour) ? "sleepy" : nil
    }

    static func sceneKey(_ partner: DigimonPartner) -> String {
        partner.speciesKey ?? "egg_\(partner.lineID)"
    }

    var currentKey: String { Self.sceneKey(digimon.state.partner) }

    func register(_ scene: DigimonScene) {
        scenes.removeAll { $0.scene == nil }
        scenes.append(WeakScene(scene: scene))
        scene.onBugDefeated = { [weak self] count in self?.digimon.recordBugDefeated(count: count) }
        scene.onGoldenBug = { [weak self] in self?.digimon.recordGoldenBug() }
        enqueue { hub in
            let key = hub.currentKey
            if let data = await hub.image(for: key) { scene.sprite(key: key, dataURI: Self.dataURI(data)) }
            scene.apply(hub.sceneState())
            for visit in hub.digimon.visitorsToday where !hub.playedVisits.contains(hub.visitID(visit.species)) {
                await hub.playVisit(visit.species, tier: visit.tier, firstSeen: visit.firstSeen, gift: visit.gift != nil, in: [scene])
            }
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
                case .jogressed(_, let partner, let to):
                    // The friend's Digimon walks in and both merge, then the evolution plays.
                    if let data = await hub.image(for: partner) {
                        hub.liveScenes.forEach { $0.sprite(key: partner, dataURI: Self.dataURI(data)) }
                        hub.broadcast(["type": "jogress", "partner": partner])
                        try? await Task.sleep(for: .seconds(2.2))
                    }
                    target = to
                case .visited(let species, let tier, let firstSeen):
                    let gift = hub.digimon.visitorsToday.last { $0.species == species }?.gift != nil
                    await hub.playVisit(species, tier: tier, firstSeen: firstSeen, gift: gift, in: hub.liveScenes)
                    target = nil
                case .stampCardFull, .digimentalMade:
                    hub.broadcast(["type": "jump"])
                    target = nil
                case .fragmentFound: target = nil   // the scene already showed the golden bug or the gift
                case .choiceOffered, .jogressOffered: target = nil
                }
                guard let target, let data = await hub.image(for: target) else { continue }
                hub.liveScenes.forEach { $0.sprite(key: target, dataURI: Self.dataURI(data)) }
                hub.broadcast(["type": "evolve", "key": target])
            }
            hub.pushState()
        }
    }

    /// Settings: stay in place (saved per Mac) or walk around. Every scene follows at once.
    func setStayInPlace(_ still: Bool, defaults: UserDefaults = .standard) {
        defaults.set(still, forKey: Self.stayInPlaceKey)
        guard still != stayInPlace else { return }
        stayInPlace = still
        refresh()
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

    /// Play a battle (already decided) in every scene: the foe walks in and the moves fly.
    func playBattle(foe: String, result: BattleResult) {
        enqueue { hub in
            guard let data = await hub.image(for: foe) else { return }
            hub.liveScenes.forEach { $0.sprite(key: foe, dataURI: Self.dataURI(data)) }
            let rounds: [[String: Any]] = result.rounds.map { ["a": $0.attacker == .me ? "me" : "foe", "hit": $0.hit] }
            let foeStage = hub.digimon.engine.catalog.species(foe)?.level.order ?? 4
            hub.broadcast(["type": "battle", "foe": foe, "foeStage": foeStage, "won": result.won, "rounds": rounds])
        }
    }

    /// A visitor walks in, greets the pet and leaves. Not marked as played while no scene shows it.
    private func playVisit(_ species: String, tier: VisitorTier, firstSeen: Bool, gift: Bool,
                           in scenes: [DigimonScene]) async {
        guard !scenes.isEmpty, let data = await image(for: species) else { return }
        playedVisits.insert(visitID(species))
        let t = DigimonText(language)
        let name = t.name(digimon.engine.catalog.species(species))
        scenes.forEach {
            $0.sprite(key: species, dataURI: Self.dataURI(data))
            $0.command(["type": "visit", "visitor": species, "tier": tier.rawValue, "fresh": firstSeen,
                        "greet": t.visitorGreeting(name, firstSeen: firstSeen), "gift": gift,
                        "giftText": t.giftCallout])
        }
    }

    private func visitID(_ species: String) -> String { "\(digimon.state.luck?.day ?? "")|\(species)" }

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
        var state: [String: Any] = ["key": currentKey, "line": partner.lineID, "stage": partner.level.order,
                                    "sleeping": sleeping, "lang": language == .ko ? "ko" : "en"]
        state["mood"] = mood ?? NSNull()
        state["still"] = stayInPlace
        // The day's fortune: more bugs, or shooting stars on a meteor shower.
        state["fortune"] = digimon.todayLuck?.fortune.rawValue ?? NSNull()
        // How often a bug is golden (it drops a Digimental fragment), and what the pet says then.
        state["golden"] = DigimentalRules.goldenBugChance(digimon.todayLuck?.fortune)
        state["goldenText"] = DigimonText(language).goldenCallout
        // The line's egg color, for the fire of lines without their own colors.
        state["lineColor"] = digimon.engine.catalog.lines[partner.lineID]?.eggColorHex ?? NSNull()
        return state
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
