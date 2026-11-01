using Nextshot.Core.Json;
using Nextshot.Core.Model;
using Nextshot.Core.Store;
using Xunit;

namespace Nextshot.Core.Tests.Store;

public sealed class RoundStoreTests : IDisposable
{
    private sealed class StubRenderer : IBundleTextRenderer
    {
        public string RenderManifest(FeedbackRound round, string folderPath, TimeZoneInfo timeZone) =>
            $"manifest {round.Name} {round.Captures.Count} {folderPath}";

        public string RenderPrompt(FeedbackRound round, string folderPath) =>
            $"prompt {round.Name} {round.Captures.Count}";
    }

    private readonly string _root = Path.Combine(Path.GetTempPath(), "nextshot-store-" + Guid.NewGuid().ToString("N"));
    private readonly StubRenderer _renderer = new();
    private DateTimeOffset _clock = new(2026, 10, 31, 12, 0, 0, TimeSpan.Zero);

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }

    private RoundStore NewStore() => new(_renderer, _root, TimeZoneInfo.Utc, () => _clock);

    private static FeedbackCapture Capture(int index) => new(
        index, $"{index}.png", $"{index}-clean.png", new PixelSize(100, 50), DateTimeOffset.UnixEpoch);

    private async Task<string> MakeEndedRound(RoundStore store, string name, int captures = 1)
    {
        var r = await store.StartAsync(name);
        await store.UpdateAsync(x => { for (var i = 1; i <= captures; i++) x.Captures.Add(Capture(i)); });
        _clock = _clock.AddMinutes(1);
        await store.EndAsync();
        _clock = _clock.AddMinutes(1);
        return r.FolderName;
    }

    [Fact]
    public async Task StartWritesThreeFilesAndMarker()
    {
        var store = NewStore();
        var round = await store.StartAsync("Pricing Review");
        var folder = Path.Combine(_root, round.FolderName);
        Assert.Equal("2026-10-31-1200-pricing-review", round.FolderName);
        Assert.True(File.Exists(Path.Combine(folder, "feedback.json")));
        Assert.Contains("manifest Pricing Review 0", File.ReadAllText(Path.Combine(folder, "manifest.md")));
        Assert.Contains("prompt Pricing Review 0", File.ReadAllText(Path.Combine(folder, "prompt.md")));
        Assert.True(File.Exists(Path.Combine(_root, ".active.json")));
        await Assert.ThrowsAsync<RoundStoreException>(() => store.StartAsync("again"));
    }

    [Fact]
    public async Task SameMinuteStartsGetUniqueSuffixes()
    {
        var store = NewStore();
        var a = await store.StartAsync("x");
        await store.EndAsync();
        var b = await store.StartAsync("x");
        Assert.Equal(a.FolderName + "-2", b.FolderName);
    }

    [Fact]
    public async Task UpdateRewritesAllFilesAndSurvivesRestart()
    {
        var store = NewStore();
        var round = await store.StartAsync("one");
        await store.UpdateAsync(r => r.Captures.Add(Capture(1)));
        var folder = Path.Combine(_root, round.FolderName);
        Assert.Contains("prompt one 1", File.ReadAllText(Path.Combine(folder, "prompt.md")));
        var onDisk = FeedbackRoundJson.Deserialize(File.ReadAllText(Path.Combine(folder, "feedback.json")));
        Assert.Single(onDisk.Captures);

        var reopened = NewStore();
        Assert.NotNull(reopened.ActiveRound);
        Assert.Single(reopened.ActiveRound!.Captures);
    }

    [Fact]
    public async Task FailedUpdateChangesNothing()
    {
        var store = NewStore();
        await store.StartAsync("one");
        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            store.UpdateAsync(r => { r.Captures.Add(Capture(1)); throw new InvalidOperationException(); }));
        Assert.Empty(store.ActiveRound!.Captures);
    }

    [Fact]
    public async Task EndClearsMarkerAndResumeReopens()
    {
        var store = NewStore();
        var folder = await MakeEndedRound(store, "one", 2);
        Assert.Null(store.ActiveRound);
        Assert.False(File.Exists(Path.Combine(_root, ".active.json")));

        var resumed = await store.ResumeAsync(folder);
        Assert.Null(resumed.EndedAt);
        Assert.Equal(2, resumed.Captures.Count);
        Assert.True(File.Exists(Path.Combine(_root, ".active.json")));
        await Assert.ThrowsAsync<RoundStoreException>(() => store.ResumeAsync(folder));
        await store.EndAsync();
        await Assert.ThrowsAsync<RoundStoreException>(() => store.ResumeAsync("missing"));
        await Assert.ThrowsAsync<RoundStoreException>(() => store.ResumeAsync("..\\x"));
    }

    [Fact]
    public async Task ListIsActiveFirstThenNewestEndFirstAndSkipsEmpty()
    {
        var store = NewStore();
        var oldest = await MakeEndedRound(store, "oldest");
        var newest = await MakeEndedRound(store, "newest");
        await MakeEndedRound(store, "empty", 0);
        await store.StartAsync("live");

        // An active round with no capture is left out.
        var first = await store.ListRecentAsync();
        Assert.Equal([newest, oldest], first.Rounds.Select(r => r.FolderName));

        await store.UpdateAsync(r => r.Captures.Add(Capture(1)));
        var second = await store.ListRecentAsync();
        Assert.Equal("live", second.Rounds[0].Name);
        Assert.Null(second.Rounds[0].EndedAt);
        Assert.Equal([newest, oldest], second.Rounds.Skip(1).Select(r => r.FolderName));

        var limited = await store.ListRecentAsync(limit: 1);
        Assert.Equal(2, limited.Rounds.Count);
    }

    [Fact]
    public async Task NewerSchemaRoundIsHiddenCountedAndUntouched()
    {
        var store = NewStore();
        var kept = await MakeEndedRound(store, "kept");
        var hiddenDir = Path.Combine(_root, "2099-01-01-0000-future");
        Directory.CreateDirectory(hiddenDir);
        const string future = "{\"schemaVersion\":99,\"somethingNew\":true}";
        File.WriteAllText(Path.Combine(hiddenDir, "feedback.json"), future);
        var badDir = Path.Combine(_root, "bad");
        Directory.CreateDirectory(badDir);
        File.WriteAllText(Path.Combine(badDir, "feedback.json"), "not json");

        var listing = await store.ListRecentAsync(limit: null);
        Assert.Equal([kept], listing.Rounds.Select(r => r.FolderName));
        Assert.Equal(1, listing.HiddenCount);
        Assert.Equal(["2099-01-01-0000-future"], listing.NewerSchema);
        Assert.Equal(["bad"], listing.Unreadable);
        await Assert.ThrowsAsync<RoundStoreException>(() => store.ResumeAsync("2099-01-01-0000-future"));
        Assert.Equal(future, File.ReadAllText(Path.Combine(hiddenDir, "feedback.json")));
    }

    [Fact]
    public async Task ConcurrentSavesKeepValidJson()
    {
        var store = NewStore();
        var round = await store.StartAsync("busy");
        var tasks = Enumerable.Range(1, 40).Select(_ =>
            Task.Run(() => store.UpdateAsync(r => r.Captures.Add(Capture(r.Captures.Count + 1))))).ToArray();
        await Task.WhenAll(tasks);

        var folder = Path.Combine(_root, round.FolderName);
        var onDisk = FeedbackRoundJson.Deserialize(File.ReadAllText(Path.Combine(folder, "feedback.json")));
        Assert.Equal(40, onDisk.Captures.Count);
        Assert.Equal(Enumerable.Range(1, 40), onDisk.Captures.Select(c => c.Index));
        Assert.Empty(Directory.GetFiles(folder, "*.tmp"));
        Assert.Contains("prompt busy 40", File.ReadAllText(Path.Combine(folder, "prompt.md")));
    }

    [Fact]
    public void DefaultRootIsLocalAppDataNextshot()
    {
        Assert.EndsWith("Nextshot", RoundStore.DefaultRoot());
    }
}
