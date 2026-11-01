using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Nextshot.Core.Model;

namespace Nextshot.Core.Json;

/// <summary>Reads and writes feedback.json with the Mac app's key names and byte layout.</summary>
public static class FeedbackRoundJson
{
    public static string Serialize(FeedbackRound round) => FoundationJsonWriter.Write(ToNode(round));

    public static byte[] SerializeBytes(FeedbackRound round) => new UTF8Encoding(false).GetBytes(Serialize(round));

    public static FeedbackRound Deserialize(string json) => FromNode(JsonNode.Parse(json)!.AsObject());

    public static FeedbackRound Deserialize(byte[] utf8) => Deserialize(new UTF8Encoding(false).GetString(utf8));

    // MARK: write

    private static JsonObject ToNode(FeedbackRound r)
    {
        var o = new JsonObject
        {
            ["schemaVersion"] = r.SchemaVersion,
            ["name"] = r.Name,
            ["slug"] = r.Slug,
            ["folderName"] = r.FolderName,
            ["startedAt"] = FoundationJsonWriter.FormatDate(r.StartedAt),
            ["captures"] = new JsonArray(r.Captures.Select(c => (JsonNode?)ToNode(c)).ToArray()),
        };
        if (r.EndedAt is { } ended) o["endedAt"] = FoundationJsonWriter.FormatDate(ended);
        return o;
    }

    private static JsonObject ToNode(FeedbackCapture c)
    {
        var o = new JsonObject
        {
            ["index"] = c.Index,
            ["imageFile"] = c.ImageFile,
            ["cleanImageFile"] = c.CleanImageFile,
            ["size"] = new JsonObject { ["width"] = c.Size.Width, ["height"] = c.Size.Height },
            ["capturedAt"] = FoundationJsonWriter.FormatDate(c.CapturedAt),
            ["marks"] = new JsonArray(c.Marks.Select(m => (JsonNode?)ToNode(m)).ToArray()),
        };
        if (c.SourceApp is not null) o["sourceApp"] = c.SourceApp;
        if (c.WindowTitle is not null) o["windowTitle"] = c.WindowTitle;
        if (c.Note is not null) o["note"] = c.Note;
        if (c.OcrText is not null) o["ocrText"] = c.OcrText;
        return o;
    }

    private static JsonObject ToNode(FeedbackMark m)
    {
        var o = new JsonObject
        {
            ["kind"] = KindName(m.Kind),
            ["box"] = new JsonObject { ["x1"] = m.Box.X1, ["y1"] = m.Box.Y1, ["x2"] = m.Box.X2, ["y2"] = m.Box.Y2 },
        };
        if (m.Badge is { } badge) o["badge"] = badge;
        if (m.Point is { } p) o["point"] = new JsonObject { ["x"] = p.X, ["y"] = p.Y };
        if (m.TextOnImage is not null) o["textOnImage"] = m.TextOnImage;
        if (m.OcrText is not null) o["ocrText"] = m.OcrText;
        if (m.Instruction is not null) o["instruction"] = m.Instruction;
        return o;
    }

    private static string KindName(MarkKind kind) => char.ToLowerInvariant(kind.ToString()[0]) + kind.ToString()[1..];

    // MARK: read

    private static FeedbackRound FromNode(JsonObject o)
    {
        var round = new FeedbackRound(
            Str(o, "name"),
            Str(o, "slug"),
            Str(o, "folderName"),
            Date(o, "startedAt"),
            OptDate(o, "endedAt"),
            Arr(o, "captures").Select(n => FromCapture(n!.AsObject())).ToList())
        {
            SchemaVersion = Int(o, "schemaVersion"),
        };
        return round;
    }

    private static FeedbackCapture FromCapture(JsonObject o)
    {
        var size = Obj(o, "size");
        return new FeedbackCapture(
            Int(o, "index"),
            Str(o, "imageFile"),
            Str(o, "cleanImageFile"),
            new PixelSize(Int(size, "width"), Int(size, "height")),
            Date(o, "capturedAt"),
            OptStr(o, "sourceApp"),
            OptStr(o, "windowTitle"),
            OptStr(o, "note"),
            OptStr(o, "ocrText"),
            Arr(o, "marks").Select(n => FromMark(n!.AsObject())).ToList());
    }

    private static FeedbackMark FromMark(JsonObject o)
    {
        var box = Obj(o, "box");
        FeedbackPoint? point = null;
        if (o["point"] is JsonObject p) point = new FeedbackPoint(Int(p, "x"), Int(p, "y"));
        return new FeedbackMark(
            ParseKind(Str(o, "kind")),
            new FeedbackBox(Int(box, "x1"), Int(box, "y1"), Int(box, "x2"), Int(box, "y2")),
            o["badge"] is null ? null : Int(o, "badge"),
            point,
            OptStr(o, "textOnImage"),
            OptStr(o, "ocrText"),
            OptStr(o, "instruction"));
    }

    private static MarkKind ParseKind(string name)
    {
        foreach (MarkKind k in Enum.GetValues<MarkKind>())
            if (KindName(k) == name) return k;
        throw new JsonException($"Unknown mark kind '{name}'.");
    }

    private static JsonNode Req(JsonObject o, string key) =>
        o[key] ?? throw new JsonException($"Missing key '{key}'.");

    private static string Str(JsonObject o, string key) => Req(o, key).GetValue<string>();
    private static string? OptStr(JsonObject o, string key) => o[key]?.GetValue<string>();
    private static int Int(JsonObject o, string key) => Req(o, key).GetValue<int>();
    private static JsonObject Obj(JsonObject o, string key) => Req(o, key).AsObject();
    private static JsonArray Arr(JsonObject o, string key) => Req(o, key).AsArray();
    private static DateTimeOffset Date(JsonObject o, string key) => FoundationJsonWriter.ParseDate(Str(o, key));
    private static DateTimeOffset? OptDate(JsonObject o, string key) =>
        o[key] is null ? null : FoundationJsonWriter.ParseDate(Str(o, key));
}
