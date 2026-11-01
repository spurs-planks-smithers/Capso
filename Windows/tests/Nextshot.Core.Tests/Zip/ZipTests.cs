using System.IO.Compression;
using System.Text;
using Nextshot.Core.Bundle;
using Nextshot.Core.Imaging;
using Nextshot.Core.Json;
using Nextshot.Core.Model;
using Nextshot.Core.Zip;
using Xunit;

namespace Nextshot.Core.Tests.Zip;

/// <summary>Returns a JPEG-sized blob whose length depends on pixels and quality, so the ladder is testable.</summary>
internal sealed class FakeJpegEncoder : IJpegEncoder
{
    public double BytesPerPixelAtFullQuality { get; init; } = 0.1;
    public List<(PixelSize Size, double Quality)> Calls { get; } = [];

    public byte[] EncodeJpeg(byte[] imageBytes, PixelSize size, double quality)
    {
        Calls.Add((size, quality));
        var length = Math.Max(16, (int)(size.Width * (double)size.Height * quality * BytesPerPixelAtFullQuality));
        var data = new byte[length];
        // Pseudo-random bytes, so the archive cannot shrink them.
        var x = 12345u;
        for (var i = 0; i < length; i++) { x = x * 1664525u + 1013904223u; data[i] = (byte)(x >> 24); }
        data[0] = 0xFF; data[1] = 0xD8;
        return data;
    }
}

public class ZipTests
{
    private static readonly TimeZoneInfo Phoenix = TimeZoneInfo.FindSystemTimeZoneById("America/Phoenix");
    private static readonly DateTimeOffset Now = new(2026, 10, 25, 14, 0, 0, TimeSpan.Zero);

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
            .Where(d => File.Exists(Path.Combine(d, "zip-readme.md")))
            .Select(d => new object[] { Path.GetFileName(d) })
            .OrderBy(o => (string)o[0], StringComparer.Ordinal);

    [Fact]
    public void AtLeastEightGoldenCasesExist() => Assert.True(CaseNames().Count() >= 8);

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void ReadmeMatchesGolden(string name)
    {
        var dir = Path.Combine(GoldenRoot(), name);
        var round = FeedbackRoundJson.Deserialize(File.ReadAllBytes(Path.Combine(dir, "feedback.json")));
        var entries = round.Captures.Select(c => new FeedbackSelectionEntry(round, c, "/golden/" + round.FolderName)).ToList();
        var plan = ZipPlanner.Plan(ZipKind.Round, entries, "nextshot-round-golden", Now, 1);
        var actual = new UTF8Encoding(false).GetBytes(ZipReadme.Render(plan, ZipKind.Round, []));
        var expected = File.ReadAllBytes(Path.Combine(dir, "zip-readme.md"));
        Assert.DoesNotContain((byte)'\r', actual);
        Assert.True(expected.SequenceEqual(actual), $"{name}/zip-readme.md differs from the golden file");
    }

    // --- names and ladder ---

    [Fact]
    public void NamesRoundAndSelectionByKindTimeAndCount()
    {
        var time = new DateTimeOffset(2026, 10, 25, 13, 37, 0, TimeSpan.Zero); // 06:37 in Phoenix
        Assert.Equal("nextshot-round-2026-10-25-0637-3-captures", ZipName.Base(ZipKind.Round, time, 3, Phoenix));
        Assert.Equal("nextshot-round-2026-10-25-0637-1-capture", ZipName.Base(ZipKind.Round, time, 1, Phoenix));
        Assert.Equal("nextshot-selection-2026-10-25-0637-5-captures", ZipName.Base(ZipKind.Selection, time, 5, Phoenix));
    }

    [Fact]
    public void LadderLowersQualityFirstThenPixels()
    {
        Assert.Equal(new ZipStep(0.75, 0.75, 1), ZipLadder.Step(0));
        Assert.Equal(new ZipStep(0.75, 0.50, 1), ZipLadder.Step(1));
        Assert.Equal(new ZipStep(0.60, 0.50, 1), ZipLadder.Step(2));
        Assert.Equal(new ZipStep(0.60, 0.50, 0.85), ZipLadder.Step(3));
        Assert.Equal(0.85 * 0.85, ZipLadder.Step(4).PixelScale, 9);
        Assert.Equal(5_000_000, ZipLadder.BudgetBytes);
        Assert.Equal(1000, ZipLadder.FloorLongEdge);
    }

