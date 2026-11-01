using Nextshot.Core.Notes;
using Xunit;

namespace Nextshot.Core.Tests.Notes;

// Ported from Packages/FeedbackKit/Tests/FeedbackKitTests/NoteParserTests.swift (7 cases).
public class NoteParserTests
{
    private static HashSet<int> Badges(params int[] n) => new(n);

    [Fact]
    public void BadgeLineBecomesInstruction()
    {
        var result = NoteParser.Parse("1: fix price", Badges(1, 2));
        Assert.Equal(new Dictionary<int, string> { [1] = "fix price" }, result.Instructions);
        Assert.Null(result.Note);
    }

    [Fact]
    public void OtherLinesStayInNote()
    {
        var result = NoteParser.Parse("The plan cards feel cramped.\n2: Make this the primary button", Badges(1, 2));
        Assert.Equal(new Dictionary<int, string> { [2] = "Make this the primary button" }, result.Instructions);
        Assert.Equal("The plan cards feel cramped.", result.Note);
    }

    [Fact]
    public void SplitsAtSemicolons()
    {
        var result = NoteParser.Parse("1: fix price; 2: make primary; cards feel cramped", Badges(1, 2));
        Assert.Equal(new Dictionary<int, string> { [1] = "fix price", [2] = "make primary" }, result.Instructions);
        Assert.Equal("cards feel cramped", result.Note);
    }

    [Fact]
    public void UnknownNumberStaysInNote()
    {
        var result = NoteParser.Parse("10:30 meeting; 5: check this", Badges(1));
        Assert.Empty(result.Instructions);
        Assert.Equal("10:30 meeting; 5: check this", result.Note);
    }

    [Fact]
    public void EmptyInstructionStaysInNote()
    {
        var result = NoteParser.Parse("1:", Badges(1));
        Assert.Empty(result.Instructions);
        Assert.Equal("1:", result.Note);
    }

    [Fact]
    public void RepeatedBadgeJoinsInstructions()
    {
        var result = NoteParser.Parse("1: fix price; 1: use bold", Badges(1));
        Assert.Equal(new Dictionary<int, string> { [1] = "fix price; use bold" }, result.Instructions);
    }

    [Fact]
    public void BlankTextHasNoNote()
    {
        var result = NoteParser.Parse("   \n ", Badges(1));
        Assert.Null(result.Note);
        Assert.Empty(result.Instructions);
    }

    // Added for the port.

    [Fact]
    public void CrLfIsOneLineBreak()
    {
        var result = NoteParser.Parse("first\r\n1: fix\r\nlast", Badges(1));
        Assert.Equal("first\nlast", result.Note);
        Assert.Equal("fix", result.Instructions[1]);
    }

    [Fact]
    public void OverflowingBadgeNumberStaysInNote()
    {
        var result = NoteParser.Parse("99999999999999999999: huge", Badges(1));
        Assert.Empty(result.Instructions);
        Assert.Equal("99999999999999999999: huge", result.Note);
    }

    [Fact]
    public void NonAsciiDigitsAreNotBadgeNumbers()
    {
        // Arabic-Indic digit one.
        var result = NoteParser.Parse("١: fix", Badges(1));
        Assert.Empty(result.Instructions);
        Assert.Equal("١: fix", result.Note);
    }

    [Fact]
    public void KeptPartsRejoinWithSemicolonAndTrim()
    {
        var result = NoteParser.Parse("a; 1: x ;b", Badges(1));
        Assert.Equal("a;b", result.Note);
        Assert.Equal("x", result.Instructions[1]);
    }
}
