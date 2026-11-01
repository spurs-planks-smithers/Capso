namespace Nextshot.Core.Settings;

/// <summary>
/// Resolves a flag. Order: dev-only rule, then the environment variable
/// NEXTSHOT_FLAG_&lt;NAME&gt; (upper case), then the settings file, then the
/// channel default. An override that is unknown or not allowed is ignored.
/// A dev-only flag is Off in a release build, whatever an override says.
/// </summary>
public sealed class FlagResolver
{
    private readonly BuildChannel _channel;
    private readonly Func<string, string?> _env;
    private readonly SettingsStore _store;

    public FlagResolver(
        BuildChannel? channel = null,
        SettingsStore? store = null,
        Func<string, string?>? env = null)
    {
        _channel = channel ?? BuildInfo.Channel;
        _store = store ?? new SettingsStore();
        _env = env ?? Environment.GetEnvironmentVariable;
    }

    public static string EnvName(string flag) => "NEXTSHOT_FLAG_" + flag.ToUpperInvariant();

    public FlagState State(string flag)
    {
        var spec = FeatureFlags.Find(flag) ?? throw new ArgumentException($"Unknown flag: {flag}", nameof(flag));
        return Resolve(spec);
    }

    public bool IsOn(string flag) => State(flag) == FlagState.On;

    /// <summary>The lookup on its own, so a test can pass a dev-only spec.</summary>
    public FlagState Resolve(FlagSpec spec)
    {
        if (spec.DevOnly && _channel == BuildChannel.Release)
        {
            return FlagState.Off;
        }
        if (TryParse(_env(EnvName(spec.Name)), spec, out var fromEnv))
        {
            return fromEnv;
        }
        if (_store.ReadFlagOverrides().TryGetValue(spec.Name, out var text) && TryParse(text, spec, out var fromFile))
        {
            return fromFile;
        }
        return spec.DefaultFor(_channel);
    }

    private static bool TryParse(string? text, FlagSpec spec, out FlagState state)
    {
        state = FlagState.Off;
        return !string.IsNullOrWhiteSpace(text)
            && Enum.TryParse(text.Trim(), ignoreCase: true, out state)
            && Enum.IsDefined(state)
            && spec.AllowedStates.Contains(state);
    }
}