    [Fact]
    public void TargetSizeIsStandardTierAndNeverLargerThanSource()
    {
        var small = new PixelSize(932, 591);
        Assert.Equal(small, ZipLadder.TargetSize(small, 1));
        var large = new PixelSize(1988, 1134);
        var standard = ImageSizing.ResizedSize(large, ImageSizing.Limits.Standard);
        Assert.Equal(standard, ZipLadder.TargetSize(large, 1));
        Assert.True(ZipLadder.TargetSize(large, 0.85).Width < standard.Width);
    }

    [Fact]
    public void TallCaptureKeepsFloorOnItsLongEdge()
    {
        var tall = new PixelSize(900, 6000);
        var baseSize = ImageSizing.ResizedSize(tall, ImageSizing.Limits.Standard);
        var floored = ZipLadder.TargetSize(tall, 0.01);
        Assert.Equal(Math.Min(1000, Math.Max(baseSize.Width, baseSize.Height)), Math.Max(floored.Width, floored.Height));
    }

    // --- plan ---

    private static FeedbackCapture Capture(int index, string stem, DateTimeOffset at, int w = 1988, int h = 1134) =>
        new(index, stem + ".png", stem + "-clean.png", new PixelSize(w, h), at,
            marks:
            [
                new FeedbackMark(MarkKind.Counter, new FeedbackBox(100, 100, 140, 140), 1, instruction: "Fix this"),
                new FeedbackMark(MarkKind.Rectangle, new FeedbackBox(90, 90, 400, 200)),
            ]);

    private static FeedbackRound RoundOf(string folder, params FeedbackCapture[] captures) =>
        new("pricing page", "pricing-page", folder, new DateTimeOffset(2026, 10, 21, 2, 12, 0, TimeSpan.Zero), null, captures.ToList());

    private static List<FeedbackSelectionEntry> Entries(FeedbackRound round, string root) =>
        round.Captures.Select(c => new FeedbackSelectionEntry(round, c, Path.Combine(root, round.FolderName))).ToList();

    [Fact]
    public void RoundPlanKeepsIndexAndRenamesFiles()
    {
        var round = RoundOf("2026-10-20-1912-pricing-page", Capture(2, "1914-pricing-acme", Now), Capture(3, "1915-pricing-acme", Now));
        var plan = ZipPlanner.Plan(ZipKind.Round, Entries(round, "/src"), "nextshot-round-x", Now, 1);
        Assert.Equal([2, 3], plan.Round.Captures.Select(c => c.Index));
        Assert.Equal(["2-1914-pricing-acme.jpg", "3-1915-pricing-acme.jpg"], plan.Round.Captures.Select(c => c.ImageFile));
        Assert.Equal(["2-1914-pricing-acme-clean.jpg", "3-1915-pricing-acme-clean.jpg"], plan.Round.Captures.Select(c => c.CleanImageFile));
        Assert.Equal(["2-1914-pricing-acme-prompt.md", "3-1915-pricing-acme-prompt.md"], plan.Round.Captures.Select(c => c.PromptFile));
        Assert.Equal("nextshot-round-x", plan.Round.FolderName);
        Assert.Equal("pricing page", plan.Round.Name);
        Assert.Empty(plan.SourceRoundLines);
        Assert.Equal(4, plan.Images.Count);
        Assert.False(plan.Images[0].IsClean);
        Assert.True(plan.Images[1].IsClean);
        Assert.EndsWith("1914-pricing-acme-clean.png", plan.Images[1].SourcePath);
    }

