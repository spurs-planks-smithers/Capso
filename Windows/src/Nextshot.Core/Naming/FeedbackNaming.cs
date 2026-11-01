// Port of Packages/FeedbackKit/Sources/FeedbackKit/FeedbackNaming.swift
using System.Globalization;
using System.Text;

namespace Nextshot.Core.Naming;

/// <summary>File and folder names inside the store's root folder.</summary>
public static class FeedbackNaming
{
    public const string DefaultSlug = "feedback";
    public const int MaxSlugLength = 40;
    private const int MaxLabelLength = 80;

    // What Foundation's case folding expands to ASCII. Letters Foundation leaves alone
    // (ø, ł, đ, æ, œ, þ, ð, ı) are not here: they are dropped, as on the Mac.
    private static readonly Dictionary<int, string> Folding = new()
    {
        ['ß'] = "ss", ['ẞ'] = "ss", ['ſ'] = "s", ['ẛ'] = "s", ['ŉ'] = "n", ['ẚ'] = "a",
        ['ﬀ'] = "ff", ['ﬁ'] = "fi", ['ﬂ'] = "fl", ['ﬃ'] = "ffi", ['ﬄ'] = "ffl", ['ﬅ'] = "st", ['ﬆ'] = "st",
    };

    /// <summary>
    /// Lowercase ASCII letters and digits joined by single hyphens. Accents are folded
    /// ("Café" becomes "cafe"). Other characters split words.
    /// </summary>
    public static string Slug(string name)
    {
        var slug = new StringBuilder();
        var needsHyphen = false;
        foreach (var rune in name.Normalize(NormalizationForm.FormD).EnumerateRunes())
        {
            if (Rune.GetUnicodeCategory(rune) == UnicodeCategory.NonSpacingMark)
                continue; // a mark joins its letter and never splits a word

            var v = rune.Value;
            string piece;
            if (v is >= 0xFF01 and <= 0xFF5E) piece = ((char)(v - 0xFEE0)).ToString(); // fullwidth ASCII
            else if (Folding.TryGetValue(v, out var folded)) piece = folded;
            else piece = rune.ToString();

            foreach (var c in piece)
            {
                var lower = c is >= 'A' and <= 'Z' ? (char)(c + 32) : c;
                if (lower is >= 'a' and <= 'z' or >= '0' and <= '9')
                {
                    if (needsHyphen && slug.Length > 0) slug.Append('-');
                    needsHyphen = false;
                    slug.Append(lower);
                }
                else
                {
                    needsHyphen = true;
                }
            }
        }

        var result = slug.ToString();
        if (result.Length > MaxSlugLength)
            result = result[..MaxSlugLength].TrimEnd('-');
        return result.Length == 0 ? DefaultSlug : result;
    }

    /// <summary><c>yyyy-MM-dd-HHmm-&lt;slug&gt;</c> in the given time zone.</summary>
    public static string FolderName(DateTimeOffset startedAt, string slug, TimeZoneInfo timeZone) =>
        $"{Format(startedAt, "yyyy-MM-dd-HHmm", timeZone)}-{slug}";

    /// <summary><c>base</c>, or <c>base-2</c>, <c>base-3</c>, and so on when a name is taken.</summary>
    public static string UniqueName(string baseName, Func<string, bool> isTaken)
    {
        if (!isTaken(baseName)) return baseName;
        var suffix = 2;
        while (isTaken($"{baseName}-{suffix}")) suffix++;
        return $"{baseName}-{suffix}";
    }

    /// <summary>
    /// The name a person sees: "Capture: &lt;window title&gt;, 2026-10-20 22:24 PDT".
    /// The app name stands in for a missing window title. With <paramref name="quoted"/>,
    /// the title sits in double quotes (its own quotes become single quotes).
    /// </summary>
    public static string CaptureName(string? windowTitle, string? sourceApp, DateTimeOffset capturedAt,
        TimeZoneInfo timeZone, bool quoted = false)
    {
        var time = Format(capturedAt, "yyyy-MM-dd HH:mm zzz", timeZone);
        var label = Label(windowTitle, sourceApp);
        if (label is null) return $"Capture: {time}";
        var shown = quoted ? ScreenText.Quoted(label) : label;
        return $"Capture: {shown}, {time}";
    }

    /// <summary>The file name without extension: "2224-pricing-acme".</summary>
    public static string CaptureFileStem(string? windowTitle, string? sourceApp, DateTimeOffset capturedAt,
        TimeZoneInfo timeZone)
    {
        var time = Format(capturedAt, "HHmm", timeZone);
        var label = Label(windowTitle, sourceApp);
        return $"{time}-{(label is null ? "capture" : Slug(label))}";
    }

    private static string? Label(string? windowTitle, string? sourceApp) =>
        ScreenText.Field(windowTitle, maxScalars: MaxLabelLength)
        ?? ScreenText.Field(sourceApp, maxScalars: MaxLabelLength);

    /// <summary>
    /// Formats with the invariant culture and the Gregorian calendar. Supports patterns
    /// made of yyyy, MM, dd, HH, mm, and zzz (the Mac abbreviation) plus literal text.
    /// </summary>
    public static string Format(DateTimeOffset date, string pattern, TimeZoneInfo timeZone)
    {
        var local = TimeZoneInfo.ConvertTime(date, timeZone);
        var offset = local.Offset;
        var isDst = timeZone.IsDaylightSavingTime(local);
        var sb = new StringBuilder();
        var ci = CultureInfo.InvariantCulture;
        for (var i = 0; i < pattern.Length;)
        {
            if (Match(pattern, i, "yyyy")) { sb.Append(local.Year.ToString("D4", ci)); i += 4; }
            else if (Match(pattern, i, "MM")) { sb.Append(local.Month.ToString("D2", ci)); i += 2; }
            else if (Match(pattern, i, "dd")) { sb.Append(local.Day.ToString("D2", ci)); i += 2; }
            else if (Match(pattern, i, "HH")) { sb.Append(local.Hour.ToString("D2", ci)); i += 2; }
            else if (Match(pattern, i, "mm")) { sb.Append(local.Minute.ToString("D2", ci)); i += 2; }
            else if (Match(pattern, i, "zzz")) { sb.Append(TimeZoneText.Abbreviation(timeZone, offset, isDst)); i += 3; }
            else { sb.Append(pattern[i]); i++; }
        }
        return sb.ToString();
    }

    private static bool Match(string s, int i, string token) =>
        string.CompareOrdinal(s, i, token, 0, token.Length) == 0;
}
