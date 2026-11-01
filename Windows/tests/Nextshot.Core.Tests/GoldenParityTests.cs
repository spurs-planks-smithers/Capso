using Nextshot.Core.Bundle;
using Nextshot.Core.Json;
using Nextshot.Core.Store;
using Xunit;

namespace Nextshot.Core.Tests;

/// <summary>
/// The parity gate. The store writes each golden round, and every text file it writes
/// must match the golden folder byte for byte.
/// </summary>
public sealed class GoldenParityTests : IDisposable
{
    // Files in a golden folder that the store does not write.
    private static readonly string[] NotStoreOutputs = ["selection-prompt.md", "zip-readme.md", "timezone.txt"];

    private readonly string _root = Path.Combine(Path.GetTempPath(), "nextshot-parity-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }

    private static string GoldenRoot()
    {
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d is not null; d = d.Parent)
        {
            var candidate = Path.Combine(d.FullName, "Windows", "golden");
            if (Directory.Exists(candidate)) return candidate;
        }
        throw new DirectoryNotFoundException("Windows/golden not found above " + AppContext.BaseDirectory);
    }

    public static IEnumerable<object[]> CaseNames() =>
        Directory.GetDirectories(GoldenRoot())
            .Where(d => File.Exists(Path.Combine(d, "feedback.json")))
            .Select(d => new object[] { Path.GetFileName(d) })
            .OrderBy(o => (string)o[0], StringComparer.Ordinal);

    [Fact]
    public void AtLeastEightCasesExist() => Assert.True(CaseNames().Count() >= 8);

    [Theory]
    [MemberData(nameof(CaseNames))]
    public async Task StoreOutputMatchesGoldenFolder(string name)
    {
        var golden = Path.Combine(GoldenRoot(), name);
        var round = FeedbackRoundJson.Deserialize(File.ReadAllBytes(Path.Combine(golden, "feedback.json")));
        var zone = TimeZoneInfo.FindSystemTimeZoneById(File.ReadAllText(Path.Combine(golden, "timezone.txt")).Trim());

        // Seed the golden round, resume it, and let the store rewrite every file.
        // The round stays as the golden file holds it.
        var folder = Path.Combine(_root, round.FolderName);
        Directory.CreateDirectory(folder);
        File.Copy(Path.Combine(golden, "feedback.json"), Path.Combine(folder, "feedback.json"));
        var store = new RoundStore(new BundleTextRenderer(), _root, zone, () => round.EndedAt ?? round.StartedAt,
            displayPath: p => "/golden/" + Path.GetFileName(p));
        await store.ResumeAsync(round.FolderName);
        if (round.EndedAt is not null) await store.EndAsync();

        var written = Directory.GetFiles(folder).Select(f => Path.GetFileName(f)!)
            .Where(f => f.EndsWith(".json") || f.EndsWith(".md")).ToList();
        var expected = Directory.GetFiles(golden).Select(f => Path.GetFileName(f)!)
            .Where(f => !NotStoreOutputs.Contains(f)).ToList();

        Assert.Equal(expected.OrderBy(f => f, StringComparer.Ordinal), written.OrderBy(f => f, StringComparer.Ordinal));
        Assert.Contains("feedback.json", expected);
        Assert.Contains("manifest.md", expected);
        Assert.Contains("prompt.md", expected);
        foreach (var file in expected)
        {
            var want = File.ReadAllBytes(Path.Combine(golden, file));
            var got = File.ReadAllBytes(Path.Combine(folder, file));
            Assert.True(want.SequenceEqual(got), $"{name}/{file} differs from the golden file");
        }
    }
}
