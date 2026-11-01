using Nextshot.Core.Model;

namespace Nextshot.Core.Zip;

public enum ExportImageErrorKind { Unreadable, EncodeFailed }

/// <summary>An image could not be read or converted for a zip export.</summary>
public sealed class ExportImageException(ExportImageErrorKind kind, string? message = null, Exception? inner = null)
    : Exception(message ?? kind.ToString(), inner)
{
    public ExportImageErrorKind Kind { get; } = kind;
}

/// <summary>
/// Encodes a bundle image as a JPEG for a zip export. Core stays free of Windows imaging, so the
/// Windows app implements this with WIC (WicJpegEncoder).
/// </summary>
public interface IJpegEncoder
{
    /// <summary>
    /// Decodes <paramref name="imageBytes"/> (PNG), draws it at exactly <paramref name="size"/> on a white
    /// background (a JPEG has no alpha, so a clear pixel shows white), and returns a JPEG at
    /// <paramref name="quality"/> (0 to 1). No metadata from the source carries over.
    /// Throws <see cref="ExportImageException"/>.
    /// </summary>
    byte[] EncodeJpeg(byte[] imageBytes, PixelSize size, double quality);
}
