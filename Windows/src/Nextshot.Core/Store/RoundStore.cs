// Port of Packages/FeedbackKit/Sources/FeedbackKit/FeedbackRoundStore.swift (text files only; no images or OCR).
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Nextshot.Core.Json;
using Nextshot.Core.Model;
using Nextshot.Core.Naming;

namespace Nextshot.Core.Store;

/// <summary>
/// Owns the active feedback round and its folder on disk. Every change rewrites
/// feedback.json, manifest.md, and prompt.md. A single lock lets one writer run
/// at a time, so two saves never interleave. Each file is written to a temp file
/// and renamed into place.
/// <c>&lt;root&gt;/.active.json</c> names the active folder, so a new store on the
/// same root resumes that round after a restart.
/// </summary>
public sealed class RoundStore
{
    public const string ActiveMarkerName = ".active.json";
    public const string RoundFileName = "feedback.json";
    public const string ManifestFileName = "manifest.md";
    public const string PromptFileName = "prompt.md";

    private static readonly UTF8Encoding Utf8 = new(false);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly IBundleTextRenderer _renderer;
    private readonly Func<DateTimeOffset> _now;
    private readonly Func<string, string> _displayPath;
    private volatile FeedbackRound? _active;

    public string Root { get; }
    public TimeZoneInfo TimeZone { get; }

    /// <summary>The default root: <c>%LOCALAPPDATA%\Nextshot</c>.</summary>
    public static string DefaultRoot() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nextshot");

    public RoundStore(IBundleTextRenderer renderer, string? root = null, TimeZoneInfo? timeZone = null,
        Func<DateTimeOffset>? now = null, Func<string, string>? displayPath = null)
    {
        // displayPath maps a folder on disk to the path the prompts and manifest print.
        // The default prints the real path. The golden tests print /golden/<folder>.
        _displayPath = displayPath ?? (p => p);
        _renderer = renderer;
        Root = root ?? DefaultRoot();
        TimeZone = timeZone ?? TimeZoneInfo.Local;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        Directory.CreateDirectory(Root);
        _active = LoadActiveRound();
    }

    /// <summary>A copy of the active round, or null. The field only ever swaps whole rounds.</summary>
    public FeedbackRound? ActiveRound => _active is { } a ? Clone(a) : null;

    public string? ActiveFolderPath => _active is { } a ? FolderPath(a.FolderName) : null;

    public string FolderPath(string folderName) => Path.Combine(Root, folderName);

    // MARK: lifecycle

    public Task<FeedbackRound> StartAsync(string name, CancellationToken ct = default) =>
        LockedAsync(() =>
        {
            if (_active is not null) throw new RoundStoreException("A round is already active.");
            return StartLocked(name);
        }, ct);

    /// <summary>The active round, or a new one when none is active.</summary>
    public Task<FeedbackRound> StartIfNeededAsync(string name, CancellationToken ct = default) =>
        LockedAsync(() => _active is { } a ? Clone(a) : StartLocked(name), ct);

    private FeedbackRound StartLocked(string name)
    {
        var displayName = ScreenText.Field(name, maxScalars: ScreenText.MaxNameLength)?.Trim(' ', '\t')
                          ?? FeedbackNaming.DefaultSlug;
        if (displayName.Length == 0) displayName = FeedbackNaming.DefaultSlug;
        var slug = FeedbackNaming.Slug(displayName);
        var startedAt = _now();
        var baseName = FeedbackNaming.FolderName(startedAt, slug, TimeZone);
        var folderName = FeedbackNaming.UniqueName(baseName, n => Directory.Exists(FolderPath(n)));

        var round = new FeedbackRound(displayName, slug, folderName, startedAt);
        Directory.CreateDirectory(FolderPath(folderName));
        Write(round);
        WriteActiveMarker(folderName);
        _active = round;
        return Clone(round);
    }

    /// <summary>Reopens an ended round, so new captures continue its numbering.</summary>
    public Task<FeedbackRound> ResumeAsync(string folderName, CancellationToken ct = default) =>
        LockedAsync(() =>
        {
            if (_active is not null) throw new RoundStoreException("A round is already active.");
            var round = ReadRound(folderName).Round
                        ?? throw new RoundStoreException($"Round '{folderName}' was not found.");
            // The folder that was read is the one to write back to.
            round.FolderName = folderName;
            round.EndedAt = null;
            Write(round);
            WriteActiveMarker(folderName);
            _active = round;
            return Clone(round);
        }, ct);

    public Task<FeedbackRound> EndAsync(CancellationToken ct = default) =>
        LockedAsync(() =>
        {
            var current = _active ?? throw new RoundStoreException("No round is active.");
            var round = Clone(current);
            round.EndedAt = _now();
            Write(round);
            var marker = Path.Combine(Root, ActiveMarkerName);
            if (File.Exists(marker)) File.Delete(marker);
            _active = null;
            return round;
        }, ct);

