using System.Globalization;
using System.Text.RegularExpressions;

namespace Nextshot.Core.Notes;

/// <summary>
/// Splits a capture note into the capture note and per-badge instructions.
/// Port of the Mac NoteParser. The note is split into lines, and each line into
/// parts at semicolons. A part that starts with a badge number and a colon
/// becomes that badge's instruction. Every other part stays in the note.
/// </summary>
public static class NoteParser
{
    public sealed record Result(string? Note, IReadOnlyDictionary<int, string> Instructions);

    // Foundation CharacterSet.newlines: LF, VT, FF, CR, NEL, LS, PS. CRLF is one break.
    private static readonly Regex NewlineSplit = new("\r\n|[\n\u000B\u000C\r\u0085\u2028\u2029]", RegexOptions.Compiled);

    public static Result Parse(string text, ISet<int> badges)
    {
        var noteLines = new List<string>();
        var instructions = new Dictionary<int, string>();

        foreach (var line in NewlineSplit.Split(text))
        {
            var kept = new List<string>();
            foreach (var part in line.Split(';'))
            {
                if (TryInstruction(part, out int badge, out string instruction) && badges.Contains(badge))
                {
                    instructions[badge] = instructions.TryGetValue(badge, out var prior)
                        ? $"{prior}; {instruction}"
                        : instruction;
                }
                else
                {
                    kept.Add(part);
                }
            }
            string remainder = TrimWhitespace(string.Join(";", kept));
            if (remainder.Length > 0) noteLines.Add(remainder);
        }

        string note = string.Join("\n", noteLines);
        return new Result(note.Length == 0 ? null : note, instructions);
    }

    private static bool TryInstruction(string part, out int badge, out string text)
    {
        badge = 0;
        text = "";
        string trimmed = TrimWhitespace(part);
        int colon = trimmed.IndexOf(':');
        if (colon < 0) return false;
        string number = TrimWhitespace(trimmed[..colon]);
        if (number.Length == 0 || !number.All(c => c >= '0' && c <= '9')) return false;
        // Swift Int(...) returns nil on overflow; TryParse does the same.
        if (!int.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out badge)) return false;
        text = TrimWhitespace(trimmed[(colon + 1)..]);
        return text.Length > 0;
    }

    // Foundation CharacterSet.whitespaces: tab and Unicode category Zs.
    private static string TrimWhitespace(string s)
    {
        int start = 0, end = s.Length;
        while (start < end && IsWhitespace(s[start])) start++;
        while (end > start && IsWhitespace(s[end - 1])) end--;
        return s[start..end];
    }

    private static bool IsWhitespace(char c) =>
        c == '\t' || CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;
}
