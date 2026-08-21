using System.Net;
using System.Net.Http;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed record NetworkTestResult(bool Success, string Code);

internal static class NetworkConnectionTester
{
    private static readonly Uri ProbeUri = new("https://api.uupdump.net/listid.php?search=Windows%2011&sortByDate=1");

    public static async Task<NetworkTestResult> TestAsync(
        NetworkPolicy policy,
        string? password,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var client = new NetworkHttpClientProvider(policy, password, TimeSpan.FromSeconds(15)).CreateClient();
            using var request = new HttpRequestMessage(HttpMethod.Get, ProbeUri);
            request.Headers.UserAgent.ParseAdd($"WindowsISOBuilder/{AppVersionInfo.Current} network-test");
            request.Headers.Accept.ParseAdd("application/json");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            return response.IsSuccessStatusCode
                ? new NetworkTestResult(true, "OK")
                : new NetworkTestResult(false, response.StatusCode == HttpStatusCode.ProxyAuthenticationRequired
                    ? "PROXY_AUTHENTICATION_FAILED"
                    : "NETWORK_ERROR");
        }
        catch (NetworkPolicyException exception)
        {
            return new NetworkTestResult(false, exception.Code);
        }
        catch (TaskCanceledException)
        {
            return new NetworkTestResult(false, "NETWORK_TIMEOUT");
        }
        catch (HttpRequestException)
        {
            return new NetworkTestResult(false, "PROXY_CONNECTION_FAILED");
        }
    }
}
