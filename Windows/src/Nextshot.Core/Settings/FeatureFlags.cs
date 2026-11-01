namespace Nextshot.Core.Settings;

/// <summary>
/// The Windows flag registry. It mirrors the Mac registry
/// (Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift and
/// AppCapabilities) for the flags the Windows v1 round flow uses.
/// The Jev flags (jevBase, noteCoach, cropsAnchors, dupesConflicts, promptLanes,
/// dataGuard, their sub-flags, and the two jevSend consent flags) are left out
/// on purpose: Jev is dev-only on the Mac and has no Windows plan. oneBreath
/// is left out too (paused on the Mac).
/// scripts/nextshot-flags.ps1 holds the same list, and a test fails when the
/// two differ.
/// </summary>
public static class FeatureFlags
{
    private static readonly IReadOnlySet<FlagState> OffOn =
        new HashSet<FlagState> { FlagState.Off, FlagState.On };

    private static FlagSpec Spec(string name, int issue, FlagState dev = FlagState.Off, FlagState release = FlagState.Off) =>
        new(name, issue, OffOn, dev, release);

    /// <summary>Every Windows flag, in the same order as the PowerShell script.</summary>
    public static IReadOnlyList<FlagSpec> All { get; } = new[]
    {
        Spec("zipHandoff", 85),
        // On in both channels on the Mac since build 887.
        Spec("supportSubmission", 0, FlagState.On, FlagState.On),
        // On in both channels on the Mac since build 889.
        Spec("sessionTitle", 164, FlagState.On, FlagState.On),
        // On in both channels on the Mac (Drew, 2026-10-31).
        Spec("updateReminder", 203, FlagState.On, FlagState.On),
        Spec("screenshotCopy", 123),
        Spec("diagnostics", 118),
        // AppCapabilities (issue 119). Off in both channels.
        Spec("standaloneCapture", 119),
        Spec("recordingTools", 119),
        Spec("translationTools", 119),
        Spec("cloudShare", 119),
        Spec("automationURLs", 119),
        Spec("automaticUpdates", 119),
    };

    public static FlagSpec? Find(string name) =>
        All.FirstOrDefault(s => string.Equals(s.Name, name, StringComparison.OrdinalIgnoreCase));
}
