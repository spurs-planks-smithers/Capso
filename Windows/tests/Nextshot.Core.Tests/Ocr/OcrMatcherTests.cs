using Nextshot.Core.Model;
using Nextshot.Core.Ocr;
using Xunit;

namespace Nextshot.Core.Tests.Ocr;

// Ported from Packages/FeedbackKit/Tests/FeedbackKitTests/OCRMatcherTests.swift (7 cases).
public class OcrMatcherTests
{
    private static readonly List<FeedbackTextLine> Lines = new()
    {
        new("Starter $19/mo", new FeedbackBox(480, 225, 640, 255)),
        new("Compare plans", new FeedbackBox(900, 620, 1100, 660)),
        new("Billed annually", new FeedbackBox(320, 810, 450, 830)),
        new("Footer", new FeedbackBox(10, 1700, 90, 1720)),
    };

    private static string? Match(FeedbackMark mark) =>
        OcrMatcher.AssignText(new[] { mark }, Lines).First().OcrText;

    [Fact]
    public void TextInsideBox()
    {
        var box = new FeedbackMark(MarkKind.Rectangle, new FeedbackBox(860, 580, 1500, 700));
        Assert.Equal("Compare plans", Match(box));
    }

    [Fact]
    public void TextAtArrowHead()
    {
        var arrow = new FeedbackMark(MarkKind.Arrow, new FeedbackBox(300, 100, 520, 240), point: new FeedbackPoint(520, 240));
        Assert.Equal("Starter $19/mo", Match(arrow));
    }

    [Fact]
    public void BadgeTipWins()
    {
        var badge = new FeedbackMark(
            MarkKind.Counter, new FeedbackBox(300, 800, 324, 824),
            badge: 1, point: new FeedbackPoint(520, 240));
        Assert.Equal("Starter $19/mo", Match(badge));
    }

    [Fact]
    public void TextNextToBadge()
    {
        var badge = new FeedbackMark(MarkKind.Counter, new FeedbackBox(288, 808, 312, 832), badge: 3);
        Assert.Equal("Billed annually", Match(badge));
    }

    [Fact]
    public void NothingNearby()
    {
        var badge = new FeedbackMark(MarkKind.Counter, new FeedbackBox(1500, 1200, 1524, 1224), badge: 4);
        Assert.Null(Match(badge));
    }

    [Fact]
    public void DropsRedactedLines()
    {
        var redaction = new FeedbackMark(MarkKind.Pixelate, new FeedbackBox(470, 220, 560, 250));
        var visible = OcrMatcher.RemovingRedacted(Lines, new[] { redaction });
        Assert.DoesNotContain("Starter $19/mo", visible.Select(l => l.Text));
        Assert.Equal(Lines.Count - 1, visible.Count);
    }

    [Fact]
    public void TextMarkHasNoOcr()
    {
        var text = new FeedbackMark(MarkKind.Text, new FeedbackBox(860, 580, 1500, 700), textOnImage: "too much padding");
        Assert.Null(Match(text));
    }

    // Added for the port.

    [Fact]
    public void AssignTextLeavesInputMarksUnchanged()
    {
        var box = new FeedbackMark(MarkKind.Rectangle, new FeedbackBox(860, 580, 1500, 700));
        var result = OcrMatcher.AssignText(new[] { box }, Lines);
        Assert.Null(box.OcrText);
        Assert.NotSame(box, result[0]);
    }

    [Fact]
    public void RegionMarkJoinsLinesInReadingOrder()
    {
        var lines = new List<FeedbackTextLine>
        {
            new("right", new FeedbackBox(200, 10, 260, 30)),
            new("below", new FeedbackBox(10, 50, 60, 70)),
            new("left", new FeedbackBox(100, 10, 160, 30)),
        };
        var region = new FeedbackMark(MarkKind.Rectangle, new FeedbackBox(0, 0, 400, 100));
        Assert.Equal("left right below", OcrMatcher.AssignText(new[] { region }, lines)[0].OcrText);
    }

    [Fact]
    public void NearestLineAtExactlyMaxDistanceMatches()
    {
        // The arrow tip is 60 px right of the line's right edge, inside the default reach.
        var lines = new List<FeedbackTextLine> { new("edge", new FeedbackBox(0, 0, 100, 20)) };
        var arrow = new FeedbackMark(MarkKind.Arrow, new FeedbackBox(0, 0, 160, 10), point: new FeedbackPoint(160, 10));
        Assert.Equal("edge", OcrMatcher.AssignText(new[] { arrow }, lines)[0].OcrText);
        var far = new FeedbackMark(MarkKind.Arrow, new FeedbackBox(0, 0, 161, 10), point: new FeedbackPoint(161, 10));
        Assert.Null(OcrMatcher.AssignText(new[] { far }, lines)[0].OcrText);
    }

    [Fact]
    public void NearestTieKeepsFirstLine()
    {
        var lines = new List<FeedbackTextLine>
        {
            new("first", new FeedbackBox(0, 0, 10, 10)),
            new("second", new FeedbackBox(30, 0, 40, 10)),
        };
        var arrow = new FeedbackMark(MarkKind.Arrow, new FeedbackBox(20, 0, 20, 5), point: new FeedbackPoint(20, 5));
        Assert.Equal("first", OcrMatcher.AssignText(new[] { arrow }, lines)[0].OcrText);
    }

    [Fact]
    public void BoxCenterUsesIntegerDivisionTowardZero()
    {
        // Center of (0..9) is 4, not 4.5. A line whose center is (4, 4) sits inside a box ending at 4.
        var line = new FeedbackTextLine("c", new FeedbackBox(0, 0, 9, 9));
        var box = new FeedbackMark(MarkKind.Rectangle, new FeedbackBox(0, 0, 4, 4));
        Assert.Equal("c", OcrMatcher.AssignText(new[] { box }, new[] { line })[0].OcrText);
    }
}
