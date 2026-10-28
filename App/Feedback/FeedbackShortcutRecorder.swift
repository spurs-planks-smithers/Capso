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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name) { [weak coordinator] shortcut in
            coordinator?.configureCancelButton()
            coordinator?.onChange?(shortcut)
        }
        coordinator.attach(to: recorder)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        context.coordinator.onChange = onChange
        recorder.shortcutName = name
        context.coordinator.configureCancelButton()
    }

    static func dismantleNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        weak var recorder: KeyboardShortcuts.RecorderCocoa?
        var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?
        private var shortcutObserver: NSObjectProtocol?

        func attach(to recorder: KeyboardShortcuts.RecorderCocoa) {
            self.recorder = recorder
            configureCancelButton()
            // KeyboardShortcuts 2.2.1 exposes no public observer for a named change.
            // Its recorder uses this notification and restores a hidden cancel cell.
            shortcutObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name else { return }
                // Run after the library restores the cell, regardless of observer order.
                DispatchQueue.main.async { [weak self] in
                    guard let self, name == self.recorder?.shortcutName else { return }
                    self.configureCancelButton()
                }
            }
        }

        func configureCancelButton() {
            (recorder?.cell as? NSSearchFieldCell)?.cancelButtonCell?.sendAction(on: .leftMouseDown)
        }

        func detach() {
            if let shortcutObserver {
                NotificationCenter.default.removeObserver(shortcutObserver)
            }
            shortcutObserver = nil
            recorder = nil
            onChange = nil
        }
    }
}
