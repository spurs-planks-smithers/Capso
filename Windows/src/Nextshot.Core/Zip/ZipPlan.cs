// Port of Packages/FeedbackKit/Sources/FeedbackKit/ZipPlan.swift
using Nextshot.Core.Bundle;
using Nextshot.Core.Imaging;
using Nextshot.Core.Model;
using Nextshot.Core.Naming;

namespace Nextshot.Core.Zip;

/// <summary>What a zip export holds.</summary>
public enum ZipKind
{
    /// <summary>Every capture of one round.</summary>
    Round,
    /// <summary>The captures checked in the Recent Rounds menu, from one round or several.</summary>
    Selection,
}

/// <summary>A capture named by its round folder and its index.</summary>
public readonly record struct BasketKey(string FolderName, int CaptureIndex);

/// <summary>The zip's file name without .zip, which is also its top folder.</summary>
public static class ZipName
{
    /// <summary>
    /// <c>nextshot-round-2026-10-25-0637-3-captures</c>. A round passes its start time,
    /// a selection passes the time of the zip.
    /// </summary>
    public static string Base(ZipKind kind, DateTimeOffset time, int captureCount, TimeZoneInfo timeZone)
    {
        var count = captureCount == 1 ? "1-capture" : $"{captureCount}-captures";
        var word = kind == ZipKind.Round ? "round" : "selection";
        return $"nextshot-{word}-{FeedbackNaming.Format(time, "yyyy-MM-dd-HHmm", timeZone)}-{count}";
    }
}

/// <summary>One step of the size ladder: JPEG quality per image kind, and a factor on the standard tier size.</summary>
public readonly record struct ZipStep(double AnnotatedQuality, double CleanQuality, double PixelScale);

/// <summary>
/// A zip over the budget steps down until it fits: clean copies first, then all
/// images, then pixels, down to the floor.
/// </summary>
public static class ZipLadder
{
    /// <summary>The goal for the real zip size, in bytes (5 MB).</summary>
    public const int BudgetBytes = 5_000_000;
    /// <summary>No image shrinks below this long edge, in pixels.</summary>
    public const int FloorLongEdge = 1000;

    public static ZipStep Step(int index) => index switch
    {
        <= 0 => new ZipStep(0.75, 0.75, 1),
        1 => new ZipStep(0.75, 0.50, 1),
        2 => new ZipStep(0.60, 0.50, 1),
        _ => new ZipStep(0.60, 0.50, Math.Pow(0.85, index - 2)),
    };

    /// <summary>
    /// The standard tier size, times <paramref name="pixelScale"/>, never below the floor and never
    /// above the standard tier size. An image smaller than the floor keeps its size.
    /// </summary>
    public static PixelSize TargetSize(PixelSize source, double pixelScale)
    {
        var baseSize = ImageSizing.ResizedSize(source, ImageSizing.Limits.Standard);
        var longEdge = Math.Max(baseSize.Width, baseSize.Height);
        if (!(pixelScale < 1) || longEdge <= 0) return baseSize;
        var floor = Math.Min(FloorLongEdge, longEdge);
        var scaledLong = Math.Max(floor, (int)Math.Round(longEdge * pixelScale, MidpointRounding.AwayFromZero));
        return WithLongEdge(scaledLong, baseSize);
    }

    /// <summary>The size with its long edge set to <paramref name="longEdge"/>, keeping the aspect ratio.</summary>
    internal static PixelSize WithLongEdge(int longEdge, PixelSize size)
    {
        var current = Math.Max(size.Width, size.Height);
        if (longEdge >= current || current <= 0) return size;
        var factor = (double)longEdge / current;
        int Scaled(int value) => Math.Max((int)Math.Round(value * factor, MidpointRounding.AwayFromZero), 1);
        return size.Width >= size.Height
            ? new PixelSize(longEdge, Scaled(size.Height))
            : new PixelSize(Scaled(size.Width), longEdge);
    }
}

