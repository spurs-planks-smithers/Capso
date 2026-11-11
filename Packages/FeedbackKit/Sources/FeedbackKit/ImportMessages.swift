import Foundation

/// The toasts of a round import (#87).
///
/// A round copies in as a folder, because a zip cannot be read here: the zip
/// writer only shares a folder with `NSFileCoordinator`, and the source scan
/// bans a subprocess. So the reviewer unzips with Finder or `unzip` and points
/// the panel at the folder.
public enum ImportMessages {
    public static func ready(name: String, captureCount: Int) -> String {
        let captures = captureCount == 1 ? "1 capture" : "\(captureCount) captures"
        return "Imported \u{201C}\(name)\u{201D}, \(captures).\nIt lists under All Rounds. Copy its prompt, or zip it again to share."
    }

    /// The toast for an import that did not happen. Like a zip's failure, it
    /// never names a path, because a folder name holds the round name, and the
    /// round name holds words the reviewer typed about their own screen.
    public static func failure(for error: Error) -> String {
        guard let error = error as? FeedbackRoundStore.StoreError else {
            return "Nothing imported.\nThe folder could not be read as a Nextshot round."
        }
        switch error {
        case .roundNotFound:
            return "Nothing imported.\nPick the folder that holds feedback.json, not the zip itself."
        case .roundWasImported:
            return "Nothing imported.\nThat round was already imported."
        default:
            return "Nothing imported.\nThe folder could not be read as a Nextshot round."
        }
    }
}
