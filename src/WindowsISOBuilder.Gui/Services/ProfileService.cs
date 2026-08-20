using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class ProfileService
{
    public const int SchemaVersion = 1;
    public const int MaxNameLength = 80;

    private readonly AtomicJsonStore<ProfileDocument> _store;
    private ProfileDocument _document;

    public ProfileService(GuiLogger log, string? path = null)
    {
        _store = new AtomicJsonStore<ProfileDocument>(
            log,
            path ?? HistoryService.LocalDataPath("profiles.json"),
            SchemaVersion,
            document => document.SchemaVersion);
        _document = _store.Load();
    }

    internal string StorePath => _store.Path;
    internal bool CanWrite => _store.CanWrite;

    public IReadOnlyList<BuildProfile> GetProfiles() => _document.Profiles
        .OrderByDescending(profile => profile.UpdatedAt)
        .ToArray();

    public BuildProfile Save(BuildProfile profile)
    {
        profile.Name = NormalizeName(profile.Name);
        var now = DateTimeOffset.UtcNow;
        if (string.IsNullOrWhiteSpace(profile.Id)) profile.Id = Guid.NewGuid().ToString("D");
        if (profile.CreatedAt == default) profile.CreatedAt = now;
        profile.UpdatedAt = now;
        profile.PinnedBuild = profile.SelectionMode == ProfileSelectionMode.Pinned ? profile.PinnedBuild : null;
        profile.Editions = profile.Editions.Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

        var index = _document.Profiles.FindIndex(item => string.Equals(item.Id, profile.Id, StringComparison.Ordinal));
        if (index >= 0) _document.Profiles[index] = profile;
        else _document.Profiles.Add(profile);
        _store.Save(_document);
        return profile;
    }

    public bool Delete(string id)
    {
        var removed = _document.Profiles.RemoveAll(profile => string.Equals(profile.Id, id, StringComparison.Ordinal)) > 0;
        if (removed) _store.Save(_document);
        return removed;
    }

    public static string NormalizeName(string? name)
    {
        var normalized = (name ?? string.Empty).Trim();
        if (normalized.Length is < 1 or > MaxNameLength)
        {
            throw new ArgumentException($"Profile name must contain 1..{MaxNameLength} characters.", nameof(name));
        }
        return normalized;
    }

    public static BuildProfile FromHistory(HistoryEntry entry, string name, bool pinned = false) => new()
    {
        Name = NormalizeName(name),
        SelectionMode = pinned ? ProfileSelectionMode.Pinned : ProfileSelectionMode.Recommended,
        Product = entry.Product,
        Architecture = entry.Architecture,
        PinnedBuild = pinned ? new PinnedBuildIdentity
        {
            Product = entry.Product,
            VersionLabel = entry.VersionLabel,
            Build = entry.Build,
            Architecture = entry.Architecture,
            IsPreview = false
        } : null,
        Language = entry.Language,
        Editions = [.. entry.Editions],
        ImageFormat = entry.ImageFormat,
        AddUpdates = entry.AddUpdates,
        Cleanup = entry.Cleanup,
        NetFx3 = entry.NetFx3,
        OutputDirectory = entry.OutputDirectory
    };
}
