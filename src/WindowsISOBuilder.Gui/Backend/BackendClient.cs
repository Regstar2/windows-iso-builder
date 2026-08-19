using System.Text;
using System.Text.Json;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Backend;

public sealed class BackendClient
{
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };

    private readonly string _script;
    private readonly BackendProcessRunner _runner;
    private readonly GuiLogger _log;

    public BackendClient(string script, GuiLogger log, BackendProcessRunner? runner = null)
    {
        _script = script;
        _log = log;
        _runner = runner ?? new BackendProcessRunner();
    }

    public static string NewRequestId() => Guid.NewGuid().ToString("N");

    public async Task<BackendResponse<T>> InvokeAsync<T>(
        string command,
        object arguments,
        Action<string, string>? transportReady = null,
        string? requestId = null,
        CancellationToken cancellationToken = default)
    {
        requestId ??= NewRequestId();

        // Transport directory names are independent from requestId so even a future
        // externally supplied requestId can never select a filesystem location.
        var operationDirectory = Path.Combine(
            Path.GetTempPath(),
            "WindowsISOBuilder",
            "backend",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(operationDirectory);

        try
        {
            var requestPath = Path.Combine(operationDirectory, "request.json");
            var responsePath = Path.Combine(operationDirectory, "response.json");
            var eventPath = Path.Combine(operationDirectory, "events.ndjson");

            // InvokeAsync executes synchronously until its first incomplete await.
            // Publish transport metadata here so a WPF caller never receives it from
            // a thread-pool continuation after ConfigureAwait(false).
            transportReady?.Invoke(eventPath, requestId);

            var request = new BackendRequest(1, requestId, command, arguments);
            var requestJson = JsonSerializer.Serialize(request, JsonOptions);
            await File.WriteAllTextAsync(
                requestPath,
                requestJson,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
                cancellationToken).ConfigureAwait(false);

            _log.Info($"backend command={command} requestId={requestId}");

            var exitCode = await _runner.RunAsync(
                _runner.CreateStartInfo(_script, requestPath, responsePath, eventPath),
                cancellationToken).ConfigureAwait(false);

            if (!File.Exists(responsePath))
            {
                throw new BackendException(
                    "INTERNAL_ERROR",
                    $"Backend exited with code {exitCode} without a response.",
                    requestId: requestId);
            }

            var responseJson = await File.ReadAllTextAsync(responsePath, cancellationToken).ConfigureAwait(false);
            var response = JsonSerializer.Deserialize<BackendResponse<T>>(responseJson, JsonOptions)
                ?? throw new BackendException("INTERNAL_ERROR", "Backend returned an empty response.", requestId: requestId);

            if (!string.Equals(response.RequestId, requestId, StringComparison.Ordinal))
            {
                throw new BackendException("INTERNAL_ERROR", "Backend response requestId mismatch.", requestId: requestId);
            }
            if (!string.Equals(response.Command, command, StringComparison.Ordinal))
            {
                throw new BackendException("INTERNAL_ERROR", "Backend response command mismatch.", requestId: requestId);
            }
            if (response.SchemaVersion != 1)
            {
                throw new BackendException("UNSUPPORTED_SCHEMA", "Несовместимая версия Backend Contract.", requestId: requestId);
            }
            if (!response.Success)
            {
                throw new BackendException(
                    response.Error?.Code ?? "INTERNAL_ERROR",
                    response.Error?.Message ?? "Backend operation failed.",
                    response.Error,
                    response.RequestId);
            }
            if (response.Data is null)
            {
                throw ProtocolError(command, requestId, "success response has no data payload");
            }

            ValidatePayload(command, response.Data, requestId);
            return response;
        }
        finally
        {
            try
            {
                Directory.Delete(operationDirectory, recursive: true);
            }
            catch
            {
                // Transport cleanup is best effort. Build logs and build data are
                // outside this directory and are never removed here.
            }
        }
    }

    private static void ValidatePayload(string command, object data, string requestId)
    {
        switch (command)
        {
            case "GetVersion":
                if (data is not VersionData version)
                {
                    throw ProtocolError(command, requestId, "unexpected data type");
                }
                if (version.ContractSchemaVersion != 1 || version.BuildPlanSchemaVersion != 1)
                {
                    throw new BackendException(
                        "UNSUPPORTED_SCHEMA",
                        $"Unsupported schemas: contract={version.ContractSchemaVersion}, buildPlan={version.BuildPlanSchemaVersion}.",
                        requestId: requestId);
                }
                if (string.IsNullOrWhiteSpace(version.ApplicationVersion))
                {
                    throw ProtocolError(command, requestId, "applicationVersion is empty");
                }
                break;

            case "SearchBuilds":
                if (data is not BuildListData builds ||
                    builds.Builds is null ||
                    builds.Builds.Any(build => !IsValidBuild(build)))
                {
                    throw ProtocolError(command, requestId, "build list contains an invalid build identity");
                }
                break;

            case "GetRecommendedBuild":
                if (data is not BuildData recommended || !IsValidBuild(recommended.Build))
                {
                    throw ProtocolError(command, requestId, "recommended build is missing or invalid");
                }
                break;

            case "GetLanguages":
                if (data is not LanguageListData languages ||
                    languages.Languages is null ||
                    languages.Languages.Count == 0 ||
                    languages.Languages.Any(x => x is null || string.IsNullOrWhiteSpace(x.Code)))
                {
                    throw ProtocolError(command, requestId, "language list is empty or invalid");
                }
                break;

            case "GetEditions":
                if (data is not EditionListData editions ||
                    editions.Editions is null ||
                    editions.Editions.Count == 0 ||
                    editions.Editions.Any(x => x is null || string.IsNullOrWhiteSpace(x.Code)))
                {
                    throw ProtocolError(command, requestId, "edition list is empty or invalid");
                }
                break;

            case "CreateBuildPlan":
                if (data is not BuildPlanData buildPlan || !IsValidBuildPlan(buildPlan.Plan))
                {
                    throw ProtocolError(command, requestId, "BuildPlan v1 payload is missing or invalid");
                }
                break;

            case "RunPreflight":
                if (data is not PreflightData preflight ||
                    preflight.Checks is null ||
                    preflight.Checks.Count == 0 ||
                    preflight.Checks.Any(check =>
                        check is null ||
                        string.IsNullOrWhiteSpace(check.Id) ||
                        string.IsNullOrWhiteSpace(check.Status) ||
                        string.IsNullOrWhiteSpace(check.Severity)))
                {
                    throw ProtocolError(command, requestId, "preflight report has no valid checks");
                }
                break;

            case "ExecuteBuildPlan":
                if (data is not BuildResultDto result ||
                    !string.Equals(result.Stage, "completed", StringComparison.OrdinalIgnoreCase) ||
                    string.IsNullOrWhiteSpace(result.IsoPath) ||
                    !IsSha256(result.Sha256))
                {
                    throw ProtocolError(command, requestId, "completed build result is missing ISO/SHA-256 data");
                }
                break;

            case "CancelBuild":
                if (data is not CancelData cancel || string.IsNullOrWhiteSpace(cancel.TargetRequestId))
                {
                    throw ProtocolError(command, requestId, "cancellation acknowledgement is invalid");
                }
                break;
        }
    }

    private static bool IsValidBuild(BuildDto? build) =>
        build is not null &&
        !string.IsNullOrWhiteSpace(build.Uuid) &&
        !string.IsNullOrWhiteSpace(build.Title) &&
        !string.IsNullOrWhiteSpace(build.Product) &&
        !string.IsNullOrWhiteSpace(build.Build) &&
        !string.IsNullOrWhiteSpace(build.Architecture);

    private static bool IsValidBuildPlan(BuildPlanDto? plan) =>
        plan is not null &&
        plan.SchemaVersion == 1 &&
        IsValidBuild(plan.Build) &&
        !string.IsNullOrWhiteSpace(plan.Language) &&
        plan.Editions is { Count: > 0 } &&
        plan.Editions.All(edition => !string.IsNullOrWhiteSpace(edition)) &&
        !string.IsNullOrWhiteSpace(plan.SourceEdition) &&
        (string.Equals(plan.ImageFormat, "ESD", StringComparison.OrdinalIgnoreCase) ||
         string.Equals(plan.ImageFormat, "WIM", StringComparison.OrdinalIgnoreCase)) &&
        !string.IsNullOrWhiteSpace(plan.OutputDirectory) &&
        !string.IsNullOrWhiteSpace(plan.CacheDirectory);

    private static bool IsSha256(string? value) =>
        value is { Length: 64 } && value.All(static c => c is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F');

    private static BackendException ProtocolError(string command, string requestId, string reason) =>
        new("INTERNAL_ERROR", $"Backend Contract violation for {command}: {reason}.", requestId: requestId);
}

public sealed class BackendException : Exception
{
    public BackendException(string code, string message, BackendError? error = null, string? requestId = null)
        : base(message)
    {
        Code = code;
        Error = error;
        RequestId = requestId;
    }

    public string Code { get; }
    public BackendError? Error { get; }
    public string? RequestId { get; }
}