/// <summary>One image to encode into the zip.</summary>
/// <param name="SourcePath">The bundle's PNG.</param>
/// <param name="FileName">The name in the zip: <c>K-stem.jpg</c> or <c>K-stem-clean.jpg</c>.</param>
public sealed record ZipImage(string SourcePath, string FileName, PixelSize Size, bool IsClean);

/// <summary>The zip's own round and its images at one ladder step.</summary>
/// <param name="Round">Renumbered, renamed, and rescaled. The README, manifest, prompts, and feedback.json all come from it.</param>
/// <param name="SourceRoundLines">A selection's source rounds, one line each. A round zip has none.</param>
/// <param name="AtFloor">True when a smaller pixel scale would shrink no image.</param>
public sealed record ZipPlan(FeedbackRound Round, IReadOnlyList<ZipImage> Images, IReadOnlyList<string> SourceRoundLines, bool AtFloor);

public static class ZipPlanner
{
    /// <summary>
    /// Builds the zip's round from the entries. A round zip keeps each capture's index as K.
    /// A selection numbers its captures 1 to N by capture time, then folder, then capture index.
    /// </summary>
    public static ZipPlan Plan(ZipKind kind, IEnumerable<FeedbackSelectionEntry> entries, string folderName,
        DateTimeOffset zipTime, double pixelScale)
    {
        var ordered = kind == ZipKind.Round
            ? entries.OrderBy(e => e.Capture.Index).ToList()
            : entries.OrderBy(e => e.Capture.CapturedAt)
                .ThenBy(e => e.FolderPath, StringComparer.Ordinal)
                .ThenBy(e => e.Capture.Index).ToList();

        var captures = new List<FeedbackCapture>();
        var images = new List<ZipImage>();
        var atFloor = true;
        for (var offset = 0; offset < ordered.Count; offset++)
        {
            var entry = ordered[offset];
            var source = entry.Capture;
            var number = kind == ZipKind.Round ? source.Index : offset + 1;
            var target = ZipLadder.TargetSize(source.Size, pixelScale);
            if (ZipLadder.TargetSize(source.Size, pixelScale * 0.85) != target) atFloor = false;
            var capture = Rescaled(source, number, target);
            captures.Add(capture);
            images.Add(new ZipImage(Combine(entry.FolderPath, source.ImageFile), capture.ImageFile, capture.Size, false));
            images.Add(new ZipImage(Combine(entry.FolderPath, source.CleanImageFile), capture.CleanImageFile, capture.Size, true));
        }

        FeedbackRound round;
        if (kind == ZipKind.Round)
        {
            var first = ordered.FirstOrDefault()?.Round;
            round = new FeedbackRound(
                first?.Name ?? FeedbackNaming.DefaultSlug,
                first?.Slug ?? FeedbackNaming.DefaultSlug,
                folderName,
                first?.StartedAt ?? zipTime,
                first?.EndedAt,
                captures);
        }
        else
        {
            round = new FeedbackRound("selection", "selection", folderName,
                ordered.FirstOrDefault()?.Capture.CapturedAt ?? zipTime, zipTime, captures);
        }

        return new ZipPlan(round, images, kind == ZipKind.Selection ? SourceLines(ordered) : [], atFloor);
    }

    private static string Combine(string folder, string file) =>
        folder.EndsWith('/') || folder.EndsWith('\\') ? folder + file : folder + Path.DirectorySeparatorChar + file;

    /// <summary>
    /// The capture with its zip number, its zip file names, and every mark scaled to the zip image.
    /// Rounding can make two boxes touch that did not touch before, which would change which shape a
    /// badge labels. So when the pairs differ, it tries a long edge 1 to 8 pixels shorter.
    /// </summary>
    internal static FeedbackCapture Rescaled(FeedbackCapture source, int index, PixelSize target)
    {
        var sourcePairs = Pairs(source);
        var longEdge = Math.Max(target.Width, target.Height);
        FeedbackCapture? first = null;
        for (var shorter = 0; shorter <= 8; shorter++)
        {
            if (longEdge - shorter <= 0) continue;
            var size = ZipLadder.WithLongEdge(longEdge - shorter, target);
            var candidate = Scaled(source, index, size);
            if (Pairs(candidate).SequenceEqual(sourcePairs)) return candidate;
            first ??= candidate;
        }
        return first ?? Scaled(source, index, target);
    }

