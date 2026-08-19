using System.Text.RegularExpressions;
using WindowsISOBuilder.Gui.Backend;

namespace WindowsISOBuilder.Gui.Services;

public sealed partial class GuiLogger
{
    public string LogPath { get; }

    public GuiLogger()
    {
        try
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var directory = string.IsNullOrWhiteSpace(localAppData)
                ? Path.Combine(Path.GetTempPath(), "WindowsISOBuilder", "logs")
                : Path.Combine(localAppData, "WindowsISOBuilder", "logs");
            LogPath = Path.Combine(directory, $"gui-{DateTime.Now:yyyyMMdd}.log");
        }
        catch
        {
            // The fallback itself deliberately avoids filesystem/path discovery.
            // Even a broken TEMP/LOCALAPPDATA configuration must not block startup.
            LogPath = $"windows-iso-builder-gui-{Environment.ProcessId}.log";
        }
    }

    public void Info(string message) => Write("INFO", message, null);
    public void Error(string message, Exception? exception = null) => Write("ERROR", message, exception);

    private void Write(string level, string message, Exception? exception)
    {
        try
        {
            var directory = Path.GetDirectoryName(LogPath);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);

            var safeMessage = Sanitize(message);
            var suffix = exception switch
            {
                null => string.Empty,
                BackendException backend => $" | BackendException: code={backend.Code} requestId={Sanitize(backend.RequestId ?? string.Empty)}",
                _ => $" | {exception.GetType().Name}: {Sanitize(exception.Message)}"
            };
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} [{level}] {safeMessage}{suffix}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never crash the GUI.
        }
    }

    private static string Sanitize(string value)
    {
        if (string.IsNullOrEmpty(value)) return value;
        var sanitized = UrlPattern().Replace(value, "<URL>");
        return ProductKeyPattern().Replace(sanitized, "<PRODUCT_KEY>");
    }

    [GeneratedRegex(@"https?://[^\s]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UrlPattern();

    [GeneratedRegex(@"\b(?:[A-Z0-9]{5}-){4}[A-Z0-9]{5}\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ProductKeyPattern();
}
