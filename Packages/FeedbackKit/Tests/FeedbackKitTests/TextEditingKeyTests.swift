import Foundation
import Testing
@testable import FeedbackKit

/// The editing keys of the search fields (#125): Command with A, C, X, V, and
/// Z, and Shift+Command+Z. Every other key press maps to nothing, so other
/// Command shortcuts keep working.
@Suite("TextEditingKey")
struct TextEditingKeyTests {
    private func action(_ characters: String?, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) -> TextEditingKey? {
        TextEditingKey.action(characters: characters, command: command, shift: shift, option: option, control: control)
    }

    @Test("Command with A, C, X, V, and Z maps to select all, copy, cut, paste, and undo")
    func commandKeys() {
        #expect(action("a") == .selectAll)
        #expect(action("c") == .copy)
        #expect(action("x") == .cut)
        #expect(action("v") == .paste)
        #expect(action("z") == .undo)
    }

    @Test("Shift+Command+Z is redo, and the letter's case does not matter")
    func redoAndCase() {
        #expect(action("z", shift: true) == .redo)
        #expect(action("Z", shift: true) == .redo)
        #expect(action("A") == .selectAll)
    }

    @Test("Other keys and other modifiers map to nothing")
    func others() {
        #expect(action("a", command: false) == nil)
        #expect(action("s") == nil)
        #expect(action("w") == nil)
        #expect(action("q") == nil)
        #expect(action("a", option: true) == nil)
        #expect(action("c", control: true) == nil)
        #expect(action("v", shift: true) == nil)
        #expect(action("a", shift: true) == nil)
        #expect(action(nil) == nil)
        #expect(action("") == nil)
    }
}
