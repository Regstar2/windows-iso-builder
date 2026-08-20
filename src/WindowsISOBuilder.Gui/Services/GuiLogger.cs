using WindowsISOBuilder.Gui.Backend;

namespace WindowsISOBuilder.Gui.Services;

public sealed class GuiLogger
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
            LogPath = $"windows-iso-builder-gui-{Environment.ProcessId}.log";
        }
    }

    public void Info(string message) => Write("INFO", message, null);
    public void Warning(string message) => Write("WARN", message, null);
    public void Error(string message, Exception? exception = null) => Write("ERROR", message, exception);
    public static string SanitizeDiagnostic(string value) => DiagnosticSanitizer.Sanitize(value);

    private void Write(string level, string message, Exception? exception)
    {
        try
        {
            var directory = Path.GetDirectoryName(LogPath);
            if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);

            var safeMessage = DiagnosticSanitizer.Sanitize(message);
            var suffix = exception switch
            {
                null => string.Empty,
                BackendException backend => $" | BackendException: code={backend.Code} requestId={DiagnosticSanitizer.Sanitize(backend.RequestId ?? string.Empty)}",
                _ => $" | {exception.GetType().Name}: {DiagnosticSanitizer.Sanitize(exception.Message)}"
            };
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} [{level}] {safeMessage}{suffix}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never crash the GUI.
        }
    }
}
