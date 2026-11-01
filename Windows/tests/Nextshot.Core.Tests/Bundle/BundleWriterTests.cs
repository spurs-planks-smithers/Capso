using System.Text;
using Nextshot.Core.Bundle;
using Nextshot.Core.Json;
using Nextshot.Core.Model;
using Xunit;

namespace Nextshot.Core.Tests.Bundle;

public class BundleWriterTests
{
    private static readonly UTF8Encoding Utf8 = new(false);

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

    private static (FeedbackRound Round, TimeZoneInfo Zone, string Dir, string Folder) Load(string name)
    {
        var dir = Path.Combine(GoldenRoot(), name);
        var round = FeedbackRoundJson.Deserialize(File.ReadAllBytes(Path.Combine(dir, "feedback.json")));
        var zone = TimeZoneInfo.FindSystemTimeZoneById(File.ReadAllText(Path.Combine(dir, "timezone.txt")).Trim());
        return (round, zone, dir, "/golden/" + round.FolderName);
    }

    private static void AssertBytes(string dir, string file, string rendered)
    {
        var expected = File.ReadAllBytes(Path.Combine(dir, file));
        var actual = Utf8.GetBytes(rendered);
        Assert.False(actual.Length >= 3 && actual[0] == 0xEF && actual[1] == 0xBB && actual[2] == 0xBF, file + " has a BOM");
        Assert.DoesNotContain('\r', rendered);
        Assert.True(expected.SequenceEqual(actual), $"{Path.GetFileName(dir)}/{file} differs from the golden file");
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void ManifestMatchesGolden(string name)
    {
        var (round, zone, dir, folder) = Load(name);
        AssertBytes(dir, "manifest.md", ManifestWriter.Render(round, folder, zone));
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void RoundPromptMatchesGolden(string name)
    {
        var (round, _, dir, folder) = Load(name);
        AssertBytes(dir, "prompt.md", PromptBuilder.Render(round, folder));
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void CapturePromptsMatchGolden(string name)
    {
        var (round, _, dir, folder) = Load(name);
        var expectedFiles = Directory.GetFiles(dir, "*-prompt.md")
            .Select(f => Path.GetFileName(f)!)
            .Where(f => f != "selection-prompt.md")
            .OrderBy(f => f, StringComparer.Ordinal)
            .ToList();
        Assert.Equal(expectedFiles, round.Captures.Select(c => c.PromptFile).OrderBy(f => f, StringComparer.Ordinal).ToList());
        foreach (var capture in round.Captures)
            AssertBytes(dir, capture.PromptFile, PromptBuilder.RenderCapture(capture, folder));
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void SelectionPromptMatchesGolden(string name)
    {
        var (round, _, dir, folder) = Load(name);
        var entries = round.Captures.Select(c => new FeedbackSelectionEntry(round, c, folder));
        AssertBytes(dir, "selection-prompt.md", PromptBuilder.RenderSelection(entries));
    }

    // zip-readme.md comes from the zip planner and README writer, which belong to issue #218.

    // --- Windows path mode ---

    private static FeedbackRound Sample() => Load("la-october-pdt").Round;

    [Theory]
    [InlineData(@"C:\Users\Drew\AppData\Local\Nextshot\r1", "/mnt/c/Users/Drew/AppData/Local/Nextshot/r1")]
    [InlineData("D:/x/", "/mnt/d/x")]
    [InlineData("c:/Nextshot", "/mnt/c/Nextshot")]
    [InlineData("C:/", "/mnt/c/")]
    public void WslPathLowercasesDrive(string windows, string wsl) =>
        Assert.Equal(wsl, BundlePathMode.Windows.ToWslPath(windows));

    [Theory]
    [InlineData("/golden/x")]
    [InlineData("relative/path")]
    [InlineData("C:foo")]
    public void WslPathIsNullWithoutDriveRoot(string path) =>
        Assert.Null(BundlePathMode.Windows.ToWslPath(path));

    [Fact]
    public void WindowsFileUsesForwardSlashes()
    {
        var mode = new BundlePathMode.Windows(@"C:\Users\Drew\Nextshot\round-1\");
        Assert.Equal("C:/Users/Drew/Nextshot/round-1/manifest.md", mode.File("manifest.md"));
        Assert.Equal("C:/Users/Drew/Nextshot/round-1", mode.TagPath);
    }

    [Fact]
    public void WindowsRoundPromptHasBacktickPathsAndOneWslLine()
    {
        var round = Sample();
        var text = PromptBuilder.Render(round, new BundlePathMode.Windows(@"C:\Users\Drew\Nextshot\r1"));
        Assert.Contains("<feedback_bundle path=\"C:/Users/Drew/Nextshot/r1\" ", text);
        Assert.Contains("1. Open `C:/Users/Drew/Nextshot/r1/manifest.md`.", text);
        Assert.Single(text.Split('\n'), l => l.Contains("/mnt/c/Users/Drew/Nextshot/r1"));
        Assert.Contains("If you run in WSL, the same folder is `/mnt/c/Users/Drew/Nextshot/r1`.", text);
        Assert.DoesNotContain('\r', text);
    }

    [Fact]
    public void WindowsCapturePromptNamesFilesAndWslLine()
    {
        var round = Sample();
        var capture = round.Captures[0];
        var text = PromptBuilder.RenderCapture(capture, new BundlePathMode.Windows("C:/N/r1"));
        Assert.Contains($"- `C:/N/r1/{capture.ImageFile}` (annotated", text);
        Assert.Single(text.Split('\n'), l => l.Contains("/mnt/c/N/r1"));
    }

    [Fact]
    public void WindowsManifestHasFolderAndWslLines()
    {
        var round = Sample();
        var text = ManifestWriter.Render(round, new BundlePathMode.Windows("C:/N/r1"), TimeZoneInfo.Utc);
        Assert.Contains("\nFolder: C:/N/r1\nIf you run in WSL, the same folder is `/mnt/c/N/r1`.\nStarted: ", text);
        Assert.Contains($"- `C:/N/r1/{round.Captures[0].ImageFile}`", text);
    }

    [Fact]
    public void WindowsSelectionAddsWslLinePerCapture()
    {
        var round = Sample();
        var entries = round.Captures.Select(c => new FeedbackSelectionEntry(round, c, "C:/N/r1")).ToList();
        var text = PromptBuilder.RenderSelection(entries, windowsPaths: true);
        Assert.Equal(round.Captures.Count, text.Split('\n').Count(l => l.Contains("/mnt/c/N/r1")));
        Assert.Contains($"- `C:/N/r1/{round.Captures[0].ImageFile}`", text);
    }

    [Fact]
    public void AbsoluteSeparatorIsInjectable()
    {
        var mode = new BundlePathMode.Absolute(@"C:\N\r1", '\\');
        Assert.Equal(@"C:\N\r1\manifest.md", mode.File("manifest.md"));
    }

    [Fact]
    public void MacModeAddsNoWslLine()
    {
        var text = PromptBuilder.Render(Sample(), "/golden/x");
        Assert.DoesNotContain("WSL", text);
    }

    // --- Prompt options ---

    [Fact]
    public void RedoLineFollowsGoalLine()
    {
        var round = Sample();
        var text = PromptBuilder.Render(round, "/f", redo: true);
        var lines = text.Split('\n');
        Assert.StartsWith("Goal:", lines[1]);
        Assert.Equal(PromptBuilder.RedoLine, lines[2]);
        Assert.Equal(PromptBuilder.RedoLine, PromptBuilder.RenderCapture(round.Captures[0], "/f", redo: true).Split('\n')[2]);
        Assert.DoesNotContain(PromptBuilder.RedoLine, PromptBuilder.Render(round, "/f"));
    }

    [Fact]
    public void RelativeModeDropsPathAndUsesImageWording()
    {
        var round = Sample();
        var text = PromptBuilder.Render(round, new BundlePathMode.Relative("zip"));
        Assert.StartsWith("<feedback_bundle captures=", text);
        Assert.Contains("1. Open `manifest.md`.", text);
        Assert.Contains("up to 1568 tokens", text);
        Assert.Contains("-clean.jpg", text);
    }

    [Fact]
    public void RefinedAddsLineAndAuthority()
    {
        var round = Sample();
        var text = PromptBuilder.RenderCapture(round.Captures[0], "/f", refined: true);
        Assert.Contains(PromptBuilder.RefinedAuthorityLine, text);
        Assert.Contains(PromptBuilder.RefinedFile(round.Captures[0]), text);
    }
}
