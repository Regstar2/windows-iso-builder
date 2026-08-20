using WindowsISOBuilder.Gui.Backend;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal interface IStoredConfigurationCatalog
{
    Task<BuildDto> GetRecommendedAsync(string product, string architecture);
    Task<IReadOnlyList<BuildDto>> SearchAsync(string search, string architecture, bool includePreview);
    Task<IReadOnlyList<LanguageDto>> GetLanguagesAsync(string updateId);
    Task<IReadOnlyList<EditionDto>> GetEditionsAsync(string updateId, string language);
}

internal sealed class BackendStoredConfigurationCatalog : IStoredConfigurationCatalog
{
    private readonly BackendClient _client;

    public BackendStoredConfigurationCatalog(BackendClient client) => _client = client;

    public async Task<BuildDto> GetRecommendedAsync(string product, string architecture)
    {
        var response = await _client.InvokeAsync<BuildData>(
            "GetRecommendedBuild",
            new { product, architecture, forceRefresh = true });
        return response.Data!.Build!;
    }

    public async Task<IReadOnlyList<BuildDto>> SearchAsync(string search, string architecture, bool includePreview)
    {
        var response = await _client.InvokeAsync<BuildListData>(
            "SearchBuilds",
            new { search, architecture, includePreview });
        return response.Data!.Builds;
    }

    public async Task<IReadOnlyList<LanguageDto>> GetLanguagesAsync(string updateId)
    {
        var response = await _client.InvokeAsync<LanguageListData>("GetLanguages", new { updateId });
        return response.Data!.Languages;
    }

    public async Task<IReadOnlyList<EditionDto>> GetEditionsAsync(string updateId, string language)
    {
        var response = await _client.InvokeAsync<EditionListData>("GetEditions", new { updateId, language });
        return response.Data!.Editions;
    }
}

internal sealed record StoredConfigurationResolution(
    BuildDto Build,
    IReadOnlyList<LanguageDto> Languages,
    LanguageDto? SelectedLanguage,
    IReadOnlyList<EditionDto> Editions,
    IReadOnlyList<string> MissingEditions,
    bool LanguageMissing)
{
    public bool HasStaleValues => LanguageMissing || MissingEditions.Count > 0;
}

internal sealed class StoredConfigurationResolver
{
    private readonly IStoredConfigurationCatalog _catalog;

    public StoredConfigurationResolver(IStoredConfigurationCatalog catalog) => _catalog = catalog;

    public Task<BuildDto> ResolveRecommendedAsync(string product, string architecture) =>
        _catalog.GetRecommendedAsync(product, architecture);

    public async Task<BuildDto?> ResolvePinnedAsync(PinnedBuildIdentity identity)
    {
        var results = await _catalog.SearchAsync(identity.Build, identity.Architecture, includePreview: true);
        return results.FirstOrDefault(build =>
            string.Equals(build.Product, identity.Product, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(build.Build, identity.Build, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(build.Architecture, identity.Architecture, StringComparison.OrdinalIgnoreCase) &&
            (string.IsNullOrWhiteSpace(identity.VersionLabel) || string.Equals(build.VersionLabel, identity.VersionLabel, StringComparison.OrdinalIgnoreCase)));
    }

    public Task<BuildDto?> ResolveHistoryAsync(HistoryEntry entry) => ResolvePinnedAsync(new PinnedBuildIdentity
    {
        Product = entry.Product,
        VersionLabel = entry.VersionLabel,
        Build = entry.Build,
        Architecture = entry.Architecture,
        IsPreview = false
    });

    public async Task<StoredConfigurationResolution> ResolveValuesAsync(
        BuildDto build,
        string language,
        IReadOnlyCollection<string> requestedEditions)
    {
        var languages = await _catalog.GetLanguagesAsync(build.Uuid);
        var selectedLanguage = languages.FirstOrDefault(item => item.Code.Equals(language, StringComparison.OrdinalIgnoreCase));
        if (selectedLanguage is null)
        {
            return new StoredConfigurationResolution(build, languages, null, [], requestedEditions.ToArray(), LanguageMissing: true);
        }

        var editions = await _catalog.GetEditionsAsync(build.Uuid, selectedLanguage.Code);
        var availableCodes = editions.Select(item => item.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing = requestedEditions.Where(code => !availableCodes.Contains(code)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        return new StoredConfigurationResolution(build, languages, selectedLanguage, editions, missing, LanguageMissing: false);
    }
}
