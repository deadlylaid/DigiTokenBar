import AppKit
import Observation

/// The Digimon walking on the desktop (opt-in, the existing "floating pet" setting). A borderless
/// transparent panel holds a desk-mode scene. The panel lets clicks through except over the pet:
/// drag it to move the panel, click it to attack. Ported from the DigiTokenTest prototype.
@MainActor
final class DigimonDeskPet {
    private let store: UsageStore
    private let hub: DigimonSceneHub
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var scene: DigimonScene?
    private var displayAwake = true
    private var petRect = CGRect.zero
    private var monitors: [Any] = []
    private var hitTimer: Timer?
    /// Coding agents reporting through digitokenbar://agent (`AgentActivityTracker` rules:
    /// several labels, working times out after 10 minutes, done shows for 6 seconds).
    private var agents = AgentActivityTracker()
    private var agentTimer: Timer?
    private let language: () -> AppLanguage
    private var tracking = false, dragging = false
    private var dragStartMouse = NSPoint.zero, dragStartOrigin = NSPoint.zero, lastMouse = NSPoint.zero

    static let size = NSSize(width: 440, height: 180)
    /// Where the Digimon was last dropped inside the window (scene units from its middle).
    static let petOffsetKey = "digimonDeskPetOffset"

    init(store: UsageStore, hub: DigimonSceneHub, defaults: UserDefaults = .standard,
         language: @escaping () -> AppLanguage = { .ko }) {
        self.store = store
        self.hub = hub
        self.defaults = defaults
        self.language = language
        observe()
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    /// Agent hooks (digitokenbar:// events): the pet reacts when a run finishes or waits for you.
    func handleAgentEvent(_ event: AgentActivityEvent, now: Date = Date()) {
        guard store.floatingPetAgentActivity else { return }
        // "working" arrives after every tool call, so only the rarer states are logged.
        if event.activity != .working {
            AppLog.write("agent event \(event.activity) label=\(event.label ?? "-") pet=\(scene != nil)")
        }
        agents.apply(event, now: now)
        switch event.activity {
        case .done: pushAgents(react: "done", now: now)
        case .waiting: pushAgents(react: "waiting", now: now)
        case .working, .idle: pushAgents(react: nil, now: now)
        }
    }

    /// What the pet shows for the tracked agents: busy dots while any works, and one bubble.
    /// A finished agent comes first (for its 6 seconds), then the latest one waiting for input.
    static func agentScene(_ summary: AgentActivitySummary, text: DigimonText) -> (working: Bool, bubble: String?) {
        func line(_ note: AgentActivitySummary.Note, _ fallback: String) -> String {
            (note.label.map { "\($0): " } ?? "") + (note.message ?? fallback)
        }
        if let done = summary.done { return (summary.working, line(done, text.agentDone)) }
        if let waiting = summary.waiting {
            let more = summary.otherWaitingCount > 0 ? text.agentMoreWaiting(summary.otherWaitingCount) : ""
            return (summary.working, line(waiting, text.agentWaiting) + more)
        }
        return (summary.working, nil)
    }

    private func pushAgents(react: String?, now: Date = Date()) {
        agents.expire(now: now)
        let view = Self.agentScene(agents.summary, text: DigimonText(language()))
        var cmd: [String: Any] = ["type": "agent", "working": view.working]
        if let bubble = view.bubble { cmd["bubble"] = bubble }
        if let react { cmd["react"] = react }
        scene?.command(cmd)
        agentTimer?.invalidate()
        agentTimer = nil
        guard let deadline = agents.deadline, scene != nil else { return }
        let timer = Timer(fire: deadline.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushAgents(react: nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        agentTimer = timer
    }

    private func observe() {
        withObservationTracking {
            _ = store.floatingPetEnabled
            _ = store.floatingPetAgentActivity
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
        sync()
    }

    private func sync() {
        if store.floatingPetEnabled && displayAwake { show() } else { hide() }
        if !store.floatingPetAgentActivity, !agents.agents.isEmpty {
            agents.reset()
            pushAgents(react: nil)
        }
    }

    private func show() {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(origin: initialOrigin(), size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let scene = DigimonScene(mode: .desk)
        scene.webView.frame = NSRect(origin: .zero, size: Self.size)
        scene.onPetRect = { [weak self] rect in
            self?.petRect = rect
            self?.updateHitTest()
        }
        scene.onPetHome = { [weak self] offset in self?.defaults.set(offset, forKey: Self.petOffsetKey) }
        // Back where it was dropped last time inside the window (the window itself is placed by its origin).
        if let offset = defaults.object(forKey: Self.petOffsetKey) as? Double {
            scene.command(["type": "place", "offset": offset])
        }
        panel.contentView = scene.webView
        panel.orderFrontRegardless()
        self.panel = panel
        self.scene = scene
        hub.register(scene)
        pushAgents(react: nil)
        installMonitors()
    }

    private func hide() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hitTimer?.invalidate()
        hitTimer = nil
        agentTimer?.invalidate()
        agentTimer = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        scene = nil
        petRect = .zero
        tracking = false
        dragging = false
    }

    private func initialOrigin() -> NSPoint {
        let size = Self.size
        if let x = defaults.object(forKey: "digimonDeskX") as? Double,
           let y = defaults.object(forKey: "digimonDeskY") as? Double {
            let saved = NSRect(x: x, y: y, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) { return saved.origin }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 24, y: vf.minY + 6)
    }

    // MARK: Mouse

    /// The panel lets clicks through until the pointer is over the pet. Where the pointer is gets
    /// polled 10 times a second while the pet is shown: a global mouse monitor would make macOS ask
    /// for Input Monitoring permission (`kTCCServiceListenEvent`), which a pet must not need.
    /// The local monitor (events this app already receives) needs no permission.
    private func installMonitors() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitTest() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        hitTimer = timer
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
                guard let self, let panel = self.panel, event.window === panel else { return event }
                return self.handleMouse(event) ? nil : event
            }) { monitors.append(local) }
    }

    private func updateHitTest() {
        guard let panel, !tracking else { return }
        let f = panel.frame, r = petRect.insetBy(dx: -6, dy: -6)
        let onScreen = NSRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
        let over = !petRect.isEmpty && onScreen.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    /// true when the event was handled here and must not reach the web view.
    private func handleMouse(_ event: NSEvent) -> Bool {
        guard let panel else { return false }
        let m = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            tracking = true
            dragging = false
            dragStartMouse = m
            lastMouse = m
            dragStartOrigin = panel.frame.origin
        case .leftMouseDragged:
            guard tracking else { return false }
            if !dragging && hypot(m.x - dragStartMouse.x, m.y - dragStartMouse.y) > 3 {
                dragging = true
                scene?.command(["type": "grab"])
            }
            if dragging {
                panel.setFrameOrigin(NSPoint(x: dragStartOrigin.x + m.x - dragStartMouse.x,
                                             y: dragStartOrigin.y + m.y - dragStartMouse.y))
                scene?.command(["type": "drag", "dx": Double(m.x - lastMouse.x)])
            }
            lastMouse = m
        case .leftMouseUp:
            guard tracking else { return false }
            tracking = false
            if dragging {
                dragging = false
                let shift = clampToScreen()
                scene?.command(["type": "drop", "shift": Double(shift)])
            } else {
                // A click answers the agents' questions and acknowledges results (work goes on).
                if agents.dismissBubble() { pushAgents(react: nil) }
                scene?.command(["type": "attack"])
            }
        default:
            return false
        }
        return true
    }

    /// Puts the window back inside the screen after a drag and returns how far it moved it sideways
    /// (points; the scene moves the Digimon the other way, so it stays where it was dropped).
    @discardableResult
    private func clampToScreen() -> CGFloat {
        guard let panel else { return 0 }
        let m = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(m) }) ?? NSScreen.main else { return 0 }
        let placed = Self.dropPlacement(window: panel.frame, visible: screen.visibleFrame)
        panel.setFrameOrigin(placed.origin)
        defaults.set(Double(placed.origin.x), forKey: "digimonDeskX")
        defaults.set(Double(placed.origin.y), forKey: "digimonDeskY")
        return placed.shift
    }

    /// The window is wider than the Digimon (it walks inside it), so the window stays inside the visible
    /// screen and the Digimon makes up the difference: dragged past the right edge by 120 points, the
    /// window comes back 120 points and the Digimon moves 120 points right inside it, reaching the edge.
    /// Before, only the window was pulled back, so the Digimon stopped short of the edge (user report).
    nonisolated static func dropPlacement(window f: NSRect, visible vf: NSRect) -> (origin: NSPoint, shift: CGFloat) {
        let x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        let y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        return (NSPoint(x: x, y: y), f.minX - x)
    }
}
