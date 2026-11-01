// Port of Packages/FeedbackKit/Sources/FeedbackKit/BundlePathMode.swift
namespace Nextshot.Core.Bundle;

/// <summary>
/// How the prompts and the manifest name a file in a bundle.
/// <see cref="Absolute"/> is the Mac form: the folder path and a separator, both injectable
/// so the Mac-style golden files render on any machine. <see cref="Windows"/> is the Windows
/// form: forward slashes in backticks, plus one line with the WSL path. <see cref="Relative"/>
/// is the zip export form: every name is relative to the folder that holds the README.
/// </summary>
public abstract record BundlePathMode
{
    private BundlePathMode() { }

    /// <summary>The text that names <paramref name="name"/> in a prompt or the manifest.</summary>
    public abstract string File(string name);

    /// <summary>The <c>path</c> attribute of the prompt's opening tag. A relative prompt has none.</summary>
    public abstract string? TagPath { get; }

    /// <summary>A bundle holds PNGs, a zip export holds JPEGs.</summary>
    internal virtual string ImageNoun => "PNG";

    /// <summary>The extension of the clean copy, for "Open the -clean.png copy".</summary>
    internal virtual string ImageExtension => "png";

    /// <summary>The most visual tokens one image costs.</summary>
    internal virtual int MaxImageTokens => FeedbackExportMaxTokens;

    /// <summary>
    /// The one line that gives the WSL path of <paramref name="folderPath"/>, or null when this
    /// mode adds none. Only the Windows mode returns a line.
    /// </summary>
    internal virtual string? WslLine(string folderPath) => null;

    internal const int FeedbackExportMaxTokens = 4784;
    internal const int StandardMaxTokens = 1568;

    /// <summary>A folder path joined to a name with <paramref name="Separator"/> (default "/").</summary>
    public sealed record Absolute(string FolderPath, char Separator = '/') : BundlePathMode
    {
        public override string File(string name) => FolderPath + Separator + name;
        public override string? TagPath => FolderPath;
    }

    /// <summary>
    /// A Windows folder. Paths use forward slashes, as in <c>C:/Users/me/AppData/.../Nextshot/&lt;round&gt;</c>.
    /// A prompt adds one line with the matching WSL path (<c>/mnt/c/...</c>).
    /// </summary>
    public sealed record Windows : BundlePathMode
    {
        public Windows(string folderPath) => FolderPath = Normalize(folderPath);

        /// <summary>The folder with forward slashes and no trailing slash.</summary>
        public string FolderPath { get; }

        public override string File(string name) => FolderPath + "/" + name;
        public override string? TagPath => FolderPath;

        /// <summary>The WSL form of a Windows path: <c>C:/Users/x</c> becomes <c>/mnt/c/Users/x</c>. Null when the path has no drive letter.</summary>
        public static string? ToWslPath(string windowsPath)
        {
            var path = Normalize(windowsPath);
            if (path.Length < 2 || path[1] != ':' || !char.IsAsciiLetter(path[0])) return null;
            var rest = path[2..];
            if (rest.Length > 0 && rest[0] != '/') return null; // "C:foo" is relative to a drive's current folder
            return "/mnt/" + char.ToLowerInvariant(path[0]) + rest;
        }

        internal override string? WslLine(string folderPath)
        {
            var wsl = ToWslPath(folderPath);
            return wsl is null ? null : $"If you run in WSL, the same folder is `{wsl}`.";
        }

        private static string Normalize(string path)
        {
            var p = path.Replace('\\', '/');
            while (p.Length > 1 && p.EndsWith('/') && !(p.Length == 3 && p[1] == ':')) p = p[..^1];
            return p;
        }
    }

    /// <summary>
    /// A zip export. <paramref name="ExportFolderName"/> is the zip's top folder. No text names it.
    /// </summary>
    public sealed record Relative(string ExportFolderName) : BundlePathMode
    {
        public override string File(string name) => name;
        public override string? TagPath => null;
        internal override string ImageNoun => "image";
        internal override string ImageExtension => "jpg";
        internal override int MaxImageTokens => StandardMaxTokens;
    }
}
