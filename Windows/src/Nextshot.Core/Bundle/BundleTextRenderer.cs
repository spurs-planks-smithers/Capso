using Nextshot.Core.Model;
using Nextshot.Core.Store;

namespace Nextshot.Core.Bundle;

/// <summary>The real renderer: the store's text comes from ManifestWriter and PromptBuilder.</summary>
public sealed class BundleTextRenderer : IBundleTextRenderer
{
    public string RenderManifest(FeedbackRound round, string folderPath, TimeZoneInfo timeZone) =>
        ManifestWriter.Render(round, folderPath, timeZone);

    public string RenderPrompt(FeedbackRound round, string folderPath) =>
        PromptBuilder.Render(round, folderPath);

    public string RenderCapturePrompt(FeedbackCapture capture, string folderPath) =>
        PromptBuilder.RenderCapture(capture, folderPath);
}
