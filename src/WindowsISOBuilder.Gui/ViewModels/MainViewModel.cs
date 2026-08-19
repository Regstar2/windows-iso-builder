using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.ViewModels;

public enum UiState
{
    Idle,
    LoadingBuild,
    LoadingLanguages,
    LoadingEditions,
    ReadyToPreflight,
    Preflighting,
    PreflightFailed,
    ReadyToBuild,
    Building,
    Cancelling,
    Completed,
    Failed,
    Cancelled
}

internal enum OperationKind
{
    Startup,
    Recommended,
    Search,
    Languages,
    Editions,
    Preflight,
    Build
}

public sealed class MainViewModel : ObservableObject
{
    private static readonly HashSet<string> KnownEventTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "stage", "progress", "completed", "failed", "cancelled", "warning", "info"
    };

    private readonly GuiLogger _log = new();
    private readonly List<BuildDto> _catalogResults = [];
    private BackendClient? _client;
    private BuildDto? _build;
    private BuildPlanDto? _plan;
    private string? _activeBuildRequestId;
    private UiState _state;
    private OperationKind _lastOperation = OperationKind.Startup;
    private string _status = "Запуск...";
    private string _version = string.Empty;
    private string _product = "Windows 11";
    private string _architecture = "amd64";
    private string _imageFormat = "ESD";
    private string _outputDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "ISO");
    private string _searchText = "Windows 11";
    private LanguageDto? _selectedLanguage;
    private double _progress;
    private string _speed = string.Empty;
    private string _stage = "startup";
    private BuildResultDto? _result;
    private string _errorTitle = string.Empty;
    private string _errorExplanation = string.Empty;
    private string _technicalDetails = string.Empty;
    private string? _errorLogPath;
    private bool _showServicing;
    private bool _addUpdates = true;
    private bool _cleanup = true;
    private bool _netFx3;
    private bool _includePreview;

    public ObservableCollection<LanguageDto> Languages { get; } = [];
    public ObservableCollection<EditionChoice> Editions { get; } = [];
    public ObservableCollection<BuildDto> Builds { get; } = [];
    public ObservableCollection<PreflightCheckDto> Checks { get; } = [];

    public string Version { get => _version; private set => Set(ref _version, value); }
    public string Status { get => _status; private set => Set(ref _status, value); }

    public string Product
    {
        get => _product;
        set
        {
            if (!Set(ref _product, value)) return;
            ResetBuildSelection();
        }
    }

    public string Architecture
    {
        get => _architecture;
        set
        {
            if (!Set(ref _architecture, value)) return;
            if (_build is not null && !string.Equals(_build.Architecture, value, StringComparison.OrdinalIgnoreCase))
            {
                ResetBuildSelection();
            }
        }
    }

    public string ImageFormat
    {
        get => _imageFormat;
        set { if (Set(ref _imageFormat, value)) InvalidatePlan(); }
    }

    public string OutputDirectory
    {
        get => _outputDirectory;
        set { if (Set(ref _outputDirectory, value)) InvalidatePlan(); }
    }

    public string SearchText { get => _searchText; set => Set(ref _searchText, value); }
    public string Stage { get => _stage; private set => Set(ref _stage, value); }
    public string ErrorTitle { get => _errorTitle; private set => Set(ref _errorTitle, value); }
    public string ErrorExplanation { get => _errorExplanation; private set => Set(ref _errorExplanation, value); }
    public string TechnicalDetails { get => _technicalDetails; private set => Set(ref _technicalDetails, value); }
    public string? ErrorLogPath { get => _errorLogPath; private set { if (Set(ref _errorLogPath, value)) Raise(nameof(HasErrorLog)); } }

    public LanguageDto? SelectedLanguage
    {
        get => _selectedLanguage;
        set
        {
            if (Set(ref _selectedLanguage, value) && value is not null)
            {
                _ = LoadEditionsAsync();
            }
        }
    }

    public BuildDto? SelectedBuild
    {
        get => _build;
        set
        {
            if (!Set(ref _build, value)) return;
            Raise(nameof(SelectedBuildSummary));
            if (value is not null)
            {
                _ = LoadLanguagesAsync();
            }
        }
    }

    public string SelectedBuildSummary => _build is null
        ? "Сборка не выбрана"
        : $"{_build.VersionLabel} · Build {_build.Build} · {ArchitectureLabel(_build.Architecture)} · {(_build.IsPreview ? "Preview" : "Stable")}";

    public double Progress { get => _progress; private set => Set(ref _progress, value); }
    public string Speed { get => _speed; private set => Set(ref _speed, value); }

    public BuildResultDto? Result
    {
        get => _result;
        private set
        {
            if (!Set(ref _result, value)) return;
            Raise(nameof(HasResult));
            Raise(nameof(HasResultLog));
            Raise(nameof(ResultDirectory));
        }
    }

    public UiState State
    {
        get => _state;
        private set
        {
            if (!Set(ref _state, value)) return;
            _log.Info($"state={value}");
            Raise(nameof(IsBuilding));
            Raise(nameof(IsConfigurationEnabled));
            Raise(nameof(CanBuild));
            Raise(nameof(HasResult));
            Raise(nameof(HasError));
            Raise(nameof(IsCancelled));
            Raise(nameof(ActiveBuildRequestId));
            LoadRecommendedCommand.RaiseCanExecuteChanged();
            SearchCommand.RaiseCanExecuteChanged();
            PreflightCommand.RaiseCanExecuteChanged();
            BuildCommand.RaiseCanExecuteChanged();
            CancelCommand.RaiseCanExecuteChanged();
            RetryCommand.RaiseCanExecuteChanged();
        }
    }

    public bool IsBuilding => State is UiState.Building or UiState.Cancelling;
    public bool IsConfigurationEnabled => State is not UiState.Building and not UiState.Cancelling and not UiState.Preflighting and not UiState.LoadingBuild and not UiState.LoadingLanguages and not UiState.LoadingEditions;
    public bool CanBuild => State == UiState.ReadyToBuild;
    public bool HasResult => State == UiState.Completed && Result is not null;
    public bool HasError => State == UiState.Failed;
    public bool IsCancelled => State == UiState.Cancelled;
    public bool HasResultLog => Result is not null && !string.IsNullOrWhiteSpace(Result.LogPath) && File.Exists(Result.LogPath);
    public bool HasErrorLog => !string.IsNullOrWhiteSpace(ErrorLogPath) && File.Exists(ErrorLogPath);
    public string? ResultDirectory => Result?.IsoPath is { Length: > 0 } path ? Path.GetDirectoryName(path) : null;
    public string? ActiveBuildRequestId => _activeBuildRequestId;

    public bool AddUpdates { get => _addUpdates; set { if (Set(ref _addUpdates, value)) InvalidatePlan(); } }
    public bool Cleanup { get => _cleanup; set { if (Set(ref _cleanup, value)) InvalidatePlan(); } }
    public bool NetFx3 { get => _netFx3; set { if (Set(ref _netFx3, value)) InvalidatePlan(); } }
    public bool IncludePreview { get => _includePreview; set => Set(ref _includePreview, value); }
    public bool ShowServicing { get => _showServicing; set { if (Set(ref _showServicing, value)) RefreshCatalogDisplay(); } }

    public AsyncCommand LoadRecommendedCommand { get; }
    public AsyncCommand SearchCommand { get; }
    public AsyncCommand PreflightCommand { get; }
    public AsyncCommand BuildCommand { get; }
    public AsyncCommand CancelCommand { get; }
    public AsyncCommand RetryCommand { get; }

    public MainViewModel()
    {
        LoadRecommendedCommand = new AsyncCommand(LoadRecommendedAsync, () => !IsBusyMetadata());
        SearchCommand = new AsyncCommand(SearchAsync, () => !IsBusyMetadata());
        PreflightCommand = new AsyncCommand(PreflightAsync, () => State is UiState.ReadyToPreflight or UiState.PreflightFailed or UiState.ReadyToBuild);
        BuildCommand = new AsyncCommand(BuildAsync, () => CanBuild);
        CancelCommand = new AsyncCommand(async () => { await CancelAsync(); }, () => State == UiState.Building);
        RetryCommand = new AsyncCommand(RetryAsync, () => State == UiState.Failed);
        _ = InitializeAsync();
    }

    private bool IsBusyMetadata() => State is UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Preflighting or UiState.Building or UiState.Cancelling;

    private async Task InitializeAsync()
    {
        _lastOperation = OperationKind.Startup;
        try
        {
            var path = new BackendPathResolver().Resolve();
            _log.Info($"backendPath={path}");
            _client = new BackendClient(path, _log);
            var response = await _client.InvokeAsync<VersionData>("GetVersion", new { });
            Version = response.Data!.ApplicationVersion;
            _log.Info($"applicationVersion={Version} contractSchema=1 buildPlanSchema=1");
            Status = "Готово";
            State = UiState.Idle;
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private async Task LoadRecommendedAsync()
    {
        if (_client is null) return;
        _lastOperation = OperationKind.Recommended;
        try
        {
            State = UiState.LoadingBuild;
            Status = "Получение рекомендуемой сборки...";
            var architecture = Architecture == "all" ? "amd64" : Architecture;
            var response = await _client.InvokeAsync<BuildData>(
                "GetRecommendedBuild",
                new { product = Product, architecture, forceRefresh = true });
            SelectedBuild = response.Data!.Build;
            Status = "Рекомендуемая сборка выбрана";
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private async Task SearchAsync()
    {
        if (_client is null) return;
        _lastOperation = OperationKind.Search;
        try
        {
            State = UiState.LoadingBuild;
            Status = "Поиск сборок...";
            var response = await _client.InvokeAsync<BuildListData>(
                "SearchBuilds",
                new { search = SearchText, architecture = Architecture, includePreview = IncludePreview });
            _catalogResults.Clear();
            _catalogResults.AddRange(response.Data!.Builds);
            RefreshCatalogDisplay();
            Status = $"Найдено: {Builds.Count}";
            State = UiState.Idle;
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private void RefreshCatalogDisplay()
    {
        Builds.Clear();
        foreach (var build in _catalogResults)
        {
            if (ShowServicing || build.EntryType.Equals("Windows", StringComparison.OrdinalIgnoreCase))
            {
                Builds.Add(build);
            }
        }
    }

    private void ResetBuildSelection()
    {
        if (IsBuilding) return;
        if (Set(ref _build, null, nameof(SelectedBuild))) Raise(nameof(SelectedBuildSummary));
        _selectedLanguage = null;
        Raise(nameof(SelectedLanguage));
        Languages.Clear();
        Editions.Clear();
        Checks.Clear();
        _plan = null;
        if (State is not UiState.LoadingBuild and not UiState.LoadingLanguages and not UiState.LoadingEditions)
        {
            State = UiState.Idle;
            Status = "Выберите сборку";
        }
    }

    private void InvalidatePlan()
    {
        if (IsBuilding || _plan is null && State != UiState.ReadyToBuild) return;
        _plan = null;
        Checks.Clear();
        if (_build is not null && SelectedLanguage is not null && Editions.Count > 0)
        {
            State = UiState.ReadyToPreflight;
            Status = "Параметры изменены. Выполните проверку снова.";
        }
    }

    private async Task LoadLanguagesAsync()
    {
        if (_client is null || _build is null) return;
        _lastOperation = OperationKind.Languages;
        try
        {
            State = UiState.LoadingLanguages;
            Status = "Загрузка языков...";
            Languages.Clear();
            Editions.Clear();
            Checks.Clear();
            _plan = null;
            var response = await _client.InvokeAsync<LanguageListData>("GetLanguages", new { updateId = _build.Uuid });
            foreach (var language in response.Data!.Languages) Languages.Add(language);
            SelectedLanguage = Languages.FirstOrDefault(x => x.Code.Equals("ru-ru", StringComparison.OrdinalIgnoreCase))
                ?? Languages.FirstOrDefault();
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private async Task LoadEditionsAsync()
    {
        if (_client is null || _build is null || SelectedLanguage is null) return;
        _lastOperation = OperationKind.Editions;
        try
        {
            State = UiState.LoadingEditions;
            Status = "Загрузка редакций...";
            Editions.Clear();
            Checks.Clear();
            _plan = null;
            var response = await _client.InvokeAsync<EditionListData>(
                "GetEditions",
                new { updateId = _build.Uuid, language = SelectedLanguage.Code });
            foreach (var edition in response.Data!.Editions)
            {
                var choice = new EditionChoice(edition);
                choice.PropertyChanged += (_, args) =>
                {
                    if (args.PropertyName == nameof(EditionChoice.Selected)) InvalidatePlan();
                };
                Editions.Add(choice);
            }
            Status = "Выберите редакции";
            State = UiState.ReadyToPreflight;
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private async Task<BuildPlanDto?> CreatePlanAsync()
    {
        if (_client is null || _build is null || SelectedLanguage is null) return null;

        var selected = Editions.Where(x => x.Selected).Select(x => x.Dto.Code).ToArray();
        if (selected.Length == 0)
        {
            MessageBox.Show("Выберите хотя бы одну редакцию.", "Windows ISO Builder", MessageBoxButton.OK, MessageBoxImage.Information);
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
            Status = "Проверка готовности...";
            Checks.Clear();
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
            State = response.Data.Ready ? UiState.ReadyToBuild : UiState.PreflightFailed;
            Status = response.Data.Ready ? "Проверка пройдена" : "Найдены проблемы";
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
            $"{_build.Product} {_build.VersionLabel}\nBuild {_build.Build}\n{ArchitectureLabel(_build.Architecture)} · {SelectedLanguage.Code}\n\n" +
            $"Редакции: {string.Join(", ", _plan.Editions)}\nФормат: {_plan.ImageFormat}\nРезультат: {_plan.OutputDirectory}\n\nСоздать ISO?",
            "Подтверждение сборки",
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
                    Status = backendEvent.Message;
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
            Status = "ISO готов";
        }
        catch (Exception exception)
        {
            if (exception is BackendException { Code: "BUILD_CANCELLED" })
            {
                State = UiState.Cancelled;
                Status = "Сборка отменена";
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
            Status = "Отмена сборки...";
            var response = await _client.InvokeAsync<CancelData>(
                "CancelBuild",
                new { targetRequestId = _activeBuildRequestId, cacheDirectory = _plan.CacheDirectory });
            if (!response.Data!.Requested)
            {
                if (State == UiState.Cancelling) State = UiState.Building;
                Status = "Backend не принял запрос отмены.";
                return false;
            }
            return true;
        }
        catch (Exception exception)
        {
            _log.Error("CancelBuild request failed", exception);
            if (State == UiState.Cancelling) State = UiState.Building;
            Status = "Не удалось отправить запрос отмены. Сборка продолжает выполняться.";
            MessageBox.Show(
                "Не удалось отправить запрос отмены. Сборка продолжает выполняться. Повторите отмену или дождитесь завершения.",
                "Windows ISO Builder",
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
        Progress = 0;
        Speed = string.Empty;
        Stage = "startup";
        _plan = null;
        State = _build is not null && SelectedLanguage is not null && Editions.Count > 0
            ? UiState.ReadyToPreflight
            : UiState.Idle;
        Status = "Готово";
    }

    private void ClearError()
    {
        ErrorTitle = string.Empty;
        ErrorExplanation = string.Empty;
        TechnicalDetails = string.Empty;
        ErrorLogPath = null;
    }

    private void Fail(Exception exception)
    {
        State = UiState.Failed;
        _log.Error("UI operation failed", exception);
        if (exception is BackendException backendException)
        {
            var mapping = ErrorMapper.Map(backendException.Code);
            ErrorLogPath = backendException.Error?.LogPath;
            ErrorTitle = mapping.Title;
            ErrorExplanation = mapping.Action;
            TechnicalDetails =
                $"error.code: {backendException.Code}\n" +
                $"stage: {backendException.Error?.Stage}\n" +
                $"backend message: {backendException.Message}\n" +
                $"logPath: {backendException.Error?.LogPath}\n" +
                $"requestId: {backendException.RequestId}";
        }
        else
        {
            ErrorTitle = "Произошла ошибка интерфейса Windows ISO Builder";
            ErrorExplanation = "Откройте технические подробности или журнал GUI.";
            TechnicalDetails = exception.Message;
        }
        Status = "Ошибка";
    }

    public void OpenPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || (!File.Exists(path) && !Directory.Exists(path))) return;
        Process.Start(new ProcessStartInfo(path!) { UseShellExecute = true });
    }

    public string DiagnosticText =>
        $"state={State}\nstage={Stage}\nactiveRequestId={ActiveBuildRequestId}\nerrorLog={ErrorLogPath}\n{TechnicalDetails}";

    private static string ArchitectureLabel(string architecture) =>
        architecture.Equals("amd64", StringComparison.OrdinalIgnoreCase) ? "x64" : architecture;
}

public sealed class EditionChoice : ObservableObject
{
    private bool _selected;

    public EditionChoice(EditionDto dto) => Dto = dto;

    public EditionDto Dto { get; }
    public string Name => Dto.ToString();
    public bool Selected { get => _selected; set => Set(ref _selected, value); }
}
