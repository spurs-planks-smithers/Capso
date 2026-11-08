// App/Feedback/FeedbackMenuSearch.swift
import AppKit
import FeedbackKit
import KeyboardShortcuts

/// Fork: the search field at the top of the Nshot menu (#125, Drew,
/// 2026-11-08).
///
/// How keys reach it: the open menu's window (`NSPopupMenuWindow`) sends key
/// presses to its first responder. With the field's editor as first
/// responder, typed characters and Delete go to the field, not to the menu,
/// so the menu does not jump to an item by its first letter. The arrow keys
/// still move the menu's highlight, and the field keeps its focus. Checks on
/// 2026-11-08 (macOS 27, keys posted into an open menu) showed this. A Carbon
/// key handler and a local key monitor, the older route for search fields in
/// menus, saw no key events there, so this view uses neither. The field takes
/// focus when the menu opens and keeps it while the window settles
/// (`focusWhileOpening`, from `FeedbackStatusItem.menuWillOpen`).
///
/// Return reaches the field's delegate as `insertNewline:` and runs
/// `onSubmit`. With an item highlighted, the menu takes Return and chooses
/// that item first, as in any menu. Esc reaches the delegate as
/// `cancelOperation:` and closes the menu, where a search field would
/// otherwise clear itself. The editing keys (Command+A, C, X, V, Z, and
/// Shift+Command+Z) go to the editor through `FeedbackMenuSearchField`.
@MainActor
final class FeedbackMenuSearchView: NSView, NSSearchFieldDelegate {
    let field = FeedbackMenuSearchField()
    /// The Option+Shift+S key, in gray at the right of the row.
    private let keyLabel = NSTextField(labelWithString: "")
    /// Return: the field's text, which can be empty.
    var onSubmit: ((String) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        // The menu sets the item's width. The view follows it.
        autoresizingMask = [.width]
        field.placeholderString = "Search captures"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        field.setAccessibilityLabel("Search captures")
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.font = .menuFont(ofSize: 0)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(field)
        addSubview(keyLabel)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: keyLabel.leadingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Empties the field before the menu opens. An editor left from the last
    /// open goes first, so the old text cannot come back. The key label
    /// follows a changed shortcut.
    func reset() {
        field.abortEditing()
        field.stringValue = ""
        keyLabel.stringValue = KeyboardShortcuts.getShortcut(for: .feedbackSearch)?.description ?? ""
    }

    /// Gives the field keyboard focus with the caret at the end. A field that
    /// already has its editor keeps it, so a click is never undone.
    func focus() {
        guard let window, field.currentEditor() == nil else { return }
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    /// The menu's window sets its own first responder while it opens, and on
    /// some opens that came after the field took focus. The field then had
    /// no focus, typed keys went to the menu, and only a click gave the field
    /// focus (found 2026-11-08 by keys posted into the real Nshot menu: one
    /// open in three lost focus). So the field checks every 20 ms while the
    /// menu opens and takes focus back when it lost it. The checks stop after
    /// half a second, or after 0.2 seconds when the field held focus on the
    /// last five checks.
    func focusWhileOpening() {
        focusTimer?.invalidate()
        focusChecks = 0
        focusHeld = 0
        focus()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocus() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        focusTimer = timer
    }

    private var focusTimer: Timer?
    private var focusChecks = 0
    private var focusHeld = 0

    private func checkFocus() {
        focusChecks += 1
        guard focusChecks <= 25, focusChecks < 10 || focusHeld < 5 else {
            focusTimer?.invalidate()
            focusTimer = nil
            return
        }
        // The view joins the menu's window after the menu starts to open.
        guard let window else { return }
        window.initialFirstResponder = field
        if field.currentEditor() == nil {
            focusHeld = 0
            focus()
        } else {
            focusHeld += 1
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { focus() }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        // Command+Z needs the editor to record its changes.
        (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.allowsUndo = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            onSubmit?(field.stringValue)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            enclosingMenuItem?.menu?.cancelTracking()
            return true
        case Selector(("noop:")):
            // An editing key that reached the editor as a plain key press.
            guard let event = NSApp.currentEvent, let key = TextEditingKey.action(for: event) else { return false }
            key.perform(in: textView)
            return true
        default:
            return false
        }
    }
}

/// Fork: the menu's search field. It takes the editing keys before the menu
/// or the system sees them, because Nextshot has no Edit menu (#125).
@MainActor
final class FeedbackMenuSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { FeedbackMenuSearchCell.self }
        set { super.cellClass = newValue }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = currentEditor() as? NSTextView, let key = TextEditingKey.action(for: event) {
            key.perform(in: editor)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Fork: gives the menu's search field its own editor, so the caret shows.
@MainActor
final class FeedbackMenuSearchCell: NSSearchFieldCell {
    private lazy var editor: FeedbackMenuFieldEditor = {
        let editor = FeedbackMenuFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor
    }
}

/// Fork: the editor of the menu's search field (#125).
///
/// Nextshot is not the active app when its menu opens, so the menu's window
/// is not the key window. The field still has focus and takes every key, but
/// AppKit adds no caret to an editor outside the key window. A check on
/// 2026-11-08 found no insertion indicator in the editor's views. With no
/// caret, the field looked as if it needed a click. This editor shows its own
/// `NSTextInsertionIndicator` at the insertion point while its window is not
/// key. In a key window AppKit's own caret shows, and this one hides.
@MainActor
final class FeedbackMenuFieldEditor: NSTextView {
    private let caret = NSTextInsertionIndicator(frame: .zero)

    override var shouldDrawInsertionPoint: Bool {
        window?.firstResponder === self
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // Placed once the editor has its text and its frame.
        RunLoop.main.perform(inModes: [.eventTracking, .default]) { [weak self] in
            MainActor.assumeIsolated { self?.updateCaret() }
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        caret.displayMode = .hidden
        return super.resignFirstResponder()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateCaret()
    }

    override func didChangeText() {
        super.didChangeText()
        updateCaret()
    }

    override func layout() {
        super.layout()
        updateCaret()
    }

    private func updateCaret() {
        guard let window, window.firstResponder === self, !window.isKeyWindow,
              selectedRange().length == 0 else {
            caret.displayMode = .hidden
            return
        }
        if caret.superview !== self { addSubview(caret) }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        var rect = convert(window.convertFromScreen(screenRect), from: nil)
        if rect.height < 1 { rect.size.height = font.map { ceil($0.ascender - $0.descender) } ?? 16 }
        rect.size.width = max(rect.width, 2)
        caret.frame = rect
        caret.displayMode = .visible
    }
}
