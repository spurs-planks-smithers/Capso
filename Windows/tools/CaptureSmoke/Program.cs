using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// Smoke test: can a hosted runner capture its screen with GDI CopyFromScreen?
// Throwaway CI probe (chore/ci-check-after-reenable). Do not merge.
var w = NativeMethods.GetSystemMetrics(0);
var h = NativeMethods.GetSystemMetrics(1);
Console.WriteLine($"Primary screen metrics: {w}x{h}");
if (w <= 0 || h <= 0) { w = 1024; h = 768; }
using var bmp = new Bitmap(w, h);
using (var g = Graphics.FromImage(bmp))
    g.CopyFromScreen(0, 0, 0, 0, bmp.Size);
var path = args.Length > 0 ? args[0] : "capture-smoke.png";
bmp.Save(path, ImageFormat.Png);
long sum = 0; int n = 0;
for (int y = 0; y < h; y += 16)
    for (int x = 0; x < w; x += 16) { var c = bmp.GetPixel(x, y); sum += c.R + c.G + c.B; n++; }
Console.WriteLine($"Saved {path}. Mean brightness (0-255): {sum / (3.0 * n):F1}");

static class NativeMethods
{
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
