// Packages/FeedbackKit/Sources/FeedbackKit/TextEditingKey.swift
import Foundation

/// Fork: the standard editing keys of a text field (#125, Drew, 2026-11-08).
/// Nextshot has no Edit menu, and a text field gets these keys from Edit menu
/// items in other apps. So the Find Capture window and the Nshot menu's
/// search field map the key press here and send the action to the field's
/// editor themselves.
public enum TextEditingKey: String, Equatable, Sendable, CaseIterable {
    case selectAll
    case copy
    case cut
    case paste
    case undo
    case redo

    /// The editing action of a key press, or nil for any other key.
    /// - Parameter characters: The key's characters with no modifiers
    ///   (`charactersIgnoringModifiers`). Case does not matter.
    public static func action(characters: String?, command: Bool, shift: Bool, option: Bool, control: Bool) -> TextEditingKey? {
        guard command, !option, !control, let characters else { return nil }
        switch characters.lowercased() {
        case "a": return shift ? nil : .selectAll
        case "c": return shift ? nil : .copy
        case "x": return shift ? nil : .cut
        case "v": return shift ? nil : .paste
        case "z": return shift ? .redo : .undo
        default: return nil
        }
    }
}
