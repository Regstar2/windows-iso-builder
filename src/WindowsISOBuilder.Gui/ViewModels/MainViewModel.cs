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

public sealed partial class MainViewModel : ObservableObject
{
    private static readonly HashSet<string> KnownEventTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "stage", "progress", "completed", "failed", "cancelled", "warning", "info"
    };

    private readonly GuiLogger _log = new();
    private readonly LocalizationService _loc = LocalizationService.Instance;
    private readonly List<BuildDto> _catalogResults = [];
    private BackendClient? _client;
    private BuildDto? _build;
    private BuildDto? _selectedCatalogBuild;
    private BuildPlanDto? _plan;
    private string? _activeBuildRequestId;
    private UiState _state;
    private OperationKind _lastOperation = OperationKind.Startup;
    private string _statusKey = "StatusStarting";
    private object?[] _statusArgs = [];
    private string _version = AppVersionInfo.Current;
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
    private string? _errorCode;
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
    public string Status => _loc.Format(_statusKey, _statusArgs);

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
    public string TechnicalDetails { get => _technicalDetails; private set => Set(ref _technicalDetails, value); }
    public string? ErrorLogPath { get => _errorLogPath; private set { if (Set(ref _errorLogPath, value)) Raise(nameof(HasErrorLog)); } }

    public string ErrorTitle
    {
        get
        {
            var mapping = ErrorMapper.Map(_errorCode);
            return _loc.Get(mapping.TitleKey);
        }
    }

    public string ErrorExplanation
    {
        get
        {
            var mapping = ErrorMapper.Map(_errorCode);
            return _loc.Get(mapping.ActionKey);
        }
    }

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

    public BuildDto? SelectedCatalogBuild
    {
        get => _selectedCatalogBuild;
        set
        {
            if (!Set(ref _selectedCatalogBuild, value)) return;
            Raise(nameof(CatalogSelectionSummary));
            Raise(nameof(CanUseCatalogSelection));
        }
    }

    public string SelectedBuildSummary => _build is null
        ? _loc.Get("NoBuildSelected")
        : $"{_build.VersionLabel} · Build {_build.Build} · {ArchitectureLabel(_build.Architecture)} · {_loc.Get(_build.IsPreview ? "ChannelPreview" : "ChannelStable")}";

    public string CatalogSelectionSummary => SelectedCatalogBuild is null
        ? _loc.Get("CatalogSelectionNone")
        : _loc.Format("CatalogSelectedFormat", SelectedCatalogBuild.Title);

    public bool CanUseCatalogSelection => SelectedCatalogBuild is not null;

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
            RaiseBuildPanelProperties();
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
            Raise(nameof(PreflightSummary));
            RaiseBuildPanelProperties();
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

    public bool ShowBuildIdle => State is not UiState.Building and not UiState.Cancelling and not UiState.Completed and not UiState.Failed and not UiState.Cancelled;
    public bool ShowBuildProgress => State is UiState.Building or UiState.Cancelling;
    public bool ShowBuildError => State == UiState.Failed;
    public bool ShowBuildResult => HasResult;
    public bool ShowBuildCancelled => State == UiState.Cancelled;

    public string BuildPanelTitle => State switch
    {
        UiState.Building => _loc.Get("BuildInProgressTitle"),
        UiState.Cancelling => _loc.Get("BuildCancellingTitle"),
        UiState.Completed => _loc.Get("BuildCompletedTitle"),
        UiState.Cancelled => _loc.Get("BuildCancelledTitle"),
        UiState.Failed => ErrorTitle,
        _ => _loc.Get("BuildSectionTitle")
    };

    public bool HasPreflightChecks => Checks.Count > 0;
    public string PreflightActionLabel => _loc.Get(Checks.Count == 0 ? "ButtonPreflight" : "ButtonPreflightAgain");

    public string PreflightSummary
    {
        get
        {
            if (State == UiState.Preflighting) return _loc.Get("PreflightRunning");
            if (Checks.Count == 0) return _loc.Get("PreflightNotRun");
            var issues = Checks.Count(x => x.Status.Equals("fail", StringComparison.OrdinalIgnoreCase));
            var warnings = Checks.Count(x => x.Status.Equals("warning", StringComparison.OrdinalIgnoreCase));
            var passed = Checks.Count(x => x.Status.Equals("pass", StringComparison.OrdinalIgnoreCase));
            if (issues == 0 && State is (UiState.ReadyToBuild or UiState.Building or UiState.Cancelling or UiState.Completed))
            {
                return _loc.Format("PreflightReadyFormat", passed);
            }
            return _loc.Format("PreflightProblemsFormat", issues, warnings);
        }
    }

    public IEnumerable<PreflightCheckDto> ProblemChecks => Checks
        .Where(x => !x.Status.Equals("pass", StringComparison.OrdinalIgnoreCase) &&
                    !x.Status.Equals("skipped", StringComparison.OrdinalIgnoreCase))
        .Take(4);

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
        _loc.CultureChanged += OnCultureChanged;
        _ = InitializeAsync();
    }

    private void OnCultureChanged(object? sender, EventArgs e)
    {
        Raise(nameof(Status));
        Raise(nameof(SelectedBuildSummary));
        Raise(nameof(CatalogSelectionSummary));
        Raise(nameof(PreflightSummary));
        Raise(nameof(PreflightActionLabel));
        Raise(nameof(BuildPanelTitle));
        Raise(nameof(ErrorTitle));
        Raise(nameof(ErrorExplanation));
    }

    private void SetStatus(string key, params object?[] args)
    {
        _statusKey = key;
        _statusArgs = args;
        Raise(nameof(Status));
    }

    private void SetBuildStageStatus(string stage)
    {
        var key = stage.ToLowerInvariant() switch
        {
            "startup" => "StageStartup",
            "catalog" => "StageCatalog",
            "metadata" => "StageMetadata",
            "plan" => "StagePlan",
            "preflight" => "StagePreflight",
            "download" => "StageDownload",
            "convert" => "StageConvert",
            "verify" => "StageVerify",
            "completed" => "StageCompleted",
            "failed" => "StageFailed",
            _ => "StageWorking"
        };
        SetStatus(key);
    }

    private void RaisePreflightProperties()
    {
        Raise(nameof(PreflightSummary));
        Raise(nameof(ProblemChecks));
        Raise(nameof(HasPreflightChecks));
        Raise(nameof(PreflightActionLabel));
    }

    private void RaiseBuildPanelProperties()
    {
        Raise(nameof(ShowBuildIdle));
        Raise(nameof(ShowBuildProgress));
        Raise(nameof(ShowBuildError));
        Raise(nameof(ShowBuildResult));
        Raise(nameof(ShowBuildCancelled));
        Raise(nameof(BuildPanelTitle));
    }

    private bool IsBusyMetadata() => State is UiState.LoadingBuild or UiState.LoadingLanguages or UiState.LoadingEditions or UiState.Preflighting or UiState.Building or UiState.Cancelling;
}

public sealed class EditionChoice : ObservableObject
{
    private bool _selected;

    public EditionChoice(EditionDto dto) => Dto = dto;

    public EditionDto Dto { get; }
    public string Name => Dto.ToString();
    public bool Selected { get => _selected; set => Set(ref _selected, value); }
}
