using System.Text.Json.Serialization;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Models;

public enum HistoryStatus
{
    Pending,
    Completed,
    Failed,
    Cancelled,
    Interrupted
}

public enum ProfileSelectionMode
{
    Recommended,
    Pinned
}

public sealed class PinnedBuildIdentity
{
    public string Product { get; set; } = "";
    public string VersionLabel { get; set; } = "";
    public string Build { get; set; } = "";
    public string Architecture { get; set; } = "";
    public bool IsPreview { get; set; }

    public static PinnedBuildIdentity FromBuild(BuildDto build) => new()
    {
        Product = build.Product,
        VersionLabel = build.VersionLabel,
        Build = build.Build,
        Architecture = build.Architecture,
        IsPreview = build.IsPreview
    };
}

public sealed class HistoryEntry
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset? FinishedAt { get; set; }
    public HistoryStatus Status { get; set; }
    public string Product { get; set; } = "";
    public string VersionLabel { get; set; } = "";
    public string Build { get; set; } = "";
    public string Architecture { get; set; } = "";
    public string Language { get; set; } = "";
    public List<string> Editions { get; set; } = [];
    public string ImageFormat { get; set; } = "ESD";
    public bool AddUpdates { get; set; } = true;
    public bool Cleanup { get; set; } = true;
    public bool NetFx3 { get; set; }
    public string OutputDirectory { get; set; } = "";
    public string? IsoPath { get; set; }
    public string? Sha256 { get; set; }
    public string? LogPath { get; set; }
    public string? ExecutionLogPath { get; set; }
    public string? MetadataPath { get; set; }
    public string? ErrorCode { get; set; }

    [JsonIgnore] public string ProductTitle => string.Join(" ", new[] { Product, VersionLabel }.Where(x => !string.IsNullOrWhiteSpace(x)));
    [JsonIgnore] public string EditionsText => string.Join(", ", Editions);
    [JsonIgnore] public string ArchitectureLabel => Architecture.Equals("amd64", StringComparison.OrdinalIgnoreCase) ? "x64" : Architecture;
    [JsonIgnore] public string StatusLabel => LocalizationService.Instance.Get(Status switch
    {
        HistoryStatus.Completed => "HistoryStatusCompleted",
        HistoryStatus.Failed => "HistoryStatusFailed",
        HistoryStatus.Cancelled => "HistoryStatusCancelled",
        HistoryStatus.Interrupted => "HistoryStatusInterrupted",
        _ => "HistoryStatusPending"
    });
    [JsonIgnore] public string StartedDisplay => StartedAt.ToLocalTime().ToString("g");
    [JsonIgnore] public string OptionsText => LocalizationService.Instance.Format("HistoryOptionsFormat", AddUpdates, Cleanup, NetFx3);
    [JsonIgnore] public bool IsoExists => !string.IsNullOrWhiteSpace(IsoPath) && File.Exists(IsoPath);
    [JsonIgnore] public bool LogExists => !string.IsNullOrWhiteSpace(LogPath) && File.Exists(LogPath);
    [JsonIgnore] public bool ExecutionLogExists => !string.IsNullOrWhiteSpace(ExecutionLogPath) && File.Exists(ExecutionLogPath);
    [JsonIgnore] public bool MetadataExists => !string.IsNullOrWhiteSpace(MetadataPath) && File.Exists(MetadataPath);
    [JsonIgnore] public bool HasSha256 => !string.IsNullOrWhiteSpace(Sha256);
    [JsonIgnore] public string AccessibilitySummary => LocalizationService.Instance.Format(
        "HistoryAccessibilitySummary",
        ProductTitle,
        Build,
        StatusLabel,
        StartedDisplay,
        ArchitectureLabel,
        ImageFormat);
}

public sealed class BuildProfile
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string Name { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public ProfileSelectionMode SelectionMode { get; set; } = ProfileSelectionMode.Recommended;
    public string Product { get; set; } = "Windows 11";
    public string Architecture { get; set; } = "amd64";
    public PinnedBuildIdentity? PinnedBuild { get; set; }
    public string Language { get; set; } = "ru-ru";
    public List<string> Editions { get; set; } = [];
    public string ImageFormat { get; set; } = "ESD";
    public bool AddUpdates { get; set; } = true;
    public bool Cleanup { get; set; } = true;
    public bool NetFx3 { get; set; }
    public string OutputDirectory { get; set; } = "";

    [JsonIgnore] public string EditionsText => string.Join(", ", Editions);
    [JsonIgnore] public string ArchitectureLabel => Architecture.Equals("amd64", StringComparison.OrdinalIgnoreCase) ? "x64" : Architecture;
    [JsonIgnore] public string SelectionModeLabel => LocalizationService.Instance.Get(
        SelectionMode == ProfileSelectionMode.Recommended ? "ProfileModeRecommended" : "ProfileModePinned");
    [JsonIgnore] public string BuildHint => SelectionMode == ProfileSelectionMode.Pinned && PinnedBuild is not null
        ? PinnedBuild.Build
        : LocalizationService.Instance.Get("ProfileRecommendedHint");
    [JsonIgnore] public string AccessibilitySummary => LocalizationService.Instance.Format(
        "ProfileAccessibilitySummary",
        Name,
        Product,
        SelectionModeLabel,
        Language,
        EditionsText);
}

internal sealed class HistoryDocument
{
    public int SchemaVersion { get; set; } = HistoryService.SchemaVersion;
    public List<HistoryEntry> Entries { get; set; } = [];
}

internal sealed class ProfileDocument
{
    public int SchemaVersion { get; set; } = ProfileService.SchemaVersion;
    public List<BuildProfile> Profiles { get; set; } = [];
}
