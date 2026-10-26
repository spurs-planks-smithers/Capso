// Packages/FeedbackKit/Sources/FeedbackKit/BundlePathMode.swift
import Foundation

/// How the prompts and the manifest name a file in a bundle.
///
/// A bundle on disk uses `absolute`: an agent on the same Mac opens the file
/// by its full path. A zip export uses `relative` (#85): every name is
/// relative to the export folder, so the text works on any Mac after unzip.
public enum BundlePathMode: Sendable, Equatable {
    case absolute(folderPath: String)
    /// `exportFolderName` is the zip's top folder. No text names it: every
    /// path in the text is relative to the folder that holds the README.
    case relative(exportFolderName: String)

    /// The text that names `name` in a prompt or the manifest.
    public func file(_ name: String) -> String {
        switch self {
        case .absolute(let folderPath): "\(folderPath)/\(name)"
        case .relative: name
        }
    }

    /// How the text names a capture image: a bundle holds PNGs, a zip export
    /// holds JPEGs.
    var imageNoun: String {
        switch self {
        case .absolute: "PNG"
        case .relative: "image"
        }
    }

    /// The extension of the clean copy, for "Open the -clean.png copy".
    var imageExtension: String {
        switch self {
        case .absolute: "png"
        case .relative: "jpg"
        }
    }

    /// The most visual tokens one image costs. Zip images are at the
    /// standard tier size.
    var maxImageTokens: Int {
        switch self {
        case .absolute: ImageSizing.Limits.feedbackExport.maxTokens
        case .relative: ImageSizing.Limits.standard.maxTokens
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
