namespace Nextshot.Core.Settings;

/// <summary>
/// The channel of this build. The RELEASE_CHANNEL compile constant marks a
/// release build. When it is undefined, the build is a dev build.
/// </summary>
public static class BuildInfo
{
    public static BuildChannel Channel
    {
        get
        {
#if RELEASE_CHANNEL
            return BuildChannel.Release;
#else
            return BuildChannel.Dev;
#endif
        }
    }
}
