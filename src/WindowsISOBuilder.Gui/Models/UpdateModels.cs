namespace WindowsISOBuilder.Gui.Models;

internal enum UpdateCheckStatus
{
    UpToDate,
    UpdateAvailable,
    NoPublishedRelease
}

internal sealed record UpdateCheckResult(
    UpdateCheckStatus Status,
    string CurrentVersion,
    string? LatestVersion,
    string? ReleaseName,
    string? ReleaseUrl,
    string? ReleaseNotes);
