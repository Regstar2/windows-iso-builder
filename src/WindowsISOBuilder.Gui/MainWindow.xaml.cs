using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using WindowsISOBuilder.Gui.Models;
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

    private void CatalogGrid_DoubleClick(object sender, MouseButtonEventArgs e) => UseSelectedCatalogBuild();
    private void UseCatalogBuild_Click(object sender, RoutedEventArgs e) => UseSelectedCatalogBuild();

    private void UseSelectedCatalogBuild()
    {
        if (CatalogGrid.SelectedItem is not BuildDto build) return;

        // Catalog selection is deliberately separate from the active build. This
        // prevents a single row click from starting metadata loading and disabling
        // the tab before the documented double-click action can complete.
        ViewModel.Product = build.Product;
        ViewModel.Architecture = build.Architecture;
        ViewModel.SelectedBuild = build;
        Tabs.SelectedIndex = 0;
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            InitialDirectory = ViewModel.OutputDirectory,
            Multiselect = false
        };

        if (dialog.ShowDialog(this) == true)
        {
            ViewModel.OutputDirectory = dialog.FolderName;
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
