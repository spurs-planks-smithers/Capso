using System.Text;
using System.Text.Json.Nodes;
using Nextshot.Core.Json;
using Nextshot.Core.Model;
using Xunit;

namespace Nextshot.Core.Tests;

public class JsonModelTests
{
    private static string GoldenRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            string candidate = Path.Combine(dir.FullName, "Windows", "golden");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("Windows/golden not found above " + AppContext.BaseDirectory);
    }

    public static IEnumerable<object[]> Fixtures() =>
        Directory.GetDirectories(GoldenRoot())
            .Select(d => Path.GetFileName(d))
            .Where(n => File.Exists(Path.Combine(GoldenRoot(), n, "feedback.json")))
            .OrderBy(n => n, StringComparer.Ordinal)
            .Select(n => new object[] { n });

    [Fact]
    public void GoldenFixturesAreFound()
    {
        Assert.True(Directory.Exists(GoldenRoot()));
        Assert.True(Fixtures().Count() >= 8);
    }

    [Theory]
    [MemberData(nameof(Fixtures))]
    public void RoundTripGivesIdenticalBytes(string caseName)
    {
        byte[] original = File.ReadAllBytes(Path.Combine(GoldenRoot(), caseName, "feedback.json"));
        Assert.NotEmpty(original);
        var round = FeedbackRoundJson.Deserialize(original);
        Assert.Equal(original, FeedbackRoundJson.SerializeBytes(round));
    }

    [Fact]
    public void EmptyArrayUsesFoundationForm()
    {
        var json = FoundationJsonWriter.Write(new JsonObject { ["a"] = new JsonArray() });
        Assert.Equal("{\n  \"a\" : [\n\n  ]\n}", json);
    }

    [Fact]
    public void ControlCharactersAndSlashesMatchFoundation()
    {
        var sb = new StringBuilder();
        for (int i = 0; i < 0x20; i++) sb.Append((char)i);
        sb.Append("\u007f\u2028\"\\/é😀");
        var json = FoundationJsonWriter.Write(new JsonObject { ["s"] = sb.ToString() });
        string expected = "{\n  \"s\" : \"\\u0000\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007\\b\\t\\n\\u000b\\f\\r\\u000e\\u000f"
            + "\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017\\u0018\\u0019\\u001a\\u001b\\u001c\\u001d\\u001e\\u001f"
            + "\u007f\u2028\\\"\\\\/é😀\"\n}";
        Assert.Equal(expected, json);
    }

    [Fact]
    public void KeysSortOrdinalAndNullsAreOmitted()
    {
        var json = FoundationJsonWriter.Write(new JsonObject { ["b"] = 1, ["B"] = 2, ["a"] = null });
        Assert.Equal("{\n  \"B\" : 2,\n  \"b\" : 1\n}", json);
    }

    [Fact]
    public void DatesDropFractionAndUseZ()
    {
        var d = new DateTimeOffset(2026, 10, 21, 2, 12, 0, 987, TimeSpan.FromHours(-7));
        Assert.Equal("2026-10-21T09:12:00Z", FoundationJsonWriter.FormatDate(d));
    }

    [Fact]
    public void ItemSplitPairsShapeWithNearestTouchingBadge()
    {
        var capture = new FeedbackCapture(1, "a.png", "a-clean.png", new PixelSize(100, 100),
            DateTimeOffset.UnixEpoch, marks: new List<FeedbackMark>
            {
                new(MarkKind.Counter, new FeedbackBox(10, 10, 20, 20), badge: 2),
                new(MarkKind.Counter, new FeedbackBox(30, 30, 40, 40), badge: 1),
                new(MarkKind.Rectangle, new FeedbackBox(25, 25, 60, 60)),
                new(MarkKind.Arrow, new FeedbackBox(0, 0, 5, 5)),
            });
        var (items, other) = FeedbackItems.Split(capture);
        Assert.Equal(new[] { "1.1", "1.2" }, items.Select(i => i.Id));
        Assert.NotNull(items[0].Shape);
        Assert.Null(items[1].Shape);
        Assert.Single(other);
        Assert.Equal("a", capture.FileStem);
        Assert.Equal("a-prompt.md", capture.PromptFile);
    }
}
