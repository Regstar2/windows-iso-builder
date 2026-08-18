using System.ComponentModel;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Input;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui;

public partial class MainWindow : Window
{
    private bool _allowClose;
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
        Closing += OnClosing;
    }

    private void Quick_Click(object sender, RoutedEventArgs e) => Tabs.SelectedIndex = 0;
    private void Catalog_Click(object sender, RoutedEventArgs e) => Tabs.SelectedIndex = 1;

    private void CatalogGrid_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (CatalogGrid.SelectedItem is not null) Tabs.SelectedIndex = 0;
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Каталог для ISO",
            UseDescriptionForTitle = true,
            SelectedPath = ViewModel.OutputDirectory
        };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            ViewModel.OutputDirectory = dialog.SelectedPath;
        }
    }

    private void OpenResultFolder_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.ResultDirectory);
    private void OpenResultLog_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.Result?.LogPath);
    private void OpenErrorLog_Click(object sender, RoutedEventArgs e) => ViewModel.OpenPath(ViewModel.ErrorLogPath);

    private void CopySha_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(ViewModel.Result?.Sha256))
        {
            System.Windows.Clipboard.SetText(ViewModel.Result.Sha256);
        }
    }

    private void CopyDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(ViewModel.DiagnosticText))
        {
            System.Windows.Clipboard.SetText(ViewModel.DiagnosticText);
        }
    }

    private void StartOver_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.StartOver();
        Tabs.SelectedIndex = 0;
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_allowClose || !ViewModel.IsBuilding) return;

        e.Cancel = true;
        var result = System.Windows.MessageBox.Show(
            "Сборка ещё выполняется.\n\nДа — отменить сборку и выйти.\nНет — продолжить сборку.",
            "Windows ISO Builder",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes) return;

        var cancellationRequested = await ViewModel.CancelAsync();
        if (!cancellationRequested) return;

        await ViewModel.WaitForBuildTerminationAsync();
        _allowClose = true;
        Close();
    }
}
