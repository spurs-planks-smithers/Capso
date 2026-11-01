using Nextshot.Core.Model;

namespace Nextshot.Core.Store;

/// <summary>The rounds found by <see cref="RoundStore.ListRecentAsync"/>.</summary>
/// <param name="Rounds">Active round first (when it holds a capture), then ended rounds newest end first.</param>
/// <param name="Unreadable">Folder names whose feedback.json could not be read.</param>
/// <param name="NewerSchema">Folder names written under a newer schemaVersion. They stay hidden and untouched.</param>
public sealed record RoundListing(
    IReadOnlyList<FeedbackRound> Rounds,
    IReadOnlyList<string> Unreadable,
    IReadOnlyList<string> NewerSchema)
{
    /// <summary>How many rounds this copy hides because another copy wrote them.</summary>
    public int HiddenCount => NewerSchema.Count;
}

public sealed class RoundStoreException : Exception
{
    public RoundStoreException(string message) : base(message) { }
}
