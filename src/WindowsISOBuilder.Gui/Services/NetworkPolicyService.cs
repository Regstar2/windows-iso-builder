using System.Text;
using System.Text.Json;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class NetworkPolicyException : Exception
{
    public NetworkPolicyException(string code, string message) : base(message) => Code = code;
    public string Code { get; }
}

internal sealed class NetworkPolicyService
{
    internal const string SystemMode = "system";
    internal const string DirectMode = "direct";
    internal const string CustomMode = "custom";
    internal const string HttpProxy = "http";
    internal const string Socks5Proxy = "socks5";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _path;

    public NetworkPolicyService(string? path = null) => _path = path ?? GetDefaultPath();

    internal string Path => _path;

    public NetworkPolicy Load()
    {
        if (!File.Exists(_path)) return DefaultPolicy();
        try
        {
            var json = File.ReadAllText(_path, Encoding.UTF8);
            var policy = JsonSerializer.Deserialize<NetworkPolicy>(json, JsonOptions)
                ?? throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Network policy is empty.");
            return NormalizeAndValidate(policy);
        }
        catch (NetworkPolicyException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", $"Network policy could not be read: {exception.GetType().Name}.");
        }
    }

    public void Save(NetworkPolicy policy)
    {
        var normalized = NormalizeAndValidate(policy);
        var directory = System.IO.Path.GetDirectoryName(_path);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
        var temporaryPath = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(normalized, JsonOptions), new UTF8Encoding(false));
            File.Move(temporaryPath, _path, true);
        }
        finally
        {
            try { if (File.Exists(temporaryPath)) File.Delete(temporaryPath); } catch { }
        }
    }

    internal static NetworkPolicy FromInput(NetworkSettingsInput input, bool hasExistingCredential)
    {
        var port = int.TryParse(input.Port?.Trim(), out var parsedPort) ? parsedPort : (int?)null;
        return NormalizeAndValidate(new NetworkPolicy
        {
            SchemaVersion = NetworkPolicy.CurrentSchemaVersion,
            Mode = input.Mode,
            ProxyType = input.ProxyType,
            Host = input.Host,
            Port = port,
            Username = input.Username,
            HasCredential = !string.IsNullOrEmpty(input.Password) || hasExistingCredential
        });
    }

    internal static NetworkPolicy NormalizeAndValidate(NetworkPolicy policy)
    {
        if (policy.SchemaVersion != NetworkPolicy.CurrentSchemaVersion)
        {
            throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Unsupported network policy schema.");
        }

        var mode = NormalizeMode(policy.Mode);
        if (mode != CustomMode)
        {
            return new NetworkPolicy
            {
                SchemaVersion = NetworkPolicy.CurrentSchemaVersion,
                Mode = mode,
                ProxyType = null,
                Host = null,
                Port = null,
                Username = null,
                HasCredential = false
            };
        }

        var proxyType = NormalizeProxyType(policy.ProxyType);
        var host = (policy.Host ?? string.Empty).Trim();
        if (host.Length is < 1 or > 255 || host.Any(char.IsWhiteSpace) ||
            host.Contains("://", StringComparison.Ordinal) || host.Contains('/') || host.Contains('\\') || host.Contains('@'))
        {
            throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Custom proxy host is invalid.");
        }
        if (policy.Port is not int port || port is < 1 or > 65535)
        {
            throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Custom proxy port is invalid.");
        }
        var username = string.IsNullOrWhiteSpace(policy.Username) ? null : policy.Username.Trim();
        if (username is { Length: > 256 } || username?.Contains('\r') == true || username?.Contains('\n') == true)
        {
            throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Custom proxy username is invalid.");
        }
        if (policy.HasCredential && string.IsNullOrWhiteSpace(username))
        {
            throw new NetworkPolicyException("PROXY_CREDENTIAL_REQUIRES_USERNAME", "Proxy username is required when a password is saved.");
        }

        return new NetworkPolicy
        {
            SchemaVersion = NetworkPolicy.CurrentSchemaVersion,
            Mode = CustomMode,
            ProxyType = proxyType,
            Host = host,
            Port = port,
            Username = username,
            HasCredential = policy.HasCredential
        };
    }

    internal static string NormalizeMode(string? value) => (value ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        "" or SystemMode => SystemMode,
        DirectMode => DirectMode,
        CustomMode => CustomMode,
        _ => throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Unsupported network mode.")
    };

    internal static string NormalizeProxyType(string? value) => (value ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        HttpProxy => HttpProxy,
        Socks5Proxy => Socks5Proxy,
        _ => throw new NetworkPolicyException("PROXY_CONFIGURATION_INVALID", "Unsupported proxy type.")
    };

    internal static NetworkPolicy DefaultPolicy() => new()
    {
        SchemaVersion = NetworkPolicy.CurrentSchemaVersion,
        Mode = SystemMode
    };

    private static string GetDefaultPath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = string.IsNullOrWhiteSpace(localAppData)
            ? System.IO.Path.Combine(System.IO.Path.GetTempPath(), "WindowsISOBuilder")
            : System.IO.Path.Combine(localAppData, "WindowsISOBuilder");
        return System.IO.Path.Combine(root, "network.json");
    }
}
