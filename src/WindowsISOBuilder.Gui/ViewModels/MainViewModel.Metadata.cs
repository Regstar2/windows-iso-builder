using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.ViewModels;

public sealed partial class MainViewModel
{
    private async Task InitializeAsync()
    {
        _lastOperation = OperationKind.Startup;
        State = UiState.LoadingBuild;
        SetStatus("StatusCheckingBackend");
        ClearError();
        try
        {
            var path = new BackendPathResolver().Resolve();
            _log.Info("backend resolved");
            _client = new BackendClient(path, _log);
            var response = await _client.InvokeAsync<VersionData>("GetVersion", new { });
            _log.Info($"guiVersion={Version} backendApplicationVersion={response.Data!.ApplicationVersion} contractSchema=1 buildPlanSchema=1");
            SetStatus("StatusReady");
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
            SetStatus("StatusLoadingRecommended");
            var architecture = Architecture == "all" ? "amd64" : Architecture;
            var response = await _client.InvokeAsync<BuildData>(
                "GetRecommendedBuild",
                new { product = Product, architecture, forceRefresh = true });
            SelectedBuild = response.Data!.Build;
            SetStatus("StatusRecommendedSelected");
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
            SetStatus("StatusSearching");
            var response = await _client.InvokeAsync<BuildListData>(
                "SearchBuilds",
                new { search = SearchText, architecture = Architecture, includePreview = IncludePreview });
            _catalogResults.Clear();
            _catalogResults.AddRange(response.Data!.Builds);
            RefreshCatalogDisplay();
            SetStatus("StatusFoundFormat", Builds.Count);
            State = UiState.Idle;
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }

    private void RefreshCatalogDisplay()
    {
        SelectedCatalogBuild = null;
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
        RaisePreflightProperties();
        _plan = null;
        if (State is not UiState.LoadingBuild and not UiState.LoadingLanguages and not UiState.LoadingEditions)
        {
            State = UiState.Idle;
            SetStatus("StatusSelectBuild");
        }
    }

    private void InvalidatePlan()
    {
        if (IsBuilding || _plan is null && State != UiState.ReadyToBuild) return;
        _plan = null;
        Checks.Clear();
        RaisePreflightProperties();
        if (_build is not null && SelectedLanguage is not null && Editions.Count > 0)
        {
            State = UiState.ReadyToPreflight;
            SetStatus("StatusParametersChanged");
        }
    }

    private async Task LoadLanguagesAsync()
    {
        if (_client is null || _build is null) return;
        _lastOperation = OperationKind.Languages;
        try
        {
            State = UiState.LoadingLanguages;
            SetStatus("StatusLoadingLanguages");
            Languages.Clear();
            Editions.Clear();
            Checks.Clear();
            RaisePreflightProperties();
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
            SetStatus("StatusLoadingEditions");
            Editions.Clear();
            Checks.Clear();
            RaisePreflightProperties();
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
            SetStatus("StatusSelectEditions");
            State = UiState.ReadyToPreflight;
        }
        catch (Exception exception)
        {
            Fail(exception);
        }
    }
}
