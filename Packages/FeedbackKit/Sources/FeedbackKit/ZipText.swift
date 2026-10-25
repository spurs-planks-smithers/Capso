// Packages/FeedbackKit/Sources/FeedbackKit/ZipText.swift
import Foundation

/// `README.md`, the file an agent opens first in a zip export (#85). It holds
/// the whole prompt, with every path relative to its folder.
public enum ZipReadme {
    /// `missing` are captures whose image file was not found. `unresolved`
    /// are checked captures whose round or capture was not found at all.
    public static func render(_ plan: ZipPlan, kind: ZipKind, missing: [FeedbackBasketKey], unresolved: [FeedbackBasketKey] = []) -> String {
        var lines = [
            "# Nextshot feedback export",
            "",
            "This folder is a Nextshot feedback export: screenshots that a reviewer marked with numbered badges, and what should change for each badge.",
            "Every path in this folder is relative to the folder that holds this README.md. If you have only the .zip file, unzip it first.",
            "If you cannot read files in this folder, ask the person to move it out of Downloads, Desktop, or Documents.",
        ]
        if kind == .selection {
            let captures = plan.round.captures.count
            let rounds = plan.sourceRoundLines.count
            lines.append("This export holds \(captures) \(captures == 1 ? "capture" : "captures") from \(rounds) \(rounds == 1 ? "round" : "rounds").")
        }
        for key in missing {
            lines.append("Left out (image file not found): round \(key.folderName), its capture \(key.captureIndex).")
        }
        for key in unresolved {
            lines.append("Left out (capture not found): round \(key.folderName), its capture \(key.captureIndex).")
        }
        lines.append("")
        // The redo line is in every zip prompt: the agent on the other Mac
        // may not be the first pass.
        let prompt = PromptBuilder.render(plan.round, paths: .relative(exportFolderName: plan.round.folderName), redo: true)
        return lines.joined(separator: "\n") + "\n" + prompt
    }
}

/// The toasts of a zip export.
public enum ZipMessages {
    public static let making = "Making zip..."
    public static let noDownloadsAccess = "Nextshot cannot write to Downloads.\nAllow it in System Settings, Privacy and Security, Files and Folders."

    public static func ready(fileName: String, bytes: Int, overBudget: Bool) -> String {
        let over = overBudget ? " (over the 5 MB goal)" : ""
        return "Zip copied: \(fileName), \(sizeText(bytes))\(over).\nPaste it into Mail, Slack, or Teams. It is also in Downloads."
    }

    /// The toast for a zip that was not written. It names the reason, and
    /// never a file name, because file names hold screen text.
    public static func failure(for error: Error) -> String {
        if let error = error as? ZipError, error == .noCaptures {
            return "Nothing to zip.\nNo capture was found with both of its images."
        }
        if let error = error as? ExportImageError {
            switch error {
            case .unreadable: return "Zip not written.\nA capture image could not be read."
            case .encodeFailed: return "Zip not written.\nA capture image could not be converted."
            }
        }
        if isNoAccess(error) {
            return noDownloadsAccess
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return "Zip not written.\nThe disk is full."
        }
        return "Zip not written.\nThe Nextshot log has the reason."
    }

    /// True for a write that macOS refused, as when Downloads access is off.
    public static func isNoAccess(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isNoAccess(underlying)
        }
        return false
    }

    /// Decimal units, as Finder shows them: "2.4 MB", or "48 KB" under 0.1 MB.
    static func sizeText(_ bytes: Int) -> String {
        if bytes < 100_000 {
            return "\(max(1, Int((Double(bytes) / 1_000).rounded()))) KB"
        }
        return String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / 1_000_000)
    }
}
