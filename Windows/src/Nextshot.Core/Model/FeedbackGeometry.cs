namespace Nextshot.Core.Model;

/// <summary>A size in whole pixels.</summary>
public readonly record struct PixelSize(int Width, int Height);

/// <summary>A point in pixels of an exported PNG. The origin is the top-left corner.</summary>
public readonly record struct FeedbackPoint(int X, int Y);

/// <summary>
/// A box in pixels of an exported PNG. (X1, Y1) is the top-left corner and
/// (X2, Y2) the bottom-right corner.
/// </summary>
public readonly record struct FeedbackBox(int X1, int Y1, int X2, int Y2)
{
    public FeedbackPoint Center => new((X1 + X2) / 2, (Y1 + Y2) / 2);

    public bool Contains(FeedbackPoint point) =>
        point.X >= X1 && point.X <= X2 && point.Y >= Y1 && point.Y <= Y2;

    public FeedbackBox Union(FeedbackBox other) =>
        new(Math.Min(X1, other.X1), Math.Min(Y1, other.Y1), Math.Max(X2, other.X2), Math.Max(Y2, other.Y2));

    public bool Intersects(FeedbackBox other) =>
        X1 <= other.X2 && other.X1 <= X2 && Y1 <= other.Y2 && other.Y1 <= Y2;

    /// <summary>Distance from <paramref name="point"/> to the nearest edge, or 0 when inside.</summary>
    public double DistanceTo(FeedbackPoint point)
    {
        int dx = Math.Max(Math.Max(X1 - point.X, 0), point.X - X2);
        int dy = Math.Max(Math.Max(Y1 - point.Y, 0), point.Y - Y2);
        return Math.Sqrt((double)dx * dx + (double)dy * dy);
    }
}
