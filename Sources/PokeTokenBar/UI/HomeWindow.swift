import AppKit
import SwiftUI

/// The menu bar popover's home in an ordinary window.
///
/// The menu bar icon can be invisible: on a crowded menu bar macOS pushes the newest item behind the
/// notch and offers no way to reach it, and DigiTokenBar's item (sprite plus two lines of usage) is
/// wide. A new user then installs the app, opens it and sees nothing (reported on a work laptop,
/// 2026-11-23). So this window opens on the first launch, and opening the app again (Finder,
/// Spotlight, `open -a DigiTokenBar`) always brings it back.
@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    static let shownKey = "homeWindowShownOnce"

    /// Only the first launch opens the window by itself; later launches (login, restarts) stay quiet.
    static func opensOnLaunch(_ defaults: UserDefaults) -> Bool { !defaults.bool(forKey: shownKey) }

    private let content: () -> AnyView
    private(set) var window: NSWindow?

    init(content: @escaping () -> AnyView) {
        self.content = content
    }

    func show(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.shownKey)
        if window == nil {
            let host = NSHostingController(rootView: content())
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = AppIdentity.name
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Drop the SwiftUI tree on close, as the popover does: a hidden live tree keeps re-laying out.
    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

/// The window's first line: where the app lives, and what to do when its icon is not there.
@MainActor
struct MenuBarHint: View {
    @Environment(AppLanguageStore.self) private var languageStore

    var body: some View {
        let t = DigimonText(languageStore.language)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .foregroundStyle(Color.accentColor)
            Text(t.menuBarHint)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: PopoverMetrics.width, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }
}
