// Port of Packages/FeedbackKit/Sources/FeedbackKit/ScreenText.swift
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Nextshot.Core.Naming;

/// <summary>
/// Cleans text that comes from the screen (OCR, window titles, app names) or from
/// another app. It removes invisible format characters (Unicode category Cf: zero-width,
/// bidirectional, tag characters), removes wrapper-tag lookalikes (any tag whose name
/// starts with <c>feedback_</c>) until none can be rebuilt, and caps the length in
/// Unicode scalars.
/// </summary>
public static class ScreenText
{
    public const int MaxFieldLength = 200;
    public const int MaxBlockLength = 5000;
    internal const int MaxNameLength = 100;

    private static readonly Regex WrapperTag = new(
        @"</?\s*feedback_[^>]*>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    // Foundation's CharacterSet.newlines: LF, VT, FF, CR, NEL, LS, PS.
    private static readonly char[] Newlines = ['\n', '\u000B', '\u000C', '\r', '\u0085', '\u2028', '\u2029'];

    public static string Clean(string text, bool singleLine, int maxScalars)
    {
        var visible = new StringBuilder(text.Length);
        foreach (var rune in text.EnumerateRunes())
        {
            if (Rune.GetUnicodeCategory(rune) != UnicodeCategory.Format)
                visible.Append(rune.ToString());
        }
        var result = visible.ToString();

        if (singleLine)
        {
            result = string.Join(" ", result.Split(Newlines).Where(p => p.Length > 0));
        }

        string previous;
        do
        {
            previous = result;
            result = WrapperTag.Replace(result, "");
        } while (result != previous);

        if (ScalarCount(result) > maxScalars)
        {
            var sb = new StringBuilder();
            var taken = 0;
            foreach (var rune in result.EnumerateRunes())
            {
                if (taken++ >= maxScalars) break;
                sb.Append(rune.ToString());
            }
            result = sb + "...";
        }
        return result;
    }

    /// <summary>
    /// Wraps screen text in double quotes. Straight and lookalike double quotes inside
    /// become single quotes, so the text cannot close the quote.
    /// </summary>
    public static string Quoted(string text)
    {
        var inner = text;
        foreach (var mark in new[] { "\"", "“", "”", "＂" })
            inner = inner.Replace(mark, "'", StringComparison.Ordinal);
        return $"\"{inner}\"";
    }

    /// <summary>Clean for an optional field. Text that is empty after cleaning becomes null.</summary>
    public static string? Field(string? text, bool singleLine = true, int maxScalars = MaxFieldLength)
    {
        if (text is null) return null;
        var cleaned = Clean(text, singleLine, maxScalars);
        return string.IsNullOrWhiteSpace(cleaned) ? null : cleaned;
    }

    private static int ScalarCount(string s)
    {
        var n = 0;
        foreach (var _ in s.EnumerateRunes()) n++;
        return n;
    }
}
