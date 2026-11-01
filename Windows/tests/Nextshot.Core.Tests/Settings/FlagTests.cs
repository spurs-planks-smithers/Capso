using Nextshot.Core.Settings;
using Xunit;

namespace Nextshot.Core.Tests.Settings;

public sealed class FlagTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "nsflags-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, true);
    }

    private SettingsStore Store() => new(Path.Combine(_dir, "NextshotSettings", "settings.json"));

    private static FlagResolver Resolver(BuildChannel c, SettingsStore s, Dictionary<string, string>? env = null) =>
        new(c, s, k => env != null && env.TryGetValue(k, out var v) ? v : null);

    [Fact]
    public void DefaultsFollowRegistry()
    {
        var r = Resolver(BuildChannel.Dev, Store());
        Assert.Equal(FlagState.Off, r.State("zipHandoff"));
        Assert.Equal(FlagState.On, r.State("sessionTitle"));
    }

    [Fact]
    public void FileOverrideApplies()
    {
        var s = Store();
        s.SetFlag("zipHandoff", "on");
        Assert.True(Resolver(BuildChannel.Release, s).IsOn("zipHandoff"));
        s.ResetFlag("zipHandoff");
        Assert.False(Resolver(BuildChannel.Release, s).IsOn("zipHandoff"));
    }

    [Fact]
    public void EnvOverridesFile()
    {
        var s = Store();
        s.SetFlag("zipHandoff", "on");
        var env = new Dictionary<string, string> { ["NEXTSHOT_FLAG_ZIPHANDOFF"] = "off" };
        Assert.False(Resolver(BuildChannel.Dev, s, env).IsOn("zipHandoff"));
    }

    [Fact]
    public void InvalidOrDisallowedOverrideIsIgnored()
    {
        var s = Store();
        s.SetFlag("zipHandoff", "shadow");
        Assert.Equal(FlagState.Off, Resolver(BuildChannel.Dev, s).State("zipHandoff"));
        s.SetFlag("zipHandoff", "banana");
        Assert.Equal(FlagState.Off, Resolver(BuildChannel.Dev, s).State("zipHandoff"));
    }

    [Fact]
    public void DevOnlyFlagIsOffInReleaseEvenWithOverride()
    {
        var spec = new FlagSpec("x", 1, new HashSet<FlagState> { FlagState.Off, FlagState.On }, FlagState.On, FlagState.On, DevOnly: true);
        var env = new Dictionary<string, string> { ["NEXTSHOT_FLAG_X"] = "on" };
        Assert.Equal(FlagState.Off, Resolver(BuildChannel.Release, Store(), env).Resolve(spec));
        Assert.Equal(FlagState.On, Resolver(BuildChannel.Dev, Store(), env).Resolve(spec));
    }

    [Fact]
    public void UnknownFlagThrows() =>
        Assert.Throws<ArgumentException>(() => Resolver(BuildChannel.Dev, Store()).State("nope"));

    [Fact]
    public void CorruptFileReadsAsDefaults()
    {
        var s = Store();
        Directory.CreateDirectory(Path.GetDirectoryName(s.Path)!);
        File.WriteAllText(s.Path, "{ not json");
        Assert.Equal(FlagState.Off, Resolver(BuildChannel.Dev, s).State("zipHandoff"));
    }

    [Fact]
    public void SetFlagKeepsOtherSettings()
    {
        var s = Store();
        Directory.CreateDirectory(Path.GetDirectoryName(s.Path)!);
        File.WriteAllText(s.Path, "{\"theme\":\"dark\"}");
        s.SetFlag("zipHandoff", "on");
        Assert.Contains("theme", File.ReadAllText(s.Path));
    }

    [Fact]
    public void DefaultPathIsOutsideRoundsRoot()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var path = SettingsStore.DefaultPath();
        Assert.EndsWith(Path.Combine("NextshotSettings", "settings.json"), path);
        Assert.False(path.StartsWith(Path.Combine(local, "Nextshot") + Path.DirectorySeparatorChar));
    }

    [Fact]
    public void ChannelIsDevWhenConstantUndefined()
    {
#if RELEASE_CHANNEL
        Assert.Equal(BuildChannel.Release, BuildInfo.Channel);
#else
        Assert.Equal(BuildChannel.Dev, BuildInfo.Channel);
#endif
    }

    [Fact]
    public void ScriptFlagListMatchesRegistry()
    {
        string? script = null;
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d != null; d = d.Parent)
        {
            var p = Path.Combine(d.FullName, "scripts", "nextshot-flags.ps1");
            if (File.Exists(p)) { script = p; break; }
        }
        Assert.NotNull(script);
        var line = File.ReadAllLines(script!).First(l => l.StartsWith("$FLAGS = "));
        var entries = line.Split('"')[1].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        Assert.NotEmpty(entries);
        var expected = FeatureFlags.All
            .Select(f => f.Name + ":" + string.Join(",", f.AllowedStates.OrderBy(s => s).Select(s => s.ToString().ToLowerInvariant())))
            .ToArray();
        Assert.Equal(expected, entries);
    }
}
