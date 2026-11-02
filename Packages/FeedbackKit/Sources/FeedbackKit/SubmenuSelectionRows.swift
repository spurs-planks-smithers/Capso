// Packages/FeedbackKit/Sources/FeedbackKit/SubmenuSelectionRows.swift
import Foundation

/// Fork: the Copy, Zip, and Clear rows at the top of a round's submenu
/// (#264). The rows are always in the submenu, so checking a capture never
/// moves a capture row under the pointer. With nothing checked they are off.
/// The count is the whole basket, across rounds, as in the top-level rows.
public struct SubmenuSelectionRows: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var title: String
        public var isEnabled: Bool

        public init(title: String, isEnabled: Bool) {
            self.title = title
            self.isEnabled = isEnabled
        }
    }

    public var copy: Row
    /// Nil when `zipHandoff` is off.
    public var zip: Row?
    public var clear: Row

    public init(selectedCount: Int, zipEnabled: Bool) {
        let count = max(selectedCount, 0)
        let hasSelection = count > 0
        copy = Row(title: Self.copyTitle(count), isEnabled: hasSelection)
        zip = zipEnabled ? Row(title: Self.zipTitle(count), isEnabled: hasSelection) : nil
        clear = Row(title: "Clear Selection", isEnabled: hasSelection)
    }

    /// Also the title of the top-level row, which shows only for a count of 1 or more.
    public static func copyTitle(_ count: Int) -> String {
        count > 0 ? "Copy \(count) Selected" : "Copy Selected"
    }

    public static func zipTitle(_ count: Int) -> String {
        count > 0 ? "Zip \(count) Selected" : "Zip Selected"
    }
}
