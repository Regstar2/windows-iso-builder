using System.Diagnostics;
using System.Windows;
using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.ViewModels;

public sealed partial class MainViewModel
{
    private async Task<BuildPlanDto?> CreatePlanAsync()
    {
        if (_client is null || _build is null || SelectedLanguage is null) return null;

        var selected = Editions.Where(x => x.Selected).Select(x => x.Dto.Code).ToArray();
        if (selected.Length == 0)
        {
            MessageBox.Show(
                _loc.Get("MsgSelectEdition"),
                _loc.Get("MsgSelectEditionTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return null;
        }

        // Path creation/writability belongs to backend preflight. The GUI must not
        // turn PATH_NOT_WRITABLE into an unrelated frontend exception before
        // CreateBuildPlan/RunPreflight can return the structured backend result.
        var systemDrive = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        var cacheDirectory = Path.Combine(systemDrive + Path.DirectorySeparatorChar, "UUP-ISO-Work");
        var response = await _client.InvokeAsync<BuildPlanData>(
            "CreateBuildPlan",
            new
            {
                build = _build,
                language = SelectedLanguage.Code,
                editions = selected,
                imageFormat = ImageFormat,
                addUpdates = AddUpdates,
                cleanup = Cleanup,
                netFx3 = NetFx3,
                outputDirectory = OutputDirectory,
                cacheDirectory
            });
        return response.Data!.Plan;
    }

    private async Task PreflightAsync()
    {
        _lastOperation = OperationKind.Preflight;
        try
        {
            State = UiState.Preflighting;
            SetStatus("StatusPreflighting");
            Checks.Clear();
            RaisePreflightProperties();
            _plan = await CreatePlanAsync();
            if (_plan is null)
            {
                State = UiState.ReadyToPreflight;
                return;
            }

            var response = await _client!.InvokeAsync<PreflightData>(
                "RunPreflight",
                new { buildPlan = _plan, onlineChecks = true });
            foreach (var check in response.Data!.Checks) Checks.Add(check);
            RaisePreflightProperties();
            State = response.Data.Ready ? UiState.ReadyToBuild : UiState.PreflightFailed;
            SetStatus(response.Data.Ready ? "StatusPreflightPassed" : "StatusPreflightProblems");
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private async Task BuildAsync()
    {
        if (_client is null || _plan is null || _build is null || SelectedLanguage is null) return;
        _lastOperation = OperationKind.Build;

        var confirmation = MessageBox.Show(
            _loc.Format(
                "BuildConfirmationMessage",
                _build.Product,
                _build.VersionLabel,
                _build.Build,
                ArchitectureLabel(_build.Architecture),
                SelectedLanguage.Code,
                string.Join(", ", _plan.Editions),
                _plan.ImageFormat,
                _plan.OutputDirectory),
            _loc.Get("BuildConfirmationTitle"),
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (confirmation != MessageBoxResult.Yes) return;

        try
        {
            State = UiState.Building;
            Progress = 0;
            Speed = string.Empty;
            ClearError();
            Result = null;

            _activeBuildRequestId = BackendClient.NewRequestId();
            Raise(nameof(ActiveBuildRequestId));
            var eventPath = string.Empty;
            var reader = new NdjsonEventReader();
            var operation = _client.InvokeAsync<BuildResultDto>(
                "ExecuteBuildPlan",
                new { plan = _plan },
                (path, _) => eventPath = path,
                _activeBuildRequestId);

            while (!operation.IsCompleted)
            {
                await Task.Delay(300);
                foreach (var backendEvent in await reader.ReadNewAsync(eventPath))
                {
                    if (!KnownEventTypes.Contains(backendEvent.Type)) continue;
                    Stage = backendEvent.Stage;
                    SetBuildStageStatus(backendEvent.Stage);
                    if (backendEvent.Progress?.Percent is double percent) Progress = percent;
                    Speed = backendEvent.Progress?.SpeedText ?? string.Empty;
                    if (backendEvent.Type.Equals("cancelled", StringComparison.OrdinalIgnoreCase))
                    {
                        State = UiState.Cancelling;
                    }
                }
            }

            var response = await operation;
            Result = response.Data!;
            Stage = response.Data!.Stage;
            State = UiState.Completed;
            Progress = 100;
            SetStatus("StatusIsoReady");
        }
        catch (Exception exception)
        {
            if (exception is BackendException { Code: "BUILD_CANCELLED" })
            {
                State = UiState.Cancelled;
                SetStatus("StatusBuildCancelled");
            }
            else
            {
                Fail(exception);
            }
        }
        finally
        {
            _activeBuildRequestId = null;
            Raise(nameof(ActiveBuildRequestId));
        }
    }

    public async Task<bool> CancelAsync()
    {
        if (_client is null || _plan is null || _activeBuildRequestId is null)
        {
            return State is UiState.Completed or UiState.Cancelled or UiState.Failed;
        }
        if (State != UiState.Building) return State != UiState.Cancelling;

        try
        {
            State = UiState.Cancelling;
            SetStatus("StatusCancelling");
            var response = await _client.InvokeAsync<CancelData>(
                "CancelBuild",
                new { targetRequestId = _activeBuildRequestId, cacheDirectory = _plan.CacheDirectory });
            if (!response.Data!.Requested)
            {
                if (State == UiState.Cancelling) State = UiState.Building;
                SetStatus("StatusCancelRejected");
                return false;
            }
            return true;
        }
        catch (Exception exception)
        {
            _log.Error("CancelBuild request failed", exception);
            if (State == UiState.Cancelling) State = UiState.Building;
            SetStatus("StatusCancelSendFailed");
            MessageBox.Show(
                _loc.Get("CancelSendFailedMessage"),
                _loc.Get("AppTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return false;
        }
    }

    public async Task WaitForBuildTerminationAsync()
    {
        while (State is UiState.Building or UiState.Cancelling)
        {
            await Task.Delay(150);
        }
    }

    private async Task RetryAsync()
    {
        ClearError();
        switch (_lastOperation)
        {
            case OperationKind.Build when _plan is not null:
                State = UiState.ReadyToBuild;
                await BuildAsync();
                break;
            case OperationKind.Preflight:
                State = UiState.ReadyToPreflight;
                await PreflightAsync();
                break;
            case OperationKind.Editions:
                await LoadEditionsAsync();
                break;
            case OperationKind.Languages:
                await LoadLanguagesAsync();
                break;
            case OperationKind.Search:
                State = UiState.Idle;
                await SearchAsync();
                break;
            case OperationKind.Recommended:
                State = UiState.Idle;
                await LoadRecommendedAsync();
                break;
            default:
                await InitializeAsync();
                break;
        }
    }

    public void StartOver()
    {
        if (IsBuilding) return;
        Result = null;
        ClearError();
        Checks.Clear();
        RaisePreflightProperties();
        Progress = 0;
        Speed = string.Empty;
        Stage = "startup";
        _plan = null;
        State = _build is not null && SelectedLanguage is not null && Editions.Count > 0
            ? UiState.ReadyToPreflight
            : UiState.Idle;
        SetStatus("StatusReady");
    }

    private void ClearError()
    {
        _errorCode = null;
        Raise(nameof(ErrorTitle));
        Raise(nameof(ErrorExplanation));
        TechnicalDetails = string.Empty;
        ErrorLogPath = null;
    }

    private void Fail(Exception exception)
    {
        State = UiState.Failed;
        _log.Error("UI operation failed", exception);
        if (exception is BackendException backendException)
        {
            _errorCode = backendException.Code;
            ErrorLogPath = backendException.Error?.LogPath;
            var safeMessage = DiagnosticSanitizer.Sanitize(backendException.Message);
            var safeLogPath = DiagnosticSanitizer.Sanitize(backendException.Error?.LogPath ?? string.Empty);
            TechnicalDetails =
                $"error.code: {backendException.Code}\n" +
                $"stage: {backendException.Error?.Stage}\n" +
                $"backend message: {safeMessage}\n" +
                $"logPath: {safeLogPath}\n" +
                $"requestId: {DiagnosticSanitizer.Sanitize(backendException.RequestId ?? string.Empty)}";
        }
        else
        {
            _errorCode = "GUI_ERROR";
            TechnicalDetails = DiagnosticSanitizer.Sanitize(exception.Message);
        }
        Raise(nameof(ErrorTitle));
        Raise(nameof(ErrorExplanation));
        Raise(nameof(BuildPanelTitle));
        SetStatus("StatusError");
    }

    public void OpenPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || (!File.Exists(path) && !Directory.Exists(path))) return;
        Process.Start(new ProcessStartInfo(path!) { UseShellExecute = true });
    }

    public string DiagnosticText => DiagnosticSanitizer.Sanitize(
        $"state={State}\nstage={Stage}\nactiveRequestId={ActiveBuildRequestId}\nerrorLog={ErrorLogPath}\n{TechnicalDetails}");

    private static string ArchitectureLabel(string architecture) =>
        architecture.Equals("amd64", StringComparison.OrdinalIgnoreCase) ? "x64" : architecture;
}
