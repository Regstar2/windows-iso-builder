using System.Collections.ObjectModel;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.ViewModels;

public enum HistoryFilter
{
    All,
    Completed,
    Failed,
    Cancelled
}

public enum StoredApplyResult
{
    Applied,
    ExactBuildUnavailable
}

public sealed partial class MainViewModel
{
    private readonly HistoryService _historyService = new(new GuiLogger());
    private readonly ProfileService _profileService = new(new GuiLogger());
    private HistoryFilter _historyFilter;
    private string _storedConfigurationWarning = string.Empty;
    private bool _applyingStoredConfiguration;

    public ObservableCollection<HistoryEntry> HistoryEntries { get; } = [];
    public ObservableCollection<BuildProfile> Profiles { get; } = [];

    public string StoredConfigurationWarning
    {
        get => _storedConfigurationWarning;
        private set
        {
            if (Set(ref _storedConfigurationWarning, value)) Raise(nameof(HasStoredConfigurationWarning));
        }
    }

    public bool HasStoredConfigurationWarning => !string.IsNullOrWhiteSpace(StoredConfigurationWarning);
    public bool CanCaptureProfile => _build is not null && SelectedLanguage is not null && Editions.Any(choice => choice.Selected);

    public void RefreshLocalData()
    {
        RefreshHistory();
        RefreshProfiles();
    }

    public void SetHistoryFilter(HistoryFilter filter)
    {
        _historyFilter = filter;
        RefreshHistory();
    }

    public void RefreshHistory()
    {
        HistoryEntries.Clear();
        foreach (var entry in _historyService.GetEntries().Where(HistoryMatchesFilter)) HistoryEntries.Add(entry);
    }

    public void RefreshProfiles()
    {
        Profiles.Clear();
        foreach (var profile in _profileService.GetProfiles()) Profiles.Add(profile);
    }

    public void DeleteHistory(HistoryEntry entry)
    {
        if (_historyService.Delete(entry.Id)) RefreshHistory();
    }

    public void ClearHistory()
    {
        _historyService.Clear();
        RefreshHistory();
    }

    public void DeleteProfile(BuildProfile profile)
    {
        if (_profileService.Delete(profile.Id)) RefreshProfiles();
    }

    public BuildProfile SaveProfile(BuildProfile profile)
    {
        var saved = _profileService.Save(profile);
        RefreshProfiles();
        return saved;
    }

    public BuildProfile CreateProfileDraftFromCurrent(string name = "")
    {
        if (_build is null) throw new InvalidOperationException("No active build is selected.");
        return new BuildProfile
        {
            Name = name,
            SelectionMode = ProfileSelectionMode.Recommended,
            Product = _build.Product,
            Architecture = _build.Architecture,
            Language = SelectedLanguage?.Code ?? string.Empty,
            Editions = Editions.Where(choice => choice.Selected).Select(choice => choice.Dto.Code).ToList(),
            ImageFormat = ImageFormat,
            AddUpdates = AddUpdates,
            Cleanup = Cleanup,
            NetFx3 = NetFx3,
            OutputDirectory = OutputDirectory
        };
    }

    public BuildProfile CreateProfileDraftFromHistory(HistoryEntry entry, string name = "", bool pinned = false) =>
        ProfileService.FromHistory(entry, name.Length == 0 ? _loc.Get("ProfileDefaultName") : name, pinned);

    public BuildProfile CreatePinnedProfileDraftFromCurrent(string name = "")
    {
        var profile = CreateProfileDraftFromCurrent(name);
        profile.SelectionMode = ProfileSelectionMode.Pinned;
        profile.PinnedBuild = PinnedBuildIdentity.FromBuild(_build!);
        return profile;
    }

    public async Task<StoredApplyResult> RepeatHistoryAsync(HistoryEntry entry, bool useRecommendedFallback = false)
    {
        if (_client is null) return StoredApplyResult.ExactBuildUnavailable;
        var resolver = new StoredConfigurationResolver(new BackendStoredConfigurationCatalog(_client));
        BuildDto? build = useRecommendedFallback
            ? await resolver.ResolveRecommendedAsync(entry.Product, entry.Architecture)
            : await resolver.ResolveHistoryAsync(entry);
        if (build is null) return StoredApplyResult.ExactBuildUnavailable;

        var resolution = await resolver.ResolveValuesAsync(build, entry.Language, entry.Editions);
        ApplyStoredConfiguration(
            resolution,
            entry.Product,
            entry.Architecture,
            entry.Language,
            entry.Editions,
            entry.ImageFormat,
            entry.AddUpdates,
            entry.Cleanup,
            entry.NetFx3,
            entry.OutputDirectory);
        return StoredApplyResult.Applied;
    }

    public async Task<StoredApplyResult> UseProfileAsync(BuildProfile profile, bool useRecommendedFallback = false)
    {
        if (_client is null) return StoredApplyResult.ExactBuildUnavailable;
        var resolver = new StoredConfigurationResolver(new BackendStoredConfigurationCatalog(_client));
        BuildDto? build;
        if (useRecommendedFallback || profile.SelectionMode == ProfileSelectionMode.Recommended)
        {
            build = await resolver.ResolveRecommendedAsync(profile.Product, profile.Architecture);
        }
        else if (profile.PinnedBuild is not null)
        {
            build = await resolver.ResolvePinnedAsync(profile.PinnedBuild);
        }
        else
        {
            build = null;
        }
        if (build is null) return StoredApplyResult.ExactBuildUnavailable;

        var resolution = await resolver.ResolveValuesAsync(build, profile.Language, profile.Editions);
        ApplyStoredConfiguration(
            resolution,
            profile.Product,
            profile.Architecture,
            profile.Language,
            profile.Editions,
            profile.ImageFormat,
            profile.AddUpdates,
            profile.Cleanup,
            profile.NetFx3,
            profile.OutputDirectory);
        return StoredApplyResult.Applied;
    }