    [Fact]
    public void SelectionPlanRenumbersByTimeAndListsSourceRounds()
    {
        var a = RoundOf("2026-10-20-1912-pricing-page",
            Capture(2, "1914-pricing-acme", new DateTimeOffset(2026, 10, 21, 2, 14, 0, TimeSpan.Zero)),
            Capture(3, "1915-pricing-acme", new DateTimeOffset(2026, 10, 21, 2, 15, 0, TimeSpan.Zero)));
        var b = RoundOf("2026-10-21-0900-other", Capture(1, "1914-pricing-acme", new DateTimeOffset(2026, 10, 21, 16, 5, 0, TimeSpan.Zero)));
        var entries = Entries(b, "/src").Concat(Entries(a, "/src").AsEnumerable().Reverse()).ToList();
        var plan = ZipPlanner.Plan(ZipKind.Selection, entries, "nextshot-selection-x", Now, 1);
        Assert.Equal([1, 2, 3], plan.Round.Captures.Select(c => c.Index));
        Assert.Equal(["1-1914-pricing-acme.jpg", "2-1915-pricing-acme.jpg", "3-1914-pricing-acme.jpg"], plan.Round.Captures.Select(c => c.ImageFile));
        Assert.Equal("selection", plan.Round.Name);
        Assert.Equal(Now, plan.Round.EndedAt);
        Assert.Equal(
        [
            "- 2026-10-20-1912-pricing-page: its captures 2 and 3, here 1 and 2",
            "- 2026-10-21-0900-other: its capture 1, here 3",
        ], plan.SourceRoundLines);
    }

    [Fact]
    public void MarksScaleToTheZipImage()
    {
        var source = Capture(1, "1914-pricing-acme", Now, 3000, 1700);
        var plan = ZipPlanner.Plan(ZipKind.Round, Entries(RoundOf("r", source), "/src"), "z", Now, 1);
        var capture = plan.Round.Captures[0];
        Assert.Equal(ImageSizing.ResizedSize(source.Size, ImageSizing.Limits.Standard), capture.Size);
        Assert.Equal(source.Marks.Count, capture.Marks.Count);
        Assert.True(capture.Marks[1].Box.X2 < source.Marks[1].Box.X2);
        Assert.Equal(MarkKind.Rectangle, capture.Marks[1].Kind);
        Assert.Equal("Fix this", capture.Marks[0].Instruction);
    }

    [Fact]
    public void FloorStopsTheLadder()
    {
        var tall = Capture(1, "tall", Now, 900, 6000);
        var round = RoundOf("r", tall);
        Assert.True(ZipPlanner.Plan(ZipKind.Round, Entries(round, "/src"), "z", Now, 0.01).AtFloor);
        Assert.False(ZipPlanner.Plan(ZipKind.Round, Entries(round, "/src"), "z", Now, 1).AtFloor);
    }

    // --- writer ---

    private sealed class Fixture : IDisposable
    {
        public string Base = Path.Combine(Path.GetTempPath(), "nextshot-ziptest-" + Guid.NewGuid().ToString("N"));
        public string Root => Path.Combine(Base, "src");
        public string Destination => Path.Combine(Base, "Downloads");
        public Fixture() { Directory.CreateDirectory(Root); Directory.CreateDirectory(Destination); }
        public void Dispose() { try { Directory.Delete(Base, true); } catch (IOException) { } }

        public List<FeedbackSelectionEntry> Write(FeedbackRound round)
        {
            var folder = Path.Combine(Root, round.FolderName);
            Directory.CreateDirectory(folder);
            foreach (var c in round.Captures)
            {
                File.WriteAllBytes(Path.Combine(folder, c.ImageFile), [1, 2, 3]);
                File.WriteAllBytes(Path.Combine(folder, c.CleanImageFile), [1, 2, 3]);
            }
            return Entries(round, Root);
        }
    }

    private static FeedbackRound TwoCaptureRound() =>
        RoundOf("2026-10-20-1912-pricing-page", Capture(1, "1914-pricing-acme", Now), Capture(2, "1915-pricing-acme", Now));

