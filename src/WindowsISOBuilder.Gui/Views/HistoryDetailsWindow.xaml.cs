using System.Diagnostics;
using System.Windows;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui.Views;

public partial class HistoryDetailsWindow : Window
{
    private readonly DetailsModel _model;

    public HistoryDetailsWindow(HistoryEntry entry)
    {
        InitializeComponent();
        _model = new DetailsModel(entry);
        DataContext = _model;
    }

    private void OpenIsoFolder_Click(object sender, RoutedEventArgs e)
    {
        if (!_model.IsoExists) return;
        OpenPath(Path.GetDirectoryName(_model.Entry.IsoPath!));
    }

    private void CopySha_Click(object sender, RoutedEventArgs e)
    {
        if (_model.HasSha) Clipboard.SetText(_model.Entry.Sha256!);
    }

    private void OpenLog_Click(object sender, RoutedEventArgs e) => OpenPath(_model.Entry.LogPath);
    private void OpenExecutionLog_Click(object sender, RoutedEventArgs e) => OpenPath(_model.Entry.ExecutionLogPath);
    private void OpenMetadata_Click(object sender, RoutedEventArgs e) => OpenPath(_model.Entry.MetadataPath);

    private static void OpenPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || (!File.Exists(path) && !Directory.Exists(path))) return;
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    private sealed class DetailsModel
    {
        private readonly LocalizationService _loc = LocalizationService.Instance;
        public HistoryEntry Entry { get; }
        public string Product => Entry.Product;
        public string VersionLabel => Entry.VersionLabel;
        public string Build => Entry.Build;
        public string ArchitectureLabel => Entry.ArchitectureLabel;
        public string Language => Entry.Language;
        public string EditionsText => Entry.EditionsText;
        public string ImageFormat => Entry.ImageFormat;
        public string OptionsText => Entry.OptionsText;
        public string Started => Entry.StartedAt.ToLocalTime().ToString("F");
        public string Finished => Entry.FinishedAt?.ToLocalTime().ToString("F") ?? "—";
        public string Status => Entry.StatusLabel;
        public string IsoDisplay => DisplayPath(Entry.IsoPath);
        public string Sha256 => Entry.Sha256 ?? string.Empty;
        public string LogDisplay => DisplayPath(Entry.LogPath);
        public string ExecutionLogDisplay => DisplayPath(Entry.ExecutionLogPath);
        public string MetadataDisplay => DisplayPath(Entry.MetadataPath);
        public string ErrorCode => Entry.ErrorCode ?? string.Empty;
        public bool IsoExists => Entry.IsoExists;
        public bool LogExists => Entry.LogExists;
        public bool ExecutionLogExists => Entry.ExecutionLogExists;
        public bool MetadataExists => Entry.MetadataExists;
        public bool HasSha => Entry.HasSha256;

        public DetailsModel(HistoryEntry entry) => Entry = entry;

        private string DisplayPath(string? path)
        {
            if (string.IsNullOrWhiteSpace(path)) return "—";
            return File.Exists(path) || Directory.Exists(path) ? path : path + " — " + _loc.Get("HistoryFileMissing");
        }
    }
}
