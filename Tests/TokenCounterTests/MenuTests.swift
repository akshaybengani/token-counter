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
