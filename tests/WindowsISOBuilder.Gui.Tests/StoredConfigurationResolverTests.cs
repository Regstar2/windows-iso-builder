using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class StoredConfigurationResolverTests
{
    [TestMethod]
    public async Task RecommendedProfileUsesRecommendedBuildLookup()
    {
        var fake = FakeCatalog.Standard();
        var resolver = new StoredConfigurationResolver(fake);
        var build = await resolver.ResolveRecommendedAsync("Windows 11", "amd64");
        Assert.AreEqual("26200.1000", build.Build);
        Assert.AreEqual(1, fake.RecommendedCalls);
        Assert.AreEqual(0, fake.SearchCalls);
    }

    [TestMethod]
    public async Task PinnedProfileSearchesForExactBuild()
    {
        var fake = FakeCatalog.Standard();
        var resolver = new StoredConfigurationResolver(fake);
        var build = await resolver.ResolvePinnedAsync(Pinned());
        Assert.IsNotNull(build);
        Assert.AreEqual("26200.1000", build.Build);
        Assert.AreEqual(1, fake.SearchCalls);
        Assert.AreEqual("26200.1000", fake.LastSearch);
    }

    [TestMethod]
    public async Task PinnedResolutionDoesNotAcceptDifferentBuild()
    {
        var fake = FakeCatalog.Standard();
        fake.Builds = [Build("26200.2000")];
        Assert.IsNull(await new StoredConfigurationResolver(fake).ResolvePinnedAsync(Pinned()));
    }

    [TestMethod]
    public async Task PinnedResolutionDoesNotAcceptDifferentProduct()
    {
        var fake = FakeCatalog.Standard();
        fake.Builds = [Build("26200.1000", product: "Windows 10")];
        Assert.IsNull(await new StoredConfigurationResolver(fake).ResolvePinnedAsync(Pinned()));
    }

    [TestMethod]
    public async Task PinnedResolutionDoesNotAcceptDifferentArchitecture()
    {
        var fake = FakeCatalog.Standard();
        fake.Builds = [Build("26200.1000", architecture: "arm64")];
        Assert.IsNull(await new StoredConfigurationResolver(fake).ResolvePinnedAsync(Pinned()));
    }

    [TestMethod]
    public async Task UnavailableLanguageIsDetectedBeforeEditionLookup()
    {
        var fake = FakeCatalog.Standard();
        var resolver = new StoredConfigurationResolver(fake);
        var result = await resolver.ResolveValuesAsync(Build("26200.1000"), "de-de", ["Professional"]);
        Assert.IsTrue(result.LanguageMissing);
        Assert.IsTrue(result.HasStaleValues);
        Assert.AreEqual(0, fake.EditionCalls);
    }

    [TestMethod]
    public async Task UnavailableEditionIsReportedWithoutSilentRemoval()
    {
        var fake = FakeCatalog.Standard();
        var resolver = new StoredConfigurationResolver(fake);
        var result = await resolver.ResolveValuesAsync(Build("26200.1000"), "ru-ru", ["Professional", "Enterprise"]);
        CollectionAssert.AreEquivalent(new[] { "Enterprise" }, result.MissingEditions.ToArray());
        CollectionAssert.AreEquivalent(new[] { "Professional", "Core" }, result.Editions.Select(x => x.Code).ToArray());
    }

    [TestMethod]
    public async Task AvailableLanguageAndEditionsResolveCleanly()
    {
        var result = await new StoredConfigurationResolver(FakeCatalog.Standard())
            .ResolveValuesAsync(Build("26200.1000"), "ru-ru", ["Professional"]);
        Assert.IsFalse(result.HasStaleValues);
        Assert.AreEqual("ru-ru", result.SelectedLanguage?.Code);
        Assert.AreEqual(0, result.MissingEditions.Count);
    }

    [DataTestMethod]
    [DataRow(HistoryStatus.Completed)]
    [DataRow(HistoryStatus.Failed)]
    [DataRow(HistoryStatus.Cancelled)]
    public async Task RepeatCanResolveAnyTerminalHistoryStatus(HistoryStatus status)
    {
        var entry = History(status);
        var build = await new StoredConfigurationResolver(FakeCatalog.Standard()).ResolveHistoryAsync(entry);
        Assert.IsNotNull(build);
        Assert.AreEqual(entry.Build, build.Build);
    }

    [TestMethod]
    public async Task RepeatReturnsNullWhenHistoricalBuildIsGone()
    {
        var fake = FakeCatalog.Standard(); fake.Builds = [];
        Assert.IsNull(await new StoredConfigurationResolver(fake).ResolveHistoryAsync(History(HistoryStatus.Completed)));
    }

    [TestMethod]
    public async Task RecommendedFallbackIsASeparateExplicitResolverCall()
    {
        var fake = FakeCatalog.Standard(); fake.Builds = [];
        var resolver = new StoredConfigurationResolver(fake);
        Assert.IsNull(await resolver.ResolveHistoryAsync(History(HistoryStatus.Completed)));
        Assert.AreEqual(0, fake.RecommendedCalls);
        Assert.IsNotNull(await resolver.ResolveRecommendedAsync("Windows 11", "amd64"));
        Assert.AreEqual(1, fake.RecommendedCalls);
    }

    [TestMethod]
    public void ProfilesDoNotContainBuildPlanOrCacheDirectoryFields()
    {
        var properties = typeof(BuildProfile).GetProperties().Select(property => property.Name).ToArray();
        CollectionAssert.DoesNotContain(properties, "BuildPlan");
        CollectionAssert.DoesNotContain(properties, "CacheDirectory");
        CollectionAssert.Contains(properties, "OutputDirectory");
    }

    [TestMethod]
    public void HistoryDoesNotContainBuildPlanOrBackendPayloadFields()
    {
        var properties = typeof(HistoryEntry).GetProperties().Select(property => property.Name).ToArray();
        CollectionAssert.DoesNotContain(properties, "BuildPlan");
        CollectionAssert.DoesNotContain(properties, "Uuid");
        CollectionAssert.DoesNotContain(properties, "SignedUrl");
        CollectionAssert.Contains(properties, "ErrorCode");
    }

    [TestMethod]
    public void ProfileFromHistoryDefaultsToRecommendedButCanBePinnedExplicitly()
    {
        var entry = History(HistoryStatus.Completed);
        var recommended = ProfileService.FromHistory(entry, "Recommended");
        var pinned = ProfileService.FromHistory(entry, "Pinned", pinned: true);
        Assert.AreEqual(ProfileSelectionMode.Recommended, recommended.SelectionMode);
        Assert.IsNull(recommended.PinnedBuild);
        Assert.AreEqual(ProfileSelectionMode.Pinned, pinned.SelectionMode);
        Assert.AreEqual(entry.Build, pinned.PinnedBuild?.Build);
    }

    private static PinnedBuildIdentity Pinned() => new()
    {
        Product = "Windows 11", VersionLabel = "25H2", Build = "26200.1000", Architecture = "amd64"
    };

    private static HistoryEntry History(HistoryStatus status) => new()
    {
        Status = status, Product = "Windows 11", VersionLabel = "25H2", Build = "26200.1000", Architecture = "amd64",
        Language = "ru-ru", Editions = ["Professional"], ImageFormat = "ESD"
    };

    private static BuildDto Build(string number, string product = "Windows 11", string architecture = "amd64") => new()
    {
        Uuid = Guid.NewGuid().ToString("D"), Title = product + " 25H2", Product = product, VersionLabel = "25H2",
        Build = number, Architecture = architecture, EntryType = "Windows", IsPreview = false
    };

    private sealed class FakeCatalog : IStoredConfigurationCatalog
    {
        public int RecommendedCalls { get; private set; }
        public int SearchCalls { get; private set; }
        public int EditionCalls { get; private set; }
        public string? LastSearch { get; private set; }
        public List<BuildDto> Builds { get; set; } = [];
        public List<LanguageDto> Languages { get; set; } = [];
        public List<EditionDto> Editions { get; set; } = [];
        public BuildDto Recommended { get; set; } = Build("26200.1000");

        public static FakeCatalog Standard() => new()
        {
            Builds = [Build("26200.1000")],
            Languages = [new LanguageDto { Code = "ru-ru", Name = "Russian" }, new LanguageDto { Code = "en-us", Name = "English" }],
            Editions = [new EditionDto { Code = "Professional", Name = "Professional" }, new EditionDto { Code = "Core", Name = "Home" }]
        };

        public Task<BuildDto> GetRecommendedAsync(string product, string architecture)
        {
            RecommendedCalls++;
            return Task.FromResult(Recommended);
        }

        public Task<IReadOnlyList<BuildDto>> SearchAsync(string search, string architecture, bool includePreview)
        {
            SearchCalls++; LastSearch = search;
            return Task.FromResult<IReadOnlyList<BuildDto>>(Builds);
        }

        public Task<IReadOnlyList<LanguageDto>> GetLanguagesAsync(string updateId) =>
            Task.FromResult<IReadOnlyList<LanguageDto>>(Languages);

        public Task<IReadOnlyList<EditionDto>> GetEditionsAsync(string updateId, string language)
        {
            EditionCalls++;
            return Task.FromResult<IReadOnlyList<EditionDto>>(Editions);
        }
    }
}
