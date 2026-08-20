using System.Net;
using System.Net.Http;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class NetworkHttpClientProvider : IHttpClientProvider
{
    private readonly NetworkPolicyService? _policyService;
    private readonly ProxyCredentialStore? _credentialStore;
    private readonly NetworkPolicy? _fixedPolicy;
    private readonly string? _fixedPassword;
    private readonly TimeSpan _timeout;

    public NetworkHttpClientProvider(
        NetworkPolicyService policyService,
        ProxyCredentialStore credentialStore,
        TimeSpan? timeout = null)
    {
        _policyService = policyService;
        _credentialStore = credentialStore;
        _timeout = timeout ?? TimeSpan.FromSeconds(10);
    }

    internal NetworkHttpClientProvider(NetworkPolicy policy, string? password, TimeSpan? timeout = null)
    {
        _fixedPolicy = NetworkPolicyService.NormalizeAndValidate(policy);
        _fixedPassword = password;
        _timeout = timeout ?? TimeSpan.FromSeconds(10);
    }

    public HttpClient CreateClient()
    {
        var policy = _fixedPolicy ?? _policyService?.Load() ?? NetworkPolicyService.DefaultPolicy();
        var password = _fixedPolicy is null ? ResolvePersistedPassword(policy) : _fixedPassword;
        var handler = CreateHandler(policy, password);
        return new HttpClient(handler, disposeHandler: true) { Timeout = _timeout };
    }

    private string? ResolvePersistedPassword(NetworkPolicy policy)
    {
        if (!policy.HasCredential) return null;
        var password = _credentialStore?.Load();
        if (password is null)
        {
            throw new NetworkPolicyException("PROXY_CREDENTIAL_UNAVAILABLE", "Saved proxy credential is unavailable.");
        }
        return password;
    }

    internal static HttpClientHandler CreateHandler(NetworkPolicy policy, string? password)
    {
        policy = NetworkPolicyService.NormalizeAndValidate(policy);
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli
        };

        switch (policy.Mode)
        {
            case NetworkPolicyService.SystemMode:
                handler.UseProxy = true;
                handler.Proxy = null;
                break;
            case NetworkPolicyService.DirectMode:
                handler.UseProxy = false;
                handler.Proxy = null;
                break;
            case NetworkPolicyService.CustomMode:
                handler.UseProxy = true;
                var scheme = policy.ProxyType == NetworkPolicyService.Socks5Proxy ? "socks5" : "http";
                var proxyUri = new UriBuilder(scheme, policy.Host!, policy.Port!.Value).Uri;
                var proxy = new WebProxy(proxyUri);
                if (!string.IsNullOrWhiteSpace(policy.Username))
                {
                    proxy.Credentials = new NetworkCredential(policy.Username, password ?? string.Empty);
                }
                handler.Proxy = proxy;
                break;
            default:
                throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Unsupported network mode.");
        }

        return handler;
    }
}
