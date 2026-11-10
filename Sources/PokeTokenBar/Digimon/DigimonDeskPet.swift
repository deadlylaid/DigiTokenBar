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
    private var tracking = false, dragging = false
    private var dragStartMouse = NSPoint.zero, dragStartOrigin = NSPoint.zero, lastMouse = NSPoint.zero

    static let size = NSSize(width: 440, height: 180)

    init(store: UsageStore, hub: DigimonSceneHub, defaults: UserDefaults = .standard) {
        self.store = store
        self.hub = hub
        self.defaults = defaults
        observe()
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    /// Agent hooks (digitokenbar:// events): the pet reacts when a run finishes or waits for you.
    func handleAgentEvent(_ event: AgentActivityEvent) {
        guard store.floatingPetAgentActivity else { return }
        switch event.activity {
        case .waiting, .done: scene?.command(["type": "notice"])
        case .working, .idle: break
        }
    }

    private func observe() {
        withObservationTracking {
            _ = store.floatingPetEnabled
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
        panel.contentView = scene.webView
        panel.orderFrontRegardless()
        self.panel = panel
        self.scene = scene
        hub.register(scene)
        installMonitors()
    }

    private func hide() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hitTimer?.invalidate()
        hitTimer = nil
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
                clampToScreen()
                scene?.command(["type": "drop"])
            } else {
                scene?.command(["type": "attack"])
            }
        default:
            return false
        }
        return true
    }

    private func clampToScreen() {
        guard let panel else { return }
        let m = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(m) }) ?? NSScreen.main else { return }
        let vf = screen.visibleFrame, f = panel.frame
        let x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        let y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        defaults.set(Double(x), forKey: "digimonDeskX")
        defaults.set(Double(y), forKey: "digimonDeskY")
    }
}
