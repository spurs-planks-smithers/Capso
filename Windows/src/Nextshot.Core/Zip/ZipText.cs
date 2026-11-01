// Port of Packages/FeedbackKit/Sources/FeedbackKit/ZipText.swift
using System.Globalization;
using Nextshot.Core.Bundle;

namespace Nextshot.Core.Zip;

/// <summary>
/// README.md, the file an agent opens first in a zip export. It holds the whole prompt, with
/// every path relative to its folder.
/// </summary>
public static class ZipReadme
{
    /// <summary>
    /// <paramref name="missing"/> are captures whose image file was not found.
    /// <paramref name="unresolved"/> are checked captures whose round or capture was not found at all.
    /// </summary>
    public static string Render(ZipPlan plan, ZipKind kind, IEnumerable<BasketKey> missing,
        IEnumerable<BasketKey>? unresolved = null)
    {
        var lines = new List<string>
        {
            "# Nextshot feedback export",
            "",
            "This folder is a Nextshot feedback export: screenshots that a reviewer marked with numbered badges, and what should change for each badge.",
            "Every path in this folder is relative to the folder that holds this README.md. If you have only the .zip file, unzip it first.",
            "If you cannot read files in this folder, ask the person to move it out of Downloads, Desktop, or Documents.",
        };
        if (kind == ZipKind.Selection)
        {
            var captures = plan.Round.Captures.Count;
            var rounds = plan.SourceRoundLines.Count;
            lines.Add($"This export holds {captures} {(captures == 1 ? "capture" : "captures")} from {rounds} {(rounds == 1 ? "round" : "rounds")}.");
        }
        foreach (var key in missing)
            lines.Add($"Left out (image file not found): round {key.FolderName}, its capture {key.CaptureIndex}.");
        foreach (var key in unresolved ?? [])
            lines.Add($"Left out (capture not found): round {key.FolderName}, its capture {key.CaptureIndex}.");
        lines.Add("");
        // The redo line is in every zip prompt: the agent on the other machine may not be the first pass.
        var prompt = PromptBuilder.Render(plan.Round, new BundlePathMode.Relative(plan.Round.FolderName), redo: true);
        return string.Join("\n", lines) + "\n" + prompt;
    }
}

/// <summary>The toasts of a zip export.</summary>
public static class ZipMessages
{
    public const string Making = "Making zip...";
    public const string NoDownloadsAccess =
        "Nextshot cannot write to Downloads.\nCheck that the folder is not read-only, and that Controlled folder access allows Nextshot.";

    public static string Ready(string fileName, long bytes, bool overBudget)
    {
        var over = overBudget ? " (over the 5 MB goal)" : "";
        return $"Zip copied: {fileName}, {SizeText(bytes)}{over}.\nPaste it into Mail, Slack, or Teams. It is also in Downloads.";
    }

    /// <summary>The toast for a zip that was not written. It names the reason, never a file name, because file names hold screen text.</summary>
    public static string Failure(Exception error)
    {
        if (error is ZipException { Kind: ZipErrorKind.NoCaptures })
            return "Nothing to zip.\nNo capture was found with both of its images.";
        if (error is ExportImageException image)
            return image.Kind == ExportImageErrorKind.Unreadable
                ? "Zip not written.\nA capture image could not be read."
                : "Zip not written.\nA capture image could not be converted.";
        if (error is UnauthorizedAccessException) return NoDownloadsAccess;
        // ERROR_DISK_FULL (0x70) and ERROR_HANDLE_DISK_FULL (0x27), as HRESULTs.
        if (error is IOException io && (io.HResult & 0xFFFF) is 0x70 or 0x27)
            return "Zip not written.\nThe disk is full.";
        return "Zip not written.\nThe Nextshot log has the reason.";
    }

    /// <summary>Decimal units: "2.4 MB", or "48 KB" under 0.1 MB.</summary>
    public static string SizeText(long bytes)
    {
        if (bytes < 100_000)
            return $"{Math.Max(1, (long)Math.Round(bytes / 1_000.0, MidpointRounding.AwayFromZero))} KB";
        return (bytes / 1_000_000.0).ToString("F1", CultureInfo.InvariantCulture) + " MB";
    }
}
