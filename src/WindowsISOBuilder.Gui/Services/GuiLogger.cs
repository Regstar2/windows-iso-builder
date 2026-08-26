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
    public void Error(string message, Exception? exception = null) => Write("ERROR", message, exception);
    public static string SanitizeDiagnostic(string value) => DiagnosticSanitizer.Sanitize(value);

    internal static string FormatExceptionForLog(Exception exception)
    {
        var parts = new List<string>
        {
            exception.GetType().Name,
            $"hresult=0x{exception.HResult:X8}"
        };

        if (!string.IsNullOrWhiteSpace(exception.Message))
        {
            parts.Add("message=" + exception.Message);
        }

        if (exception is FileNotFoundException fileNotFound && !string.IsNullOrWhiteSpace(fileNotFound.FileName))
        {
            parts.Add("file=" + fileNotFound.FileName);
        }
        else if (exception is FileLoadException fileLoad && !string.IsNullOrWhiteSpace(fileLoad.FileName))
        {
            parts.Add("file=" + fileLoad.FileName);
        }

        if (!string.IsNullOrWhiteSpace(exception.StackTrace))
        {
            parts.Add("stack=" + NormalizeMultiline(exception.StackTrace));
        }

        if (exception.InnerException is not null)
        {
            parts.Add("inner={" + FormatExceptionForLog(exception.InnerException) + "}");
        }

        return DiagnosticSanitizer.Sanitize(string.Join(" | ", parts));
    }

    private static string NormalizeMultiline(string value) =>
        value.Replace("\r\n", " <- ", StringComparison.Ordinal)
             .Replace("\n", " <- ", StringComparison.Ordinal)
             .Replace("\r", " <- ", StringComparison.Ordinal);

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
                _ => " | " + FormatExceptionForLog(exception)
            };
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} [{level}] {safeMessage}{suffix}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never crash the GUI.
        }
    }
}
