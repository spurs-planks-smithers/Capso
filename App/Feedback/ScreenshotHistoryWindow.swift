import AppKit
import QuickLookUI
import SwiftUI

/// Fork: the Find Capture window (#125). It owns one panel, made at the first
/// show and kept when it closes, so the search and the filters stay for the
/// next open. Opening it starts no capture, no request, and no optional
/// service.
@MainActor
final class ScreenshotHistoryWindow: NSObject, NSWindowDelegate {
    let presentation = ScreenshotHistoryPresentation()
    private let actions: FindCaptureActions
    private var window: ScreenshotHistoryPanel?
    /// Runs each time the window becomes key, so the list reloads.
    var onBecomeKey: (() -> Void)?

    var isVisible: Bool { window?.isVisible == true }

    init(actions: FindCaptureActions) {
        self.actions = actions
    }

    /// - Parameter query: Text for the search field, caret at the end. Nil
    ///   keeps the field's text and selects it, so typing replaces it.
    func show(query: String? = nil) {
        if window == nil {
            // Not a nonactivating panel: the search field needs real keyboard focus.
            let panel = ScreenshotHistoryPanel(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Find Capture"
            panel.minSize = NSSize(width: 760, height: 560)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: ScreenshotHistoryView(
                presentation: presentation,
                actions: actions
            ))
            panel.center()
            window = panel
        }
        // This is a menu bar app, so it is not active when the menu row runs.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.focusSearch(query: query)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?()
    }
}

private final class ScreenshotHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc closes the window, also while the search field has focus. A text
    /// field that composes text with an input method keeps its Esc.
    ///
    /// A key that types text while the grid has focus goes to the search
    /// field (#125): the field takes focus with its caret at the end, and then
    /// gets the key. The key event itself goes on, so an input method and a
    /// held key work as in the field. Space stays with the grid for Quick Look.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53,
               event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
               (firstResponder as? NSTextView)?.hasMarkedText() != true {
                cancelOperation(nil)
                return
            }
            if !(firstResponder is NSText), Self.typesText(event), let field = searchField(),
               makeFirstResponder(field), let editor = field.currentEditor() {
                // A field that takes focus selects all its text. Put the caret
                // at the end instead, so the key adds to the search.
                editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
            }
        }
        super.sendEvent(event)
    }

    /// True for a key that types text: no Command or Control key, and no
    /// white space (Space), control (Esc, Return, Tab, Delete), or
    /// private-use (arrow and function keys) character.
    private static func typesText(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: false
            default: !scalar.properties.isWhitespace
            }
        }
    }

    /// Gives the search field keyboard focus. With a query, the field's text
    /// becomes the query through the field editor, as typing would, so the
    /// SwiftUI binding and the results follow, and the caret ends at the end.
    /// AppKit does this, not SwiftUI focus: a field that SwiftUI focuses
    /// selects all its text, and the next key would replace the query. The
    /// hosting view can build the field after the first show, so a missing
    /// field is tried again on the next turns of the run loop.
    func focusSearch(query: String?, attempt: Int = 0) {
        contentView?.layoutSubtreeIfNeeded()
        guard let field = searchField() else {
            guard attempt < 5 else { return }
            Task { @MainActor [weak self] in self?.focusSearch(query: query, attempt: attempt + 1) }
            return
        }
        guard makeFirstResponder(field), let query, let editor = field.currentEditor() as? NSTextView else { return }
        editor.selectAll(nil)
        if query.isEmpty {
            if editor.selectedRange().length > 0 { editor.delete(nil) }
        } else {
            editor.insertText(query, replacementRange: editor.selectedRange())
        }
    }

    /// The search field: the one editable text field in the window.
    private func searchField() -> NSTextField? {
        func find(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            for subview in view.subviews {
                if let field = find(in: subview) { return field }
            }
            return nil
        }
        return contentView.flatMap { find(in: $0) }
    }

    /// Quick Look takes Esc first while its panel shows.
    override func cancelOperation(_ sender: Any?) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.isVisible {
            preview.orderOut(nil)
            return
        }
        close()
    }
}
