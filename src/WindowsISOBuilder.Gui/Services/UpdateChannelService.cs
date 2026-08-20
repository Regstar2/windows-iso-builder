namespace WindowsISOBuilder.Gui.Services;

internal static class UpdateChannelService
{
    public const string Stable = "stable";
    public const string Prerelease = "prerelease";

    public static string Normalize(string? value) =>
        string.Equals(value?.Trim(), Prerelease, StringComparison.OrdinalIgnoreCase) ? Prerelease : Stable;
}
