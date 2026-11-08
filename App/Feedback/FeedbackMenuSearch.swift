// App/Feedback/FeedbackMenuSearch.swift
import AppKit

/// Fork: the search field at the top of the Nshot menu (#125, Drew,
/// 2026-11-08).
///
/// How keys reach it: the open menu is a key window (`NSPopupMenuWindow`), and
/// AppKit gives an editable field in a menu item's view first responder when
/// the menu opens. Typed characters and Delete then go to the field's editor,
/// not to the menu, so the menu does not jump to an item by its first letter.
/// The arrow keys still move the menu's highlight, and the field keeps its
/// focus. A check on 2026-11-08 (macOS 27, keys posted into an open menu)
/// showed this. A Carbon key handler and a local key monitor, the older route
/// for search fields in menus, saw no key events there, so this view uses
/// neither. `viewDidMoveToWindow` also asks for first responder, in case a
/// system does not give it.
///
/// Return reaches the field's delegate as `insertNewline:` and runs
/// `onSubmit`. With an item highlighted, the menu takes Return and chooses
/// that item first, as in any menu. Esc reaches the delegate as
/// `cancelOperation:` and closes the menu, where a search field would
/// otherwise clear itself.
@MainActor
final class FeedbackMenuSearchView: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    /// Return: the field's text, which can be empty.
    var onSubmit: ((String) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 32))
        // The menu sets the item's width. The view follows it.
        autoresizingMask = [.width]
        field.placeholderString = "Search captures"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        field.setAccessibilityLabel("Search captures")
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Empties the field before the menu opens. An editor left from the last
    /// open goes first, so the old text cannot come back.
    func reset() {
        field.abortEditing()
        field.stringValue = ""
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            onSubmit?(field.stringValue)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            enclosingMenuItem?.menu?.cancelTracking()
            return true
        default:
            return false
        }
    }
}
