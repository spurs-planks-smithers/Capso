using Nextshot.Core.Naming;
using Xunit;

namespace Nextshot.Core.Tests.Naming;

public class FeedbackNamingTests
{
    // Mirror of Windows/golden/slug-corpus/slugs.tsv (PR #249), made by the Mac code.
    public static TheoryData<string, string> SlugRows => new()
    {
        { "Straße", "strasse" },
        { "STRAẞE", "strasse" },
        { "oﬁce ﬁle", "ofice-file" },
        { "İstanbul", "istanbul" },
        { "i̇stanbul", "istanbul" },
        { "øresund", "resund" },
        { "Łódź", "odz" },
        { "ład", "ad" },
        { "đường", "uong" },
        { "Đại", "ai" },
        { "ＡＢＣ１２３", "abc123" },
        { "Café Crème", "cafe-creme" },
        { "Pricing | Acme", "pricing-acme" },
        { "", "feedback" },
        { "!!!", "feedback" },
        { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bcd", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
    };

    [Theory]
    [MemberData(nameof(SlugRows))]
    public void SlugMatchesMac(string input, string expected) =>
        Assert.Equal(expected, FeedbackNaming.Slug(input));

    [Fact]
    public void SlugMatchesEveryRowOfCorpusFile()
    {
        var dir = AppContext.BaseDirectory;
        string? path = null;
        for (var d = new DirectoryInfo(dir); d is not null; d = d.Parent)
        {
            var candidate = Path.Combine(d.FullName, "Windows", "golden", "slug-corpus", "slugs.tsv");
            var local = Path.Combine(d.FullName, "golden", "slug-corpus", "slugs.tsv");
            if (File.Exists(candidate)) { path = candidate; break; }
            if (File.Exists(local)) { path = local; break; }
        }
        Assert.True(path is not null, "slugs.tsv not found");
        var rows = File.ReadAllLines(path!).Where(l => !string.IsNullOrWhiteSpace(l)).ToList();
        Assert.NotEmpty(rows);
        foreach (var row in rows)
        {
            var parts = row.Split('\t');
            Assert.Equal(parts[1], FeedbackNaming.Slug(parts[0]));
        }
    }

    [Fact]
    public void SlugCapsAtFortyAndTrimsHyphen()
    {
        var slug = FeedbackNaming.Slug(new string('a', 39) + " b");
        Assert.Equal(new string('a', 39), slug);
        Assert.Equal(40, FeedbackNaming.Slug(new string('a', 60)).Length);
    }

    private static readonly DateTimeOffset Oct = DateTimeOffset.Parse("2026-10-21T02:14:00Z");
    private static readonly DateTimeOffset Jan = DateTimeOffset.Parse("2026-01-21T03:14:00Z");

    [Theory]
    [InlineData("America/Los_Angeles", true, "Capture: \"Pricing | Acme\", 2026-10-20 19:14 PDT")]
    [InlineData("America/Phoenix", true, "Capture: \"Pricing | Acme\", 2026-10-20 19:14 MST")]
    [InlineData("America/Los_Angeles", false, "Capture: \"Pricing | Acme\", 2026-01-20 19:14 PST")]
    public void CaptureNameMatchesGoldenManifests(string zone, bool october, string expected)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(zone);
        Assert.Equal(expected,
            FeedbackNaming.CaptureName("Pricing | Acme", null, october ? Oct : Jan, tz, quoted: true));
    }

    [Fact]
    public void FolderAndStem()
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById("America/Los_Angeles");
        Assert.Equal("2026-10-20-1914-pricing-acme", FeedbackNaming.FolderName(Oct, "pricing-acme", tz));
        Assert.Equal("1914-pricing-acme", FeedbackNaming.CaptureFileStem("Pricing | Acme", null, Oct, tz));
        Assert.Equal("1914-capture", FeedbackNaming.CaptureFileStem(null, null, Oct, tz));
        Assert.Equal("Capture: 2026-10-20 19:14 PDT", FeedbackNaming.CaptureName(null, "  ", Oct, tz));
    }

    [Theory]
    [InlineData("Europe/London", "2025-10-20T22:40:00Z", "2025-10-20 23:40 GMT+1")]
    [InlineData("Europe/London", "2026-01-09T23:06:00Z", "2026-01-09 23:06 GMT")]
    [InlineData("Asia/Tokyo", "2025-10-20T22:40:00Z", "2025-10-21 07:40 GMT+9")]
    [InlineData("Asia/Kolkata", "2025-10-20T22:40:00Z", "2025-10-21 04:10 GMT+5:30")]
    [InlineData("America/Sao_Paulo", "2025-10-20T22:40:00Z", "2025-10-20 19:40 GMT-3")]
    [InlineData("America/Halifax", "2026-01-09T23:06:00Z", "2026-01-09 19:06 AST")]
    [InlineData("America/Denver", "2026-01-09T23:06:00Z", "2026-01-09 16:06 MST")]
    [InlineData("America/Anchorage", "2025-10-20T22:40:00Z", "2025-10-20 14:40 AKDT")]
    [InlineData("Pacific/Honolulu", "2025-10-20T22:40:00Z", "2025-10-20 12:40 HST")]
    [InlineData("America/Phoenix", "2026-01-09T23:06:00Z", "2026-01-09 16:06 MST")]
    public void ZoneTextMatchesFoundation(string zone, string instant, string expected)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(zone);
        Assert.Equal(expected,
            FeedbackNaming.Format(DateTimeOffset.Parse(instant), "yyyy-MM-dd HH:mm zzz", tz));
    }

    [Fact]
    public void UniqueNameAddsSuffix()
    {
        var taken = new HashSet<string> { "a", "a-2" };
        Assert.Equal("a-3", FeedbackNaming.UniqueName("a", taken.Contains));
        Assert.Equal("b", FeedbackNaming.UniqueName("b", taken.Contains));
    }
}
