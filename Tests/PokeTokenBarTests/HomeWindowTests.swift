import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The menu bar icon can sit hidden behind the notch, so the home also opens in a window: by itself on
/// the first launch only, and whenever the app is opened again (user report, 2026-11-23).
@MainActor
final class HomeWindowTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "HomeWindowTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testTheWindowOpensByItselfOnlyOnTheFirstLaunch() {
        XCTAssertTrue(HomeWindowController.opensOnLaunch(defaults), "a new install opens the window")
        let controller = HomeWindowController { AnyView(Text(verbatim: "home")) }
        controller.show(defaults: defaults)
        XCTAssertFalse(HomeWindowController.opensOnLaunch(defaults), "later launches stay in the menu bar")
        let window = try? XCTUnwrap(controller.window)
        XCTAssertEqual(window?.title, AppIdentity.name)
        XCTAssertTrue(window?.styleMask.contains(.closable) ?? false)
        window?.close()
    }

    func testShowingAgainReusesTheWindowAndClosingDropsIt() {
        let controller = HomeWindowController { AnyView(Text(verbatim: "home")) }
        controller.show(defaults: defaults)
        let first = controller.window
        controller.show(defaults: defaults)
        XCTAssertTrue(controller.window === first, "opening the app twice does not stack windows")
        first?.close()
        XCTAssertNil(controller.window, "closed: the SwiftUI tree is released, like the popover's")
        XCTAssertNil(first?.contentViewController)
        controller.show(defaults: defaults)
        XCTAssertNotNil(controller.window, "and it can open again after closing")
        controller.window?.close()
    }

    func testTheHintSaysWhereTheIconIsAndHowToGetBack() {
        for language in [AppLanguage.ko, .en] {
            let hint = DigimonText(language).menuBarHint
            XCTAssertTrue(hint.contains("DigiTokenBar"))
            XCTAssertTrue(hint.contains(language == .ko ? "노치" : "notch"), hint)
            XCTAssertTrue(hint.contains("Spotlight"), hint)
        }
    }
}
