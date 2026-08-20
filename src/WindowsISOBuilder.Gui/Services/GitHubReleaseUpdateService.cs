using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class GitHubReleaseUpdateService
{
    internal const string ReleasesEndpoint = "https://api.github.com/repos/Regstar2/windows-iso-builder/releases?per_page=30";
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly IHttpClientProvider _httpClientProvider;

    public GitHubReleaseUpdateService(IHttpClientProvider httpClientProvider) =>
        _httpClientProvider = httpClientProvider;

    public async Task<UpdateCheckResult> CheckAsync(string currentVersion, string channel, CancellationToken cancellationToken = default)
    {
        if (!SemanticVersion.TryParse(currentVersion, out var installed) || installed is null)
        {
            throw new InvalidOperationException("The installed application version is not valid SemVer.");
        }

        using var client = _httpClientProvider.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, ReleasesEndpoint);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.UserAgent.ParseAdd($"WindowsISOBuilder/{currentVersion}");
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");

        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        var releases = await JsonSerializer.DeserializeAsync<List<GitHubReleaseDto>>(stream, JsonOptions, cancellationToken).ConfigureAwait(false) ?? [];

        var normalizedChannel = UpdateChannelService.Normalize(channel);
        Candidate? latest = null;
        foreach (var release in releases)
        {
            if (release.Draft || normalizedChannel == UpdateChannelService.Stable && release.Prerelease) continue;
            if (!SemanticVersion.TryParse(release.TagName, out var parsed) || parsed is null) continue;
            if (latest is null || parsed.CompareTo(latest.Version) > 0) latest = new Candidate(parsed, release);
        }

        if (latest is null)
        {
            return new UpdateCheckResult(UpdateCheckStatus.NoPublishedRelease, currentVersion, null, null, null, null);
        }

        var latestVersion = NormalizeTag(latest.Release.TagName!);
        var status = latest.Version.CompareTo(installed) > 0 ? UpdateCheckStatus.UpdateAvailable : UpdateCheckStatus.UpToDate;
        return new UpdateCheckResult(
            status,
            currentVersion,
            latestVersion,
            latest.Release.Name,
            GetTrustedReleaseUrl(latest.Release.HtmlUrl),
            SummarizeNotes(latest.Release.Body));
    }

    private static string NormalizeTag(string tag) => tag.Trim().TrimStart('v');

    private static string? GetTrustedReleaseUrl(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        return uri.AbsoluteUri;
    }

    private static string? SummarizeNotes(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var notes = value.Trim();
        return notes.Length <= 1200 ? notes : notes[..1200] + "…";
    }

    private sealed record Candidate(SemanticVersion Version, GitHubReleaseDto Release);

    private sealed class GitHubReleaseDto
    {
        [JsonPropertyName("tag_name")]
        public string? TagName { get; set; }
        [JsonPropertyName("html_url")]
        public string? HtmlUrl { get; set; }
        [JsonPropertyName("name")]
        public string? Name { get; set; }
        [JsonPropertyName("body")]
        public string? Body { get; set; }
        [JsonPropertyName("draft")]
        public bool Draft { get; set; }
        [JsonPropertyName("prerelease")]
        public bool Prerelease { get; set; }
    }
}
