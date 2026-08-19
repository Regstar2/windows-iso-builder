using System.Text.Json;
using System.Text.Json.Serialization;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Models;

public sealed record BackendRequest(
    [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
    [property: JsonPropertyName("requestId")] string RequestId,
    [property: JsonPropertyName("command")] string Command,
    [property: JsonPropertyName("arguments")] object Arguments);

public sealed class BackendResponse<T>
{
    public int SchemaVersion { get; set; }
    public string RequestId { get; set; } = "";
    public string Command { get; set; } = "";
    public bool Success { get; set; }
    public string ApplicationVersion { get; set; } = "";
    public T? Data { get; set; }
    public BackendError? Error { get; set; }
}

public sealed class BackendError
{
    public string Code { get; set; } = "";
    public string Message { get; set; } = "";
    public string Stage { get; set; } = "";
    public JsonElement? Details { get; set; }
    public string? LogPath { get; set; }
}

public sealed class VersionData
{
    public string ApplicationVersion { get; set; } = "";
    public int ContractSchemaVersion { get; set; }
    public int BuildPlanSchemaVersion { get; set; }
}

public sealed class BuildListData { public List<BuildDto> Builds { get; set; } = []; }
public sealed class BuildData { public BuildDto? Build { get; set; } }

public sealed class BuildDto
{
    public string Uuid { get; set; } = "";
    public string Title { get; set; } = "";
    public string Product { get; set; } = "";
    public string VersionLabel { get; set; } = "";
    public string Build { get; set; } = "";
    public string Architecture { get; set; } = "";
    public string EntryType { get; set; } = "";
    public DateTimeOffset? CreatedAt { get; set; }
    public bool IsPreview { get; set; }
}

public sealed class LanguageListData { public List<LanguageDto> Languages { get; set; } = []; }
public sealed class LanguageDto
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public override string ToString() => string.IsNullOrWhiteSpace(Name) ? Code : $"{Name} ({Code})";
}

public sealed class EditionListData { public List<EditionDto> Editions { get; set; } = []; }
public sealed class EditionDto
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public override string ToString() => string.IsNullOrWhiteSpace(Name) ? Code : Name;
}

public sealed class BuildPlanData { public BuildPlanDto? Plan { get; set; } }
public sealed class BuildPlanDto
{
    public int SchemaVersion { get; set; }
    public string ApplicationVersion { get; set; } = "";
    public DateTimeOffset? CreatedAt { get; set; }
    public BuildDto? Build { get; set; }
    public string Language { get; set; } = "";
    public List<string> Editions { get; set; } = [];
    public string SourceEdition { get; set; } = "";
    public List<string> VirtualEditions { get; set; } = [];
    public string ImageFormat { get; set; } = "ESD";
    public bool AddUpdates { get; set; } = true;
    public bool Cleanup { get; set; } = true;
    public bool NetFx3 { get; set; }
    public string OutputDirectory { get; set; } = "";
    public string CacheDirectory { get; set; } = "";
    public bool RemoveWorkAfterSuccess { get; set; }
}

public sealed class PreflightData
{
    public bool Ready { get; set; }
    public List<PreflightCheckDto> Checks { get; set; } = [];
}

public sealed class PreflightCheckDto
{
    public string Id { get; set; } = "";
    public string Status { get; set; } = "";
    public string Severity { get; set; } = "";
    public string Code { get; set; } = "";
    public string Message { get; set; } = "";
    public JsonElement? Data { get; set; }

    [JsonIgnore]
    public string StatusLabel => Status.ToLowerInvariant() switch
    {
        "pass" => LocalizationService.Instance.Get("StatusPass"),
        "warning" => LocalizationService.Instance.Get("StatusWarning"),
        "fail" => LocalizationService.Instance.Get("StatusFail"),
        "skipped" => LocalizationService.Instance.Get("StatusSkipped"),
        _ => Status
    };
}

public sealed class BuildResultDto
{
    public string Stage { get; set; } = "";
    public string IsoPath { get; set; } = "";
    public string Sha256 { get; set; } = "";
    public string LogPath { get; set; } = "";
    public string ExecutionLogPath { get; set; } = "";
    public string WorkDirectory { get; set; } = "";
    public string MetadataPath { get; set; } = "";
}

public sealed class CancelData
{
    public bool Requested { get; set; }
    public string TargetRequestId { get; set; } = "";
}

public sealed class BackendEvent
{
    public int SchemaVersion { get; set; }
    public string RequestId { get; set; } = "";
    public long Sequence { get; set; }
    public DateTimeOffset Timestamp { get; set; }
    public string Type { get; set; } = "";
    public string Stage { get; set; } = "";
    public string Message { get; set; } = "";
    public ProgressDto? Progress { get; set; }
}

public sealed class ProgressDto
{
    public double? Percent { get; set; }
    public double? DetailPercent { get; set; }
    public string? SpeedText { get; set; }
    public long? SpeedBytesPerSecond { get; set; }
}
