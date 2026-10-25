// Packages/FeedbackKit/Sources/FeedbackKit/BundlePathMode.swift
import Foundation

/// How the prompts and the manifest name a file in a bundle.
///
/// A bundle on disk uses `absolute`: an agent on the same Mac opens the file
/// by its full path. A zip export uses `relative` (#85): every name is
/// relative to the export folder, so the text works on any Mac after unzip.
public enum BundlePathMode: Sendable, Equatable {
    case absolute(folderPath: String)
    /// `exportFolderName` is the zip's top folder. Only the Codex command
    /// names it, through a shell variable.
    case relative(exportFolderName: String)

    /// The text that names `name` in a prompt or the manifest.
    public func file(_ name: String) -> String {
        switch self {
        case .absolute(let folderPath): "\(folderPath)/\(name)"
        case .relative: name
        }
    }

    /// The `path` attribute of the prompt's opening tag. A relative prompt
    /// has none.
    public var tagPath: String? {
        switch self {
        case .absolute(let folderPath): folderPath
        case .relative: nil
        }
    }
}
