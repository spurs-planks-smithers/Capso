namespace Nextshot.Core.Model;

/// <summary>
/// A numbered badge, plus the box or ellipse it sits on, if any.
/// Item 2.3 is badge 3 in capture 2.
/// </summary>
public sealed record FeedbackItem(int CaptureIndex, FeedbackMark Badge, FeedbackMark? Shape)
{
    public string Id => $"{CaptureIndex}.{Badge.Badge ?? 0}";

    /// <summary>The shape's OCR text names the marked region best, so it wins.</summary>
    public string? OcrText => Shape?.OcrText ?? Badge.OcrText;

    /// <summary>The box that holds the badge, its shape, and the point its arrow aims at.</summary>
    public FeedbackBox Focus
    {
        get
        {
            var focus = Badge.Box;
            if (Shape is not null) focus = focus.Union(Shape.Box);
            if (Badge.Point is { } tip) focus = focus.Union(new FeedbackBox(tip.X, tip.Y, tip.X, tip.Y));
            return focus;
        }
    }
}

public static class FeedbackItems
{
    private static bool IsShapeKind(MarkKind kind) => kind is MarkKind.Rectangle or MarkKind.Ellipse;

    /// <summary>
    /// Splits a capture's marks into items and the marks left over. A shape goes
    /// to the touching badge whose center is nearest (lower badge number on a
    /// tie). Each badge takes at most one shape.
    /// </summary>
    public static (List<FeedbackItem> Items, List<FeedbackMark> OtherMarks) Split(FeedbackCapture capture)
    {
        var marks = capture.Marks;
        var badges = Enumerable.Range(0, marks.Count)
            .Where(i => marks[i].Kind == MarkKind.Counter && marks[i].Badge.HasValue)
            .ToList();

        var shapeForBadge = new Dictionary<int, int>();
        for (int shapeIndex = 0; shapeIndex < marks.Count; shapeIndex++)
        {
            if (!IsShapeKind(marks[shapeIndex].Kind)) continue;
            var shapeBox = marks[shapeIndex].Box;
            int? best = null;
            double bestDist = 0;
            foreach (int b in badges)
            {
                if (shapeForBadge.ContainsKey(b) || !marks[b].Box.Intersects(shapeBox)) continue;
                double d = shapeBox.DistanceTo(marks[b].Box.Center);
                if (best is null || d < bestDist ||
                    (d == bestDist && (marks[b].Badge ?? 0) < (marks[best.Value].Badge ?? 0)))
                {
                    best = b;
                    bestDist = d;
                }
            }
            if (best is { } chosen) shapeForBadge[chosen] = shapeIndex;
        }

        var items = badges
            .OrderBy(i => marks[i].Badge ?? 0)
            .ThenBy(i => i)
            .Select(i => new FeedbackItem(
                capture.Index,
                marks[i],
                shapeForBadge.TryGetValue(i, out int s) ? marks[s] : null))
            .ToList();

        var used = new HashSet<int>(badges);
        used.UnionWith(shapeForBadge.Values);
        var other = Enumerable.Range(0, marks.Count).Where(i => !used.Contains(i)).Select(i => marks[i]).ToList();
        return (items, other);
    }
}
