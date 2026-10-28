import AppKit
import KeyboardShortcuts
import SwiftUI

/// Fork: keeps the native recorder and clears its binding on mouse-down.
/// The library consumes mouse-up inside a focused recorder (#159).
struct FeedbackShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(for name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil) {
        self.name = name
        self.onChange = onChange
    }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        (recorder.cell as? NSSearchFieldCell)?.cancelButtonCell?.sendAction(on: .leftMouseDown)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        recorder.shortcutName = name
    }
}
