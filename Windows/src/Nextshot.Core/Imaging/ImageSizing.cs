using Nextshot.Core.Model;

namespace Nextshot.Core.Imaging;

/// <summary>A rectangle in source pixels. The origin is the top-left corner. Width or height may be negative.</summary>
public readonly record struct PixelRect(double X, double Y, double Width, double Height);

/// <summary>
/// Export sizing for feedback images. Port of the Mac ImageSizing, which follows
/// Anthropic's published resize rule. An image exported at ResizedSize is the
/// exact image Claude sees, so manifest pixel coordinates need no conversion.
/// </summary>
public static class ImageSizing
{
    /// <summary>Claude views images in 28 by 28 pixel patches. One patch is one visual token.</summary>
    public const int PatchSize = 28;

    public readonly record struct Limits(int MaxEdge, int MaxTokens)
    {
        public static Limits Standard => new(1568, 1568);
        public static Limits HighResolution => new(2576, 4784);
        /// <summary>Requests with more than 20 images reject any image over 2000 px.</summary>
        public static Limits FeedbackExport => new(2000, 4784);
    }

    public static int VisualTokens(PixelSize size) => Patches(size.Width) * Patches(size.Height);

    /// <summary>The largest aspect-preserving size that fits both limits. A fitting image is returned unchanged.</summary>
    public static PixelSize ResizedSize(PixelSize size, Limits limits)
    {
        if (size.Width <= 0 || size.Height <= 0) return size;
        if (Fits(size, limits)) return size;
        if (size.Height > size.Width)
        {
            var rotated = ResizedSize(new PixelSize(size.Height, size.Width), limits);
            return new PixelSize(rotated.Height, rotated.Width);
        }

        // Binary search along the long edge. low always fits; high never fits.
        double aspectRatio = (double)size.Width / size.Height;
        int ShortEdge(int longEdge) =>
            Math.Max((int)Math.Round(longEdge / aspectRatio, MidpointRounding.ToEven), 1);

        int low = 1;
        int high = size.Width;
        while (low + 1 < high)
        {
            int mid = (low + high) / 2;
            if (Fits(new PixelSize(mid, ShortEdge(mid)), limits)) low = mid;
            else high = mid;
        }
        return new PixelSize(low, ShortEdge(low));
    }

    /// <summary>Maps a rectangle in source pixels to the exported size.</summary>
    public static FeedbackBox Scale(PixelRect rect, PixelSize source, PixelSize target)
    {
        // Standardize: a negative width or height flips the rectangle.
        double minX = Math.Min(rect.X, rect.X + rect.Width);
        double maxX = Math.Max(rect.X, rect.X + rect.Width);
        double minY = Math.Min(rect.Y, rect.Y + rect.Height);
        double maxY = Math.Max(rect.Y, rect.Y + rect.Height);
        var topLeft = Scale(minX, minY, source, target);
        var bottomRight = Scale(maxX, maxY, source, target);
        return new FeedbackBox(topLeft.X, topLeft.Y, bottomRight.X, bottomRight.Y);
    }

    /// <summary>Maps a point in source pixels to the exported size, clamped to the exported image.</summary>
    public static FeedbackPoint Scale(double x, double y, PixelSize source, PixelSize target) =>
        new(Scaled(x, source.Width, target.Width), Scaled(y, source.Height, target.Height));

    private static int Patches(int length) => (length + PatchSize - 1) / PatchSize;

    private static bool Fits(PixelSize size, Limits limits) =>
        Patches(size.Width) * PatchSize <= limits.MaxEdge
        && Patches(size.Height) * PatchSize <= limits.MaxEdge
        && VisualTokens(size) <= limits.MaxTokens;

    private static int Scaled(double value, int source, int target)
    {
        if (source <= 0) return 0;
        double mapped = Math.Round(value * target / source, MidpointRounding.AwayFromZero);
        return (int)Math.Min(Math.Max(mapped, 0), target);
    }
}
