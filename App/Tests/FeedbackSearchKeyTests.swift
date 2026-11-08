import KeyboardShortcuts
import XCTest
@testable import Capso

/// Option+Shift+S opens the Nshot menu with the cursor in its search field
/// (#125, Drew, 2026-11-08). It is always on while `findCapture` is on, and the
/// shortcut guard keeps it apart from every other key.
@MainActor
final class FeedbackSearchKeyTests: XCTestCase {
    func testSearchKeyDefaultsToOptionShiftS() {
        XCTAssertEqual(KeyboardShortcuts.Name.feedbackSearch.defaultShortcut, .init(.s, modifiers: [.option, .shift]))
    }

    func testSearchKeyIsAlwaysOnAndGuarded() throws {
        try XCTSkipUnless(Flags.isOn(.findCapture), "findCapture is off on this Mac")
        XCTAssertTrue(KeyboardShortcuts.Name.alwaysOnKeys.contains(.feedbackSearch))
        XCTAssertTrue(KeyboardShortcuts.Name.nextshotKeys.contains(.feedbackSearch))
        XCTAssertFalse(KeyboardShortcuts.Name.feedbackRoundKeys.contains(.feedbackSearch))
        XCTAssertEqual(Array(KeyboardShortcuts.Name.alwaysOnKeys.prefix(2)), [.feedbackCapture, .feedbackRepeatCapture])
    }

    func testNextshotDefaultsShareNoKey() throws {
        let names = KeyboardShortcuts.Name.nextshotKeys + [.feedbackSearch]
        let defaults = names.compactMap(\.defaultShortcut)
        XCTAssertEqual(defaults.count, names.count, "every Nextshot key has a default")
        XCTAssertEqual(Set(defaults).count, Set(names).count, "two Nextshot keys share a default")
        let upstream = Set(KeyboardShortcuts.Name.allCapso.compactMap(\.defaultShortcut))
        for name in names {
            let shortcut = try XCTUnwrap(name.defaultShortcut)
            XCTAssertFalse(upstream.contains(shortcut), "\(name.rawValue) shares its default with an upstream action")
        }
    }
}
