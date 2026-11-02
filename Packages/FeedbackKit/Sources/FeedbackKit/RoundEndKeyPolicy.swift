import Foundation

/// Decides when Option+Shift+R and Option+Shift+E may end the round.
///
/// A selection, an editor, or a busy screenshot holds a capture that is not
/// saved yet, so ending the round then would put it in a new round (#25).
/// The note panel is different: its capture is already stored, so the keys
/// end the round at the current step and keep what the round holds (#266).
public enum RoundEndKeyPolicy {
    public static func allows(
        selectionActive: Bool,
        editorOpen: Bool,
        screenshotBusy: Bool,
        notePanelOpen: Bool
    ) -> Bool {
        !(selectionActive || editorOpen || screenshotBusy)
    }
}
