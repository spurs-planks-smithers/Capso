using System.Runtime.InteropServices.WindowsRuntime;
using Nextshot.Core.Model;
using Nextshot.Core.Zip;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Nextshot.Windows.Imaging;

/// <summary>
/// JPEG encoder for zip exports, built on WIC through Windows.Graphics.Imaging. It decodes the PNG,
/// scales it with Fant interpolation, composites it on white (a JPEG has no alpha), and encodes at the
/// requested quality. Only the quality goes to the encoder, so no source metadata carries over.
/// </summary>
public sealed class WicJpegEncoder : IJpegEncoder
{
    public byte[] EncodeJpeg(byte[] imageBytes, PixelSize size, double quality)
    {
        if (size.Width <= 0 || size.Height <= 0)
            throw new ExportImageException(ExportImageErrorKind.EncodeFailed, "Target size is empty");
        try
        {
            return EncodeAsync(imageBytes, size, quality).GetAwaiter().GetResult();
        }
        catch (ExportImageException)
        {
            throw;
        }
        catch (Exception e)
        {
            throw new ExportImageException(ExportImageErrorKind.EncodeFailed, "JPEG encoding failed", e);
        }
    }

    private static async Task<byte[]> EncodeAsync(byte[] imageBytes, PixelSize size, double quality)
    {
        BitmapDecoder decoder;
        PixelDataProvider pixels;
        using (var input = new InMemoryRandomAccessStream())
        {
            await input.WriteAsync(imageBytes.AsBuffer());
            input.Seek(0);
            try
            {
                decoder = await BitmapDecoder.CreateAsync(input);
            }
            catch (Exception e)
            {
                throw new ExportImageException(ExportImageErrorKind.Unreadable, "Image could not be decoded", e);
            }

            var transform = new BitmapTransform
            {
                ScaledWidth = (uint)size.Width,
                ScaledHeight = (uint)size.Height,
                InterpolationMode = BitmapInterpolationMode.Fant,
            };
            pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Straight,
                transform,
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.ColorManageToSRgb);
        }

        var bgra = pixels.DetachPixelData();
        CompositeOnWhite(bgra);

        using var output = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet
        {
            { "ImageQuality", new BitmapTypedValue((float)Math.Clamp(quality, 0, 1), PropertyType.Single) },
        };
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Ignore,
            (uint)size.Width,
            (uint)size.Height,
            96,
            96,
            bgra);
        await encoder.FlushAsync();

        var length = checked((int)output.Size);
        var result = new byte[length];
        output.Seek(0);
        await output.ReadAsync(result.AsBuffer(), (uint)length, InputStreamOptions.None);
        return result;
    }

    /// <summary>Blends straight-alpha BGRA pixels over white, in place, and makes every pixel opaque.</summary>
    internal static void CompositeOnWhite(byte[] bgra)
    {
        for (var i = 0; i + 3 < bgra.Length; i += 4)
        {
            int a = bgra[i + 3];
            if (a == 255) continue;
            for (var c = 0; c < 3; c++)
                bgra[i + c] = (byte)((bgra[i + c] * a + 255 * (255 - a) + 127) / 255);
            bgra[i + 3] = 255;
        }
    }
}
