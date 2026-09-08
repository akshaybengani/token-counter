import AppKit
import XCTest
@testable import TokenCounter

/// Structure only. Whether the checkmark visibly follows the mode is flagged for
/// manual sign-off (spec-26 t-4), because the menu cannot be driven on this machine.
///
/// Every test here holds the delegate for the duration of its assertions, because
/// `NSMenuItem.target` is a weak reference: let the delegate go and the whole menu
/// silently reports no targets, which is also what would happen at run time if
/// nothing retained the delegate.
@MainActor
final class MenuTests: XCTestCase {

    func testMenuOffersBothDisplayModes() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let menu = delegate.buildMenu()
            let combined = menu.item(withTag: 110)
            let separate = menu.item(withTag: 111)

            XCTAssertNotNil(combined, "the combined mode item is missing")
            XCTAssertNotNil(separate, "the per-provider mode item is missing")
            XCTAssertEqual(combined?.title, "Combined")
            XCTAssertEqual(separate?.title, "Per Provider")
        }
    }

    /// An item with an action but no target renders greyed out and does nothing.
    func testEveryActionableItemHasATarget() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let menu = delegate.buildMenu()
            let actionable = menu.items.filter { $0.action != nil }
            XCTAssertFalse(actionable.isEmpty, "no actionable items found, so this proves nothing")
            for item in actionable {
                XCTAssertNotNil(item.target, "\"\(item.title)\" has an action but no target")
            }
        }
    }

    /// The checkmark has to follow the mode, including when settings changes it.
    /// This was on the manual sign-off list until the state was separated from the
    /// status bar item it used to be entangled with.
    func testTheCheckmarkFollowsTheDisplayMode() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let menu = delegate.buildMenu()
            let store = UsageStore.shared
            let original = store.mode
            defer { store.mode = original }

            store.mode = .combined
            delegate.applyState(to: menu, panelVisible: true)
            XCTAssertEqual(menu.item(withTag: 110)?.state, .on, "Combined should be ticked")
            XCTAssertEqual(menu.item(withTag: 111)?.state, .off)

            store.mode = .separate
            delegate.applyState(to: menu, panelVisible: true)
            XCTAssertEqual(menu.item(withTag: 110)?.state, .off)
            XCTAssertEqual(menu.item(withTag: 111)?.state, .on, "Per Provider should be ticked")
        }
    }

    /// Show Panel reflects whether the panel is actually on screen.
    func testShowPanelReflectsVisibility() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let menu = delegate.buildMenu()
            delegate.applyState(to: menu, panelVisible: false)
            XCTAssertEqual(menu.item(withTag: 101)?.state, .off)
            delegate.applyState(to: menu, panelVisible: true)
            XCTAssertEqual(menu.item(withTag: 101)?.state, .on)
        }
    }

    /// Tags are how the checkmarks and the header are found later, so a collision
    /// would make one item silently unreachable.
    func testTagsAreUnique() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let tags = delegate.buildMenu().items.map(\.tag).filter { $0 != 0 }
            XCTAssertFalse(tags.isEmpty, "no tagged items found, so this proves nothing")
            XCTAssertEqual(tags.count, Set(tags).count, "duplicate menu tags: \(tags)")
        }
    }
}

/// Closes the gap between "the settings view renders" and "choosing Settings opens
/// it". The capture harness in tools/uishot builds its own window, so it proves the
/// panes but not the plumbing that puts them on screen. These drive the same action
/// the menu item targets.
@MainActor
final class SettingsWindowTests: XCTestCase {

    func testTheMenuRoutesSettingsToTheOpenAction() {
        let delegate = AppDelegate()
        withExtendedLifetime(delegate) {
            let menu = delegate.buildMenu()
            let item = menu.items.first { $0.title.hasPrefix("Settings") }
            XCTAssertNotNil(item, "no Settings item in the menu")
            XCTAssertEqual(item?.action, #selector(AppDelegate.showSettings))
            XCTAssertTrue(item?.target === delegate, "the Settings item points at nothing")
            XCTAssertEqual(item?.keyEquivalent, ",", "the conventional shortcut is missing")
        }
    }

    /// Opening builds a window of the shape the panes were laid out for, and opening
    /// twice reuses it rather than stacking a second one.
    func testOpeningSettingsProducesOneWindowOfTheExpectedShape() throws {
        let delegate = AppDelegate()
        try withExtendedLifetime(delegate) {
            delegate.openSettings()
            let window = try XCTUnwrap(delegate.settingsWindowForTesting, "no window was created")

            // The window and the view must agree on one size. They used to be two
            // hardcoded pairs of numbers in two files.
            XCTAssertEqual(window.contentView?.frame.width ?? 0, SettingsView.windowSize.width, accuracy: 1)
            XCTAssertEqual(window.contentView?.frame.height ?? 0, SettingsView.windowSize.height, accuracy: 1)
            XCTAssertNotNil(window.contentView, "the window has no content view")
            XCTAssertTrue(window.isVisible, "the window was created but never shown")

            delegate.openSettings()
            XCTAssertTrue(delegate.settingsWindowForTesting === window, "a second window was opened")

            delegate.closeSettings()
            XCTAssertFalse(window.isVisible, "closing left the window on screen")
        }
    }
}
