using System.Windows;
using Microsoft.Win32;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Services;

internal static class UiActions
{
    public static void CreateDiagnostics(Window owner, MainViewModel viewModel, GuiLogger log)
    {
        var loc = LocalizationService.Instance;
        var dialog = new SaveFileDialog
        {
            FileName = "windows-iso-builder-diagnostics.zip",
            DefaultExt = ".zip",
            AddExtension = true,
            Filter = loc.Get("DiagnosticsFilter"),
            Title = loc.Get("DiagnosticsSaveTitle")
        };
        if (dialog.ShowDialog(owner) != true) return;

        try
        {
            var result = viewModel.Result;
            var fallbackWorkDirectory = !string.IsNullOrWhiteSpace(viewModel.ErrorLogPath)
                ? Path.GetDirectoryName(viewModel.ErrorLogPath)
                : null;
            var converterLog = DiagnosticsService.FindLatestConverterLog(result?.WorkDirectory)
                ?? DiagnosticsService.FindLatestConverterLog(fallbackWorkDirectory);
            new DiagnosticsService().CreatePackage(
                dialog.FileName,
                new DiagnosticsSource(result?.ExecutionLogPath, result?.LogPath ?? viewModel.ErrorLogPath, converterLog));
            MessageBox.Show(owner, loc.Get("DiagnosticsSuccessMessage"), loc.Get("DiagnosticsSuccessTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception exception)
        {
            log.Error("Failed to create diagnostics package", exception);
            MessageBox.Show(owner, loc.Get("DiagnosticsFailureMessage"), loc.Get("DiagnosticsFailureTitle"), MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
