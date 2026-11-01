using System.Globalization;

namespace Nextshot.Core.Naming;

/// <summary>
/// Time zone abbreviations as Foundation prints them with en_US_POSIX and the pattern
/// <c>zzz</c>. US and Canadian zones in the table use a short name (PST/PDT and so on).
/// Every other zone prints "GMT" plus the offset: "GMT" for zero, then a sign, hours
/// without padding, and ":mm" only when minutes are not zero (Europe/London in summer:
/// GMT+1, Asia/Tokyo: GMT+9, Asia/Kolkata: GMT+5:30).
/// </summary>
public static class TimeZoneText
{
    // IANA id (and the matching Windows id) to (standard, daylight).
    private static readonly Dictionary<string, (string Std, string Dst)> Table = Build();

    private static Dictionary<string, (string Std, string Dst)> Build()
    {
        var t = new Dictionary<string, (string Std, string Dst)>(StringComparer.Ordinal);
        void Add((string Std, string Dst) names, params string[] ids)
        {
            foreach (var id in ids) t[id] = names;
        }
        Add(("PST", "PDT"), "America/Los_Angeles", "America/Vancouver", "US/Pacific", "Pacific Standard Time");
        Add(("MST", "MDT"), "America/Denver", "America/Boise", "America/Edmonton", "US/Mountain", "Mountain Standard Time");
        Add(("MST", "MST"), "America/Phoenix", "US/Arizona", "US Mountain Standard Time");
        Add(("CST", "CDT"), "America/Chicago", "America/Winnipeg", "US/Central", "Central Standard Time");
        Add(("EST", "EDT"), "America/New_York", "America/Toronto", "America/Detroit", "US/Eastern", "Eastern Standard Time");
        Add(("AST", "ADT"), "America/Halifax", "Atlantic Standard Time");
        Add(("AKST", "AKDT"), "America/Anchorage", "US/Alaska", "Alaskan Standard Time");
        Add(("HST", "HST"), "Pacific/Honolulu", "US/Hawaii", "Hawaiian Standard Time");
        return t;
    }

    public static string Abbreviation(TimeZoneInfo timeZone, TimeSpan offset, bool isDaylightSaving)
    {
        if (Table.TryGetValue(timeZone.Id, out var names))
            return isDaylightSaving ? names.Dst : names.Std;
        return GmtOffset(offset);
    }

    public static string GmtOffset(TimeSpan offset)
    {
        var totalMinutes = (int)offset.TotalMinutes;
        if (totalMinutes == 0) return "GMT";
        var sign = totalMinutes < 0 ? "-" : "+";
        var abs = Math.Abs(totalMinutes);
        var hours = abs / 60;
        var minutes = abs % 60;
        var text = hours.ToString(CultureInfo.InvariantCulture);
        return minutes == 0
            ? $"GMT{sign}{text}"
            : $"GMT{sign}{text}:{minutes.ToString("D2", CultureInfo.InvariantCulture)}";
    }
}