    [Fact]
    public void WrittenZipExtractsToTheExpectedEntryList()
    {
        using var f = new Fixture();
        var entries = f.Write(TwoCaptureRound());
        var result = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        Assert.Equal(0, result.StepIndex);
        Assert.False(result.OverBudget);
        Assert.Equal(2, result.CaptureCount);
        var name = Path.GetFileNameWithoutExtension(result.Path);
        Assert.Equal("nextshot-round-2026-10-20-1912-2-captures".Length, name.Length);
        Assert.StartsWith("nextshot-round-", name);

        using var zip = ZipFile.OpenRead(result.Path);
        var names = zip.Entries.Select(e => e.FullName).OrderBy(n => n, StringComparer.Ordinal).ToList();
        string[] expected =
        [
            "1-1914-pricing-acme-clean.jpg", "1-1914-pricing-acme-prompt.md", "1-1914-pricing-acme.jpg",
            "2-1915-pricing-acme-clean.jpg", "2-1915-pricing-acme-prompt.md", "2-1915-pricing-acme.jpg",
            "README.md", "feedback.json", "manifest.md",
        ];
        Assert.Equal(expected.Select(e => name + "/" + e).OrderBy(n => n, StringComparer.Ordinal), names);
        Assert.DoesNotContain(names, n => n.Contains('\\') || n.Contains("__MACOSX") || Path.GetFileName(n).StartsWith("._"));
        Assert.All(names, n => Assert.StartsWith(name + "/", n));

        // Text files match what the plan renders, and name no source path.
        string Text(string file) { using var r = new StreamReader(zip.GetEntry(name + "/" + file)!.Open(), new UTF8Encoding(false)); return r.ReadToEnd(); }
        var readme = Text("README.md");
        Assert.StartsWith("# Nextshot feedback export\n", readme);
        Assert.Contains("<feedback_bundle captures=\"2\" ", readme);
        Assert.DoesNotContain(f.Root, readme);
        Assert.DoesNotContain(".png", Text("manifest.md"));
        var json = FeedbackRoundJson.Deserialize(Text("feedback.json"));
        Assert.Equal(name, json.FolderName);
        Assert.Equal("1-1914-pricing-acme.jpg", json.Captures[0].ImageFile);
    }