    private static FeedbackCapture Scaled(FeedbackCapture source, int index, PixelSize size)
    {
        var marks = source.Marks.Select(m =>
        {
            var b = m.Box;
            var box = ImageSizing.Scale(new PixelRect(b.X1, b.Y1, b.X2 - b.X1, b.Y2 - b.Y1), source.Size, size);
            FeedbackPoint? point = m.Point is { } p ? ImageSizing.Scale(p.X, p.Y, source.Size, size) : null;
            return new FeedbackMark(m.Kind, box, m.Badge, point, m.TextOnImage, m.OcrText, m.Instruction);
        }).ToList();
        return new FeedbackCapture(
            index,
            $"{index}-{source.FileStem}.jpg",
            $"{index}-{StripExtension(source.CleanImageFile)}.jpg",
            size,
            source.CapturedAt,
            source.SourceApp,
            source.WindowTitle,
            source.Note,
            source.OcrText,
            marks);
    }

    private static string StripExtension(string file)
    {
        var slash = file.LastIndexOf('/');
        var dot = file.LastIndexOf('.');
        return dot > slash + 1 ? file[..dot] : file;
    }

    /// <summary>Badge number and the position of its shape in the marks, per item.</summary>
    private static List<string> Pairs(FeedbackCapture capture) =>
        FeedbackItems.Split(capture).Items.Select(item =>
        {
            var shape = item.Shape is null ? "none" : FirstIndexOf(capture.Marks, item.Shape).ToString();
            return $"{item.Badge.Badge ?? 0}:{shape}";
        }).ToList();

    /// <summary>Swift firstIndex(of:) compares marks by value, so equal marks give the first index.</summary>
    private static int FirstIndexOf(List<FeedbackMark> marks, FeedbackMark target)
    {
        for (var i = 0; i < marks.Count; i++)
            if (SameMark(marks[i], target)) return i;
        return -1;
    }

    private static bool SameMark(FeedbackMark a, FeedbackMark b) =>
        a.Kind == b.Kind && a.Badge == b.Badge && a.Box == b.Box && a.Point == b.Point
        && a.TextOnImage == b.TextOnImage && a.OcrText == b.OcrText && a.Instruction == b.Instruction;

    /// <summary>"- 2026-10-20-1912-pricing-page: its captures 2 and 3, here 1 and 2", one line per source round.</summary>
    private static List<string> SourceLines(List<FeedbackSelectionEntry> ordered)
    {
        var folders = new List<string>();
        var theirs = new Dictionary<string, List<int>>();
        var here = new Dictionary<string, List<int>>();
        for (var offset = 0; offset < ordered.Count; offset++)
        {
            var entry = ordered[offset];
            var folder = LastComponent(entry.FolderPath);
            if (!theirs.ContainsKey(folder))
            {
                folders.Add(folder);
                theirs[folder] = [];
                here[folder] = [];
            }
            theirs[folder].Add(entry.Capture.Index);
            here[folder].Add(offset + 1);
        }
        return folders.Select(folder =>
        {
            var noun = theirs[folder].Count == 1 ? "capture" : "captures";
            return $"- {folder}: its {noun} {NumberList(theirs[folder])}, here {NumberList(here[folder])}";
        }).ToList();
    }

    internal static string LastComponent(string path)
    {
        var trimmed = path.TrimEnd('/', '\\');
        var cut = trimmed.LastIndexOfAny(['/', '\\']);
        return cut < 0 ? trimmed : trimmed[(cut + 1)..];
    }

    /// <summary>"2", "2 and 3", or "1, 2, and 3".</summary>
    private static string NumberList(List<int> numbers)
    {
        var text = numbers.Select(n => n.ToString(System.Globalization.CultureInfo.InvariantCulture)).ToList();
        return text.Count switch
        {
            0 => "",
            1 => text[0],
            2 => $"{text[0]} and {text[1]}",
            _ => string.Join(", ", text.Take(text.Count - 1)) + ", and " + text[^1],
        };
    }
}
