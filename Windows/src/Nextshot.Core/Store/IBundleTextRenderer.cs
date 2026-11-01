using Nextshot.Core.Model;

namespace Nextshot.Core.Store;

/// <summary>
/// Renders the Markdown files of a bundle. The store calls it on each change.
/// The real writers (Bundle/) implement it later (issue #219).
/// </summary>
public interface IBundleTextRenderer
{
    /// <summary>The text of manifest.md for the round.</summary>
    string RenderManifest(FeedbackRound round, string folderPath, TimeZoneInfo timeZone);

    /// <summary>The text of prompt.md for the round.</summary>
    string RenderPrompt(FeedbackRound round, string folderPath);
}
