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

        var requestPath = Path.Combine(operationDirectory, "request.json");
        var responsePath = Path.Combine(operationDirectory, "response.json");
        var eventPath = Path.Combine(operationDirectory, "events.ndjson");

        var request = new BackendRequest(1, requestId, command, arguments);
        var requestJson = JsonSerializer.Serialize(request, JsonOptions);
        await File.WriteAllTextAsync(
            requestPath,
            requestJson,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            cancellationToken).ConfigureAwait(false);

        transportReady?.Invoke(eventPath, requestId);
        _log.Info($"backend command={command} requestId={requestId}");

        try
        {
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

            // GetVersion is the GUI compatibility handshake. Contract and BuildPlan
            // schemas are independent interfaces and both must be supported before
            // the GUI starts issuing metadata/plan/build commands.
            if (string.Equals(command, "GetVersion", StringComparison.Ordinal) &&
                response.Data is VersionData version &&
                (version.ContractSchemaVersion != 1 || version.BuildPlanSchemaVersion != 1))
            {
                throw new BackendException(
                    "UNSUPPORTED_SCHEMA",
                    $"Unsupported schemas: contract={version.ContractSchemaVersion}, buildPlan={version.BuildPlanSchemaVersion}.",
                    requestId: requestId);
            }

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
