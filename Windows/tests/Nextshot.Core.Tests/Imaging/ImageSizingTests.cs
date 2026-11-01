using Nextshot.Core.Imaging;
using Nextshot.Core.Model;
using Xunit;

namespace Nextshot.Core.Tests.Imaging;

// Ported from Packages/FeedbackKit/Tests/FeedbackKitTests/ImageSizingTests.swift (8 cases).
public class ImageSizingTests
{
    [Fact]
    public void VisualTokensRoundUpToPatches()
    {
        Assert.Equal(2145, ImageSizing.VisualTokens(new PixelSize(1075, 1520)));
        Assert.Equal(2, ImageSizing.VisualTokens(new PixelSize(28, 29)));
    }

    [Fact]
    public void A4ScanAtStandardTier() =>
        Assert.Equal(new PixelSize(924, 1307), ImageSizing.ResizedSize(new PixelSize(1075, 1520), ImageSizing.Limits.Standard));

    [Fact]
    public void FullHdAtStandardTier() =>
        Assert.Equal(new PixelSize(1456, 819), ImageSizing.ResizedSize(new PixelSize(1920, 1080), ImageSizing.Limits.Standard));

    [Fact]
    public void FourKAtHighResolutionTier() =>
        Assert.Equal(new PixelSize(2576, 1449), ImageSizing.ResizedSize(new PixelSize(3840, 2160), ImageSizing.Limits.HighResolution));

    [Fact]
    public void KeepsImageThatFitsTheLimits()
    {
        Assert.Equal(new PixelSize(200, 200), ImageSizing.ResizedSize(new PixelSize(200, 200), ImageSizing.Limits.Standard));
        Assert.Equal(new PixelSize(1920, 1080), ImageSizing.ResizedSize(new PixelSize(1920, 1080), ImageSizing.Limits.HighResolution));
    }

    // Expected sizes come from Anthropic's Python reference run with max_edge=2000 and max_tokens=4784.
    [Theory]
    [InlineData(3840, 2160, 1988, 1118)]
    [InlineData(2880, 1800, 1988, 1242)]
    [InlineData(1170, 2532, 919, 1988)]
    [InlineData(1920, 1080, 1920, 1080)]
    public void ExportLimits(int w, int h, int expectedW, int expectedH)
    {
        var size = ImageSizing.ResizedSize(new PixelSize(w, h), ImageSizing.Limits.FeedbackExport);
        Assert.Equal(new PixelSize(expectedW, expectedH), size);
        Assert.True(Math.Max(size.Width, size.Height) <= 2000);
        Assert.True(ImageSizing.VisualTokens(size) <= 4784);
    }

    [Fact]
    public void ScalesBox()
    {
        var box = ImageSizing.Scale(
            new PixelRect(100, 50, 200, 100),
            new PixelSize(3840, 2160),
            new PixelSize(1988, 1118));
        // 100 * 1988/3840 = 51.8, 50 * 1118/2160 = 25.9, 300 * 1988/3840 = 155.3, 150 * 1118/2160 = 77.6
        Assert.Equal(new FeedbackBox(52, 26, 155, 78), box);
    }

    [Fact]
    public void ScalesAndClampsPoint()
    {
        var source = new PixelSize(3840, 2160);
        var target = new PixelSize(1988, 1118);
        Assert.Equal(new FeedbackPoint(994, 559), ImageSizing.Scale(1920, 1080, source, target));
        Assert.Equal(new FeedbackPoint(1988, 0), ImageSizing.Scale(4000, -5, source, target));
    }

    // Added for the port: midpoint cases that show the rounding mode.

    [Fact]
    public void ShortEdgeMidpointRoundsToEven()
    {
        // 2000x1000 with a 3-token cap ends at long edge 57. 57 / 2 = 28.5, and ToEven gives 28 (AwayFromZero would give 29).
        var size = ImageSizing.ResizedSize(new PixelSize(2000, 1000), new ImageSizing.Limits(100000, 3));
        Assert.Equal(new PixelSize(57, 28), size);
    }

    [Fact]
    public void ShortEdgeMidpointRoundsToEvenWhenPortrait()
    {
        var size = ImageSizing.ResizedSize(new PixelSize(1000, 2000), new ImageSizing.Limits(100000, 3));
        Assert.Equal(new PixelSize(28, 57), size);
    }

    [Theory]
    [InlineData(0.5, 1)]
    [InlineData(1.5, 2)]
    [InlineData(2.5, 3)]
    [InlineData(3.5, 4)]
    public void ScaleMidpointRoundsAwayFromZero(double value, int expected)
    {
        // Source and target are equal, so the mapped value stays at x.5. ToEven would give 0, 2, 2, 4.
        var size = new PixelSize(10, 10);
        Assert.Equal(new FeedbackPoint(expected, expected), ImageSizing.Scale(value, value, size, size));
    }

    [Fact]
    public void ScaleStandardizesNegativeRect()
    {
        var box = ImageSizing.Scale(new PixelRect(300, 150, -200, -100), new PixelSize(3840, 2160), new PixelSize(1988, 1118));
        Assert.Equal(new FeedbackBox(52, 26, 155, 78), box);
    }

    [Fact]
    public void ScaleWithEmptySourceGivesZero() =>
        Assert.Equal(new FeedbackPoint(0, 0), ImageSizing.Scale(5, 5, new PixelSize(0, 0), new PixelSize(10, 10)));

    [Fact]
    public void NonPositiveSizeIsReturnedUnchanged() =>
        Assert.Equal(new PixelSize(0, 50), ImageSizing.ResizedSize(new PixelSize(0, 50), ImageSizing.Limits.Standard));
}
