namespace Nextshot.Core.Settings;

/// <summary>How far a feature runs. Mirrors Mac FlagState.</summary>
public enum FlagState
{
    Off,
    Shadow,
    On,
}

/// <summary>The kind of build. Mirrors Mac BuildChannel.</summary>
public enum BuildChannel
{
    Dev,
    Release,
}

/// <summary>One flag's registry entry. Mirrors Mac FlagSpec.</summary>
public sealed record FlagSpec(
    string Name,
    int Issue,
    IReadOnlySet<FlagState> AllowedStates,
    FlagState DevDefault,
    FlagState ReleaseDefault,
    bool DevOnly = false)
{
    public FlagState DefaultFor(BuildChannel channel) =>
        channel == BuildChannel.Dev ? DevDefault : ReleaseDefault;
}
