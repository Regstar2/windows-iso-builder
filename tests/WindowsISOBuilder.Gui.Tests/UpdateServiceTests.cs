using System.Net;
using System.Net.Http;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class UpdateServiceTests
{
    [TestMethod]
    public void SemanticVersionImplementsPrereleasePrecedence()
    {
        var stable = Parse("1.0.0");
        var rc = Parse("1.0.0-rc.1");
        var rc2 = Parse("1.0.0-rc.2");
        var rc11 = Parse("1.0.0-rc.11");
        Assert.IsTrue(stable.CompareTo(rc) > 0);
        Assert.IsTrue(rc2.CompareTo(rc11) < 0);
        Assert.AreEqual(0, Parse("1.2.3+build.1").CompareTo(Parse("1.2.3+build.9")));
    }

    [TestMethod]
    public void SemanticVersionRejectsMalformedValues()
    {
        foreach (var value in new[] { "", "1", "1.2", "01.2.3", "1.2.3-01", "1.2.3-", "1.2.3+" })
        {
            Assert.IsFalse(SemanticVersion.TryParse(value, out _), value);
        }
    }

    [TestMethod]
    public async Task StableChannelIgnoresPrereleaseAndUsesOfficialEndpointWithoutAuthorization()
    {
        HttpRequestMessage? captured = null;
        var provider = new StubHttpClientProvider((request, _) =>
        {
            captured = request;
            return Task.FromResult(JsonResponse("""[{"tag_name":"v1.1.0-rc.1","html_url":"https://github.com/Regstar2/windows-iso-builder/releases/tag/v1.1.0-rc.1","draft":false,"prerelease":true},{"tag_name":"v1.0.1","html_url":"https://github.com/Regstar2/windows-iso-builder/releases/tag/v1.0.1","body":"notes","draft":false,"prerelease":false}]"""));
        });
        var result = await new GitHubReleaseUpdateService(provider).CheckAsync("1.0.0", UpdateChannelService.Stable);
        Assert.AreEqual(UpdateCheckStatus.UpdateAvailable, result.Status);
        Assert.AreEqual("1.0.1", result.LatestVersion);
        Assert.IsNotNull(captured);
        Assert.AreEqual(GitHubReleaseUpdateService.ReleasesEndpoint, captured.RequestUri!.AbsoluteUri);
        Assert.IsNull(captured.Headers.Authorization);
    }

    [TestMethod]
    public async Task PrereleaseChannelCanSelectHigherPrerelease()
    {
        var provider = ProviderFor("""[{"tag_name":"v1.1.0-rc.2","html_url":"https://github.com/Regstar2/windows-iso-builder/releases/tag/v1.1.0-rc.2","draft":false,"prerelease":true},{"tag_name":"v1.0.1","html_url":"https://github.com/Regstar2/windows-iso-builder/releases/tag/v1.0.1","draft":false,"prerelease":false}]""");
        var result = await new GitHubReleaseUpdateService(provider).CheckAsync("1.0.0", UpdateChannelService.Prerelease);
        Assert.AreEqual(UpdateCheckStatus.UpdateAvailable, result.Status);
        Assert.AreEqual("1.1.0-rc.2", result.LatestVersion);
    }

    [TestMethod]
    public async Task EqualOrNewerInstalledVersionIsUpToDate()
    {
        var json = """[{"tag_name":"v1.0.1","html_url":"https://github.com/Regstar2/windows-iso-builder/releases/tag/v1.0.1","draft":false,"prerelease":false}]""";
        var equal = await new GitHubReleaseUpdateService(ProviderFor(json)).CheckAsync("1.0.1", UpdateChannelService.Stable);
        var newer = await new GitHubReleaseUpdateService(ProviderFor(json)).CheckAsync("1.0.2", UpdateChannelService.Stable);
        Assert.AreEqual(UpdateCheckStatus.UpToDate, equal.Status);
        Assert.AreEqual(UpdateCheckStatus.UpToDate, newer.Status);
    }

    [TestMethod]
    public async Task InvalidOrMissingReleaseTagsAreIgnored()
    {
        var provider = ProviderFor("""[{"tag_name":"not-semver","draft":false,"prerelease":false},{"draft":false,"prerelease":false}]""");
        var result = await new GitHubReleaseUpdateService(provider).CheckAsync("1.0.0", UpdateChannelService.Stable);
        Assert.AreEqual(UpdateCheckStatus.NoPublishedRelease, result.Status);
    }

    [TestMethod]
    public async Task UntrustedReleaseUrlIsNeverReturned()
    {
        var provider = ProviderFor("""[{"tag_name":"v1.0.1","html_url":"https://example.test/evil","draft":false,"prerelease":false}]""");
        var result = await new GitHubReleaseUpdateService(provider).CheckAsync("1.0.0", UpdateChannelService.Stable);
        Assert.AreEqual(UpdateCheckStatus.UpdateAvailable, result.Status);
        Assert.IsNull(result.ReleaseUrl);
    }

    [TestMethod]
    public async Task NetworkAndTimeoutFailuresRemainControlledFailures()
    {
        var offline = new GitHubReleaseUpdateService(new StubHttpClientProvider((_, _) => throw new HttpRequestException("offline")));
        var timeout = new GitHubReleaseUpdateService(new StubHttpClientProvider((_, _) => Task.FromCanceled<HttpResponseMessage>(new CancellationToken(true))));
        await AssertThrowsAsync<HttpRequestException>(() => offline.CheckAsync("1.0.0", UpdateChannelService.Stable));
        await AssertThrowsAsync<TaskCanceledException>(() => timeout.CheckAsync("1.0.0", UpdateChannelService.Stable));
    }

    [TestMethod]
    public void UpdateChannelDefaultsToStable()
    {
        Assert.AreEqual(UpdateChannelService.Stable, UpdateChannelService.Normalize(null));
        Assert.AreEqual(UpdateChannelService.Stable, UpdateChannelService.Normalize("unknown"));
        Assert.AreEqual(UpdateChannelService.Prerelease, UpdateChannelService.Normalize(" PRERELEASE "));
    }

    [TestMethod]
    public void UpdateChannelPersistsWithoutCredentials()
    {
        var root = Path.Combine(Path.GetTempPath(), "wib-update-settings", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "settings.json");
            var service = new AppSettingsService(new GuiLogger(), path);
            service.Save(new AppSettings { UpdateChannel = UpdateChannelService.Prerelease });
            var loaded = service.Load();
            Assert.AreEqual(UpdateChannelService.Prerelease, loaded.UpdateChannel);
            var json = File.ReadAllText(path);
            Assert.IsFalse(json.Contains("password", StringComparison.OrdinalIgnoreCase));
            Assert.IsFalse(json.Contains("token", StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static SemanticVersion Parse(string value)
    {
        Assert.IsTrue(SemanticVersion.TryParse(value, out var version), value);
        return version!;
    }

    private static StubHttpClientProvider ProviderFor(string json) => new((_, _) => Task.FromResult(JsonResponse(json)));

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
    };

    private static async Task AssertThrowsAsync<T>(Func<Task> action) where T : Exception
    {
        try
        {
            await action();
            Assert.Fail($"Expected {typeof(T).Name}.");
        }
        catch (T)
        {
        }
    }

    private sealed class StubHttpClientProvider : IHttpClientProvider
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _send;
        public StubHttpClientProvider(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) => _send = send;
        public HttpClient CreateClient() => new(new StubHandler(_send)) { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _send;
        public StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) => _send = send;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => _send(request, cancellationToken);
    }
}
