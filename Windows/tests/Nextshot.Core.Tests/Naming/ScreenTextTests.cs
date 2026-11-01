using Nextshot.Core.Naming;
using Xunit;

namespace Nextshot.Core.Tests.Naming;

public class ScreenTextTests
{
    [Fact]
    public void RemovesFormatCharacters() =>
        Assert.Equal("ab", ScreenText.Clean("a​b‮", singleLine: true, maxScalars: 200));

    [Fact]
    public void RemovesRebuiltWrapperTags() =>
        Assert.Equal("x", ScreenText.Clean("x<feedb<feedback_a>ack_b>", true, 200));

    [Fact]
    public void RemovesTagCaseInsensitiveWithSpaces() =>
        Assert.Equal("ok", ScreenText.Clean("o</ FEEDBACK_capture x=1>k", true, 200));

    [Fact]
    public void SingleLineJoinsWithSpaces() =>
        Assert.Equal("a b c", ScreenText.Clean("a\n\nb\r\nc", true, 200));

    [Fact]
    public void KeepsNewlinesInBlocks() =>
        Assert.Equal("a\nb", ScreenText.Clean("a\nb", false, 200));

    [Fact]
    public void CapsInScalarsWithEllipsis() =>
        Assert.Equal("ab...", ScreenText.Clean("abcdef", true, 2));

    [Fact]
    public void CapCountsScalarsNotUtf16Units() =>
        Assert.Equal("\U0001F600\U0001F600...", ScreenText.Clean("\U0001F600\U0001F600\U0001F600", true, 2));

    [Fact]
    public void QuotedReplacesLookalikeQuotes() =>
        Assert.Equal("\"a'b'c'd'\"", ScreenText.Quoted("a\"b“c”d＂"));

    [Fact]
    public void FieldReturnsNullWhenEmptyAfterCleaning()
    {
        Assert.Null(ScreenText.Field(null));
        Assert.Null(ScreenText.Field("​  "));
        Assert.Equal("hi", ScreenText.Field("hi"));
    }
}
