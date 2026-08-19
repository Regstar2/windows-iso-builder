namespace WindowsISOBuilder.Gui.Models;

internal sealed record DiagnosticsSource(
    string? ExecutionLogPath,
    string? BuildLogPath,
    string? ConverterLogPath);
