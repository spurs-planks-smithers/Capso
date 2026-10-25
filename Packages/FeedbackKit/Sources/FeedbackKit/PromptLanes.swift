// Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift
import Foundation

/// Lanes and priority (issue #69): the round plan that sorts a round's items
/// into exact edits and judgment calls, and orders them by severity. JevKit
/// builds the plan from jev.json and the round. This type holds the plan and
/// writes its prompt section, so FeedbackKit never needs to know about Jev.
/// It holds item ids and level names only, never the reviewer's words. See
/// `docs/superpowers/specs/2026-10-24-prompt-lanes-design.md`.
public struct PromptLanes: Equatable, Sendable {
    /// One item in a lane. Both levels nil means the item is not rated: its
    /// capture has no usable labels.
    public struct Entry: Equatable, Sendable {
        /// The item id, K.N.
        public var item: String
        public var severity: Severity?
        public var size: Size?

        public init(item: String, severity: Severity? = nil, size: Size? = nil) {
            self.item = item
            self.severity = severity
            self.size = size
        }
    }

    /// What the section shows. The reviewer turns each part on with a
    /// sub-flag of `promptLanes` (Drew, 2026-10-25, #94). The title names
    /// what the section holds.
    public enum Layout: Equatable, Sendable {
        /// Both sub-flags on: the lane A and lane B split, and each lane
        /// worst first.
        case orderAndLanes
        /// `lanesOrder` only: one list, worst first, with no lanes. The list
        /// is `laneB`, and `laneA` is empty.
        case order
        /// `lanesSplit` only: lane A and lane B, each in capture order.
        case lanes

        var title: String {
            switch self {
            case .orderAndLanes: "Order and lanes"
            case .order: "Order"
            case .lanes: "Lanes"
            }
        }
    }

    /// Exact edits, in the order to do them.
    public var laneA: [Entry]
    /// Items that need judgment, in the order to plan them. In the `order`
    /// layout, every item, worst first.
    public var laneB: [Entry]
    /// Item ids that have no note.
    public var askFirst: [String]
    public var layout: Layout

    public init(laneA: [Entry], laneB: [Entry], askFirst: [String], layout: Layout = .orderAndLanes) {
        self.laneA = laneA
        self.laneB = laneB
        self.askFirst = askFirst
        self.layout = layout
    }

    /// The section, as lines for the end of the round prompt: "Order and
    /// lanes", "Order", or "Lanes", by `layout`. An empty lane prints a none
    /// line, and the last line points to the lane that has items. With no
    /// item in either lane, there is no last line. The `order` layout has no
    /// last line either.
    public var promptLines: [String] {
        var lines = [
            "\(layout.title):",
            "These labels come from an automated model. The reviewer's words win. Each item appears once.",
        ]
        switch layout {
        case .order:
            let items = laneA + laneB
            if items.isEmpty {
                lines.append("Items, worst first: none.")
            } else {
                lines.append("Plan and work these items in this order, worst first:")
                lines += items.map(Self.line)
            }
        case .orderAndLanes, .lanes:
            if laneA.isEmpty {
                lines.append("Lane A, exact edits: none.")
            } else {
                lines.append("Lane A, exact edits. After your plan table, hand these items to a subagent on a fast, low-cost model as one batch, with each item's instruction from manifest.md and its file from your plan table. In Claude Code, set the subagent's model to haiku. With fewer than three items, do them yourself. Check each edit before you start lane B.")
                lines += laneA.map(Self.line)
            }
            if laneB.isEmpty {
                lines.append("Lane B, needs judgment: none.")
            } else {
                lines.append(layout == .lanes ? "Lane B, needs judgment. Plan these yourself:" : "Lane B, needs judgment. Plan these yourself, in this order:")
                lines += laneB.map(Self.line)
            }
        }
        if !askFirst.isEmpty {
            lines.append("Ask first: \(askFirst.joined(separator: ", ")) (no instruction).")
        }
        switch (layout, laneA.isEmpty, laneB.isEmpty) {
        case (.order, _, _): break
        case (.orderAndLanes, false, false): lines.append("Start with lane A. Then work lane B from the top.")
        case (.orderAndLanes, true, false): lines.append("Work lane B from the top.")
        case (.lanes, false, false): lines.append("Start with lane A. Then work lane B.")
        case (.lanes, true, false): lines.append("Work lane B.")
        case (_, false, true): lines.append("Start with lane A.")
        case (_, true, true): break
        }
        return lines
    }

    private static func line(_ entry: Entry) -> String {
        guard let severity = entry.severity, let size = entry.size else {
            return "- \(entry.item) not rated"
        }
        return "- \(entry.item) \(severity.name), \(size.name)"
    }

    /// How serious the problem in an item's note is. The raw value is Jev's
    /// level number, nit first.
    public enum Severity: Int, CaseIterable, Sendable {
        /// A small taste preference.
        case nit = 0
        /// The change improves the look, the wording, or the layout.
        case polish
        /// Something is broken, inconsistent, or cut off, but the screen works.
        case bug
        /// The feature fails, shows wrong data, or blocks a task.
        case blocker

        public var name: String {
            switch self {
            case .nit: "nit"
            case .polish: "polish"
            case .bug: "bug"
            case .blocker: "blocker"
            }
        }
    }

    /// How much code a developer will likely change for an item. The raw
    /// value is Jev's level number, smallest first.
    public enum Size: Int, CaseIterable, Sendable {
        /// One value, word, or sentence in one place.
        case oneLine = 0
        /// A few related edits in one place.
        case oneFile
        /// Edits in a few files or places.
        case severalFiles
        /// A change across the app, the repository, or every page.
        case manyFiles

        public var name: String {
            switch self {
            case .oneLine: "one line"
            case .oneFile: "one file"
            case .severalFiles: "several files"
            case .manyFiles: "many files"
            }
        }
    }
}
