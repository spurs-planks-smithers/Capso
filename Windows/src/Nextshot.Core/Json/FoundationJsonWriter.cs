using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Nextshot.Core.Json;

/// <summary>
/// Writes JSON byte-for-byte like Swift's JSONEncoder with
/// [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] and the .iso8601
/// date strategy: "key" : value, two-space indent, ordinal sorted keys, empty
/// containers as open, blank line, indent, close, no trailing newline, raw
/// non-ASCII and slashes. Null object members are omitted (Swift omits nil
/// optionals).
/// </summary>
public static class FoundationJsonWriter
{
    public static string Write(JsonNode? node)
    {
        var sb = new StringBuilder();
        WriteNode(sb, node, 0);
        return sb.ToString();
    }

    public static byte[] WriteBytes(JsonNode? node) => new UTF8Encoding(false).GetBytes(Write(node));

    /// <summary>Whole-second UTC ISO 8601 with Z, as Foundation's .iso8601 strategy writes.</summary>
    public static string FormatDate(DateTimeOffset date)
    {
        long ticks = date.UtcTicks - (date.UtcTicks % TimeSpan.TicksPerSecond);
        // Floor toward negative infinity for dates before year 1 offsets; ticks are non-negative here.
        return new DateTime(ticks, DateTimeKind.Utc).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
    }

    public static DateTimeOffset ParseDate(string text) =>
        DateTimeOffset.Parse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal);

    private static void Indent(StringBuilder sb, int level) => sb.Append(' ', level * 2);

    private static void WriteNode(StringBuilder sb, JsonNode? node, int level)
    {
        switch (node)
        {
            case null:
                sb.Append("null");
                break;
            case JsonObject obj:
                WriteObject(sb, obj, level);
                break;
            case JsonArray arr:
                WriteArray(sb, arr, level);
                break;
            case JsonValue value:
                WriteValue(sb, value);
                break;
        }
    }

    private static void WriteObject(StringBuilder sb, JsonObject obj, int level)
    {
        var members = obj.Where(p => p.Value is not null).OrderBy(p => p.Key, StringComparer.Ordinal).ToList();
        sb.Append('{');
        if (members.Count == 0)
        {
            sb.Append('\n').Append('\n');
            Indent(sb, level);
            sb.Append('}');
            return;
        }
        sb.Append('\n');
        for (int i = 0; i < members.Count; i++)
        {
            Indent(sb, level + 1);
            WriteString(sb, members[i].Key);
            sb.Append(" : ");
            WriteNode(sb, members[i].Value, level + 1);
            if (i < members.Count - 1) sb.Append(',');
            sb.Append('\n');
        }
        Indent(sb, level);
        sb.Append('}');
    }

    private static void WriteArray(StringBuilder sb, JsonArray arr, int level)
    {
        sb.Append('[');
        if (arr.Count == 0)
        {
            sb.Append('\n').Append('\n');
            Indent(sb, level);
            sb.Append(']');
            return;
        }
        sb.Append('\n');
        for (int i = 0; i < arr.Count; i++)
        {
            Indent(sb, level + 1);
            WriteNode(sb, arr[i], level + 1);
            if (i < arr.Count - 1) sb.Append(',');
            sb.Append('\n');
        }
        Indent(sb, level);
        sb.Append(']');
    }

    private static void WriteValue(StringBuilder sb, JsonValue value)
    {
        if (value.TryGetValue<string>(out var text))
            WriteString(sb, text);
        else
            sb.Append(value.ToJsonString());
    }

    /// <summary>Foundation escapes only quote, backslash, and C0 controls (lowercase u-escapes).</summary>
    private static void WriteString(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}
