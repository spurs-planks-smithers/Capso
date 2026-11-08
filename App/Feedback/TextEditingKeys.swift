// App/Feedback/TextEditingKeys.swift
import AppKit
import FeedbackKit

/// Fork: the standard editing keys in Nextshot's search fields (#125).
/// Nextshot has no Edit menu, so Command+A, C, X, V, Z, and Shift+Command+Z
/// never reach a field editor on their own. The Find Capture panel and the
/// Nshot menu's search field read the key here and send the action to the
/// editor. Every other key press maps to nothing and goes on as before.
extension TextEditingKey {
    /// The editing action of a key-down event, or nil.
    static func action(for event: NSEvent) -> TextEditingKey? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags
        return action(characters: event.charactersIgnoringModifiers, command: flags.contains(.command),
                      shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control))
    }

    /// Sends the action to a field editor. Undo and redo use the editor's
    /// undo manager and beep when there is nothing to undo or redo.
    @MainActor
    func perform(in textView: NSTextView) {
        switch self {
        case .selectAll: textView.selectAll(nil)
        case .copy: textView.copy(nil)
        case .cut: textView.cut(nil)
        case .paste: textView.paste(nil)
        case .undo:
            if let manager = textView.undoManager, manager.canUndo { manager.undo() } else { NSSound.beep() }
        case .redo:
            if let manager = textView.undoManager, manager.canRedo { manager.redo() } else { NSSound.beep() }
        }
    }
}