    internal async Task<StoredConfigurationResolution?> ResolveProfileEditorAsync(BuildProfile profile)
    {
        if (_client is null) return null;
        var resolver = new StoredConfigurationResolver(new BackendStoredConfigurationCatalog(_client));
        BuildDto? build = profile.SelectionMode == ProfileSelectionMode.Recommended
            ? await resolver.ResolveRecommendedAsync(profile.Product, profile.Architecture)
            : profile.PinnedBuild is null ? null : await resolver.ResolvePinnedAsync(profile.PinnedBuild);
        if (build is null) return null;
        return await resolver.ResolveValuesAsync(build, profile.Language, profile.Editions);
    }

    public void AcknowledgeStoredConfigurationChange()
    {
        if (_applyingStoredConfiguration) return;
        StoredConfigurationWarning = string.Empty;
    }

    private void ApplyStoredConfiguration(
        StoredConfigurationResolution resolution,
        string product,
        string architecture,
        string language,
        IReadOnlyCollection<string> requestedEditions,
        string imageFormat,
        bool addUpdates,
        bool cleanup,
        bool netFx3,
        string outputDirectory)
    {
        _applyingStoredConfiguration = true;
        try
        {
            Set(ref _product, product, nameof(Product));
            Set(ref _architecture, architecture, nameof(Architecture));
            Set(ref _build, resolution.Build, nameof(SelectedBuild));
            Raise(nameof(SelectedBuildSummary));
            Languages.Clear();
            foreach (var item in resolution.Languages) Languages.Add(item);
            _selectedLanguage = resolution.SelectedLanguage;
            Raise(nameof(SelectedLanguage));
            Editions.Clear();
            var requested = requestedEditions.ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var edition in resolution.Editions)
            {
                var choice = new EditionChoice(edition) { Selected = requested.Contains(edition.Code) };
                choice.PropertyChanged += (_, args) =>
                {
                    if (args.PropertyName != nameof(EditionChoice.Selected)) return;
                    AcknowledgeStoredConfigurationChange();
                    InvalidatePlan();
                    RaiseWorkflowGuidance();
                    Raise(nameof(CanCaptureProfile));
                };
                Editions.Add(choice);
            }
            _imageFormat = imageFormat;
            Raise(nameof(ImageFormat));
            _addUpdates = addUpdates;
            Raise(nameof(AddUpdates));
            _cleanup = cleanup;
            Raise(nameof(Cleanup));
            _netFx3 = netFx3;
            Raise(nameof(NetFx3));
            _outputDirectory = outputDirectory;
            Raise(nameof(OutputDirectory));
            _plan = null;
            Checks.Clear();
            RaisePreflightProperties();
            Result = null;
            ClearError();

            if (resolution.LanguageMissing)
            {
                StoredConfigurationWarning = _loc.Format("StoredLanguageUnavailable", language);
                State = UiState.Idle;
                SetStatus("StatusStoredConfigurationNeedsAttention");
            }
            else if (resolution.MissingEditions.Count > 0)
            {
                StoredConfigurationWarning = _loc.Format("StoredEditionsUnavailable", string.Join(", ", resolution.MissingEditions));
                State = UiState.Idle;
                SetStatus("StatusStoredConfigurationNeedsAttention");
            }
            else
            {
                StoredConfigurationWarning = string.Empty;
                State = UiState.ReadyToPreflight;
                SetStatus("StatusStoredConfigurationApplied");
            }
            Raise(nameof(CanCaptureProfile));
            RaiseWorkflowGuidance();
        }
        finally
        {
            _applyingStoredConfiguration = false;
        }
    }

    private bool HistoryMatchesFilter(HistoryEntry entry) => _historyFilter switch
    {
        HistoryFilter.Completed => entry.Status == HistoryStatus.Completed,
        HistoryFilter.Failed => entry.Status == HistoryStatus.Failed,
        HistoryFilter.Cancelled => entry.Status is HistoryStatus.Cancelled or HistoryStatus.Interrupted,
        _ => entry.Status != HistoryStatus.Pending
    };

    private HistoryEntry CreatePendingHistoryEntry() => new()
    {
        Product = _build?.Product ?? Product,
        VersionLabel = _build?.VersionLabel ?? string.Empty,
        Build = _build?.Build ?? string.Empty,
        Architecture = _build?.Architecture ?? Architecture,
        Language = SelectedLanguage?.Code ?? string.Empty,
        Editions = _plan?.Editions.ToList() ?? Editions.Where(choice => choice.Selected).Select(choice => choice.Dto.Code).ToList(),
        ImageFormat = _plan?.ImageFormat ?? ImageFormat,
        AddUpdates = _plan?.AddUpdates ?? AddUpdates,
        Cleanup = _plan?.Cleanup ?? Cleanup,
        NetFx3 = _plan?.NetFx3 ?? NetFx3,
        OutputDirectory = _plan?.OutputDirectory ?? OutputDirectory
    };
}
