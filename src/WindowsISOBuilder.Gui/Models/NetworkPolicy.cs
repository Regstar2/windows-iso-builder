namespace WindowsISOBuilder.Gui.Models;

internal sealed class NetworkPolicy
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public string Mode { get; set; } = "system";
    public string? ProxyType { get; set; }
    public string? Host { get; set; }
    public int? Port { get; set; }
    public string? Username { get; set; }
    public bool HasCredential { get; set; }
}

internal sealed record NetworkSettingsInput(
    string Mode,
    string ProxyType,
    string Host,
    string Port,
    string Username,
    string Password);
