import AppKit

/// The desktop pet's size (Settings, saved per Mac). The scene keeps its 220 x 90 units at every size;
/// only the scale (points per unit) changes, so the pet's spot, its saved offset and the hit test stay
/// in the same units.
enum DeskPetSize: String, CaseIterable, Sendable {
    case small, medium, large

    static let defaultsKey = "digimonDeskPetSize"

    /// Points per scene unit. Medium is the size the pet always had (440 x 180).
    var scale: CGFloat {
        switch self {
        case .small: return 1.5
        case .medium: return 2
        case .large: return 2.5
        }
    }

    var panelSize: NSSize { NSSize(width: 220 * scale, height: 90 * scale) }

    static func saved(in defaults: UserDefaults) -> DeskPetSize {
        defaults.string(forKey: defaultsKey).flatMap(DeskPetSize.init(rawValue:)) ?? .medium
    }
}

/// A stroke: the pointer going back and forth over the Digimon (no button), seen through the pet's
/// 10-times-a-second pointer poll (a global mouse monitor would ask for Input Monitoring). Moves under
/// `minStep` points are jitter; a stroke is `minReversals` turns of direction within `window` seconds on
/// the axis that moved most, covering at least `minTravel` points. After one, `cooldown` seconds pass
/// before the next.
struct StrokeDetector {
    var window: TimeInterval = 1.5
    var minReversals = 3
    var minStep: CGFloat = 3
    var minTravel: CGFloat = 30
    var cooldown: TimeInterval = 4

    private var samples: [(t: TimeInterval, p: CGPoint)] = []
    private var lastStroke = -Double.infinity

    /// Feeds one pointer sample; true when this sample completes a stroke.
    mutating func feed(_ p: CGPoint, over: Bool, at t: TimeInterval) -> Bool {
        guard over else { samples.removeAll(); return false }
        samples.append((t, p))
        samples.removeAll { t - $0.t > window }
        guard t - lastStroke >= cooldown, samples.count >= minReversals + 1 else { return false }
        let x = Self.turns(samples.map(\.p.x), minStep: minStep)
        let y = Self.turns(samples.map(\.p.y), minStep: minStep)
        let axis = x.travel >= y.travel ? x : y
        guard axis.turns >= minReversals, axis.travel >= minTravel else { return false }
        lastStroke = t
        samples.removeAll()
        return true
    }

    /// Direction changes along one axis (steps under `minStep` ignored) and the distance moved.
    static func turns(_ values: [CGFloat], minStep: CGFloat) -> (turns: Int, travel: CGFloat) {
        var signs: [Int] = []
        var travel: CGFloat = 0
        for (a, b) in zip(values, values.dropFirst()) {
            let d = b - a
            travel += abs(d)
            guard abs(d) >= minStep else { continue }
            let s = d > 0 ? 1 : -1
            if signs.last != s { signs.append(s) }
        }
        return (max(0, signs.count - 1), travel)
    }
}

extension DigimonDeskPet {
    /// A click attacks at once. The second click of a double-click (macOS's own double-click time and
    /// distance, `NSEvent.clickCount`) jumps instead of attacking again; so does every quicker one after.
    enum ClickAction: Equatable { case attack, jump }

    nonisolated static func clickAction(clickCount: Int) -> ClickAction { clickCount >= 2 ? .jump : .attack }

    /// The window frame after a size change that keeps the Digimon's feet where they were on the screen.
    /// `petRect` is where the scene draws it (top-left based points); everything in the scene scales by
    /// the size ratio. Without a pet rect yet, the window keeps its bottom middle.
    nonisolated static func resizedFrame(window f: NSRect, petRect: CGRect, to size: DeskPetSize, from old: DeskPetSize) -> NSRect {
        let k = size.scale / old.scale, new = size.panelSize
        let anchor = petRect.isEmpty ? CGPoint(x: f.width / 2, y: f.height) : CGPoint(x: petRect.midX, y: petRect.maxY)
        let feetX = f.minX + anchor.x, feetY = f.maxY - anchor.y
        return NSRect(x: feetX - anchor.x * k, y: feetY + anchor.y * k - new.height, width: new.width, height: new.height)
    }
}

extension DigimonText {
    var deskPetSizeLabel: String { ko ? "크기" : "Size" }
    func deskPetSize(_ size: DeskPetSize) -> String {
        switch size {
        case .small: return ko ? "작게" : "Small"
        case .medium: return ko ? "보통" : "Medium"
        case .large: return ko ? "크게" : "Large"
        }
    }
    /// Bubbles after a stroke, in turn (one every other stroke).
    var strokeBubbles: [String] { ko ? ["좋아!", "기분 좋아~", "헤헤"] : ["Yay!", "That feels nice~", "Hehe"] }
    var deskPetTouchHint: String {
        ko ? "디지몬 위에서 마우스를 좌우로 문지르면 쓰다듬어요. 두 번 누르면 점프해요."
           : "Rub the pointer back and forth over the Digimon to pet it. Double-click to make it jump."
    }
}
