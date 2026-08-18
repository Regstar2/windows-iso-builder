namespace WindowsISOBuilder.Gui.Services;

public sealed class GuiLogger
{
    public string LogPath { get; }

    public GuiLogger()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsISOBuilder", "logs");
        Directory.CreateDirectory(directory);
        LogPath = Path.Combine(directory, $"gui-{DateTime.Now:yyyyMMdd}.log");
    }

    public void Info(string message) => Write("INFO", message, null);
    public void Error(string message, Exception? exception = null) => Write("ERROR", message, exception);

    private void Write(string level, string message, Exception? exception)
    {
        try
        {
            var suffix = exception is null ? string.Empty : $" | {exception.GetType().Name}: {exception.Message}";
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} [{level}] {message}{suffix}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never crash the GUI.
        }
    }
}
