// Port of Packages/FeedbackKit/Sources/FeedbackKit/ZipWriter.swift
using System.IO.Compression;
using System.Text;
using Nextshot.Core.Bundle;
using Nextshot.Core.Json;
using Nextshot.Core.Naming;

namespace Nextshot.Core.Zip;

public enum ZipErrorKind
{
    /// <summary>No capture has both of its images, so there is nothing to zip.</summary>
    NoCaptures,
}

public sealed class ZipException(ZipErrorKind kind) : Exception(kind.ToString())
{
    public ZipErrorKind Kind { get; } = kind;
}

public sealed record ZipResult(
    string Path,
    long Bytes,
    int StepIndex,
    bool OverBudget,
    int CaptureCount,
    IReadOnlyList<BasketKey> Missing);

/// <summary>
/// Writes a zip export: one top folder of JPEGs, README.md, manifest.md, feedback.json, and the capture
/// prompts. Entry names use forward slashes, and the archive has no __MACOSX or dot-underscore entries.
/// </summary>
public static class ZipWriter
{
    private static readonly UTF8Encoding Utf8 = new(false);

    /// <summary>
    /// Builds the zip, steps down the size ladder until it fits <paramref name="budget"/> or the ladder
    /// ends, then moves it into <paramref name="destination"/> under a name no file there has. Never overwrites.
    /// <paramref name="unresolved"/> are checked captures that were not found. The README names them.
    /// </summary>
    public static ZipResult Write(
        ZipKind kind,
        IReadOnlyList<FeedbackSelectionEntry> entries,
        IJpegEncoder encoder,
        string destination,
        DateTimeOffset now,
        TimeZoneInfo timeZone,
        IReadOnlyList<BasketKey>? unresolved = null,
        int budget = ZipLadder.BudgetBytes,
        string? stagingRoot = null)
    {
        unresolved ??= [];
        var present = new List<FeedbackSelectionEntry>();
        var missing = new List<BasketKey>();
        foreach (var entry in entries)
        {
            var folder = entry.FolderPath;
            if (File.Exists(System.IO.Path.Combine(folder, entry.Capture.ImageFile))
                && File.Exists(System.IO.Path.Combine(folder, entry.Capture.CleanImageFile)))
                present.Add(entry);
            else
                missing.Add(new BasketKey(ZipPlanner.LastComponent(folder), entry.Capture.Index));
        }
        if (present.Count == 0) throw new ZipException(ZipErrorKind.NoCaptures);

        var time = kind == ZipKind.Round ? present[0].Round.StartedAt : now;
        var baseName = ZipName.Base(kind, time, present.Count, timeZone);
        // A folder left from an earlier unzip takes the name too, so the person never opens the old folder.
        var name = FeedbackNaming.UniqueName(baseName, n =>
            File.Exists(System.IO.Path.Combine(destination, n + ".zip"))
            || Directory.Exists(System.IO.Path.Combine(destination, n)));

        var staging = System.IO.Path.Combine(stagingRoot ?? System.IO.Path.GetTempPath(), "nextshot-zip-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            var stepIndex = 0;
            while (true)
            {
                var step = ZipLadder.Step(stepIndex);
                var plan = ZipPlanner.Plan(kind, present, name, now, step.PixelScale);
                var zipPath = System.IO.Path.Combine(staging, name + ".zip");
                if (File.Exists(zipPath)) File.Delete(zipPath);
                WriteArchive(zipPath, plan, kind, step, encoder, timeZone, missing, unresolved, now);
                var bytes = new FileInfo(zipPath).Length;
                // Quality steps 0 to 2 always run before the floor can end the ladder.
                var ladderDone = stepIndex >= 2 && plan.AtFloor;
                if (bytes <= budget || ladderDone)
                {
                    Directory.CreateDirectory(destination);
                    var target = System.IO.Path.Combine(destination, name + ".zip");
                    File.Move(zipPath, target);
                    return new ZipResult(target, bytes, stepIndex, bytes > budget, present.Count,
                        missing.Concat(unresolved).ToList());
                }
                stepIndex++;
            }
        }
        finally
        {
            try { Directory.Delete(staging, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static void WriteArchive(string zipPath, ZipPlan plan, ZipKind kind, ZipStep step, IJpegEncoder encoder,
        TimeZoneInfo timeZone, IReadOnlyList<BasketKey> missing, IReadOnlyList<BasketKey> unresolved, DateTimeOffset now)
    {
        var top = plan.Round.FolderName;
        var paths = new BundlePathMode.Relative(top);
        string[] headerLines = plan.SourceRoundLines.Count == 0
            ? []
            : new[] { "Source rounds:" }.Concat(plan.SourceRoundLines).ToArray();

        using var stream = new FileStream(zipPath, FileMode.CreateNew, FileAccess.ReadWrite);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create);
        // ZIP timestamps start in 1980.
        var stamp = now.Year < 1980 ? new DateTimeOffset(1980, 1, 1, 0, 0, 0, TimeSpan.Zero) : now;

        void Add(string file, byte[] data, CompressionLevel level)
        {
            var entry = archive.CreateEntry(top + "/" + file, level);
            entry.LastWriteTime = stamp;
            using var s = entry.Open();
            s.Write(data, 0, data.Length);
        }

        Add("README.md", Utf8.GetBytes(ZipReadme.Render(plan, kind, missing, unresolved)), CompressionLevel.Optimal);
        Add("manifest.md", Utf8.GetBytes(ManifestWriter.Render(plan.Round, paths, timeZone, headerLines)), CompressionLevel.Optimal);
        foreach (var capture in plan.Round.Captures)
            Add(capture.PromptFile, Utf8.GetBytes(PromptBuilder.RenderCapture(capture, paths, redo: true)), CompressionLevel.Optimal);
        Add("feedback.json", FeedbackRoundJson.SerializeBytes(plan.Round), CompressionLevel.Optimal);

        foreach (var image in plan.Images)
        {
            var quality = image.IsClean ? step.CleanQuality : step.AnnotatedQuality;
            byte[] source;
            try { source = File.ReadAllBytes(image.SourcePath); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                throw new ExportImageException(ExportImageErrorKind.Unreadable, "Image could not be read", e);
            }
            // A JPEG does not compress again, so store it.
            Add(image.FileName, encoder.EncodeJpeg(source, image.Size, quality), CompressionLevel.NoCompression);
        }
    }
}
