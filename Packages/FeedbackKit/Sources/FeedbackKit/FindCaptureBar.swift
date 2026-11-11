// Packages/FeedbackKit/Sources/FeedbackKit/FindCaptureBar.swift
import Foundation

/// Fork: the bar at the bottom of the Find Capture window (#125, Drew,
/// 2026-11-08). It has two modes.
///
/// Selection mode shows the count of checked captures, Copy N Selected, Zip N
/// Selected (with `zipHandoff` on), and Clear. The checks are the basket of the
/// Nshot menu, so the count covers every round. The buttons are off with
/// nothing checked.
///
/// Round mode shows after a click on a card's round chip. It shows the round
/// name, Back, Copy Round Prompt, Zip Round (with `zipHandoff` on), Open
/// Folder, and Resume Round. Resume Round shows only when no round is active.
public struct FindCaptureBar: Equatable, Sendable {
    public enum Action: Hashable, Sendable {
        case copySelected
        case zipSelected
        case clearSelection
        case back
        case copyRoundPrompt
        case zipRound
        case openFolder
        case resumeRound
    }

    public struct Button: Equatable, Sendable {
        public var action: Action
        public var title: String
        public var isEnabled: Bool

        public init(action: Action, title: String, isEnabled: Bool) {
            self.action = action
            self.title = title
            self.isEnabled = isEnabled
        }
    }

    /// The text at the leading edge: "N selected", or the round name.
    public var label: String
    public var buttons: [Button]

    /// - Parameter roundName: The name of the round the window shows, or nil
    ///   for selection mode.
    /// - Parameter roundImported: The round was copied in from another Mac's
    ///   zip, so its captures keep that Mac's coordinates and new captures
    ///   must not join it.
    public init(roundName: String?, selectedCount: Int, zipEnabled: Bool, roundActive: Bool, roundImported: Bool = false) {
        if let roundName {
            label = roundName
            var buttons = [
                Button(action: .back, title: "Back", isEnabled: true),
                Button(action: .copyRoundPrompt, title: "Copy Round Prompt", isEnabled: true),
            ]
            if zipEnabled {
                buttons.append(Button(action: .zipRound, title: "Zip Round", isEnabled: true))
            }
            buttons.append(Button(action: .openFolder, title: "Open Folder", isEnabled: true))
            // Only one round can be active, so Resume waits until it ends. An
            // imported round is never resumable (#87).
            if !roundActive, !roundImported {
                buttons.append(Button(action: .resumeRound, title: "Resume Round", isEnabled: true))
            }
            self.buttons = buttons
        } else {
            let count = max(selectedCount, 0)
            let hasSelection = count > 0
            label = "\(count) selected"
            var buttons = [
                Button(action: .copySelected, title: SubmenuSelectionRows.copyTitle(count), isEnabled: hasSelection),
            ]
            if zipEnabled {
                buttons.append(Button(action: .zipSelected, title: SubmenuSelectionRows.zipTitle(count), isEnabled: hasSelection))
            }
            buttons.append(Button(action: .clearSelection, title: "Clear", isEnabled: hasSelection))
            self.buttons = buttons
        }
    }
}
