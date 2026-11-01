namespace Nextshot.Core.Model;

/// <summary>
/// A feedback round: one folder under the store's root with numbered captures.
/// feedback.json stores this value and is the bundle's source of truth.
/// </summary>
public sealed class FeedbackRound
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public string Name { get; set; }
    public string Slug { get; set; }
    public string FolderName { get; set; }
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset? EndedAt { get; set; }
    public List<FeedbackCapture> Captures { get; set; }

    public FeedbackRound(
        string name,
        string slug,
        string folderName,
        DateTimeOffset startedAt,
        DateTimeOffset? endedAt = null,
        List<FeedbackCapture>? captures = null)
    {
        Name = name;
        Slug = slug;
        FolderName = folderName;
        StartedAt = startedAt;
        EndedAt = endedAt;
        Captures = captures ?? new List<FeedbackCapture>();
    }

    /// <summary>Items are the numbered badges across all captures.</summary>
    public int ItemCount => Captures.Sum(c => c.BadgeNumbers.Count);
}

/// <summary>One saved capture. All coordinates are pixels of ImageFile.</summary>
public sealed class FeedbackCapture
{
    /// <summary>1-based position in the round. It is the item prefix K in the manifest.</summary>
    public int Index { get; set; }
    public string ImageFile { get; set; }
    public string CleanImageFile { get; set; }
    public PixelSize Size { get; set; }
    public DateTimeOffset CapturedAt { get; set; }
    public string? SourceApp { get; set; }
    public string? WindowTitle { get; set; }
    /// <summary>The capture note after badge instructions are taken out of it.</summary>
    public string? Note { get; set; }
    /// <summary>All on-device OCR text of the clean image.</summary>
    public string? OcrText { get; set; }
    public List<FeedbackMark> Marks { get; set; }

    public FeedbackCapture(
        int index,
        string imageFile,
        string cleanImageFile,
        PixelSize size,
        DateTimeOffset capturedAt,
        string? sourceApp = null,
        string? windowTitle = null,
        string? note = null,
        string? ocrText = null,
        List<FeedbackMark>? marks = null)
    {
        Index = index;
        ImageFile = imageFile;
        CleanImageFile = cleanImageFile;
        Size = size;
        CapturedAt = capturedAt;
        SourceApp = sourceApp;
        WindowTitle = windowTitle;
        Note = note;
        OcrText = ocrText;
        Marks = marks ?? new List<FeedbackMark>();
    }

    public HashSet<int> BadgeNumbers =>
        Marks.Where(m => m.Badge.HasValue).Select(m => m.Badge!.Value).ToHashSet();

    /// <summary>The capture's own prompt, next to its images: stem-prompt.md.</summary>
    public string PromptFile => FileStem + "-prompt.md";

    /// <summary>ImageFile without its extension (Swift deletingPathExtension).</summary>
    public string FileStem
    {
        get
        {
            int slash = ImageFile.LastIndexOf('/');
            int dot = ImageFile.LastIndexOf('.');
            return dot > slash + 1 ? ImageFile[..dot] : ImageFile;
        }
    }
}

public enum MarkKind
{
    Counter,
    Rectangle,
    Ellipse,
    Arrow,
    Line,
    Freehand,
    Text,
    Pixelate,
    Spotlight,
}

/// <summary>
/// One annotation on a capture. For Arrow and Line, Box spans the two end
/// points and Point is the head. For Counter, Box is the badge circle and
/// Point is the arrow tip, if any.
/// </summary>
public sealed class FeedbackMark
{
    public MarkKind Kind { get; set; }
    public int? Badge { get; set; }
    public FeedbackBox Box { get; set; }
    public FeedbackPoint? Point { get; set; }
    /// <summary>Text typed on the image with the Text tool.</summary>
    public string? TextOnImage { get; set; }
    /// <summary>On-device OCR text under or next to the mark.</summary>
    public string? OcrText { get; set; }
    /// <summary>The written instruction for a badge, from the capture note.</summary>
    public string? Instruction { get; set; }

    public FeedbackMark(
        MarkKind kind,
        FeedbackBox box,
        int? badge = null,
        FeedbackPoint? point = null,
        string? textOnImage = null,
        string? ocrText = null,
        string? instruction = null)
    {
        Kind = kind;
        Box = box;
        Badge = badge;
        Point = point;
        TextOnImage = textOnImage;
        OcrText = ocrText;
        Instruction = instruction;
    }
}

/// <summary>One line of on-device OCR text, in pixels of the exported PNG.</summary>
public readonly record struct FeedbackTextLine(string Text, FeedbackBox Box);
