import XCTest
@testable import BanglaEngine

/// Bornolipi's input menu names the modes explicitly: macOS shows a cached copy of it, so its items must
/// mean the same whatever the current mode, and choosing one must leave typing in that mode.
final class ModeMenuTests: XCTestCase {
    func testItemsDoNotDependOnTheMode() {
        XCTAssertEqual(ModeMenu.items.map(\.title), ["Bangla", "English"])
        XCTAssertEqual(ModeMenu.items.map(\.bangla), [true, false])
    }

    func testChoosingAModeAlwaysEndsInThatModeBothWays() {
        for current in [true, false] {
            for item in ModeMenu.items {
                let result = ModeMenu.choose(item, current: current) ?? current
                XCTAssertEqual(result, item.bangla, "\(item.title) chosen while bangla=\(current)")
            }
        }
        XCTAssertNil(ModeMenu.choose(ModeMenu.items[0], current: true), "choosing the mode in use changes nothing")
    }

    /// Shortcut, then menu, then shortcut: whatever the (possibly cached) menu shows, typing ends in
    /// the mode last chosen.
    func testShortcutAndMenuStayInStep() {
        var bangla = true
        bangla.toggle()                                                                   // Control-Shift-B: English
        bangla = ModeMenu.choose(ModeMenu.items[0], current: bangla) ?? bangla             // menu: Bangla
        XCTAssertTrue(bangla)
        bangla = ModeMenu.choose(ModeMenu.items[0], current: bangla) ?? bangla             // menu: Bangla again
        XCTAssertTrue(bangla, "a stale menu chosen twice cannot flip the mode")
        bangla.toggle()                                                                   // Control-Shift-B: English
        XCTAssertFalse(bangla)
    }

    func testTheHintNamesTheUsersShortcut() {
        XCTAssertEqual(ModeMenu.hint(.defaultToggle), "Switch with ⌃⇧B (the বাং/EN bubble shows the mode)")
        XCTAssertTrue(ModeMenu.hint(Shortcut(keyCode: 96, modifiers: 0)).hasPrefix("Switch with F5"))
    }
}