    [Fact]
    public void LadderStepsDownUntilTheZipFitsTheBudget()
    {
        using var f = new Fixture();
        var entries = f.Write(RoundOf("r1", Capture(1, "a", Now, 1988, 1134), Capture(2, "b", Now, 1988, 1134)));
        var encoder = new FakeJpegEncoder { BytesPerPixelAtFullQuality = 0.8 };
        // Step 0: 4 images at ~1.7 MB each. Pick a budget that needs pixel steps.
        var big = ZipWriter.Write(ZipKind.Round, entries, encoder, f.Destination, Now, Phoenix, budget: int.MaxValue);
        Assert.Equal(0, big.StepIndex);

        var small = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder { BytesPerPixelAtFullQuality = 0.8 }, f.Destination, Now, Phoenix, budget: 2_000_000);
        Assert.True(small.StepIndex >= 3, "pixel steps were needed, got step " + small.StepIndex);
        Assert.True(small.Bytes <= 2_000_000);
        Assert.False(small.OverBudget);
        Assert.NotEqual(big.Path, small.Path);
    }

    [Fact]
    public void LadderEndsAtTheFloorAndReportsOverBudget()
    {
        using var f = new Fixture();
        var entries = f.Write(RoundOf("r1", Capture(1, "a", Now, 1988, 1134)));
        var encoder = new FakeJpegEncoder { BytesPerPixelAtFullQuality = 0.8 };
        var result = ZipWriter.Write(ZipKind.Round, entries, encoder, f.Destination, Now, Phoenix, budget: 10_000);
        Assert.True(result.OverBudget);
        // The last calls sit at the 1000 px floor with the lowest qualities.
        var last = encoder.Calls[^1];
        Assert.Equal(1000, Math.Max(last.Size.Width, last.Size.Height));
        Assert.Equal(0.5, last.Quality);
        Assert.Contains(encoder.Calls, c => c.Quality == 0.6);
    }

    [Fact]
    public void LadderStepQualitiesAreUsedPerImageKind()
    {
        using var f = new Fixture();
        var entries = f.Write(RoundOf("r1", Capture(1, "a", Now, 1988, 1134)));
        var encoder = new FakeJpegEncoder { BytesPerPixelAtFullQuality = 0.8 };
        ZipWriter.Write(ZipKind.Round, entries, encoder, f.Destination, Now, Phoenix, budget: int.MaxValue);
        Assert.Equal([0.75, 0.75], encoder.Calls.Select(c => c.Quality));
    }

    [Fact]
    public void TakenNameGetsSuffix()
    {
        using var f = new Fixture();
        var entries = f.Write(TwoCaptureRound());
        var first = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        var second = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        Assert.Equal(Path.GetFileNameWithoutExtension(first.Path) + "-2", Path.GetFileNameWithoutExtension(second.Path));
        Assert.True(File.Exists(first.Path));
        // A folder from an earlier unzip also takes the name.
        Directory.CreateDirectory(Path.Combine(f.Destination, Path.GetFileNameWithoutExtension(first.Path) + "-3"));
        var third = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        Assert.EndsWith("-4.zip", third.Path);
    }

    [Fact]
    public void MissingImageIsLeftOutAndNamed()
    {
        using var f = new Fixture();
        var entries = f.Write(TwoCaptureRound());
        File.Delete(Path.Combine(f.Root, "2026-10-20-1912-pricing-page", "1915-pricing-acme-clean.png"));
        var result = ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        Assert.Equal(1, result.CaptureCount);
        Assert.Equal([new BasketKey("2026-10-20-1912-pricing-page", 2)], result.Missing);
        using var zip = ZipFile.OpenRead(result.Path);
        var readme = zip.Entries.Single(e => e.Name == "README.md");
        using var r = new StreamReader(readme.Open());
        Assert.Contains("Left out (image file not found): round 2026-10-20-1912-pricing-page, its capture 2.", r.ReadToEnd());
        Assert.EndsWith("-1-capture.zip", result.Path);
    }

    [Fact]
    public void NoCapturesThrows()
    {
        using var f = new Fixture();
        var entries = Entries(TwoCaptureRound(), f.Root); // no files on disk
        var e = Assert.Throws<ZipException>(() => ZipWriter.Write(ZipKind.Round, entries, new FakeJpegEncoder(), f.Destination, Now, Phoenix));
        Assert.Equal(ZipErrorKind.NoCaptures, e.Kind);
        Assert.Equal("Nothing to zip.\nNo capture was found with both of its images.", ZipMessages.Failure(e));
        Assert.Empty(Directory.GetFiles(f.Destination));
    }

    [Fact]
    public void SelectionZipManifestListsSources()
    {
        using var f = new Fixture();
        var a = f.Write(TwoCaptureRound());
        var b = f.Write(RoundOf("2026-10-21-0900-other", Capture(1, "0900-other", Now.AddDays(1))));
        var result = ZipWriter.Write(ZipKind.Selection, a.Concat(b).ToList(), new FakeJpegEncoder(), f.Destination, Now, Phoenix);
        Assert.Contains("nextshot-selection-", result.Path);
        using var zip = ZipFile.OpenRead(result.Path);
        using var r = new StreamReader(zip.Entries.Single(e => e.Name == "manifest.md").Open());
        var manifest = r.ReadToEnd();
        Assert.Contains("Source rounds:", manifest);
        Assert.Contains("- 2026-10-20-1912-pricing-page: its captures 1 and 2, here 1 and 2", manifest);
    }

    [Fact]
    public void StagingIsRemoved()
    {
        using var f = new Fixture();
        var staging = Path.Combine(f.Base, "staging");
        Directory.CreateDirectory(staging);
        ZipWriter.Write(ZipKind.Round, f.Write(TwoCaptureRound()), new FakeJpegEncoder(), f.Destination, Now, Phoenix, stagingRoot: staging);
        Assert.Empty(Directory.GetFileSystemEntries(staging));
    }

    [Fact]
    public void ReadyMessageAndSizeText()
    {
        Assert.Equal("Zip copied: a.zip, 48 KB.\nPaste it into Mail, Slack, or Teams. It is also in Downloads.", ZipMessages.Ready("a.zip", 48_000, false));
        Assert.Contains("2.4 MB (over the 5 MB goal)", ZipMessages.Ready("a.zip", 2_400_000, true));
        Assert.Equal("1 KB", ZipMessages.SizeText(10));
        Assert.Equal("Zip not written.\nA capture image could not be read.", ZipMessages.Failure(new ExportImageException(ExportImageErrorKind.Unreadable)));
        Assert.Equal(ZipMessages.NoDownloadsAccess, ZipMessages.Failure(new UnauthorizedAccessException()));
    }
}
