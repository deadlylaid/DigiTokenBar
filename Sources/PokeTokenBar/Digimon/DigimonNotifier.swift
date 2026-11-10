import Foundation
import UserNotifications

/// System notifications for Digimon milestones. Same switch as the Pokemon companion's
/// ("companionNotifications", on by default) and only from the bundled app.
enum DigimonNotifier {
    static func post(_ title: String, _ body: String) {
        guard AppEnv.isBundledApp else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "digimon-\(UUID().uuidString)", content: content, trigger: nil))
    }
}
