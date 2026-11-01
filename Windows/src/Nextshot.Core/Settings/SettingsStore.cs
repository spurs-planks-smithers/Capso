using System.Text.Json;
using System.Text.Json.Nodes;

namespace Nextshot.Core.Settings;

/// <summary>
/// JSON settings file. The default path is %LOCALAPPDATA%\NextshotSettings\settings.json.
/// It sits outside the rounds root (%LOCALAPPDATA%\Nextshot), so a round scan never sees it.
/// Shape: { "flags": { "zipHandoff": "on" }, ...other settings }.
/// </summary>
public sealed class SettingsStore
{
    public string Path { get; }

    public SettingsStore(string? path = null)
    {
        Path = path ?? DefaultPath();
    }

    public static string DefaultPath() =>
        System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NextshotSettings",
            "settings.json");

    /// <summary>Flag overrides from the file. A missing or bad file gives an empty map.</summary>
    public IReadOnlyDictionary<string, string> ReadFlagOverrides()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (LoadRoot()["flags"] is JsonObject flags)
        {
            foreach (var (key, value) in flags)
            {
                if (value is JsonValue v && v.TryGetValue<string>(out var text))
                {
                    result[key] = text;
                }
            }
        }
        return result;
    }

    public void SetFlag(string name, string state) => Mutate(flags => flags[name] = state);

    public void ResetFlag(string name) => Mutate(flags => flags.Remove(name));

    private void Mutate(Action<JsonObject> change)
    {
        var root = LoadRoot();
        var flags = root["flags"] as JsonObject ?? new JsonObject();
        change(flags);
        root["flags"] = flags;
        var dir = System.IO.Path.GetDirectoryName(Path);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }
        var temp = Path + ".tmp";
        File.WriteAllText(temp, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, Path, overwrite: true);
    }

    private JsonObject LoadRoot()
    {
        try
        {
            if (File.Exists(Path) && JsonNode.Parse(File.ReadAllText(Path)) is JsonObject obj)
            {
                return obj;
            }
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException)
        {
            // A bad file reads as empty. Defaults apply.
        }
        return new JsonObject();
    }
}
