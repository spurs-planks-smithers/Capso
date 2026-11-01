using Nextshot.Core.Model;

namespace Nextshot.Core.Ocr;

/// <summary>
/// Finds the OCR text under each mark. Port of the Mac OCRMatcher.
/// Region marks take the lines whose center is inside the mark. Arrows, lines,
/// and badges with a tip take the line at the tip, else the nearest line within
/// MaxDistance pixels. Badges with no tip take touching lines, else the nearest.
/// Text marks get none.
/// </summary>
public static class OcrMatcher
{
    public const int DefaultMaxDistance = 60;

    /// <summary>Returns copies of the marks with OcrText set. The input marks stay unchanged.</summary>
    public static List<FeedbackMark> AssignText(
        IEnumerable<FeedbackMark> marks,
        IReadOnlyList<FeedbackTextLine> lines,
        int maxDistance = DefaultMaxDistance)
    {
        var result = new List<FeedbackMark>();
        foreach (var source in marks)
        {
            var mark = new FeedbackMark(
                source.Kind, source.Box, source.Badge, source.Point,
                source.TextOnImage, source.OcrText, source.Instruction);
            mark.OcrText = Joined(MatchedLines(mark, lines, maxDistance));
            result.Add(mark);
        }
        return result;
    }

    /// <summary>The lines the rules pick for one mark, in reading order.</summary>
    public static List<FeedbackTextLine> MatchedLines(
        FeedbackMark mark,
        IReadOnlyList<FeedbackTextLine> lines,
        int maxDistance = DefaultMaxDistance)
    {
        double reach = maxDistance;
        switch (mark.Kind)
        {
            case MarkKind.Text:
                return new List<FeedbackTextLine>();
            case MarkKind.Rectangle:
            case MarkKind.Ellipse:
            case MarkKind.Freehand:
            case MarkKind.Pixelate:
            case MarkKind.Spotlight:
                return ReadingOrder(lines.Where(l => mark.Box.Contains(l.Box.Center)));
            case MarkKind.Arrow:
            case MarkKind.Line:
                if (mark.Point is not { } head) return new List<FeedbackTextLine>();
                return Matches(head, lines, reach);
            case MarkKind.Counter:
                if (mark.Point is { } tip) return Matches(tip, lines, reach);
                var touching = lines.Where(l => l.Box.Intersects(mark.Box)).ToList();
                if (touching.Count > 0) return ReadingOrder(touching);
                var near = Nearest(mark.Box.Center, lines, reach);
                return near is { } n ? new List<FeedbackTextLine> { n } : new List<FeedbackTextLine>();
            default:
                return new List<FeedbackTextLine>();
        }
    }

    /// <summary>Drops every OCR line that a Redact (Pixelate) mark touches.</summary>
    public static List<FeedbackTextLine> RemovingRedacted(
        IReadOnlyList<FeedbackTextLine> lines,
        IEnumerable<FeedbackMark> marks)
    {
        var redactions = marks.Where(m => m.Kind == MarkKind.Pixelate).Select(m => m.Box).ToList();
        if (redactions.Count == 0) return lines.ToList();
        return lines.Where(line => !redactions.Any(r => r.Intersects(line.Box))).ToList();
    }

    private static List<FeedbackTextLine> Matches(FeedbackPoint point, IReadOnlyList<FeedbackTextLine> lines, double maxDistance)
    {
        foreach (var line in lines)
        {
            if (line.Box.Contains(point)) return new List<FeedbackTextLine> { line };
        }
        var near = Nearest(point, lines, maxDistance);
        return near is { } n ? new List<FeedbackTextLine> { n } : new List<FeedbackTextLine>();
    }

    // The first line wins a tie, as Swift's min(by:) does.
    private static FeedbackTextLine? Nearest(FeedbackPoint point, IReadOnlyList<FeedbackTextLine> lines, double maxDistance)
    {
        FeedbackTextLine? best = null;
        double bestDistance = double.MaxValue;
        foreach (var line in lines)
        {
            double d = line.Box.DistanceTo(point);
            if (d <= maxDistance && d < bestDistance)
            {
                best = line;
                bestDistance = d;
            }
        }
        return best;
    }

    // OrderBy is stable, so equal keys keep input order.
    private static List<FeedbackTextLine> ReadingOrder(IEnumerable<FeedbackTextLine> lines) =>
        lines.OrderBy(l => l.Box.Y1).ThenBy(l => l.Box.X1).ToList();

    private static string? Joined(List<FeedbackTextLine> lines) =>
        lines.Count == 0 ? null : string.Join(" ", ReadingOrder(lines).Select(l => l.Text));
}