    /// <summary>
    /// Changes the active round and saves it. If the change throws, nothing is written
    /// and the round stays as it was.
    /// </summary>
    public Task<FeedbackRound> UpdateAsync(Action<FeedbackRound> change, CancellationToken ct = default) =>
        LockedAsync(() =>
        {
            var current = _active ?? throw new RoundStoreException("No round is active.");
            var working = Clone(current);
            change(working);
            working.FolderName = current.FolderName; // the folder on disk never moves
            Write(working);
            _active = working;
            return Clone(working);
        }, ct);

    // MARK: listing

    /// <summary>
    /// The active round first (once it holds a capture), then ended rounds that hold a
    /// capture, newest end first, up to <paramref name="limit"/> (null lists all).
    /// Rounds with a newer schemaVersion are hidden and counted.
    /// </summary>
    public Task<RoundListing> ListRecentAsync(int? limit = 5, CancellationToken ct = default) =>
        LockedAsync(() =>
        {
            var ended = new List<FeedbackRound>();
            var unreadable = new List<string>();
            var newer = new List<string>();
            foreach (var dir in Directory.EnumerateDirectories(Root).OrderBy(d => d, StringComparer.Ordinal))
            {
                var name = Path.GetFileName(dir);
                if (!File.Exists(Path.Combine(dir, RoundFileName))) continue;
                var read = ReadRound(name);
                if (read.Round is { } round)
                {
                    if (round.EndedAt is not null && round.Captures.Count > 0) ended.Add(round);
                }
                else if (read.NewerSchema) newer.Add(name);
                else unreadable.Add(name);
            }

            var sorted = ended.OrderByDescending(r => r.EndedAt).ThenByDescending(r => r.StartedAt).ToList();
            if (limit is { } l) sorted = sorted.Take(l).ToList();
            var rounds = new List<FeedbackRound>();
            if (_active is { Captures.Count: > 0 } active) rounds.Add(Clone(active));
            rounds.AddRange(sorted);
            return new RoundListing(rounds, unreadable, newer);
        }, ct);

    // MARK: reading

    private readonly record struct Read(FeedbackRound? Round, bool NewerSchema);

    private Read ReadRound(string folderName)
    {
        if (folderName.Length == 0 || folderName is "." or ".." || folderName.IndexOfAny(['/', '\\']) >= 0)
            return default;
        try
        {
            var text = File.ReadAllText(Path.Combine(FolderPath(folderName), RoundFileName), Utf8);
            // The schema number is read first: a newer schema can change other fields.
            var version = JsonNode.Parse(text)?["schemaVersion"]?.GetValue<int>();
            if (version > FeedbackRound.CurrentSchemaVersion) return new Read(null, true);
            return new Read(FeedbackRoundJson.Deserialize(text), false);
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException
                                      or FormatException or KeyNotFoundException or UnauthorizedAccessException)
        {
            return default;
        }
    }

    /// <summary>A bad marker must not block the app from starting.</summary>
    private FeedbackRound? LoadActiveRound()
    {
        try
        {
            var marker = JsonNode.Parse(File.ReadAllText(Path.Combine(Root, ActiveMarkerName), Utf8));
            var folder = marker?["folderName"]?.GetValue<string>();
            if (folder is null) return null;
            var round = ReadRound(folder).Round;
            if (round is null || round.EndedAt is not null) return null;
            round.FolderName = folder;
            return round;
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException
                                      or FormatException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    // MARK: writing (call only while holding the gate)

    private void Write(FeedbackRound round)
    {
        var folder = FolderPath(round.FolderName);
        Directory.CreateDirectory(folder);
        var shown = _displayPath(folder);
        var manifest = _renderer.RenderManifest(round, shown, TimeZone);
        var prompt = _renderer.RenderPrompt(round, shown);
        var capturePrompts = round.Captures
            .Select(c => (File: c.PromptFile, Text: _renderer.RenderCapturePrompt(c, shown))).ToList();
        WriteAtomic(Path.Combine(folder, RoundFileName), FeedbackRoundJson.SerializeBytes(round));
        WriteAtomic(Path.Combine(folder, ManifestFileName), Utf8.GetBytes(manifest));
        WriteAtomic(Path.Combine(folder, PromptFileName), Utf8.GetBytes(prompt));
        foreach (var (file, text) in capturePrompts)
            WriteAtomic(Path.Combine(folder, file), Utf8.GetBytes(text));
    }

    private void WriteActiveMarker(string folderName)
    {
        var json = new JsonObject { ["folderName"] = folderName }.ToJsonString();
        WriteAtomic(Path.Combine(Root, ActiveMarkerName), Utf8.GetBytes(json));
    }

    private static void WriteAtomic(string path, byte[] bytes)
    {
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    // MARK: helpers

    private static FeedbackRound Clone(FeedbackRound round) =>
        FeedbackRoundJson.Deserialize(FeedbackRoundJson.Serialize(round));

    private async Task<T> LockedAsync<T>(Func<T> action, CancellationToken ct)
    {
        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try { return action(); }
        finally { _gate.Release(); }
    }
}
